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
