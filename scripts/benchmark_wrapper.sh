#!/bin/bash
# =============================================================================
# Benchmark Wrapper for Slurm
# Wraps any script with metrics collection: wall clock, CPU, memory, I/O.
# Outputs per-run timeseries CSV and appends a row to a shared summary CSV.
#
# Usage:
#   sbatch bench_wrapper.sh <label> <your_script.sh> [args...]
#
#   label       : a name to identify this run in the summary (e.g. "native",
#                 "apptainer", "podman" — whatever you want to call it)
#   your_script : the script you already have that runs your workload
#   args        : any arguments to pass through to your script
#
# Examples:
#   sbatch bench_wrapper.sh native       ./run_workload.sh
#   sbatch bench_wrapper.sh apptainer    ./run_apptainer.sh input.dat
#   sbatch bench_wrapper.sh podman       ./run_podman.sh input.dat
#   sbatch bench_wrapper.sh charliecloud ./run_charliecloud.sh input.dat
# =============================================================================
#SBATCH --output=./results/bench_results/slurm_%j.out

LABEL="${1}"
SCRIPT="${2}"
shift 2
EXTRA_ARGS=("$@")   # any remaining args are forwarded to your script

# ── Validate inputs ───────────────────────────────────────────────────────────
if [[ -z "$LABEL" || -z "$SCRIPT" ]]; then
    echo "Usage: sbatch $0 <label> <your_script.sh> [args...]"
    exit 1
fi

if [[ ! -f "$SCRIPT" ]]; then
    echo "Error: script not found: $SCRIPT"
    exit 1
fi

# ── Output paths ──────────────────────────────────────────────────────────────
OUT_DIR="./../results/bench_results/${LABEL}_${SLURM_JOB_ID}"
mkdir -p "$OUT_DIR"

SUMMARY_CSV="bench_results/summary.csv"
TIMESERIES_CSV="$OUT_DIR/timeseries.csv"
TIME_TMP="$OUT_DIR/.time_raw.txt"

# ── Create summary CSV header if this is the first run ───────────────────────
if [[ ! -f "$SUMMARY_CSV" ]]; then
    echo "job_id,label,script,extra_args,wall_clock_s,user_cpu_s,sys_cpu_s,cpu_percent,max_rss_kb,avg_rss_kb,major_page_faults,minor_page_faults,voluntary_ctx_switches,involuntary_ctx_switches,fs_inputs,fs_outputs,exit_status,timestamp" \
        > "$SUMMARY_CSV"
fi

# ── Timeseries CSV header ─────────────────────────────────────────────────────
echo "timestamp_ms,epoch_s,cpu_percent,mem_used_kb,mem_available_kb,mem_total_kb" \
    > "$TIMESERIES_CSV"

# ── Background time-series sampler (1s resolution) ───────────────────────────
_sample_metrics() {
    local MEM_TOTAL
    MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    while true; do
        local TS_MS TS_S CPU_PCT MEM_AVAIL MEM_USED
        TS_MS=$(date +%s%3N)
        TS_S=$(date +%s)

        # Two /proc/stat snapshots 200ms apart → accurate CPU %
        read -r _ c1 c2 c3 c4 c5 c6 c7 _ < /proc/stat
        CPU1=$((c1+c2+c3+c4+c5+c6+c7)); IDLE1=$c4
        sleep 0.2
        read -r _ d1 d2 d3 d4 d5 d6 d7 _ < /proc/stat
        CPU2=$((d1+d2+d3+d4+d5+d6+d7)); IDLE2=$d4

        DIFF_TOTAL=$((CPU2 - CPU1))
        DIFF_IDLE=$((IDLE2 - IDLE1))
        [[ $DIFF_TOTAL -gt 0 ]] \
            && CPU_PCT=$(( (DIFF_TOTAL - DIFF_IDLE) * 100 / DIFF_TOTAL )) \
            || CPU_PCT=0

        MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))

        echo "${TS_MS},${TS_S},${CPU_PCT},${MEM_USED},${MEM_AVAIL},${MEM_TOTAL}"
        sleep 0.8   # total ~1s per sample (0.2 cpu probe + 0.8 sleep)
    done
}

_sample_metrics >> "$TIMESERIES_CSV" &
MONITOR_PID=$!

# ── Run your script ───────────────────────────────────────────────────────────
/usr/bin/time -v bash "$SCRIPT" "${EXTRA_ARGS[@]}" 2>"$TIME_TMP"
EXIT_STATUS=$?

kill $MONITOR_PID 2>/dev/null
wait $MONITOR_PID 2>/dev/null

# ── Parse /usr/bin/time -v output ────────────────────────────────────────────
_parse_time() { grep "$1" "$TIME_TMP" | awk -F': ' '{print $2}' | tr -d ' '; }

WALL_RAW=$(_parse_time "Elapsed (wall clock) time")
USER_CPU=$(_parse_time "User time (seconds)")
SYS_CPU=$(_parse_time "System time (seconds)")
CPU_PCT=$(_parse_time "Percent of CPU this job got" | tr -d '%')
MAX_RSS=$(_parse_time "Maximum resident set size (kbytes)")
AVG_RSS=$(_parse_time "Average resident set size (kbytes)")
MAJOR_PF=$(_parse_time "Major (requiring I/O) page faults")
MINOR_PF=$(_parse_time "Minor (reclaiming a frame) page faults")
VOL_CTX=$(_parse_time "Voluntary context switches")
INVOL_CTX=$(_parse_time "Involuntary context switches")
FS_IN=$(_parse_time "File system inputs")
FS_OUT=$(_parse_time "File system outputs")

# Convert wall clock "h:mm:ss" or "m:ss.ms" → total seconds
_wall_to_seconds() {
    local raw="$1"
    if [[ "$raw" =~ ^([0-9]+):([0-9]+):([0-9]+\.[0-9]+)$ ]]; then
        echo "$(echo "${BASH_REMATCH[1]}*3600 + ${BASH_REMATCH[2]}*60 + ${BASH_REMATCH[3]}" | bc)"
    elif [[ "$raw" =~ ^([0-9]+):([0-9]+\.[0-9]+)$ ]]; then
        echo "$(echo "${BASH_REMATCH[1]}*60 + ${BASH_REMATCH[2]}" | bc)"
    else
        echo "$raw"
    fi
}

WALL_S=$(_wall_to_seconds "$WALL_RAW")
TIMESTAMP=$(date --iso-8601=seconds)
ARGS_STR="${EXTRA_ARGS[*]}"   # flatten args for CSV column

# ── Append row to shared summary CSV ─────────────────────────────────────────
echo "${SLURM_JOB_ID},${LABEL},${SCRIPT},\"${ARGS_STR}\",${WALL_S},${USER_CPU},${SYS_CPU},${CPU_PCT},${MAX_RSS},${AVG_RSS},${MAJOR_PF},${MINOR_PF},${VOL_CTX},${INVOL_CTX},${FS_IN},${FS_OUT},${EXIT_STATUS},${TIMESTAMP}" \
    >> "$SUMMARY_CSV"

# ── Dump sacct accounting data ────────────────────────────────────────────────
sacct -j "$SLURM_JOB_ID" \
    --format=JobID,JobName,Elapsed,CPUTime,AveCPU,MinCPU,MaxRSS,MaxVMSize,AveRSS,AveVMSize,TotalCPU,UserCPU,SystemCPU,NNodes,NCPUS,ExitCode \
    --units=M -P > "$OUT_DIR/sacct.csv"

# ── Print summary ─────────────────────────────────────────────────────────────
echo ""
echo "======================================================="
echo " Benchmark Complete: $LABEL"
echo "======================================================="
echo " Script         : $SCRIPT ${EXTRA_ARGS[*]}"
echo " Wall clock     : ${WALL_S}s"
echo " CPU percent    : ${CPU_PCT}%"
echo " Max RSS        : ${MAX_RSS} KB"
echo " Exit status    : ${EXIT_STATUS}"
echo "-------------------------------------------------------"
echo " Summary CSV    : $SUMMARY_CSV"
echo " Timeseries CSV : $TIMESERIES_CSV"
echo " Sacct CSV      : $OUT_DIR/sacct.csv"
echo " Raw time output: $TIME_TMP"
echo "======================================================="