#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /opt/canonical-gap-lab
install -m 0755 "$(dirname "$0")/inc017_crash_service.py" /opt/canonical-gap-lab/inc017_crash_service.py

cat >/etc/default/canonical-crash-demo <<'EOF'
TRIGGER_CRASH=0
EOF

cat >/etc/systemd/system/canonical-crash-demo.service <<'EOF'
[Unit]
Description=Canonical gap lab controlled crash demo
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/default/canonical-crash-demo
ExecStart=/usr/bin/python3 /opt/canonical-gap-lab/inc017_crash_service.py
Restart=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now canonical-crash-demo.service

echo "Installed canonical-crash-demo.service with TRIGGER_CRASH=0"
echo "Run: systemctl status canonical-crash-demo.service --no-pager"
