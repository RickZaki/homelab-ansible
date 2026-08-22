#!/usr/bin/env bash
# pct-df-metrics.sh — Collect mount point storage from running LXC containers.
# Outputs InfluxDB line protocol for Telegraf exec input.
#
# Metrics produced:
#   lxc_mountpoint,host=<pve_node>,vmid=<id>,path=<mount> total=<bytes>,used=<bytes>,avail=<bytes>

set -euo pipefail

HOSTNAME=$(hostname)

for VMID in $(sudo pct list 2>/dev/null | awk 'NR>1 && $2=="running" {print $1}'); do
  sudo pct df "$VMID" 2>/dev/null | awk -v vmid="$VMID" -v host="$HOSTNAME" '
    NR > 1 {
      path  = $7
      size  = $3
      used  = $4
      avail = $5

      # sudo pct df outputs sizes like 8.0G, 364.0M, 7.6G
      total_bytes = to_bytes(size)
      used_bytes  = to_bytes(used)
      avail_bytes = to_bytes(avail)

      if (total_bytes > 0) {
        # Escape spaces and commas in path for line protocol
        gsub(/[ ,]/, "\\ ", path)
        printf "lxc_mountpoint,host=%s,vmid=%s,path=%s total=%di,used=%di,avail=%di\n", \
          host, vmid, path, total_bytes, used_bytes, avail_bytes
      }
    }

    function to_bytes(s,    i, val, unit) {
      i = match(s, /[A-Za-z]/)
      if (i > 0) {
        val  = substr(s, 1, i - 1) + 0
        unit = substr(s, i)
      } else {
        return int(s + 0)
      }
      if (unit == "T") return int(val * 1099511627776)
      if (unit == "G") return int(val * 1073741824)
      if (unit == "M") return int(val * 1048576)
      if (unit == "K") return int(val * 1024)
      return int(val)
    }
  '
done
