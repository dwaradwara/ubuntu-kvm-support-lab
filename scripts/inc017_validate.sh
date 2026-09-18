#!/usr/bin/env bash
set -euo pipefail

service="canonical-crash-demo.service"

echo "== service state =="
systemctl is-active "$service"
systemctl show "$service" -p ActiveState -p SubState -p MainPID -p Result

echo
echo "== recent journal =="
journalctl -u "$service" -n 10 --no-pager

echo
echo "== process =="
main_pid="$(systemctl show "$service" -p MainPID --value)"
if [[ "$main_pid" == "0" ]]; then
    echo "No running MainPID" >&2
    exit 1
fi
ps -p "$main_pid" -o pid,ppid,stat,etime,cmd
