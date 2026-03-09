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
#       One row per node per run. A 2-node job produces 2 rows.
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
#   #SBATCH --job-name=my_job
#   #SBATCH ...your normal directives...
#
#   source /path/to/bench_lib.sh
#   bench_start "slurm"
#
#   mpirun -np 2 ./my_workload     # your actual workload unchanged
#
#   bench_end
# ─────────────────────────────────────────────────────────────────────────────

_bench_write_collector_script() {
    local SCRIPT_PATH="$1"
    cat > "$SCRIPT_PATH" << 'COLLECTOR_SCRIPT'
#!/bin/bash
OUT_DIR="$1"
NODE=$(hostname -s)
TIMESERIES_CSV="${OUT_DIR}/${NODE}_timeseries.csv"
SUMMARY_TMP="${OUT_DIR}/${NODE}_summary.tmp"
STOP_FILE="${OUT_DIR}/.stop_${NODE}"

echo "timestamp_ms,epoch_s,cpu_percent,mem_used_kb,mem_available_kb,mem_total_kb" \
    > "$TIMESERIES_CSV"

MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MAX_CPU=0; MAX_MEM=0; SUM_CPU=0; SAMPLE_COUNT=0

while [[ ! -f "$STOP_FILE" ]]; do
    TS_MS=$(date +%s%3N)
    TS_S=$(date +%s)

    read -r _ c1 c2 c3 c4 c5 c6 c7 _ < /proc/stat
    CPU1=$((c1+c2+c3+c4+c5+c6+c7)); IDLE1=$c4
    sleep 0.2
    read -r _ d1 d2 d3 d4 d5 d6 d7 _ < /proc/stat
    CPU2=$((d1+d2+d3+d4+d5+d6+d7)); IDLE2=$d4

    DIFF_TOTAL=$((CPU2 - CPU1)); DIFF_IDLE=$((IDLE2 - IDLE1))
    [[ $DIFF_TOTAL -gt 0 ]] \
        && CPU_PCT=$(( (DIFF_TOTAL - DIFF_IDLE) * 100 / DIFF_TOTAL )) \
        || CPU_PCT=0

    MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))

    echo "${TS_MS},${TS_S},${CPU_PCT},${MEM_USED},${MEM_AVAIL},${MEM_TOTAL}" \
        >> "$TIMESERIES_CSV"

    [[ $CPU_PCT -gt $MAX_CPU ]] && MAX_CPU=$CPU_PCT
    [[ $MEM_USED -gt $MAX_MEM ]] && MAX_MEM=$MEM_USED
    SUM_CPU=$(( SUM_CPU + CPU_PCT ))
    SAMPLE_COUNT=$(( SAMPLE_COUNT + 1 ))
    sleep 0.8
done

AVG_CPU=0
[[ $SAMPLE_COUNT -gt 0 ]] && AVG_CPU=$(( SUM_CPU / SAMPLE_COUNT ))
echo "${NODE},${MAX_CPU},${AVG_CPU},${MAX_MEM}" > "$SUMMARY_TMP"
COLLECTOR_SCRIPT
    chmod +x "$SCRIPT_PATH"
}

bench_start() {
    BENCH_LABEL="${1:?bench_start requires a label, e.g. bench_start \"slurm\"}"
    CURRENT_DIR=$(pwd)
    BENCH_OUT_DIR="${CURRENT_DIR}/../results/bench_results/${BENCH_LABEL}_${SLURM_JOB_ID}"
    mkdir -p "$BENCH_OUT_DIR"

    # Clean up any stop files from a previous run in this directory
    rm -f "$BENCH_OUT_DIR"/.stop_*

    BENCH_SUMMARY_CSV="${BENCH_OUT_DIR}/summary.csv"
    if [[ ! -f "$BENCH_SUMMARY_CSV" ]]; then
        echo "job_id,label,node,wall_clock_s,peak_cpu_percent,avg_cpu_percent,peak_mem_used_kb,exit_status,timestamp" \
            > "$BENCH_SUMMARY_CSV"
    fi

    BENCH_COLLECTOR_SCRIPT="$BENCH_OUT_DIR/.node_collector.sh"
    _bench_write_collector_script "$BENCH_COLLECTOR_SCRIPT"

    # Save the full node list so bench_end uses the same list
    # without any variable name collision with inner loops
    BENCH_NODELIST=( $(scontrol show hostnames "$SLURM_NODELIST") )
    echo "Node List"
    echo "$BENCH_NODELIST"
    # SSH user — defaults to current user, override with: export BENCH_SSH_USER=cloud
    BENCH_SSH_USER="${BENCH_SSH_USER:-$(whoami)}"

    # Launch one collector per node via ssh in the background
    BENCH_COLLECTOR_PIDS=()
    for BENCH_NODE in "${BENCH_NODELIST[@]}"; do
        ssh -i ~/.ssh/id_rsa \
            -o StrictHostKeyChecking=no \
            -o BatchMode=yes \
            "${BENCH_SSH_USER}@${BENCH_NODE}" \
            "bash '${BENCH_COLLECTOR_SCRIPT}' '${BENCH_OUT_DIR}'" &
        BENCH_COLLECTOR_PIDS+=($!)
        echo "[bench_lib] Started collector on ${BENCH_NODE} (pid $!)"
    done

    # Give collectors a moment to initialise before workload begins
    sleep 1

    BENCH_START_TIME=$(date +%s%3N)
    echo "[bench_lib] Benchmark started: label=${BENCH_LABEL}, job=${SLURM_JOB_ID}"
    echo "[bench_lib] Nodes: ${BENCH_NODELIST[*]}"
}

bench_end() {
    local BENCH_EXIT_STATUS=${1:-$?}   # use a prefixed name to avoid collision

    BENCH_END_TIME=$(date +%s%3N)
    local WALL_MS=$(( BENCH_END_TIME - BENCH_START_TIME ))
    local WALL_S
    WALL_S=$(echo "scale=3; $WALL_MS / 1000" | bc)

    # Touch each node's stop file directly on the shared filesystem —
    # no ssh needed, the file appears on every node immediately
    for BENCH_NODE in "${BENCH_NODELIST[@]}"; do
        touch "${BENCH_OUT_DIR}/.stop_${BENCH_NODE}"
        echo "[bench_lib] Sent stop signal to ${BENCH_NODE}"
    done

    # Wait for all collectors to finish
    for PID in "${BENCH_COLLECTOR_PIDS[@]}"; do
        wait "$PID" 2>/dev/null
    done

    local TIMESTAMP
    TIMESTAMP=$(date --iso-8601=seconds)

    # Append one row per node to summary CSV
    local NODE_COUNT=0
    for TMP in "$BENCH_OUT_DIR"/*_summary.tmp; do
        [[ -f "$TMP" ]] || continue
        local BENCH_NODE_NAME PEAK_CPU AVG_CPU PEAK_MEM
        IFS=',' read -r BENCH_NODE_NAME PEAK_CPU AVG_CPU PEAK_MEM < "$TMP"
        echo "${SLURM_JOB_ID},${BENCH_LABEL},${BENCH_NODE_NAME},${WALL_S},${PEAK_CPU},${AVG_CPU},${PEAK_MEM},${BENCH_EXIT_STATUS},${TIMESTAMP}" \
            >> "$BENCH_SUMMARY_CSV"
        NODE_COUNT=$(( NODE_COUNT + 1 ))
    done

    sacct -j "$SLURM_JOB_ID" \
        --format=JobID,JobName,Elapsed,CPUTime,AveCPU,MinCPU,MaxRSS,MaxVMSize,AveRSS,AveVMSize,TotalCPU,UserCPU,SystemCPU,NNodes,NCPUS,ExitCode \
        --units=M -P > "$BENCH_OUT_DIR/sacct.csv" 2>/dev/null

    echo ""
    echo "======================================================="
    echo " Benchmark Complete: $BENCH_LABEL"
    echo "======================================================="
    echo " Nodes collected  : ${NODE_COUNT} / ${#BENCH_NODELIST[@]}"
    echo " Wall clock       : ${WALL_S}s"
    echo " Exit status      : ${BENCH_EXIT_STATUS}"
    echo "-------------------------------------------------------"
    echo " Summary CSV      : $BENCH_SUMMARY_CSV"
    echo " Timeseries CSVs  : $BENCH_OUT_DIR/<node>_timeseries.csv"
    echo " Sacct CSV        : $BENCH_OUT_DIR/sacct.csv"
    echo "======================================================="
}