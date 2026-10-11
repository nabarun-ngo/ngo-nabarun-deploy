#!/usr/bin/env python3
"""Contract tests for the unified release-model action."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ACTION_DIR = Path(__file__).resolve().parent
ACTION = (ACTION_DIR / "action.yml").read_text(encoding="utf-8")
RUNNER = (ACTION_DIR / "run-release-model.sh").read_text(encoding="utf-8")


class ReleaseModelActionTests(unittest.TestCase):
    def test_bootstrap_inputs_are_required(self) -> None:
        for name in (
            "templates_repository",
            "templates_ref",
            "templates_token",
            "operation",
        ):
            with self.subTest(input=name):
                block = re.search(
                    rf"^  {name}:\n(?P<body>(?:    .*\n)+)",
                    ACTION,
                    re.MULTILINE,
                )
                self.assertIsNotNone(block)
                self.assertIn("required: true", block.group("body"))

    def test_templates_ref_is_validated_as_an_immutable_sha(self) -> None:
        self.assertIn(
            '[[ ! "$TEMPLATES_REF" =~ ^[0-9a-fA-F]{40}$ ]]',
            ACTION,
        )
        self.assertIn("persist-credentials: false", ACTION)
        self.assertIn("path: platform", ACTION)

    def test_all_supported_operations_are_dispatched(self) -> None:
        operations = (
            "plan",
            "baseline",
            "validate-pr",
            "apply",
            "check-pr",
            "shift-prerelease",
            "skip-if-published",
            "verify-dist-tag",
            "assert-versions",
            "create-tag-release",
            "publish-packages",
            "open-version-pr",
        )
        for operation in operations:
            with self.subTest(operation=operation):
                self.assertRegex(
                    RUNNER,
                    rf"(?m)^  [^\n)]*\b{re.escape(operation)}\b[^\n]*\)",
                )

    def test_result_outputs_are_exposed(self) -> None:
        for name in (
            "result_json",
            "version",
            "baseline",
            "valid",
            "changed_json",
            "already_published",
        ):
            with self.subTest(output=name):
                self.assertIn(f"  {name}:", ACTION)
                self.assertIn(f'write_output "{name}"', RUNNER)

    def test_action_uses_colocated_release_model_without_temp_copy(self) -> None:
        self.assertIn(
            'RELEASE_ACTION_DIR="$PLATFORM_DIR/.github/actions/release-model"',
            RUNNER,
        )
        self.assertIn(
            'MODEL="$RELEASE_ACTION_DIR/release_model.py"',
            RUNNER,
        )
        self.assertNotIn("$RUNNER_TEMP/release-model/release_model.py", RUNNER)

    @unittest.skipIf(os.name == "nt", "GitHub runner behavior test requires POSIX paths")
    def test_direct_operation_runs_in_nested_working_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            model = (
                workspace
                / "platform"
                / ".github"
                / "actions"
                / "release-model"
                / "release_model.py"
            )
            work_dir = workspace / "consumer" / "nested"
            record = workspace / "record.json"
            github_output = workspace / "github-output.txt"
            model.parent.mkdir(parents=True)
            work_dir.mkdir(parents=True)
            model.write_text(
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "Path(os.environ['RECORD_FILE']).write_text("
                "json.dumps({'cwd': os.getcwd(), 'args': sys.argv[1:], "
                "'working_directory': os.environ.get('WORKING_DIRECTORY')}), "
                "encoding='utf-8')\n",
                encoding="utf-8",
            )
            env = {
                **os.environ,
                "GITHUB_WORKSPACE": str(workspace),
                "OPERATION": "check-pr",
                "WORK_DIR": "consumer/nested",
                "RECORD_FILE": str(record),
                "GITHUB_OUTPUT": str(github_output),
            }

            subprocess.run(
                ["bash", str(ACTION_DIR / "run-release-model.sh")],
                cwd=workspace,
                env=env,
                check=True,
            )

            result = json.loads(record.read_text(encoding="utf-8"))
            self.assertEqual(str(work_dir), result["cwd"])
            self.assertEqual(["check-pr"], result["args"])
            self.assertEqual(".", result["working_directory"])
            self.assertIn("valid", github_output.read_text(encoding="utf-8"))

    @unittest.skipIf(os.name == "nt", "GitHub runner behavior test requires POSIX paths")
    def test_not_published_is_a_successful_action_result(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            model = (
                workspace
                / "platform"
                / ".github"
                / "actions"
                / "release-model"
                / "release_model.py"
            )
            work_dir = workspace / "consumer"
            github_output = workspace / "github-output.txt"
            model.parent.mkdir(parents=True)
            work_dir.mkdir()
            model.write_text(
                "import sys\n"
                "raise SystemExit(1 if sys.argv[1] == 'skip-if-published' else 0)\n",
                encoding="utf-8",
            )
            env = {
                **os.environ,
                "GITHUB_WORKSPACE": str(workspace),
                "GITHUB_OUTPUT": str(github_output),
                "OPERATION": "skip-if-published",
                "WORK_DIR": "consumer",
            }

            result = subprocess.run(
                ["bash", str(ACTION_DIR / "run-release-model.sh")],
                cwd=workspace,
                env=env,
                check=False,
            )

            self.assertEqual(0, result.returncode)
            output = github_output.read_text(encoding="utf-8")
            self.assertIn("already_published", output)
            self.assertIn("false", output)

    @unittest.skipIf(os.name == "nt", "GitHub runner behavior test requires POSIX paths")
    def test_wrapped_operation_does_not_enter_working_directory_twice(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            model = (
                workspace
                / "platform"
                / ".github"
                / "actions"
                / "release-model"
                / "release_model.py"
            )
            publish = (
                workspace
                / "platform"
                / ".github"
                / "actions"
                / "publish-npm-packages"
                / "publish-npm-packages.sh"
            )
            work_dir = workspace / "consumer" / "nested"
            record = workspace / "publish-cwd.txt"
            model.parent.mkdir(parents=True)
            publish.parent.mkdir(parents=True)
            work_dir.mkdir(parents=True)
            model.write_text("# placeholder\n", encoding="utf-8")
            publish.write_text(
                '#!/usr/bin/env bash\nset -euo pipefail\ncd "$WORK_DIR"\npwd > "$RECORD_FILE"\n',
                encoding="utf-8",
            )
            env = {
                **os.environ,
                "GITHUB_WORKSPACE": str(workspace),
                "OPERATION": "publish-packages",
                "WORK_DIR": "consumer/nested",
                "STABLE_COMMAND": "npm publish",
                "PRERELEASE_COMMAND": "npm publish --tag beta",
                "RECORD_FILE": str(record),
            }

            subprocess.run(
                ["bash", str(ACTION_DIR / "run-release-model.sh")],
                cwd=workspace,
                env=env,
                check=True,
            )

            self.assertEqual(str(work_dir), record.read_text(encoding="utf-8").strip())


if __name__ == "__main__":
    unittest.main()
