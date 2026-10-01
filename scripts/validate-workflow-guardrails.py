#!/usr/bin/env python3
"""Static guardrails for the deploy platform's GitHub Actions files."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
MUTABLE_REF = re.compile(r"uses:\s*\S+@(main|master|latest)\s*$", re.MULTILINE)
POST_INCREMENT = re.compile(r"\(\(\s*[A-Za-z_][A-Za-z0-9_]*\+\+\s*\)\)")
SCHEDULE_MANIFEST = re.compile(
    r"github\.event_name\s*==\s*['\"]schedule['\"]\s*&&\s*['\"]([^'\"]+)['\"]"
)
CLOUD_SECRET_MAPPING = re.compile(
    r"^\s+(?:GCP_PROJECT_ID|GCP_SA_KEY|FB_PROJECT_ID|FB_SA_KEY|"
    r"DOPPLER_TOKEN(?:_FE)?):\s*\$\{\{\s*secrets\.",
    re.MULTILINE,
)


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def checkout_blocks(text: str) -> list[tuple[int, str]]:
    """Return actions/checkout step blocks and their first line number."""
    lines = text.splitlines()
    blocks: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if not re.search(r"uses:\s*actions/checkout@", line):
            continue
        uses_indent = len(line) - len(line.lstrip())
        end = len(lines)
        for cursor in range(index + 1, len(lines)):
            candidate = lines[cursor]
            indent = len(candidate) - len(candidate.lstrip())
            if re.match(r"\s*-\s+(?:name|uses):", candidate) and indent < uses_indent:
                end = cursor
                break
            if re.match(r"\s*-\s+uses:", candidate) and indent == uses_indent:
                end = cursor
                break
        blocks.append((index + 1, "\n".join(lines[index:end])))
    return blocks


def main() -> int:
    errors: list[str] = []
    workflow_files = sorted(WORKFLOWS.glob("*.yml"))

    if not workflow_files:
        errors.append("No workflow files found")

    for path in workflow_files:
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)

        if not re.search(r"^permissions:", text, re.MULTILINE):
            errors.append(f"{relative}: missing explicit top-level permissions")

        for match in MUTABLE_REF.finditer(text):
            errors.append(
                f"{relative}:{line_number(text, match.start())}: "
                f"mutable action reference @{match.group(1)}"
            )

        for start_line, block in checkout_blocks(text):
            if re.search(r"^\s*repository:", block, re.MULTILINE) and not re.search(
                r"^\s*path:", block, re.MULTILINE
            ):
                errors.append(
                    f"{relative}:{start_line}: external checkout must set a path"
                )

        manifest_sections = re.finditer(
            r"^\s{6}manifest_name:\s*>-\s*$.*?(?=^\s{6}[A-Za-z_][A-Za-z0-9_]*:)",
            text,
            re.MULTILINE | re.DOTALL,
        )
        for section in manifest_sections:
            for match in SCHEDULE_MANIFEST.finditer(section.group(0)):
                manifest = match.group(1)
                manifest_path = ROOT / "config" / "manifests" / f"{manifest}.json"
                if not manifest_path.is_file():
                    errors.append(
                        f"{relative}:{line_number(text, section.start() + match.start())}: "
                        f"scheduled manifest '{manifest}' does not exist"
                    )

        if path.name in {"ops-deploy-backend.yml", "ops-deploy-frontend.yml"}:
            for match in CLOUD_SECRET_MAPPING.finditer(text):
                errors.append(
                    f"{relative}:{line_number(text, match.start())}: cloud and "
                    "environment secrets must be resolved by the environment-bound job"
                )

    source_files = [
        *workflow_files,
        *sorted((ROOT / ".github" / "actions").glob("**/*.yml")),
        *sorted((ROOT / "scripts").glob("*.sh")),
    ]
    for path in source_files:
        text = path.read_text(encoding="utf-8")
        for match in POST_INCREMENT.finditer(text):
            errors.append(
                f"{path.relative_to(ROOT)}:{line_number(text, match.start())}: "
                "post-increment is unsafe with 'set -e'; use ((++counter))"
            )

    cleanup_text = (WORKFLOWS / "ops-gcp-cleanup.yml").read_text(encoding="utf-8")
    dry_run = re.search(
        r"^\s{6}dry_run:\s*$.*?^\s{8}default:\s*(\S+)",
        cleanup_text,
        re.MULTILINE | re.DOTALL,
    )
    if not dry_run or dry_run.group(1).lower() != "true":
        errors.append(
            ".github/workflows/ops-gcp-cleanup.yml: manual cleanup must default "
            "dry_run to true"
        )

    ci_text = (WORKFLOWS / "ci-validate.yml").read_text(encoding="utf-8")
    for forbidden in (
        "actionlint download failed",
        "Some shellcheck warnings found",
        "shellcheck not available — skipping",
    ):
        if forbidden in ci_text:
            errors.append(
                f".github/workflows/ci-validate.yml: validation may soft-pass: "
                f"{forbidden!r}"
            )

    if errors:
        print("Workflow guardrails failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(f"Workflow guardrails passed for {len(workflow_files)} workflows.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
