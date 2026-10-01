#!/usr/bin/env python3
"""The release model inlined into workflows must match scripts/release_model.py."""

from __future__ import annotations

import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "scripts" / "release_model.py").read_text(encoding="utf-8").replace("\r\n", "\n").strip() + "\n"


def embedded_copies() -> list[tuple[str, str]]:
    copies = []
    marker = "<< 'END_RELEASE_MODEL'\n"
    for path in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
        text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        cursor = 0
        while True:
            start = text.find(marker, cursor)
            if start < 0:
                break
            body_start = start + len(marker)
            end = text.find("\nEND_RELEASE_MODEL\n", body_start)
            if end < 0:
                # The terminator is indented; dedent will expose it at column zero only after extraction.
                end = text.find("END_RELEASE_MODEL\n", body_start)
            body = text[body_start:end]
            copies.append((str(path.relative_to(ROOT)), textwrap.dedent(body).lstrip("\n")))
            cursor = end + 1
    return copies


class ReleaseModelEmbedTests(unittest.TestCase):
    def test_every_workflow_copy_matches_the_source_script(self) -> None:
        copies = embedded_copies()
        self.assertGreaterEqual(len(copies), 4)
        for name, copy in copies:
            self.assertEqual(SOURCE, copy.strip() + "\n", name)


if __name__ == "__main__":
    unittest.main()
