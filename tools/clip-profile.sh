#!/usr/bin/env bash
#
# clip-profile.sh — pin Clip's process and sample its resource usage.
#
# Phase 6 performance harness. Run this in Terminal while you use Clip; it
# samples CPU, memory, threads, and energy-relevant counters once a second and
# writes a CSV + a printed summary you can paste back.
#
# Usage:
#   ./clip-profile.sh                 # auto-finds Clip, samples until Ctrl-C
#   ./clip-profile.sh 60              # sample for 60 seconds then stop
#   ./clip-profile.sh 60 idle         # label the run "idle" (for the report)
#
# Tip: run one labeled pass per scenario, e.g.
#   ./clip-profile.sh 30 idle         # do nothing
#   ./clip-profile.sh 30 popup        # open the popup, scroll, search
#   ./clip-profile.sh 30 capture      # copy text/images, take screenshots
#
set -euo pipefail

DURATION="${1:-0}"          # 0 = until Ctrl-C
LABEL="${2:-run}"
INTERVAL=1                  # seconds between samples
OUT="clip-profile-${LABEL}-$(date +%Y%m%d-%H%M%S).csv"

# --- find Clip's PID (the app binary, not the helper/debugger) ---------------
PID="$(pgrep -f 'Clip.app/Contents/MacOS/Clip' | head -1 || true)"
if [[ -z "${PID}" ]]; then
  echo "Clip is not running. Launch it first, then re-run this script." >&2
  exit 1
fi
echo "Profiling Clip  pid=${PID}  label=${LABEL}  interval=${INTERVAL}s"
echo "Writing samples to: ${OUT}"
echo "(press Ctrl-C to stop early)"
echo

echo "elapsed_s,cpu_pct,rss_mb,threads,ports" > "${OUT}"

start=$(date +%s)
cpu_sum=0; cpu_n=0; cpu_max=0
rss_sum=0; rss_n=0; rss_max=0

cleanup() {
  echo
  echo "================ SUMMARY ($LABEL) ================"
  if [[ "$cpu_n" -gt 0 ]]; then
    awk -v s="$cpu_sum" -v n="$cpu_n" -v m="$cpu_max" \
      'BEGIN{printf "CPU %%   : avg %.2f   max %.2f\n", s/n, m}'
    awk -v s="$rss_sum" -v n="$rss_n" -v m="$rss_max" \
      'BEGIN{printf "Memory  : avg %.1f MB   max %.1f MB\n", s/n, m}'
    echo "Samples : $cpu_n over $(( $(date +%s) - start ))s"
  else
    echo "No samples captured (did Clip exit?)."
  fi
  echo "CSV     : ${OUT}"
  echo "================================================="
  echo "Paste the SUMMARY block (and the label) back to continue the report."
  exit 0
}
trap cleanup INT TERM

while true; do
  # ps gives %CPU and RSS(KB); thread + mach-port counts approximate energy load.
  read -r cpu rsskb <<<"$(ps -o %cpu=,rss= -p "${PID}" 2>/dev/null | awk '{print $1, $2}')"
  if [[ -z "${cpu:-}" ]]; then
    echo "Clip (pid ${PID}) exited."; cleanup
  fi
  threads="$(ps -M -p "${PID}" 2>/dev/null | grep -c . || echo 0)"
  ports="$(lsof -p "${PID}" 2>/dev/null | wc -l | tr -d ' ')"
  rssmb="$(awk -v k="$rsskb" 'BEGIN{printf "%.1f", k/1024}')"
  elapsed=$(( $(date +%s) - start ))

  echo "${elapsed},${cpu},${rssmb},${threads},${ports}" >> "${OUT}"
  printf "\r t=%3ds  cpu=%5s%%  rss=%6s MB  threads=%s   " "$elapsed" "$cpu" "$rssmb" "$threads"

  cpu_sum=$(awk -v a="$cpu_sum" -v b="$cpu" 'BEGIN{print a+b}')
  cpu_n=$((cpu_n+1))
  cpu_max=$(awk -v a="$cpu_max" -v b="$cpu" 'BEGIN{print (b>a)?b:a}')
  rss_sum=$(awk -v a="$rss_sum" -v b="$rssmb" 'BEGIN{print a+b}')
  rss_n=$((rss_n+1))
  rss_max=$(awk -v a="$rss_max" -v b="$rssmb" 'BEGIN{print (b>a)?b:a}')

  if [[ "$DURATION" -gt 0 && "$elapsed" -ge "$DURATION" ]]; then cleanup; fi
  sleep "$INTERVAL"
done
