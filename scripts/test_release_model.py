#!/usr/bin/env python3
"""Tests for the develop/main release model."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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
        result = release_model.validate_pull_request({
            "title": "feat: add filtering",
            "commits": ["feat: add filtering"],
            "packages_changed": True,
            "changesets": ['---\n"@example/pkg": patch\n---\n\nNotes\n'],
        })
        self.assertTrue(any("does not match" in error for error in result["errors"]))

    def test_maintenance_pr_cannot_declare_a_release(self) -> None:
        result = release_model.validate_pull_request({
            "title": "chore: tidy build",
            "commits": ["chore: tidy build"],
            "packages_changed": True,
            "changesets": ['---\n"@example/pkg": patch\n---\n\nNotes\n'],
        })
        self.assertTrue(result["errors"])

    def test_invalid_individual_commit_warns_but_does_not_block(self) -> None:
        # The PR title is a conventional commit, so this only has one bad
        # individual commit message (e.g. a "wip" commit before cleanup).
        # That must be a warning, not an error: it should not block merge.
        result = release_model.validate_pull_request({
            "title": "fix: correct validation",
            "commits": ["fix: correct validation", "wip", "address review comments"],
            "packages_changed": False,
            "skip_changeset": True,
        })
        self.assertEqual([], result["errors"])
        self.assertTrue(any("wip" in warning for warning in result["warnings"]))
        self.assertTrue(any("address review comments" in warning for warning in result["warnings"]))

    def test_invalid_pull_request_title_still_blocks(self) -> None:
        result = release_model.validate_pull_request({
            "title": "update stuff",
            "commits": ["update stuff"],
            "packages_changed": False,
            "skip_changeset": True,
        })
        self.assertTrue(any("conventional commit" in error for error in result["errors"]))

    def test_report_pull_request_findings_warnings_do_not_fail(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()) as out:
            exit_code = release_model.report_pull_request_findings(
                {"errors": [], "warnings": ["Invalid commit title: wip"]}
            )
        self.assertEqual(0, exit_code)
        self.assertIn("::warning::Invalid commit title: wip", out.getvalue())

    def test_report_pull_request_findings_errors_fail(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            exit_code = release_model.report_pull_request_findings(
                {"errors": ["Pull request title must be a conventional commit."], "warnings": []}
            )
        self.assertEqual(1, exit_code)

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

    def test_parse_commit_log_splits_on_unit_separator(self) -> None:
        blob = "fix: a\x1f\nfeat: b\n\x1f\n\x1f"
        self.assertEqual(["fix: a", "feat: b"], release_model.parse_commit_log(blob))

    def test_read_changesets_skips_readme(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            changeset_dir = root / ".changeset"
            changeset_dir.mkdir()
            (changeset_dir / "README.md").write_text("ignored", encoding="utf-8")
            (changeset_dir / "bump.md").write_text(
                '---\n"@example/pkg": patch\n---\n', encoding="utf-8"
            )
            contents = release_model.read_changesets(str(root))
            self.assertEqual(1, len(contents))
            self.assertIn("patch", contents[0])

    def test_read_changesets_missing_directory_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual([], release_model.read_changesets(directory))

    def test_check_pull_request_defaults_skip_changeset_like_commit_check(self) -> None:
        # reusable-ci-commit-check.yml leaves SKIP_CHANGESET/PACKAGES_CHANGED/
        # WORKING_DIRECTORY unset; defaults must reproduce its narrower,
        # title-only check.
        env = {"BASE_REF": "main", "PR_TITLE": "chore: tidy build"}
        with mock.patch.object(release_model, "commits_since", return_value=["chore: tidy build"]):
            with mock.patch.dict("os.environ", env, clear=True):
                result = release_model.check_pull_request_from_env()
                self.assertEqual({"errors": [], "warnings": []}, result)

    def test_check_pull_request_rejects_invalid_title_by_default(self) -> None:
        env = {"BASE_REF": "main", "PR_TITLE": "update stuff"}
        with mock.patch.object(release_model, "commits_since", return_value=[]):
            with mock.patch.dict("os.environ", env, clear=True):
                result = release_model.check_pull_request_from_env()
                self.assertTrue(any("conventional commit" in error for error in result["errors"]))

    def test_check_pull_request_warns_on_invalid_individual_commit(self) -> None:
        # Matches reusable-ci-commit-check.yml's defaults: valid title, one
        # messy individual commit. Must warn, not fail.
        env = {"BASE_REF": "main", "PR_TITLE": "fix: correct validation"}
        with mock.patch.object(
            release_model, "commits_since", return_value=["fix: correct validation", "wip"]
        ):
            with mock.patch.dict("os.environ", env, clear=True):
                result = release_model.check_pull_request_from_env()
                self.assertEqual([], result["errors"])
                self.assertTrue(any("wip" in warning for warning in result["warnings"]))

    def test_check_pull_request_enforces_changeset_bump_when_not_skipped(self) -> None:
        env = {
            "BASE_REF": "main",
            "PR_TITLE": "feat: add filtering",
            "SKIP_CHANGESET": "false",
            "PACKAGES_CHANGED": "true",
        }
        with mock.patch.object(release_model, "commits_since", return_value=["feat: add filtering"]):
            with mock.patch.object(release_model, "read_changesets", return_value=[]):
                with mock.patch.dict("os.environ", env, clear=True):
                    result = release_model.check_pull_request_from_env()
                    self.assertTrue(any("changeset" in error for error in result["errors"]))

    def test_skip_if_already_published_true_without_public_packages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(release_model.skip_if_already_published(Path(directory)))

    def test_skip_if_already_published_reflects_npm_view(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "package.json").write_text(
                '{"name":"example","version":"1.0.0"}\n', encoding="utf-8"
            )
            with mock.patch.object(release_model.subprocess, "run", return_value=mock.Mock(returncode=0)):
                self.assertTrue(release_model.skip_if_already_published(root))
            with mock.patch.object(release_model.subprocess, "run", return_value=mock.Mock(returncode=1)):
                self.assertFalse(release_model.skip_if_already_published(root))

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
