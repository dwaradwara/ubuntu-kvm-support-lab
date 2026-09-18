#!/usr/bin/env python3
"""Controlled crash service for INC017.

Healthy by default. Set TRIGGER_CRASH=1 to deliberately invoke a native
segmentation fault through ctypes inside an isolated lab VM.
"""

import ctypes
import os
import sys
import time


def main() -> None:
    trigger = os.environ.get("TRIGGER_CRASH", "0")
    print(
        f"canonical-crash-demo started pid={os.getpid()} trigger_crash={trigger}",
        flush=True,
    )

    if trigger == "1":
        print("controlled failure injection: invoking native crash", flush=True)
        ctypes.string_at(0)

    while True:
        print("health=ok", flush=True)
        time.sleep(30)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
