#!/usr/bin/env bash
# ubuntu_health.sh
# Quick Ubuntu system-health assessment for support investigations.

set -u

printf '=== UBUNTU SYSTEM HEALTH CHECK ===\n'
printf 'Date: %s | Host: %s\n\n' "$(date --iso-8601=seconds 2>/dev/null || date)" "$(hostname)"

printf '%s\n' '--- OS / Kernel ---'
if [ -r /etc/os-release ]; then
  grep -E '^(NAME|VERSION|PRETTY_NAME)=' /etc/os-release || true
fi
uname -r
printf '\n'

printf '%s\n' '--- Failed Services ---'
systemctl --failed --no-pager 2>&1 || true
printf '\n'

printf '%s\n' '--- Disk Usage >= 80% ---'
df -hP | awk 'NR==1 {print; next} {gsub(/%/,"",$5); if ($5+0 >= 80) print}'
printf '\n'

printf '%s\n' '--- Inode Usage >= 80% ---'
df -iP | awk 'NR==1 {print; next} {gsub(/%/,"",$5); if ($5+0 >= 80) print}'
printf '\n'

printf '%s\n' '--- Memory / Swap ---'
free -h
printf '\n'

printf '%s\n' '--- Load / Uptime ---'
uptime
printf '\n'

printf '%s\n' '--- Kernel Errors (last 24h) ---'
journalctl -k -p err --since "24 hours ago" --no-pager 2>&1 | tail -20 || true
printf '\n'

printf '%s\n' '--- Top CPU Processes ---'
ps aux --sort=-%cpu | head -6
printf '\n'

printf '%s\n' '--- Top Memory Processes ---'
ps aux --sort=-%mem | head -6
printf '\n'

printf '%s\n' '--- Listening TCP/UDP Ports ---'
ss -tulnp 2>&1 || true
