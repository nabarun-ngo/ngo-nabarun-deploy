#!/usr/bin/env python3
"""Refresh inlined copies of scripts/release_model.py inside workflows."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "scripts" / "release_model.py").read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")
MARKER = "<< 'END_RELEASE_MODEL'\n"
TERMINATOR = "END_RELEASE_MODEL\n"

for path in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    cursor = 0
    updated = []
    count = 0
    while True:
        start = text.find(MARKER, cursor)
        if start < 0:
            updated.append(text[cursor:])
            break
        body_start = start + len(MARKER)
        end = text.find(TERMINATOR, body_start)
        if end < 0:
            raise SystemExit(f"{path.name}: unterminated release model")
        indent = " " * (len(text[text.rfind("\n", 0, end) + 1:end]))
        embedded = "\n".join(f"{indent}{line}" if line else "" for line in SOURCE.split("\n"))
        updated.append(text[cursor:body_start])
        updated.append(embedded + "\n")
        cursor = end
        count += 1
    if count:
        path.write_text("".join(updated), encoding="utf-8")
        print(f"{path.name}: refreshed {count}")
