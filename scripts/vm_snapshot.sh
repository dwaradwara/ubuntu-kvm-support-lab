#!/usr/bin/env bash
# vm_snapshot.sh
# Manage libvirt VM snapshots: create, list, restore, delete.

set -euo pipefail

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
VM="${1:-}"
ACTION="${2:-list}"
NAME="${3:-}"

usage() {
  echo "Usage: $0 <vm> [create|list|restore|delete] [snapshot-name]"
  echo "Environment: LIBVIRT_URI defaults to qemu:///system"
}

[ -n "$VM" ] || { usage; exit 1; }
command -v virsh >/dev/null 2>&1 || { echo "ERROR: virsh not found" >&2; exit 1; }

if ! virsh -c "$LIBVIRT_URI" dominfo "$VM" >/dev/null 2>&1; then
  echo "ERROR: VM '$VM' not found on $LIBVIRT_URI" >&2
  exit 1
fi

case "$ACTION" in
  create)
    NAME="${NAME:-snap_$(date +%Y%m%d_%H%M%S)}"
    virsh -c "$LIBVIRT_URI" snapshot-create-as \
      "$VM" \
      --name "$NAME" \
      --description "Created $(date --iso-8601=seconds 2>/dev/null || date)"
    echo "Snapshot created: $NAME"
    ;;

  list)
    virsh -c "$LIBVIRT_URI" snapshot-list "$VM"
    ;;

  restore)
    [ -n "$NAME" ] || { echo "ERROR: restore requires a snapshot name" >&2; usage; exit 1; }
    virsh -c "$LIBVIRT_URI" snapshot-info "$VM" "$NAME" >/dev/null
    virsh -c "$LIBVIRT_URI" snapshot-revert "$VM" "$NAME"
    echo "Restored '$VM' to snapshot: $NAME"
    ;;

  delete)
    [ -n "$NAME" ] || { echo "ERROR: delete requires a snapshot name" >&2; usage; exit 1; }
    virsh -c "$LIBVIRT_URI" snapshot-info "$VM" "$NAME" >/dev/null
    virsh -c "$LIBVIRT_URI" snapshot-delete "$VM" "$NAME"
    echo "Deleted snapshot: $NAME"
    ;;

  *)
    echo "ERROR: unknown action '$ACTION'" >&2
    usage
    exit 1
    ;;
esac
