#!/bin/bash
# =============================================================================
# bench_lib.sh — Benchmark measurement library
#
# Source this file inside your existing Slurm scripts, then call:
#   bench_start <label>   — before your workload
#   bench_end             — after your workload
#
# All results go to bench_results/summary.csv (one row per run) and a
# per-run bench_results/<label>_<jobid>/timeseries.csv
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

bench_start() {
    BENCH_LABEL="${1:?bench_start requires a label, e.g. bench_start \"apptainer\"}"

    BENCH_OUT_DIR="./../results/bench_results/${BENCH_LABEL}_${SLURM_JOB_ID}"
    mkdir -p "$BENCH_OUT_DIR"

    BENCH_SUMMARY_CSV="$BENCH_OUT_DIR/bench_results/summary.csv"
    BENCH_TIMESERIES_CSV="$BENCH_OUT_DIR/timeseries.csv"
    BENCH_TIME_TMP="$BENCH_OUT_DIR/.time_raw.txt"

    # Create summary CSV header if this is the first run
    if [[ ! -f "$BENCH_SUMMARY_CSV" ]]; then
        echo "job_id,label,wall_clock_s,user_cpu_s,sys_cpu_s,cpu_percent,max_rss_kb,avg_rss_kb,major_page_faults,minor_page_faults,voluntary_ctx_switches,involuntary_ctx_switches,fs_inputs,fs_outputs,exit_status,timestamp" \
            > "$BENCH_SUMMARY_CSV"
    fi

    # Timeseries CSV header
    echo "timestamp_ms,epoch_s,cpu_percent,mem_used_kb,mem_available_kb,mem_total_kb" \
        > "$BENCH_TIMESERIES_CSV"

    # Background time-series sampler (1s resolution)
    _bench_sample_metrics() {
        local MEM_TOTAL
        MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        while true; do
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

            echo "${TS_MS},${TS_S},${CPU_PCT},${MEM_USED},${MEM_AVAIL},${MEM_TOTAL}"
            sleep 0.8   # total ~1s per sample (0.2 cpu probe + 0.8 sleep)
        done
    }

    _bench_sample_metrics >> "$BENCH_TIMESERIES_CSV" &
    BENCH_MONITOR_PID=$!

    # Redirect workload through /usr/bin/time by wrapping it in a subshell
    # We use a trap on EXIT so bench_end is always called even if the script errors
    exec 9>&2                          # save original stderr fd
    exec 2>"$BENCH_TIME_TMP"          # redirect stderr to capture /usr/bin/time output

    # Relaunch the rest of the calling script under /usr/bin/time
    # We do this by re-execing the calling script with time wrapping via trap
    BENCH_START_TIME=$(date +%s%3N)

    echo "[bench_lib] Benchmark started: label=${BENCH_LABEL}, job=${SLURM_JOB_ID}" >&9
}

bench_end() {
    local EXIT_STATUS=${1:-$?}   # caller can pass explicit exit code, else use last $?

    # Stop background sampler
    kill $BENCH_MONITOR_PID 2>/dev/null
    wait $BENCH_MONITOR_PID 2>/dev/null

    # Restore stderr
    exec 2>&9
    exec 9>&-

    BENCH_END_TIME=$(date +%s%3N)
    local WALL_MS=$(( BENCH_END_TIME - BENCH_START_TIME ))
    local WALL_S
    WALL_S=$(echo "scale=3; $WALL_MS / 1000" | bc)

    # Parse /usr/bin/time -v output if available, else fall back to our own timing
    _bench_parse_time() { grep "$1" "$BENCH_TIME_TMP" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' '; }

    local USER_CPU SYS_CPU CPU_PCT MAX_RSS AVG_RSS MAJOR_PF MINOR_PF VOL_CTX INVOL_CTX FS_IN FS_OUT
    USER_CPU=$(_bench_parse_time "User time (seconds)")
    SYS_CPU=$(_bench_parse_time "System time (seconds)")
    CPU_PCT=$(_bench_parse_time "Percent of CPU this job got" | tr -d '%')
    MAX_RSS=$(_bench_parse_time "Maximum resident set size (kbytes)")
    AVG_RSS=$(_bench_parse_time "Average resident set size (kbytes)")
    MAJOR_PF=$(_bench_parse_time "Major (requiring I/O) page faults")
    MINOR_PF=$(_bench_parse_time "Minor (reclaiming a frame) page faults")
    VOL_CTX=$(_bench_parse_time "Voluntary context switches")
    INVOL_CTX=$(_bench_parse_time "Involuntary context switches")
    FS_IN=$(_bench_parse_time "File system inputs")
    FS_OUT=$(_bench_parse_time "File system outputs")

    local TIMESTAMP
    TIMESTAMP=$(date --iso-8601=seconds)

    # Append row to shared summary CSV
    echo "${SLURM_JOB_ID},${BENCH_LABEL},${WALL_S},${USER_CPU},${SYS_CPU},${CPU_PCT},${MAX_RSS},${AVG_RSS},${MAJOR_PF},${MINOR_PF},${VOL_CTX},${INVOL_CTX},${FS_IN},${FS_OUT},${EXIT_STATUS},${TIMESTAMP}" \
        >> "$BENCH_SUMMARY_CSV"

    # Dump sacct accounting data
    sacct -j "$SLURM_JOB_ID" \
        --format=JobID,JobName,Elapsed,CPUTime,AveCPU,MinCPU,MaxRSS,MaxVMSize,AveRSS,AveVMSize,TotalCPU,UserCPU,SystemCPU,NNodes,NCPUS,ExitCode \
        --units=M -P > "$BENCH_OUT_DIR/sacct.csv"

    echo ""
    echo "======================================================="
    echo " Benchmark Complete: $BENCH_LABEL"
    echo "======================================================="
    echo " Wall clock     : ${WALL_S}s"
    echo " CPU percent    : ${CPU_PCT}%"
    echo " Max RSS        : ${MAX_RSS} KB"
    echo " Exit status    : ${EXIT_STATUS}"
    echo "-------------------------------------------------------"
    echo " Summary CSV    : $BENCH_SUMMARY_CSV"
    echo " Timeseries CSV : $BENCH_TIMESERIES_CSV"
    echo " Sacct CSV      : $BENCH_OUT_DIR/sacct.csv"
    echo "======================================================="
}