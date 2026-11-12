#!/usr/bin/env python3
"""Render bats JUnit reports as a Markdown table for the Actions run summary."""
import sys
import xml.etree.ElementTree as ET


def main(paths):
    rows, failed = [], 0
    for path in paths:
        for case in ET.parse(path).getroot().iter("testcase"):
            bad = case.find("failure") is not None or case.find("error") is not None
            skipped = case.find("skipped") is not None
            failed += bad
            mark = "❌ fail" if bad else ("⏭ skipped" if skipped else "✅ pass")
            rows.append(f"| {mark} | {case.get('name')} | {float(case.get('time') or 0):.1f}s |")
    print("### e2e Guardrail results\n")
    if not rows:
        print("_No test cases found._")
        return 1
    print("| result | test | time |\n|---|---|---|")
    print("\n".join(rows))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
