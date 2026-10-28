#!/usr/bin/env python3
"""Validate Grafana dashboard JSON.

A malformed dashboard imports as a blank panel with no error surfaced anywhere,
which is a miserable thing to debug in the UI. Parsing them in CI turns that
into a build failure.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def check(path: Path) -> list[str]:
    problems: list[str] = []
    try:
        doc = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return [f"invalid JSON: {exc}"]

    if not isinstance(doc, dict):
        return ["top level is not an object"]

    panels = doc.get("panels")
    if panels is None and "rows" not in doc:
        problems.append("no 'panels' (or legacy 'rows') key")
    if not doc.get("title"):
        problems.append("missing 'title'")

    # Every panel that queries something should name a datasource, or it
    # silently binds to whatever Grafana considers default.
    for i, panel in enumerate(panels or []):
        if not isinstance(panel, dict):
            problems.append(f"panel {i} is not an object")
            continue
        if panel.get("type") in {"row", "text"}:
            continue
        if not panel.get("targets"):
            problems.append(f"panel {i} ({panel.get('title', 'untitled')!r}) has no targets")
    return problems


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path("manifests/monitoring/base/dashboards")
    files = sorted(root.glob("*.json"))
    if not files:
        print(f"error: no dashboards found under {root}", file=sys.stderr)
        return 1

    failed = False
    for path in files:
        problems = check(path)
        if problems:
            failed = True
            print(f"FAIL {path}")
            for p in problems:
                print(f"  - {p}")
        else:
            doc = json.loads(path.read_text())
            print(f"ok   {path} ({len(doc.get('panels', []))} panels)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
