#!/bin/bash
# =============================================================================
# bench_lib.sh — Benchmark measurement library (per-node metrics)
#
# Source this file inside your existing Slurm scripts, then call:
#   bench_start <label>   — before your workload
#   bench_end             — after your workload
#
# Output files:
#   bench_results/summary.csv
#       One row per node per run. A 3-node job produces 3 rows.
#       Columns: job_id, label, node, wall_clock_s, peak_cpu_percent,
#                avg_cpu_percent, peak_mem_used_kb, exit_status, timestamp
#
#   bench_results/<label>_<jobid>/<node>_timeseries.csv
#       1-second CPU + memory samples from each node, for time-series graphs.
#
#   bench_results/<label>_<jobid>/sacct.csv
#       Full Slurm accounting dump for the job.
#
# Example usage in your script:
# ─────────────────────────────────────────────────────────────────────────────
#   #!/bin/bash
#   #SBATCH --job-name=my_apptainer_job
#   #SBATCH ...your normal directives...
#
#   source /path/to/bench_lib.sh
#   bench_start "apptainer"
#
#   apptainer exec image.sif my_workload          # ← your actual workload
#
#   bench_end
# ─────────────────────────────────────────────────────────────────────────────

# Internal helper — runs on every node via srun, collects metrics until signalled
_bench_node_collector() {
    local OUT_DIR="$1"
    local NODE
    NODE=$(hostname -s)
    local TIMESERIES_CSV="$OUT_DIR/${NODE}_timeseries.csv"
    local SUMMARY_TMP="$OUT_DIR/${NODE}_summary.tmp"
    local STOP_FILE="$OUT_DIR/.stop_${NODE}"

    echo "timestamp_ms,epoch_s,cpu_percent,mem_used_kb,mem_available_kb,mem_total_kb" \
        > "$TIMESERIES_CSV"

    local MEM_TOTAL
    MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')

    local MAX_CPU=0 MAX_MEM=0 SUM_CPU=0 SAMPLE_COUNT=0

    while [[ ! -f "$STOP_FILE" ]]; do
        local TS_MS TS_S CPU_PCT MEM_AVAIL MEM_USED
        TS_MS=$(date +%s%3N)
        TS_S=$(date +%s)

        # Two /proc/stat snapshots 200ms apart → accurate CPU %
        read -r _ c1 c2 c3 c4 c5 c6 c7 _ < /proc/stat
        local CPU1=$((c1+c2+c3+c4+c5+c6+c7)) IDLE1=$c4
        sleep 0.2
        read -r _ d1 d2 d3 d4 d5 d6 d7 _ < /proc/stat
        local CPU2=$((d1+d2+d3+d4+d5+d6+d7)) IDLE2=$d4

        local DIFF_TOTAL=$((CPU2 - CPU1))
        local DIFF_IDLE=$((IDLE2 - IDLE1))
        [[ $DIFF_TOTAL -gt 0 ]] \
            && CPU_PCT=$(( (DIFF_TOTAL - DIFF_IDLE) * 100 / DIFF_TOTAL )) \
            || CPU_PCT=0

        MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))

        echo "${TS_MS},${TS_S},${CPU_PCT},${MEM_USED},${MEM_AVAIL},${MEM_TOTAL}" \
            >> "$TIMESERIES_CSV"

        # Track peak and running average for summary
        [[ $CPU_PCT -gt $MAX_CPU ]] && MAX_CPU=$CPU_PCT
        [[ $MEM_USED -gt $MAX_MEM ]] && MAX_MEM=$MEM_USED
        SUM_CPU=$(( SUM_CPU + CPU_PCT ))
        SAMPLE_COUNT=$(( SAMPLE_COUNT + 1 ))

        sleep 0.8   # total ~1s per sample (0.2 cpu probe + 0.8 sleep)
    done

    # Write per-node summary tmp — picked up by bench_end on the head node
    local AVG_CPU=0
    [[ $SAMPLE_COUNT -gt 0 ]] && AVG_CPU=$(( SUM_CPU / SAMPLE_COUNT ))
    echo "${NODE},${MAX_CPU},${AVG_CPU},${MAX_MEM}" > "$SUMMARY_TMP"
}
export -f _bench_node_collector   # must be exported so srun can call it

bench_start() {
    BENCH_LABEL="${1:?bench_start requires a label, e.g. bench_start \"apptainer\"}"
    CURRENT_DIR=$(pwd)
    BENCH_OUT_DIR="${CURRENT_DIR}/results/bench_results/${BENCH_LABEL}_${SLURM_JOB_ID}"
    mkdir -p "$BENCH_OUT_DIR"

    BENCH_SUMMARY_CSV="bench_results/summary.csv"

    # Create summary CSV header if this is the first run
    if [[ ! -f "$BENCH_SUMMARY_CSV" ]]; then
        echo "job_id,label,node,wall_clock_s,peak_cpu_percent,avg_cpu_percent,peak_mem_used_kb,exit_status,timestamp" \
            > "$BENCH_SUMMARY_CSV"
    fi

    # Launch exactly one collector per allocated node, all in the background.
    # --overlap allows this srun to run alongside the main job step.
    srun --ntasks-per-node=1 --overlap \
        bash -c "_bench_node_collector '$BENCH_OUT_DIR'" &
    BENCH_SRUN_PID=$!

    BENCH_START_TIME=$(date +%s%3N)

    echo "[bench_lib] Benchmark started: label=${BENCH_LABEL}, job=${SLURM_JOB_ID}"
    echo "[bench_lib] Collecting metrics on nodes: ${SLURM_NODELIST}"
}

bench_end() {
    local EXIT_STATUS=${1:-$?}

    BENCH_END_TIME=$(date +%s%3N)
    local WALL_MS=$(( BENCH_END_TIME - BENCH_START_TIME ))
    local WALL_S
    WALL_S=$(echo "scale=3; $WALL_MS / 1000" | bc)

    # Signal all node collectors to stop by touching a stop file on each node
    srun --ntasks-per-node=1 --overlap \
        bash -c "touch '$BENCH_OUT_DIR/.stop_\$(hostname -s)'"

    # Wait for all collectors to finish writing their summary tmp files
    wait $BENCH_SRUN_PID 2>/dev/null

    local TIMESTAMP
    TIMESTAMP=$(date --iso-8601=seconds)

    # Read each node's summary tmp and append one row per node to summary CSV
    local NODE_COUNT=0
    for TMP in "$BENCH_OUT_DIR"/*_summary.tmp; do
        [[ -f "$TMP" ]] || continue
        local NODE PEAK_CPU AVG_CPU PEAK_MEM
        IFS=',' read -r NODE PEAK_CPU AVG_CPU PEAK_MEM < "$TMP"
        echo "${SLURM_JOB_ID},${BENCH_LABEL},${NODE},${WALL_S},${PEAK_CPU},${AVG_CPU},${PEAK_MEM},${EXIT_STATUS},${TIMESTAMP}" \
            >> "$BENCH_SUMMARY_CSV"
        NODE_COUNT=$(( NODE_COUNT + 1 ))
    done

    # Dump full Slurm accounting data (once, from the head node)
    sacct -j "$SLURM_JOB_ID" \
        --format=JobID,JobName,Elapsed,CPUTime,AveCPU,MinCPU,MaxRSS,MaxVMSize,AveRSS,AveVMSize,TotalCPU,UserCPU,SystemCPU,NNodes,NCPUS,ExitCode \
        --units=M -P > "$BENCH_OUT_DIR/sacct.csv"

    echo ""
    echo "======================================================="
    echo " Benchmark Complete: $BENCH_LABEL"
    echo "======================================================="
    echo " Nodes collected  : ${NODE_COUNT} (${SLURM_NODELIST})"
    echo " Wall clock       : ${WALL_S}s"
    echo " Exit status      : ${EXIT_STATUS}"
    echo "-------------------------------------------------------"
    echo " Summary CSV      : $BENCH_SUMMARY_CSV"
    echo " Timeseries CSVs  : $BENCH_OUT_DIR/<node>_timeseries.csv"
    echo " Sacct CSV        : $BENCH_OUT_DIR/sacct.csv"
    echo "======================================================="
}