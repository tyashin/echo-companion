#!/usr/bin/env bash
# Device-side metrics collector for the Phase 0.2 camera spike.
# Samples load, memory, the spike app's CPU ticks and thermal zones over adb
# while the app runs its 30-minute benchmark. Thermal zones under
# /sys/class/thermal are usually SELinux-blocked for the app itself but
# readable for the adb shell user.
#
# Usage: ./collect_device_metrics.sh [interval_s] [duration_s] [out.csv]
#   defaults: 1 s interval, 1800 s duration, device_metrics_<timestamp>.csv
set -u

INTERVAL="${1:-1}"
DURATION="${2:-1800}"
OUT="${3:-device_metrics_$(date +%Y%m%d_%H%M%S).csv}"
PKG="org.echo.camspike"
USER_HZ=100

if ! adb get-state >/dev/null 2>&1; then
  echo "error: no adb device connected" >&2
  exit 1
fi
PID="$(adb shell "pidof $PKG" | tr -d '\r' || true)"
if [ -z "$PID" ]; then
  echo "warning: $PKG not running yet; start the app, CPU column will be empty until found" >&2
fi

echo "thermal zones on device:"
adb shell 'for z in /sys/class/thermal/thermal_zone*; do
  printf "  %s = %s\n" "$z" "$(cat "$z/type" 2>/dev/null || echo unreadable)"
done' 2>/dev/null | tr -d '\r'

echo "elapsed_s,load1,mem_avail_mb,proc_cpu_pct,temp_max_c,temps_raw" > "$OUT"
echo "logging to $OUT (interval ${INTERVAL}s, duration ${DURATION}s)"

prev_ticks=-1
prev_time=-1
start=$(date +%s)
end=$((start + DURATION))
while [ "$(date +%s)" -lt "$end" ]; do
  now=$(date +%s)
  elapsed=$((now - start))
  if [ -z "$PID" ]; then
    PID="$(adb shell "pidof $PKG" | tr -d '\r' || true)"
  fi
  blob="$(adb shell "cat /proc/loadavg; grep MemAvailable /proc/meminfo; \
    cat /proc/$PID/stat 2>/dev/null; \
    grep -h '' /sys/class/thermal/thermal_zone*/temp 2>/dev/null" 2>/dev/null | tr -d '\r')"

  load1="$(printf '%s\n' "$blob" | awk 'NR==1 {print $1}')"
  mem_kb="$(printf '%s\n' "$blob" | awk '/MemAvailable/ {print $2}')"
  mem_mb="$([ -n "$mem_kb" ] && echo $((mem_kb / 1024)) || echo '')"

  # /proc/<pid>/stat: comm may contain spaces/parens; utime/stime are fields 14/15.
  ticks="$(printf '%s\n' "$blob" | awk '/\)/ {line=$0} END {
    sub(/^.*\) /, "", line); split(line, f, " "); print f[12] + f[13]}')"
  cpu_pct=""
  if [ -n "$ticks" ] && [ "$prev_ticks" -ge 0 ] && [ "$now" -gt "$prev_time" ]; then
    cpu_pct="$(awk "BEGIN {printf \"%.1f\", ($ticks - $prev_ticks) / $USER_HZ / ($now - $prev_time) * 100}")"
  fi
  [ -n "$ticks" ] && { prev_ticks="$ticks"; prev_time="$now"; }

  temps="$(printf '%s\n' "$blob" | awk -F: '/thermal_zone/ {gsub(/ /, "", $NF); print $NF}' \
    | paste -sd';' -)"
  temp_max="$(printf '%s\n' "$temps" | tr ';' '\n' | awk 'NF {t=$1/1000; if (t>m) m=t} END {
    if (m > 0) printf "%.1f", m}')"

  echo "$elapsed,$load1,$mem_mb,$cpu_pct,$temp_max,\"$temps\"" >> "$OUT"
  sleep "$INTERVAL"
done
echo "done -> $OUT"
