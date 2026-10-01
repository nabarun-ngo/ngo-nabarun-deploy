#!/usr/bin/env python3
"""Tests for the develop/main release model."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import release_model


def plan(**overrides):
    payload = {
        "branch": "develop",
        "stable_branch": "main",
        "prerelease_branch": "develop",
        "prerelease_tag": "beta",
        "last_stable": "2.3.2",
        "merged_tags": ["2.3.2"],
        "commits": ["fix: correct validation"],
    }
    payload.update(overrides)
    return release_model.plan_release(payload)


class ReleaseModelTests(unittest.TestCase):
    def test_develop_patch_starts_at_beta_one(self) -> None:
        self.assertEqual("2.3.3-beta.1", plan()["version"])

    def test_second_patch_increments_beta(self) -> None:
        result = plan(
            merged_tags=["2.3.2", "2.3.3-beta.1"],
            commits=["fix: correct another validation"],
        )
        self.assertEqual("2.3.3-beta.2", result["version"])

    def test_minor_and_major_start_new_beta_lines(self) -> None:
        self.assertEqual("2.4.0-beta.1", plan(commits=["feat: add filtering"])["version"])
        self.assertEqual("3.0.0-beta.1", plan(commits=["feat!: replace public API"])["version"])

    def test_higher_bump_leaves_existing_patch_beta(self) -> None:
        result = plan(
            merged_tags=["2.3.2", "2.3.3-beta.2"],
            commits=["feat: add filtering"],
        )
        self.assertEqual("2.4.0-beta.1", result["version"])

    def test_non_release_commits_skip(self) -> None:
        result = plan(commits=["docs: update guide", "chore: tidy config", "ci: fix action"])
        self.assertEqual("skip", result["action"])

    def test_main_promotes_beta_without_adding_a_release(self) -> None:
        result = plan(
            branch="main",
            merged_tags=["2.3.2", "2.3.3-beta.2"],
            commits=["Merge pull request #10 from develop"],
        )
        self.assertEqual({"action": "release", "version": "2.3.3", "prerelease": False}, {
            "action": result["action"],
            "version": result["version"],
            "prerelease": result["prerelease"],
        })

    def test_main_hotfix_creates_next_stable(self) -> None:
        result = plan(
            branch="main",
            last_stable="2.3.3",
            merged_tags=["2.3.3", "2.3.3-beta.2"],
            commits=["fix: correct production validation"],
        )
        self.assertEqual("2.3.4", result["version"])
        self.assertFalse(result["prerelease"])

    def test_develop_cannot_create_stable_and_main_cannot_create_beta(self) -> None:
        with self.assertRaises(ValueError):
            plan(explicit_version="2.3.3")
        with self.assertRaises(ValueError):
            plan(branch="main", explicit_version="2.3.3-beta.1")

    def test_invalid_commit_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            plan(commits=["update validation"])

    def test_library_pr_requires_matching_changeset_bump(self) -> None:
        errors = release_model.validate_pull_request({
            "title": "feat: add filtering",
            "commits": ["feat: add filtering"],
            "packages_changed": True,
            "changesets": ['---\n"@example/pkg": patch\n---\n\nNotes\n'],
        })
        self.assertTrue(any("does not match" in error for error in errors))

    def test_maintenance_pr_cannot_declare_a_release(self) -> None:
        errors = release_model.validate_pull_request({
            "title": "chore: tidy build",
            "commits": ["chore: tidy build"],
            "packages_changed": True,
            "changesets": ['---\n"@example/pkg": patch\n---\n\nNotes\n'],
        })
        self.assertTrue(errors)

    def test_initial_prerelease_zero_becomes_one(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package.json"
            changelog = root / "CHANGELOG.md"
            package.write_text('{"name":"example","version":"2.3.3-beta.0"}\n', encoding="utf-8")
            changelog.write_text("## 2.3.3-beta.0\n\n- fix: correct validation\n", encoding="utf-8")
            release_model.shift_initial_prerelease(root, "beta")
            self.assertIn("2.3.3-beta.1", package.read_text(encoding="utf-8"))
            self.assertIn("2.3.3-beta.1", changelog.read_text(encoding="utf-8"))
            self.assertNotIn("beta.0", changelog.read_text(encoding="utf-8"))

    def test_apply_updates_version_and_changelog(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package.json"
            changelog = root / "CHANGELOG.md"
            subjects = root / "subjects.txt"
            package.write_text('{"name":"app","version":"2.3.2"}\n', encoding="utf-8")
            subjects.write_text("fix: correct validation\n", encoding="utf-8")
            release_model.main([
                "apply",
                "--version", "2.3.3-beta.1",
                "--version-file", str(package),
                "--changelog", str(changelog),
                "--subjects-file", str(subjects),
            ])
            self.assertIn('"version":"2.3.3-beta.1"', package.read_text(encoding="utf-8"))
            self.assertIn("## 2.3.3-beta.1", changelog.read_text(encoding="utf-8"))

    def test_library_versions_follow_the_branch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "package.json").write_text(
                '{"name":"@example/pkg","version":"2.3.3-beta.0"}\n',
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                release_model.assert_library_versions(root, prerelease=True, tag="beta")
            release_model.shift_initial_prerelease(root, "beta")
            release_model.assert_library_versions(root, prerelease=True, tag="beta")

    def test_cli_plan_is_stable_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            payload = Path(directory) / "payload.json"
            payload.write_text(json.dumps({
                "branch": "develop",
                "last_stable": "2.3.2",
                "merged_tags": ["2.3.2"],
                "commits": ["fix: correct validation"],
            }), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(0, release_model.main(["plan", str(payload)]))


if __name__ == "__main__":
    unittest.main()
