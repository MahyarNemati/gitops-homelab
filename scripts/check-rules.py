#!/usr/bin/env python3
"""Unwrap PrometheusRule objects and hand the rule groups to promtool.

PrometheusRule wraps the groups under .spec, which promtool does not
understand, so a bad expression would otherwise only fail at evaluation time
inside the cluster -- i.e. an alert that silently never fires.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path("manifests/monitoring/base/rules")
    files = sorted(root.glob("*.yaml"))
    if not files:
        print(f"error: no rule files found under {root}", file=sys.stderr)
        return 1

    failed = False
    for path in files:
        groups: list[dict] = []
        for doc in yaml.safe_load_all(path.read_text()):
            if not isinstance(doc, dict):
                continue
            spec = doc.get("spec", doc)
            groups.extend(spec.get("groups", []) or [])

        if not groups:
            print(f"FAIL {path}: no rule groups found")
            failed = True
            continue

        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as tmp:
            yaml.safe_dump({"groups": groups}, tmp, sort_keys=False)
            tmp_path = tmp.name

        result = subprocess.run(
            ["promtool", "check", "rules", tmp_path],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            failed = True
            print(f"FAIL {path}")
            print(result.stdout.strip())
            print(result.stderr.strip(), file=sys.stderr)
        else:
            rule_count = sum(len(g.get("rules", [])) for g in groups)
            print(f"ok   {path} ({len(groups)} groups, {rule_count} rules)")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
