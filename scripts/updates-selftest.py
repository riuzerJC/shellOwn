#!/usr/bin/env python3
"""Run the update detection self-test harness and report a real exit code.

quickshell cannot exit with a status of its own, so modules/updates/selftest.qml prints TAP output
and then terminates itself. This runner launches it, reads the TAP lines out of quickshell's logging
prefix, and exits 0 only when the harness reached its summary with every case passing.

Usage: python3 scripts/updates-selftest.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

HARNESS = Path(__file__).resolve().parent.parent / "modules" / "updates" / "selftest.qml"
TIMEOUT_SECONDS = 60
ANSI = re.compile(r"\x1b\[[0-9;]*m")
CASE = re.compile(r"^(ok|not ok) (\d+) - (.*)$")
PLAN = re.compile(r"^1\.\.(\d+)$")
SUMMARY = re.compile(r"^# (all (\d+) cases passed|(\d+) of (\d+) cases failed)$")


def tap_line(raw: str) -> str:
    """Strip quickshell's log prefix and colour codes from one output line."""
    line = ANSI.sub("", raw).rstrip("\n")
    marker = "qml: "
    if marker in line:
        line = line.split(marker, 1)[1]
    return line.strip()


def main() -> int:
    try:
        result = subprocess.run(
            ["quickshell", "-p", str(HARNESS)],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        print("updates-selftest: quickshell is not installed", file=sys.stderr)
        return 1
    except subprocess.TimeoutExpired:
        print(f"updates-selftest: the harness did not finish within {TIMEOUT_SECONDS}s", file=sys.stderr)
        return 1

    lines = [tap_line(line) for line in (result.stdout + result.stderr).splitlines()]
    cases = [line for line in lines if CASE.match(line)]
    planned = next((int(m.group(1)) for line in lines if (m := PLAN.match(line))), None)
    summary = next((m for line in lines if (m := SUMMARY.match(line))), None)

    for line in cases:
        print(line)

    if planned is None or summary is None:
        print("updates-selftest: the harness did not reach its summary; raw output follows", file=sys.stderr)
        for line in lines:
            if line and not line.startswith(("ok ", "not ok ")):
                print(line, file=sys.stderr)
        return 1

    failed = [line for line in cases if line.startswith("not ok ")]
    if len(cases) != planned:
        print(f"updates-selftest: expected {planned} cases but saw {len(cases)}", file=sys.stderr)
        return 1
    if failed or summary.group(3):
        print(f"updates-selftest: {len(failed)} of {planned} cases failed", file=sys.stderr)
        return 1

    print(f"updates-selftest: all {planned} cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
