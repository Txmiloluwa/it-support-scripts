#!/usr/bin/env bash
#
# system_health.sh - quick health report for a Linux or macOS machine.
#
# Shows OS, uptime, CPU load, memory, disk usage and the busiest processes,
# and flags anything above a warning threshold. Useful as the first step when
# a user reports "my computer is slow".
#
# Usage: ./system_health.sh [--disk-warn PERCENT]   (default warning: 85%)

set -euo pipefail

DISK_WARN=85
WARNINGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk-warn)
      DISK_WARN="${2:?--disk-warn needs a number}"
      shift 2
      ;;
    -h|--help)
      sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 2
      ;;
  esac
done

if ! [[ "$DISK_WARN" =~ ^[0-9]+$ ]] || (( DISK_WARN < 1 || DISK_WARN > 100 )); then
  echo "--disk-warn must be a whole number between 1 and 100" >&2
  exit 2
fi

OS="$(uname -s)"

section() { printf '\n== %s ==\n' "$1"; }
warn() { printf '  [WARNING] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }

echo "System health report for $(hostname)"
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"

section "Operating system"
if [[ "$OS" == "Darwin" ]]; then
  echo "  macOS $(sw_vers -productVersion)"
elif [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "  ${PRETTY_NAME:-Linux}"
else
  echo "  $OS"
fi
echo "  Kernel: $(uname -r)"
echo "  Uptime: $(uptime | sed 's/.*up \([^,]*\),.*/\1/')"

section "CPU"
if [[ "$OS" == "Darwin" ]]; then
  CORES="$(sysctl -n hw.ncpu)"
else
  CORES="$(nproc)"
fi
LOAD="$(uptime | awk -F'load averages?: ' '{print $2}' | awk -F'[, ]+' '{print $1}')"
echo "  Cores: $CORES"
echo "  Load (1 min average): $LOAD"
# A load higher than the number of cores means processes are queuing for CPU.
if awk -v l="$LOAD" -v c="$CORES" 'BEGIN { exit !(l > c) }'; then
  warn "CPU load ($LOAD) is higher than the number of cores ($CORES)"
fi

section "Memory"
if [[ "$OS" == "Darwin" ]]; then
  TOTAL_MB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
  PAGE_SIZE="$(sysctl -n hw.pagesize)"
  FREE_PAGES="$(vm_stat | awk '/Pages free|Pages inactive/ {gsub(/\./, "", $NF); sum += $NF} END {print sum}')"
  AVAILABLE_MB=$(( FREE_PAGES * PAGE_SIZE / 1024 / 1024 ))
else
  TOTAL_MB="$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"
  AVAILABLE_MB="$(awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo)"
fi
USED_PCT=$(( (TOTAL_MB - AVAILABLE_MB) * 100 / TOTAL_MB ))
echo "  Total: ${TOTAL_MB} MB | Available: ${AVAILABLE_MB} MB | Used: ${USED_PCT}%"
if (( USED_PCT > 90 )); then
  warn "Memory usage is above 90%"
fi

section "Disk usage (warning above ${DISK_WARN}%)"
# -P gives one line per filesystem, so the columns are predictable.
while read -r filesystem size used avail pct mount; do
  usage="${pct%\%}"
  printf '  %-25s %6s used of %6s (%s)\n' "$mount" "$used" "$size" "$pct"
  if (( usage >= DISK_WARN )); then
    warn "$mount is ${pct} full (filesystem $filesystem, $avail free)"
  fi
done < <(df -hP | awk 'NR > 1 && $1 !~ /^(tmpfs|devfs|devtmpfs|overlay|map|none)/')

section "Top 5 processes by CPU"
if [[ "$OS" == "Darwin" ]]; then
  ps -Ao pid,pcpu,pmem,comm -r | head -6 | sed 's/^/  /'
else
  ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -6 | sed 's/^/  /'
fi

section "Summary"
if (( WARNINGS == 0 )); then
  echo "  OK: no problems found"
else
  echo "  $WARNINGS warning(s) found, see above"
fi
