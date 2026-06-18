#!/bin/sh

set -eu

metric_value() {
  metric="$1"
  instance="$2"

  if [ -n "$instance" ]; then
    pminfo -f "$metric" 2>/dev/null | awk -v instance="$instance" '
      index($0, "\"" instance "\"") && /value / {
        print $NF
        exit
      }
    '
  else
    pminfo -f "$metric" 2>/dev/null | awk '/value / { print $NF; exit }'
  fi
}

round2() {
  awk -v value="${1:-0}" 'BEGIN { printf "%.2f", value + 0 }'
}

load_1m="$(metric_value kernel.all.load "1 minute")"
cpu_user="$(metric_value kernel.all.cpu.user "")"
mem_used="$(metric_value mem.util.used "")"
mem_cached="$(metric_value mem.util.cached "")"
mem_bufmem="$(metric_value mem.util.bufmem "")"
mem_total="$(metric_value mem.physmem "")"
disk_full="$(metric_value filesys.full "overlay")"
mem_app_used="$(awk -v used="${mem_used:-0}" -v cached="${mem_cached:-0}" -v buffers="${mem_bufmem:-0}" 'BEGIN { value = used - cached - buffers; if (value > 0) printf "%.2f", value; else printf "0.00" }')"
mem_used_pct="$(awk -v used="${mem_app_used:-0}" -v total="${mem_total:-0}" 'BEGIN { if (total > 0) printf "%.2f", (used / total) * 100; else printf "0.00" }')"

printf '{"load_1m":%s,"cpu_user":%s,"memory_used":%s,"memory_used_pct":%s,"disk_full_pct":%s}\n' \
  "$(round2 "$load_1m")" \
  "$(round2 "$cpu_user")" \
  "$(round2 "$mem_app_used")" \
  "$mem_used_pct" \
  "$(round2 "$disk_full")"
