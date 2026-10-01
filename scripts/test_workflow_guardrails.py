#!/usr/bin/env python3
"""Tests for validate-workflow-guardrails.py."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path


SCRIPT = Path(__file__).with_name("validate-workflow-guardrails.py")
SPEC = importlib.util.spec_from_file_location("workflow_guardrails", SCRIPT)
assert SPEC and SPEC.loader
GUARDRAILS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARDRAILS)


class WorkflowGuardrailTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        workflows = self.root / ".github" / "workflows"
        workflows.mkdir(parents=True)
        (self.root / ".github" / "actions").mkdir()
        (self.root / "scripts").mkdir()
        (self.root / "config" / "manifests").mkdir(parents=True)

        (workflows / "ci-validate.yml").write_text(
            "name: CI\npermissions:\n  contents: read\n", encoding="utf-8"
        )
        (workflows / "ops-gcp-cleanup.yml").write_text(
            "name: Cleanup\n"
            "permissions:\n"
            "  contents: read\n"
            "on:\n"
            "  workflow_dispatch:\n"
            "    inputs:\n"
            "      dry_run:\n"
            "        type: boolean\n"
            "        default: true\n",
            encoding="utf-8",
        )
        GUARDRAILS.ROOT = self.root
        GUARDRAILS.WORKFLOWS = workflows

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_guardrails(self) -> tuple[int, str]:
        output = StringIO()
        with redirect_stdout(output):
            result = GUARDRAILS.main()
        return result, output.getvalue()

    def test_accepts_safe_workflows(self) -> None:
        result, output = self.run_guardrails()
        self.assertEqual(0, result, output)

    def test_rejects_external_checkout_without_path(self) -> None:
        workflow = GUARDRAILS.WORKFLOWS / "external.yml"
        workflow.write_text(
            "name: External\n"
            "permissions:\n"
            "  contents: read\n"
            "jobs:\n"
            "  build:\n"
            "    runs-on: ubuntu-latest\n"
            "    steps:\n"
            "      - uses: actions/checkout@v7\n"
            "        with:\n"
            "          repository: example/application\n",
            encoding="utf-8",
        )
        result, output = self.run_guardrails()
        self.assertEqual(1, result)
        self.assertIn("external checkout must set a path", output)


if __name__ == "__main__":
    unittest.main()
