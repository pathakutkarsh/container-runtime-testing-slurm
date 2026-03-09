#!/bin/bash
# =============================================================================
# bench_lib.sh — Benchmark measurement library (per-node metrics via mpirun)
#
# Source this file inside your existing Slurm scripts, then call:
#   bench_start <label>   — before your workload
#   bench_end             — after your workload
#
# How it works:
#   Uses mpirun to launch one collector process per node at the start of the
#   job. Each collector samples CPU and memory every second and writes to its
#   own timeseries CSV on the shared filesystem. No srun, no ssh required.
#
# Output files:
#   bench_results/summary.csv
#       One row per node per run appended after each job completes.
#       Columns: job_id, label, node, wall_clock_s, peak_cpu_percent,
#                avg_cpu_percent, peak_mem_used_kb, exit_status, timestamp
#
#   bench_results/<label>_<jobid>/<node>_timeseries.csv
#       1-second CPU + memory samples from each node.
#
#   bench_results/<label>_<jobid>/sacct.csv
#       Full Slurm accounting dump for the job.
#
# Requirements:
#   - Shared filesystem accessible from all nodes (NFS, Lustre, etc.)
#   - mpirun available and working (already true if your benchmarks use it)
#
# Example usage in your script:
# ─────────────────────────────────────────────────────────────────────────────
#   #!/bin/bash
#   #SBATCH --job-name=osu_benchmarks
#   #SBATCH --nodes=2
#   #SBATCH --ntasks=2
#   #SBATCH ...your normal directives...
#
#   source /path/to/bench_lib.sh
#   bench_start "slurm"
#
#   mpirun -np 2 ./osu_latency    # ← your workload unchanged
#
#   bench_end
# ─────────────────────────────────────────────────────────────────────────────

# Write the per-node collector script to shared storage
_bench_write_collector() {
    local SCRIPT_PATH="$1"
    cat > "$SCRIPT_PATH" << 'COLLECTOR'
#!/bin/bash
# One instance of this runs on each node via mpirun --pernode
OUT_DIR="$1"
NODE=$(hostname -s)
TIMESERIES_CSV="${OUT_DIR}/${NODE}_timeseries.csv"
SUMMARY_TMP="${OUT_DIR}/${NODE}_summary.tmp"
STOP_FILE="${OUT_DIR}/.stop"           # single shared stop file — head node touches it

echo "timestamp_ms,epoch_s,cpu_percent,mem_used_kb,mem_available_kb,mem_total_kb" \
    > "$TIMESERIES_CSV"

MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MAX_CPU=0; MAX_MEM=0; SUM_CPU=0; N=0

while [[ ! -f "$STOP_FILE" ]]; do
    TS_MS=$(date +%s%3N)
    TS_S=$(date +%s)

    read -r _ c1 c2 c3 c4 c5 c6 c7 _ < /proc/stat
    CPU1=$((c1+c2+c3+c4+c5+c6+c7)); IDLE1=$c4
    sleep 0.2
    read -r _ d1 d2 d3 d4 d5 d6 d7 _ < /proc/stat
    CPU2=$((d1+d2+d3+d4+d5+d6+d7)); IDLE2=$d4

    DIFF_TOTAL=$((CPU2-CPU1)); DIFF_IDLE=$((IDLE2-IDLE1))
    [[ $DIFF_TOTAL -gt 0 ]] \
        && CPU_PCT=$(( (DIFF_TOTAL-DIFF_IDLE)*100/DIFF_TOTAL )) \
        || CPU_PCT=0

    MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))

    echo "${TS_MS},${TS_S},${CPU_PCT},${MEM_USED},${MEM_AVAIL},${MEM_TOTAL}" \
        >> "$TIMESERIES_CSV"

    [[ $CPU_PCT -gt $MAX_CPU ]] && MAX_CPU=$CPU_PCT
    [[ $MEM_USED -gt $MAX_MEM ]] && MAX_MEM=$MEM_USED
    SUM_CPU=$(( SUM_CPU+CPU_PCT )); N=$(( N+1 ))
    sleep 0.8
done

AVG_CPU=0
[[ $N -gt 0 ]] && AVG_CPU=$(( SUM_CPU/N ))
echo "${NODE},${MAX_CPU},${AVG_CPU},${MAX_MEM}" > "$SUMMARY_TMP"
COLLECTOR
    chmod +x "$SCRIPT_PATH"
}

bench_start() {
    BENCH_LABEL="${1:?bench_start requires a label, e.g. bench_start \"slurm\"}"

    # Resolve paths relative to the calling script's directory
    local BENCH_BASE_DIR
    CURRENT_DIR=$(pwd)
    BENCH_OUT_DIR="${CURRENT_DIR}/../results/bench_results/${BENCH_LABEL}_${SLURM_JOB_ID}"
    mkdir -p "$BENCH_OUT_DIR"

    BENCH_SUMMARY_CSV="${BENCH_OUT_DIR}/summary.csv"

    # Remove any leftover stop file from a previous run
    rm -f "$BENCH_OUT_DIR/.stop"

    # Create summary CSV header on first run
    if [[ ! -f "$BENCH_SUMMARY_CSV" ]]; then
        echo "job_id,label,node,wall_clock_s,peak_cpu_percent,avg_cpu_percent,peak_mem_used_kb,exit_status,timestamp" \
            > "$BENCH_SUMMARY_CSV"
    fi

    # Write collector script to shared storage so all nodes can execute it
    local BENCH_COLLECTOR_SCRIPT="${BENCH_OUT_DIR}/.node_collector.sh"
    _bench_write_collector "$BENCH_COLLECTOR_SCRIPT"

    # Launch one collector per node using mpirun --pernode.
    # --pernode places exactly one process per allocated node.
    # Running in background so it doesn't block the rest of the script.
    mpirun --pernode bash "$BENCH_COLLECTOR_SCRIPT" "$BENCH_OUT_DIR" &
    BENCH_MPIRUN_PID=$!

    # Give collectors a moment to start up before workload begins
    sleep 1

    BENCH_START_TIME=$(date +%s%3N)

    echo "[bench_lib] Benchmark started: label=${BENCH_LABEL}, job=${SLURM_JOB_ID}"
    echo "[bench_lib] Collecting metrics on all nodes: ${SLURM_NODELIST}"
}

bench_end() {
    local EXIT_STATUS=${1:-$?}

    BENCH_END_TIME=$(date +%s%3N)
    local WALL_MS=$(( BENCH_END_TIME - BENCH_START_TIME ))
    local WALL_S
    WALL_S=$(echo "scale=3; $WALL_MS / 1000" | bc)

    # Touch the shared stop file — all nodes see this immediately via shared fs
    touch "$BENCH_OUT_DIR/.stop"

    # Wait for all collectors to finish writing their summary tmp files
    wait "$BENCH_MPIRUN_PID" 2>/dev/null

    local TIMESTAMP
    TIMESTAMP=$(date --iso-8601=seconds)

    # Read each node's summary and append one row per node to summary CSV
    local NODE_COUNT=0
    for TMP in "$BENCH_OUT_DIR"/*_summary.tmp; do
        [[ -f "$TMP" ]] || continue
        local NODE PEAK_CPU AVG_CPU PEAK_MEM
        IFS=',' read -r NODE PEAK_CPU AVG_CPU PEAK_MEM < "$TMP"
        echo "${SLURM_JOB_ID},${BENCH_LABEL},${NODE},${WALL_S},${PEAK_CPU},${AVG_CPU},${PEAK_MEM},${EXIT_STATUS},${TIMESTAMP}" \
            >> "$BENCH_SUMMARY_CSV"
        NODE_COUNT=$(( NODE_COUNT + 1 ))
    done

    # Full Slurm accounting dump
    sacct -j "$SLURM_JOB_ID" \
        --format=JobID,JobName,Elapsed,CPUTime,AveCPU,MinCPU,MaxRSS,MaxVMSize,AveRSS,AveVMSize,TotalCPU,UserCPU,SystemCPU,NNodes,NCPUS,ExitCode \
        --units=M -P > "$BENCH_OUT_DIR/sacct.csv" 2>/dev/null

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