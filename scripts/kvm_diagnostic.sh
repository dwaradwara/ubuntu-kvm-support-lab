#!/usr/bin/env bash
# kvm_diagnostic.sh
# KVM/libvirt environment diagnostic collection for support investigations.

set -u

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
LOGFILE="${1:-/tmp/kvm_diag_$(date +%Y%m%d_%H%M%S).txt}"
SEP="============================================================"

log() {
  printf '%s\n' "$1" | tee -a "$LOGFILE"
}

run_section() {
  local title="$1"
  shift
  log "$SEP"
  log "$title"
  "$@" 2>&1 | tee -a "$LOGFILE" || true
}

log "KVM DIAGNOSTIC REPORT"
log "Generated: $(date --iso-8601=seconds 2>/dev/null || date)"
log "Host: $(hostname)"
log "Libvirt URI: $LIBVIRT_URI"

run_section "SECTION 1: HOST / KVM MODULES" uname -a
if command -v lsmod >/dev/null 2>&1; then
  lsmod | grep -E '^kvm| kvm' | tee -a "$LOGFILE" || true
fi
if command -v kvm-ok >/dev/null 2>&1; then
  kvm-ok 2>&1 | tee -a "$LOGFILE" || true
fi

if command -v virsh >/dev/null 2>&1; then
  run_section "SECTION 2: VIRTUAL MACHINES" virsh -c "$LIBVIRT_URI" list --all
  run_section "SECTION 3: LIBVIRT NETWORKS" virsh -c "$LIBVIRT_URI" net-list --all
  run_section "SECTION 4: STORAGE POOLS" virsh -c "$LIBVIRT_URI" pool-list --all
else
  log "$SEP"
  log "virsh not found"
fi

log "$SEP"
log "SECTION 5: BRIDGES AND LINKS"
if command -v ip >/dev/null 2>&1; then
  ip -br link 2>&1 | tee -a "$LOGFILE" || true
  ip -br addr 2>&1 | tee -a "$LOGFILE" || true
fi
if command -v brctl >/dev/null 2>&1; then
  brctl show 2>&1 | tee -a "$LOGFILE" || true
fi

log "$SEP"
log "SECTION 6: RECENT LIBVIRT ERRORS/WARNINGS"
if command -v journalctl >/dev/null 2>&1; then
  journalctl --no-pager --since "1 hour ago" \
    -u libvirtd -u virtqemud -u virtnetworkd 2>/dev/null \
    | grep -iE 'error|warn|fail' \
    | tail -100 \
    | tee -a "$LOGFILE" || true
fi

for candidate in /var/log/libvirt/libvirtd.log /var/log/libvirt/qemu/*.log; do
  for file in $candidate; do
    [ -f "$file" ] || continue
    printf '\n--- %s ---\n' "$file" | tee -a "$LOGFILE"
    tail -100 "$file" 2>/dev/null \
      | grep -iE 'error|warn|fail' \
      | tee -a "$LOGFILE" || true
  done
done

log "$SEP"
log "Report saved: $LOGFILE"
