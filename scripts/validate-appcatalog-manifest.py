#!/usr/bin/env python3
"""Validate the Apps & TUIs catalog manifest contract.

This is intentionally lightweight: it mirrors the QML Catalog service manifest
contract without adding a QML test harness or external dependencies.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


VALID_TYPES = {"gui", "tui", "cli"}


def string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if item is not None]


def command_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value if item is not None]
    if isinstance(value, str) and value.strip():
        return value.split()
    return []


def load_entries(path: Path) -> tuple[list[dict[str, Any]], list[str], str | None]:
    try:
        parsed = json.loads(path.read_text())
    except OSError as exc:
        return [], [], f"failed to read {path}: {exc}"
    except json.JSONDecodeError as exc:
        return [], [], f"failed to parse {path}: {exc}"

    raw_entries = parsed if isinstance(parsed, list) else parsed.get("entries") if isinstance(parsed, dict) else None
    if not isinstance(raw_entries, list):
        return [], [], f"invalid {path}: expected an `entries` array"

    valid: list[dict[str, Any]] = []
    invalid: list[str] = []
    for index, raw in enumerate(raw_entries):
        error = validate_entry(raw)
        if error:
            invalid.append(f"entry {index}: {error}")
        else:
            valid.append(raw)

    return valid, invalid, None


def validate_entry(raw: Any) -> str | None:
    if not isinstance(raw, dict):
        return "entry must be an object"

    entry_type = str(raw.get("type", "")).lower()
    if not raw.get("id") or not raw.get("name") or not raw.get("description"):
        return "missing id, name, or description"
    if entry_type not in VALID_TYPES:
        return f"unsupported type: {raw.get('type')}"
    if not any(raw.get(field) for field in ("desktopId", "binary", "command", "packages", "examples")):
        return "missing launch or metadata field"

    # Exercise normalisation-compatible fields to keep the contract aligned with QML.
    string_list(raw.get("tags"))
    command_list(raw.get("command"))
    packages = raw.get("packages") if isinstance(raw.get("packages"), dict) else {}
    string_list(packages.get("arch"))
    string_list(packages.get("nixos"))
    string_list(raw.get("examples"))
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="Manifest to validate")
    parser.add_argument("--fallback", type=Path, help="Bundled fallback manifest for user-manifest failure simulation")
    args = parser.parse_args()

    valid, invalid, root_error = load_entries(args.manifest)
    if root_error and args.fallback:
        fallback_valid, fallback_invalid, fallback_error = load_entries(args.fallback)
        if fallback_error:
            print(f"ERROR: {root_error}; fallback also failed: {fallback_error}", file=sys.stderr)
            return 1
        if fallback_invalid:
            print(f"ERROR: {root_error}; fallback has invalid entries: {fallback_invalid}", file=sys.stderr)
            return 1
        print(f"WARNING: {root_error}; fallback valid with {len(fallback_valid)} entries")
        return 0

    if root_error:
        print(f"ERROR: {root_error}", file=sys.stderr)
        return 1
    if invalid:
        print(f"ERROR: invalid entries: {invalid}", file=sys.stderr)
        return 1

    print(f"OK: {args.manifest} has {len(valid)} valid entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
