#!/usr/bin/env bash

set -u

SSH_KEY="${SSH_KEY:-$HOME/.ssh/canonical-lab}"
OUT_ROOT="${OUT_ROOT:-$(pwd)/support-bundles}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BUNDLE_NAME="enterprise-support-${STAMP}"
BUNDLE_DIR="${OUT_ROOT}/${BUNDLE_NAME}"
ARCHIVE="${OUT_ROOT}/${BUNDLE_NAME}.tar.gz"

WEB_IP="${WEB_IP:-192.168.100.10}"
DB_IP="${DB_IP:-192.168.100.20}"
MON_IP="${MON_IP:-192.168.100.30}"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -i "$SSH_KEY"
)

mkdir -p \
  "$BUNDLE_DIR/host" \
  "$BUNDLE_DIR/web" \
  "$BUNDLE_DIR/db" \
  "$BUNDLE_DIR/monitor"

echo "Enterprise Support Bundle"
echo "Timestamp: $STAMP"
echo "Output:    $BUNDLE_DIR"
echo

collect_common() {
  local ip="$1"
  local output="$2"

  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" '
    echo "=== DATE ==="
    date -Is

    echo
    echo "=== HOSTNAME ==="
    hostname
    hostnamectl 2>/dev/null || true

    echo
    echo "=== UPTIME ==="
    uptime

    echo
    echo "=== KERNEL ==="
    uname -a

    echo
    echo "=== ADDRESSES ==="
    ip -br address

    echo
    echo "=== ROUTES ==="
    ip route

    echo
    echo "=== MEMORY ==="
    free -m

    echo
    echo "=== FILESYSTEMS ==="
    df -hT

    echo
    echo "=== FAILED SERVICES ==="
    systemctl --failed --no-pager || true

    echo
    echo "=== LISTENING SOCKETS ==="
    ss -lntup 2>/dev/null || ss -lntu
  ' > "$output" 2>&1
}

echo "[1/8] Collecting libvirt host state"

{
  echo "=== DATE ==="
  date -Is

  echo
  echo "=== VIRTUAL MACHINES ==="
  virsh -c qemu:///system list --all

  echo
  echo "=== LIBVIRT NETWORKS ==="
  virsh -c qemu:///system net-list --all

  echo
  echo "=== ENTERPRISE NETWORK ==="
  virsh -c qemu:///system net-info enterprise

  for vm in vm-web-01 vm-db-01 vm-monitor-01
  do
    echo
    echo "=== $vm INTERFACES ==="
    virsh -c qemu:///system domiflist "$vm"
  done
} > "$BUNDLE_DIR/host/libvirt.txt" 2>&1

echo "[2/8] Collecting web VM diagnostics"
collect_common "$WEB_IP" "$BUNDLE_DIR/web/system.txt"

ssh "${SSH_OPTS[@]}" "ubuntu@$WEB_IP" '
  echo "=== SERVICE STATE ==="
  for svc in nginx php8.1-fpm prometheus-node-exporter
  do
    printf "%-28s " "$svc"
    systemctl is-active "$svc" 2>/dev/null || true
  done

  echo
  echo "=== LOCAL APPLICATION HEALTH ==="
  curl -sS -i --max-time 5 http://127.0.0.1/db-health.php || true

  echo
  echo "=== NGINX CONFIG TEST ==="
  sudo -n nginx -t 2>&1 || nginx -t 2>&1 || true

  echo
  echo "=== RECENT NGINX LOGS ==="
  sudo -n journalctl -u nginx -n 50 --no-pager 2>/dev/null ||
    journalctl -u nginx -n 50 --no-pager 2>/dev/null || true

  echo
  echo "=== RECENT PHP-FPM LOGS ==="
  sudo -n journalctl -u php8.1-fpm -n 50 --no-pager 2>/dev/null ||
    journalctl -u php8.1-fpm -n 50 --no-pager 2>/dev/null || true
' > "$BUNDLE_DIR/web/application.txt" 2>&1

echo "[3/8] Collecting database VM diagnostics"
collect_common "$DB_IP" "$BUNDLE_DIR/db/system.txt"

ssh "${SSH_OPTS[@]}" "ubuntu@$DB_IP" '
  echo "=== SERVICE STATE ==="
  for svc in postgresql prometheus-node-exporter
  do
    printf "%-28s " "$svc"
    systemctl is-active "$svc" 2>/dev/null || true
  done

  echo
  echo "=== POSTGRESQL READINESS ==="
  pg_isready 2>&1 || true

  echo
  echo "=== POSTGRESQL BASIC QUERY ==="
  cd /tmp
  sudo -n -u postgres psql -Atqc \
    "SELECT current_database(), current_user, version();" 2>&1 || true

  echo
  echo "=== DATABASE FILESYSTEMS ==="
  df -hT
  echo
  df -hT /mnt/inc012-db 2>/dev/null || true

  echo
  echo "=== RECENT POSTGRESQL LOGS ==="
  sudo -n journalctl -u postgresql -n 75 --no-pager 2>/dev/null ||
    journalctl -u postgresql -n 75 --no-pager 2>/dev/null || true
' > "$BUNDLE_DIR/db/postgresql.txt" 2>&1

echo "[4/8] Collecting monitoring VM diagnostics"
collect_common "$MON_IP" "$BUNDLE_DIR/monitor/system.txt"

ssh "${SSH_OPTS[@]}" "ubuntu@$MON_IP" '
  echo "=== SERVICE STATE ==="
  for svc in prometheus prometheus-alertmanager prometheus-node-exporter
  do
    printf "%-28s " "$svc"
    systemctl is-active "$svc" 2>/dev/null || true
  done

  echo
  echo "=== PROMETHEUS HEALTH ==="
  curl -sS -i --max-time 5 http://127.0.0.1:9090/-/healthy || true

  echo
  echo "=== PROMETHEUS ACTIVE TARGETS ==="
  curl -sS --max-time 5 \
    "http://127.0.0.1:9090/api/v1/targets?state=active" || true

  echo
  echo
  echo "=== PROMETHEUS ALERTS ==="
  curl -sS --max-time 5 \
    "http://127.0.0.1:9090/api/v1/alerts" || true

  echo
  echo
  echo "=== ALERTMANAGER READINESS ==="
  curl -sS -i --max-time 5 http://127.0.0.1:9093/-/ready || true

  echo
  echo "=== ALERTMANAGER ACTIVE ALERTS ==="
  curl -sS --max-time 5 \
    "http://127.0.0.1:9093/api/v2/alerts" || true
' > "$BUNDLE_DIR/monitor/monitoring.txt" 2>&1

echo "[5/8] Running cross-VM health checks"

{
  echo "=== WEB APPLICATION ==="
  curl -sS -o /dev/null \
    -w "HTTP %{http_code}\n" \
    --max-time 5 \
    "http://${WEB_IP}/db-health.php" || true

  echo
  echo "=== PROMETHEUS ==="
  curl -sS -o /dev/null \
    -w "HTTP %{http_code}\n" \
    --max-time 5 \
    "http://${MON_IP}:9090/-/healthy" || true

  echo
  echo "=== ALERTMANAGER ==="
  curl -sS -o /dev/null \
    -w "HTTP %{http_code}\n" \
    --max-time 5 \
    "http://${MON_IP}:9093/-/ready" || true

  echo
  echo "=== SSH REACHABILITY ==="
  for ip in "$WEB_IP" "$DB_IP" "$MON_IP"
  do
    printf "%-18s " "$ip"

    if ssh "${SSH_OPTS[@]}" "ubuntu@$ip" \
      'printf "%s" "$(hostname)"' 2>/dev/null
    then
      echo " reachable"
    else
      echo " unreachable"
    fi
  done
} > "$BUNDLE_DIR/summary.txt" 2>&1

echo "[6/8] Writing manifest"

HTTP_OK=$(grep -c '^HTTP 200$' "$BUNDLE_DIR/summary.txt" || true)
SSH_OK=$(grep -c ' reachable$' "$BUNDLE_DIR/summary.txt" || true)

if [[ "$HTTP_OK" -eq 3 && "$SSH_OK" -eq 3 ]]; then
  BUNDLE_STATUS="PASS"
  EXIT_CODE=0
else
  BUNDLE_STATUS="WARN"
  EXIT_CODE=2
fi

{
  echo "bundle_name=$BUNDLE_NAME"
  echo "timestamp_utc=$STAMP"
  echo "git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "status=$BUNDLE_STATUS"
  echo "http_checks_ok=$HTTP_OK/3"
  echo "ssh_checks_ok=$SSH_OK/3"
  echo "web_vm=$WEB_IP"
  echo "db_vm=$DB_IP"
  echo "monitor_vm=$MON_IP"
} > "$BUNDLE_DIR/manifest.txt"

echo "collected_files:" >> "$BUNDLE_DIR/manifest.txt"

find "$BUNDLE_DIR"   -maxdepth 2   -type f   ! -name manifest.txt   -printf "%P\n"   | sort >> "$BUNDLE_DIR/manifest.txt"

echo "[7/8] Creating archive"

tar -C "$OUT_ROOT" \
  -czf "$ARCHIVE" \
  "$BUNDLE_NAME"

sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"

echo "[8/8] Complete"
echo
echo "Bundle directory:"
echo "$BUNDLE_DIR"
echo
echo "Archive:"
echo "$ARCHIVE"
echo
echo "SHA256:"
cat "${ARCHIVE}.sha256"

echo
echo "Bundle status: $BUNDLE_STATUS"

exit "$EXIT_CODE"
