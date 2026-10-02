#!/usr/bin/env python3
"""Static guardrails for the deploy platform's GitHub Actions files."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
MUTABLE_REF = re.compile(r"uses:\s*\S+@(main|master|latest)\s*$", re.MULTILINE)
RELATIVE_ACTION = re.compile(
    r"uses:\s*\./(?:platform/)?\.github/actions/"
)
POST_INCREMENT = re.compile(r"\(\(\s*[A-Za-z_][A-Za-z0-9_]*\+\+\s*\)\)")
SCHEDULE_MANIFEST = re.compile(
    r"github\.event_name\s*==\s*['\"]schedule['\"]\s*&&\s*['\"]([^'\"]+)['\"]"
)
CLOUD_SECRET_MAPPING = re.compile(
    r"^\s+(?:GCP_PROJECT_ID|GCP_SA_KEY|FB_PROJECT_ID|FB_SA_KEY|"
    r"DOPPLER_TOKEN(?:_FE)?):\s*\$\{\{\s*secrets\.",
    re.MULTILINE,
)
DRY_RUN_EXPRESSION = re.compile(
    r"^\s*(?P<key>[A-Za-z_][A-Za-z0-9_]*):\s*\$\{\{(?P<expr>.+?)\}\}\s*$",
    re.MULTILINE,
)
EXPRESSION_TOKEN = re.compile(
    r"(?P<string>'[^']*')|(?P<operator>==|!=|&&|\|\||!|\(|\))"
    r"|(?P<name>[A-Za-z_][A-Za-z0-9_.]*)"
)


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


class ExpressionError(Exception):
    """The expression uses a construct this checker cannot resolve."""


def rendered(value: object) -> str:
    """Literal text GitHub substitutes for an evaluated expression."""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def truthy(value: object) -> bool:
    return value not in (False, 0, "", None)


class ExpressionParser:
    """Minimal evaluator for the GitHub expression subset used in env values.

    Supports string/boolean literals, context lookups, `!`, `==`, `!=`, `&&`,
    `||` and parentheses, with GitHub's value-returning (not boolean-coercing)
    `&&`/`||`. Anything else raises, so an expression this cannot resolve is
    reported rather than assumed safe.
    """

    def __init__(self, tokens: list[tuple[str, str]], context: dict[str, object]):
        self.tokens = tokens
        self.context = context
        self.index = 0

    def peek(self) -> tuple[str, str] | None:
        return self.tokens[self.index] if self.index < len(self.tokens) else None

    def parse(self) -> object:
        value = self.parse_or()
        if self.index != len(self.tokens):
            raise ExpressionError("unexpected trailing tokens")
        return value

    def parse_or(self) -> object:
        value = self.parse_and()
        while (token := self.peek()) and token[1] == "||":
            self.index += 1
            right = self.parse_and()
            value = value if truthy(value) else right
        return value

    def parse_and(self) -> object:
        value = self.parse_comparison()
        while (token := self.peek()) and token[1] == "&&":
            self.index += 1
            right = self.parse_comparison()
            value = value if not truthy(value) else right
        return value

    def parse_comparison(self) -> object:
        value = self.parse_unary()
        while (token := self.peek()) and token[1] in ("==", "!="):
            self.index += 1
            right = self.parse_unary()
            equal = rendered(value) == rendered(right)
            value = equal if token[1] == "==" else not equal
        return value

    def parse_unary(self) -> object:
        token = self.peek()
        if token and token[1] == "!":
            self.index += 1
            return not truthy(self.parse_unary())
        return self.parse_primary()

    def parse_primary(self) -> object:
        token = self.peek()
        if token is None:
            raise ExpressionError("unexpected end of expression")
        kind, text = token
        self.index += 1
        if kind == "operator":
            if text != "(":
                raise ExpressionError(f"unexpected operator {text!r}")
            value = self.parse_or()
            closing = self.peek()
            if not closing or closing[1] != ")":
                raise ExpressionError("unbalanced parenthesis")
            self.index += 1
            return value
        if kind == "string":
            return text[1:-1]
        if text in ("true", "false"):
            return text == "true"
        if text in self.context:
            return self.context[text]
        raise ExpressionError(f"unresolved reference {text!r}")


def evaluate(expression: str, context: dict[str, object]) -> object:
    tokens: list[tuple[str, str]] = []
    position = 0
    while position < len(expression):
        if expression[position].isspace():
            position += 1
            continue
        match = EXPRESSION_TOKEN.match(expression, position)
        if not match:
            raise ExpressionError(f"unparsable input {expression[position:]!r}")
        tokens.append((match.lastgroup or "", match.group()))
        position = match.end()
    return ExpressionParser(tokens, context).parse()


def scheduled_dry_run_errors(text: str, relative: str) -> list[str]:
    """Fail if the non-dispatch path of the cleanup workflow can turn deletion on.

    The manual `default: true` check below says nothing about the scheduled
    branch, which is how `event == 'workflow_dispatch' && inputs.dry_run ||
    'false'` shipped: on `schedule` the left operand is falsy and the fallback
    armed real deletion. Only `schedule` is simulated because that is the one
    non-dispatch trigger this workflow declares.
    """
    errors: list[str] = []
    resolutions = 0
    for match in DRY_RUN_EXPRESSION.finditer(text):
        key = match.group("key")
        expression = match.group("expr")
        if "dry" not in key.lower() or "github.event_name" not in expression:
            continue
        resolutions += 1
        line = line_number(text, match.start())
        # On a scheduled run GitHub leaves `inputs` empty, but a correct
        # expression must stay dry whatever the dispatch input would have been.
        for dispatch_input in ("", True, False):
            try:
                value = evaluate(
                    expression,
                    {
                        "github.event_name": "schedule",
                        "inputs.dry_run": dispatch_input,
                    },
                )
            except ExpressionError as error:
                errors.append(
                    f"{relative}:{line}: scheduled dry_run for '{key}' cannot "
                    f"be verified statically ({error})"
                )
                break
            if rendered(value).lower() != "true":
                errors.append(
                    f"{relative}:{line}: scheduled cleanup must resolve "
                    f"'{key}' to 'true'; with inputs.dry_run="
                    f"{rendered(dispatch_input)!r} it resolves to "
                    f"{rendered(value)!r}"
                )
    if not resolutions:
        errors.append(
            f"{relative}: no dry_run resolution keyed on github.event_name "
            "found; the scheduled dry-run guarantee cannot be verified"
        )
    return errors


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

        if path.name.startswith("reusable-"):
            for match in RELATIVE_ACTION.finditer(text):
                errors.append(
                    f"{relative}:{line_number(text, match.start())}: "
                    "reusable workflow must run local scripts from the "
                    "platform/ checkout, not uses: ./"
                )

        for start_line, block in checkout_blocks(text):
            if re.search(r"^\s*repository:", block, re.MULTILINE) and not re.search(
                r"^\s*path:", block, re.MULTILINE
            ):
                errors.append(
                    f"{relative}:{start_line}: external checkout must set a path"
                )

        manifest_sections = re.finditer(
            r"^\s{6}manifest_name:\s*(?:>-\s*\n.*?(?=^\s{6}[A-Za-z_][A-Za-z0-9_]*:)|\S[^\n]*)",
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
        *sorted((ROOT / ".github" / "actions").glob("**/*.sh")),
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

    errors.extend(
        scheduled_dry_run_errors(
            cleanup_text, ".github/workflows/ops-gcp-cleanup.yml"
        )
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
