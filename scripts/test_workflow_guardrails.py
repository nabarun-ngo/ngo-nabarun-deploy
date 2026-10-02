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


def _checkout_workflow(repository: str) -> str:
    """Workflow with one external actions/checkout step, no path: set."""
    return (
        "name: External\n"
        "permissions:\n"
        "  contents: read\n"
        "jobs:\n"
        "  build:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n"
        "      - uses: actions/checkout@v7\n"
        "        with:\n"
        "          repository: " + repository + "\n"
    )


def _scheduled_deploy_workflow(manifest: str, environment: str, tag: str) -> str:
    """Workflow whose schedule branch hard-routes manifest/environment/tag,
    shaped like ops-deploy-frontend.yml's context job."""
    return (
        "name: Frontend\n"
        "permissions:\n"
        "  contents: read\n"
        "jobs:\n"
        "  context:\n"
        "    uses: ./.github/workflows/reusable-setup-context.yml\n"
        "    with:\n"
        "      manifest_name: ${{ github.event_name == 'schedule' && '"
        + manifest
        + "' || inputs.manifest_name }}\n"
        "      target_environment: ${{ github.event_name == 'schedule' && '"
        + environment
        + "' || inputs.target_environment }}\n"
        "      tag_name: ${{ github.event_name == 'schedule' && '"
        + tag
        + "' || inputs.tag_name }}\n"
    )


def _cleanup_workflow(dry_run_expression: str) -> str:
    """ops-gcp-cleanup.yml shaped fixture whose matrix job resolves INPUT_DRY
    from the given expression."""
    return (
        "name: Cleanup\n"
        "permissions:\n"
        "  contents: read\n"
        "on:\n"
        "  schedule:\n"
        "    - cron: '0 17 * * 1,3,5'\n"
        "  workflow_dispatch:\n"
        "    inputs:\n"
        "      dry_run:\n"
        "        type: boolean\n"
        "        default: true\n"
        "jobs:\n"
        "  setup:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n"
        "      - name: Build matrix\n"
        "        env:\n"
        "          INPUT_DRY: ${{ " + dry_run_expression + " }}\n"
        "        run: echo \"$INPUT_DRY\"\n"
    )


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
            _cleanup_workflow(
                "github.event_name != 'workflow_dispatch' "
                "&& 'true' || inputs.dry_run"
            ),
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

    def write_manifest(self, name: str) -> None:
        (self.root / "config" / "manifests" / f"{name}.json").write_text(
            "{}\n", encoding="utf-8"
        )

    def test_accepts_safe_workflows(self) -> None:
        result, output = self.run_guardrails()
        self.assertEqual(0, result, output)

    # Any repository value should trip the same rule; the specific org/repo
    # string is incidental, not part of what is being validated.
    EXTERNAL_REPOSITORIES = (
        "example/application",
        "nabarun-ngo/ngo-nabarun-be",
        "owner-name/some.repo-name",
    )

    def test_rejects_relative_action_in_reusable_workflow(self) -> None:
        workflow = GUARDRAILS.WORKFLOWS / "reusable-example.yml"
        workflow.write_text(
            "name: Reusable\n"
            "permissions:\n"
            "  contents: read\n"
            "jobs:\n"
            "  build:\n"
            "    runs-on: ubuntu-latest\n"
            "    steps:\n"
            "      - uses: ./.github/actions/example\n",
            encoding="utf-8",
        )
        result, output = self.run_guardrails()
        self.assertEqual(1, result)
        self.assertIn("platform/ checkout, not uses: ./", output)
        workflow.unlink()

    def test_rejects_external_checkout_without_path(self) -> None:
        for repository in self.EXTERNAL_REPOSITORIES:
            with self.subTest(repository=repository):
                workflow = GUARDRAILS.WORKFLOWS / "external.yml"
                workflow.write_text(
                    _checkout_workflow(repository), encoding="utf-8"
                )
                result, output = self.run_guardrails()
                self.assertEqual(1, result)
                self.assertIn("external checkout must set a path", output)
                workflow.unlink()

    # (manifest, target_environment, tag) triples that each represent one
    # existing manifest paired with arbitrary environment/tag values. The
    # environment and tag strings are deliberately varied — and deliberately
    # include values that look like manifest names — to prove the guardrail
    # keys only on manifest_name, not on whatever else appears in the section.
    SCHEDULED_MANIFEST_CASES = (
        ("fe-public-site", "stage", "latest"),
        ("fe-public-site", "prod", "v1.2.3"),
        ("backend", "stage", "fe-public-site"),
        ("fe-internal-app", "fe-public-site", "latest"),
    )

    def test_scheduled_manifest_ignores_environment_and_tag(self) -> None:
        for manifest, environment, tag in self.SCHEDULED_MANIFEST_CASES:
            with self.subTest(manifest=manifest, environment=environment, tag=tag):
                self.write_manifest(manifest)
                workflow = GUARDRAILS.WORKFLOWS / "ops-deploy-frontend.yml"
                workflow.write_text(
                    _scheduled_deploy_workflow(manifest, environment, tag),
                    encoding="utf-8",
                )
                result, output = self.run_guardrails()
                self.assertEqual(0, result, output)
                workflow.unlink()

    MISSING_MANIFEST_CASES = ("missing-app", "stage", "latest", "does-not-exist")

    def test_rejects_missing_scheduled_manifest(self) -> None:
        for manifest in self.MISSING_MANIFEST_CASES:
            with self.subTest(manifest=manifest):
                workflow = GUARDRAILS.WORKFLOWS / "ops-deploy-frontend.yml"
                workflow.write_text(
                    _scheduled_deploy_workflow(manifest, "stage", "latest"),
                    encoding="utf-8",
                )
                result, output = self.run_guardrails()
                self.assertEqual(1, result)
                self.assertIn(
                    f"scheduled manifest '{manifest}' does not exist", output
                )
                workflow.unlink()

    # Expressions that keep a scheduled (non-dispatch) cleanup run in dry-run
    # mode while still letting a manual dispatch opt out.
    SAFE_DRY_RUN_EXPRESSIONS = (
        "github.event_name != 'workflow_dispatch' && 'true' || inputs.dry_run",
        "github.event_name == 'schedule' && 'true' || inputs.dry_run",
        "github.event_name == 'workflow_dispatch' "
        "&& inputs.dry_run || github.event_name != 'workflow_dispatch'",
    )

    def test_accepts_scheduled_dry_run_expressions(self) -> None:
        workflow = GUARDRAILS.WORKFLOWS / "ops-gcp-cleanup.yml"
        for expression in self.SAFE_DRY_RUN_EXPRESSIONS:
            with self.subTest(expression=expression):
                workflow.write_text(
                    _cleanup_workflow(expression), encoding="utf-8"
                )
                result, output = self.run_guardrails()
                self.assertEqual(0, result, output)

    # Each of these lets a cron run resolve dry_run to a false-y literal.
    # The first is the exact expression that shipped the live-deletion bug.
    UNSAFE_DRY_RUN_EXPRESSIONS = (
        "github.event_name == 'workflow_dispatch' && inputs.dry_run || 'false'",
        "github.event_name == 'workflow_dispatch' && 'true' || 'false'",
        "github.event_name == 'schedule' && inputs.dry_run || 'false'",
        "github.event_name != 'schedule' && 'true' || ''",
    )

    def test_rejects_scheduled_dry_run_expressions(self) -> None:
        workflow = GUARDRAILS.WORKFLOWS / "ops-gcp-cleanup.yml"
        for expression in self.UNSAFE_DRY_RUN_EXPRESSIONS:
            with self.subTest(expression=expression):
                workflow.write_text(
                    _cleanup_workflow(expression), encoding="utf-8"
                )
                result, output = self.run_guardrails()
                self.assertEqual(1, result)
                self.assertIn("scheduled cleanup must resolve", output)

    # A dry_run value the checker cannot statically resolve must be reported,
    # not assumed safe.
    UNVERIFIABLE_DRY_RUN_EXPRESSIONS = (
        "github.event_name == 'workflow_dispatch' "
        "&& inputs.dry_run || vars.CLEANUP_DRY_RUN",
        "contains(github.event_name, 'dispatch') && inputs.dry_run || 'true'",
    )

    def test_rejects_unverifiable_scheduled_dry_run(self) -> None:
        workflow = GUARDRAILS.WORKFLOWS / "ops-gcp-cleanup.yml"
        for expression in self.UNVERIFIABLE_DRY_RUN_EXPRESSIONS:
            with self.subTest(expression=expression):
                workflow.write_text(
                    _cleanup_workflow(expression), encoding="utf-8"
                )
                result, output = self.run_guardrails()
                self.assertEqual(1, result)
                self.assertIn("cannot be verified statically", output)

    def test_rejects_missing_scheduled_dry_run_resolution(self) -> None:
        workflow = GUARDRAILS.WORKFLOWS / "ops-gcp-cleanup.yml"
        workflow.write_text(
            "name: Cleanup\n"
            "permissions:\n"
            "  contents: read\n"
            "on:\n"
            "  schedule:\n"
            "    - cron: '0 17 * * 1,3,5'\n"
            "  workflow_dispatch:\n"
            "    inputs:\n"
            "      dry_run:\n"
            "        type: boolean\n"
            "        default: true\n",
            encoding="utf-8",
        )
        result, output = self.run_guardrails()
        self.assertEqual(1, result)
        self.assertIn("no dry_run resolution keyed on github.event_name", output)


if __name__ == "__main__":
    unittest.main()
