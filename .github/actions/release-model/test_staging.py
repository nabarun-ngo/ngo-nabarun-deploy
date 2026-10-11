#!/usr/bin/env python3
"""Verify legacy callers stage release_model.py from its action directory."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github" / "workflows"
STAGE_COMMAND = re.compile(
    r"cp (ext_repo|platform)/\.github/actions/release-model/release_model\.py "
    r'"\$RUNNER_TEMP/release-model/release_model\.py"'
)
EXPECTED_STAGING = {
    "reusable-ci-changeset-check.yml": ["ext_repo"],
    "reusable-ci-commit-check.yml": ["ext_repo"],
    "reusable-ci-npm-publish.yml": ["platform", "platform"],
    "reusable-ci-tag-release.yml": ["platform"],
}


def staged_sources() -> dict[str, list[str]]:
    staged: dict[str, list[str]] = {}
    for path in sorted(WORKFLOWS.glob("*.yml")):
        matches = STAGE_COMMAND.findall(path.read_text(encoding="utf-8"))
        if matches:
            staged[path.name] = matches
    return staged


class ReleaseModelStagingTests(unittest.TestCase):
    def test_workflows_stage_release_model_from_expected_checkout(self) -> None:
        self.assertEqual(EXPECTED_STAGING, staged_sources())

    def test_legacy_release_paths_remain_compatible(self) -> None:
        pairs = (
            (
                ROOT / "scripts" / "release_model.py",
                ROOT / ".github" / "actions" / "release-model" / "release_model.py",
            ),
            (
                ROOT / ".github" / "actions" / "create-tag-release" / "create-tag-release.py",
                ROOT / ".github" / "actions" / "release-model" / "create-tag-release.py",
            ),
        )
        for legacy, current in pairs:
            with self.subTest(path=legacy.relative_to(ROOT)):
                self.assertEqual(
                    current.read_bytes(),
                    legacy.read_bytes(),
                    f"{legacy.relative_to(ROOT)} must mirror the relocated implementation",
                )

    def test_legacy_embedded_copies_are_not_used(self) -> None:
        for path in sorted(WORKFLOWS.glob("*.yml")):
            with self.subTest(workflow=path.name):
                text = path.read_text(encoding="utf-8")
                self.assertNotIn("END_RELEASE_MODEL", text)


if __name__ == "__main__":
    unittest.main()
