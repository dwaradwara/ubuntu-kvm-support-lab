#!/usr/bin/env python3
"""Generate a KVM/libvirt VM status report and flag stopped guests."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

LIBVIRT_URI = os.environ.get("LIBVIRT_URI", "qemu:///system")


def run_cmd(args: list[str], check: bool = False) -> str:
    """Run a command safely and return combined stdout/stderr text."""
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    output = (result.stdout + result.stderr).strip()
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(args)}\n{output}")
    return output


def virsh(*args: str, check: bool = False) -> str:
    return run_cmd(["virsh", "-c", LIBVIRT_URI, *args], check=check)


def get_all_vms() -> list[str]:
    output = virsh("list", "--all", "--name", check=True)
    return [line.strip() for line in output.splitlines() if line.strip()]


def get_vm_details(name: str) -> dict[str, str]:
    return {
        "name": name,
        "state": virsh("domstate", name),
        "id": virsh("domid", name) or "N/A",
        "interfaces": virsh("domiflist", name),
        "disks": virsh("domblklist", name),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def check_network_health() -> dict[str, str]:
    return {
        "libvirt_networks": virsh("net-list", "--all"),
        "links": run_cmd(["ip", "-br", "link"]),
        "addresses": run_cmd(["ip", "-br", "addr"]),
    }


def generate_report(output_file: str | None = "/tmp/kvm_report.json") -> dict:
    report = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "host": run_cmd(["hostname"]),
        "libvirt_uri": LIBVIRT_URI,
        "kvm_modules": run_cmd(["sh", "-c", "lsmod | grep -E '^kvm| kvm' || true"]),
        "vms": [get_vm_details(vm) for vm in get_all_vms()],
        "network": check_network_health(),
        "storage_pools": virsh("pool-list", "--all"),
    }

    rendered = json.dumps(report, indent=2)
    if output_file:
        Path(output_file).write_text(rendered + "\n", encoding="utf-8")
        print(f"Report saved: {output_file}")
    else:
        print(rendered)

    return report


def alert_on_stopped_vms(report: dict) -> bool:
    stopped = [vm["name"] for vm in report["vms"] if vm["state"].strip() == "shut off"]
    for name in stopped:
        print(f"ALERT: VM {name} is shut off", file=sys.stderr)
    return bool(stopped)


def main() -> int:
    try:
        report = generate_report()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if alert_on_stopped_vms(report):
        return 1

    print(f"All {len(report['vms'])} VMs checked successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
