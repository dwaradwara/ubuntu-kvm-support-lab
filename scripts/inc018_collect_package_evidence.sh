#!/usr/bin/env bash
set -euo pipefail

echo "== host =="
if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -ds
else
    awk -F= '$1 == "PRETTY_NAME" {gsub(/^"|"$/, "", $2); print $2}' /etc/os-release
fi
uname -a

echo
echo "== package =="
dpkg-query -W -f='Package: ${Package}\nVersion: ${Version}\nStatus: ${Status}\n' support-demo 2>/dev/null || true
apt-cache policy support-demo || true

echo
echo "== dpkg history =="
grep -F 'support-demo' /var/log/dpkg.log 2>/dev/null | tail -n 20 || true

echo
echo "== service state =="
systemctl status support-demo.service --no-pager || true

echo
echo "== recent service journal =="
journalctl -u support-demo.service -n 80 --no-pager || true

echo
echo "== listening socket =="
ss -ltnp | grep ':18080' || true

echo
echo "== health request =="
curl -sv --max-time 3 http://127.0.0.1:18080/health 2>&1 || true
