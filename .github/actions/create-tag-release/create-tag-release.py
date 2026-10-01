#!/usr/bin/env python3
"""Create one application git tag and GitHub Release.

The calling workflow stages release_model.py on PYTHONPATH and checks out
the application repository before running this script.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import release_model


TAG_RE = re.compile(r"^\d+\.\d+\.\d+(-(alpha|beta|rc)\.[1-9]\d*)?$")


def notice(message: str) -> None:
    print(f"::notice::{message}")


def fail(message: str) -> None:
    print(f"::error::{message}")
    raise SystemExit(1)


def write_outputs(tag: str, created: bool, prerelease: bool, skipped: bool) -> None:
    path = Path(os.environ["GITHUB_OUTPUT"])
    with path.open("a", encoding="utf-8") as handle:
        handle.write(
            f"tag={tag}\n"
            f"created={'true' if created else 'false'}\n"
            f"prerelease={'true' if prerelease else 'false'}\n"
            f"skipped={'true' if skipped else 'false'}\n"
        )


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        fail(f"{' '.join(command)} failed: {detail}")
    return result


def normalize_tag(value: str) -> str:
    value = value.strip()
    if value.startswith("v") and len(value) > 1 and value[1].isdigit():
        return value[1:]
    return value


def merged_tags() -> list[str]:
    listed = run(["git", "tag", "--merged", "HEAD"]).stdout.splitlines()
    return [normalize_tag(tag) for tag in listed if TAG_RE.fullmatch(normalize_tag(tag))]


def tag_commit(version: str) -> str:
    result = run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{version}^{{}}"], check=False)
    return result.stdout.strip()


def remote_tag_exists(version: str) -> bool:
    result = run(["git", "ls-remote", "--tags", "origin", f"refs/tags/{version}"], check=False)
    return bool(result.stdout.strip())


def commits_since(baseline: str | None) -> list[str]:
    if baseline:
        ref = baseline
        if run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{baseline}^{{}}"], check=False).returncode != 0:
            ref = f"v{baseline}"
        log = run(["git", "log", "--format=%B%x1f", f"{ref}..HEAD"]).stdout
    else:
        log = run(["git", "log", "--format=%B%x1f", "HEAD"]).stdout
    return [item.strip("\n") for item in log.split("\x1f") if item.strip()]


def plan() -> dict:
    version_file = os.environ["VERSION_FILE"]
    file_version = ""
    if Path(version_file).is_file():
        file_version = json.loads(Path(version_file).read_text(encoding="utf-8")).get("version") or ""
    merged = merged_tags()
    stables = [tag for tag in merged if "-" not in tag]
    last_stable = max(stables, key=release_model.version_sort_key) if stables else file_version
    payload = {
        "branch": os.environ["CURRENT_BRANCH"],
        "stable_branch": os.environ["STABLE_BRANCH"],
        "prerelease_branch": os.environ["PRERELEASE_BRANCH"],
        "prerelease_tag": os.environ["PRERELEASE_TAG"],
        "last_stable": last_stable,
        "merged_tags": merged,
        "explicit_version": os.environ.get("INPUT_VERSION", ""),
        "commits": [],
    }
    try:
        if not payload["explicit_version"]:
            payload["commits"] = commits_since(release_model.select_baseline(payload))
        return release_model.plan_release(payload)
    except ValueError as exc:
        fail(str(exc))


def apply_version(version: str, version_file: str) -> None:
    subjects = Path(os.environ["RUNNER_TEMP"]) / "release-subjects.txt"
    code = release_model.main([
        "apply",
        "--version", version,
        "--version-file", version_file,
        "--changelog", "CHANGELOG.md",
        "--subjects-file", str(subjects),
    ])
    if code != 0:
        fail(f"Could not apply version {version}")


def create_release(version: str, prerelease: bool, repository: str) -> None:
    existing = run(["gh", "release", "view", version, "--repo", repository], check=False)
    if existing.returncode == 0:
        notice(f"GitHub Release {version} already exists.")
        return
    command = ["gh", "release", "create", version, "--title", version, "--generate-notes", "--repo", repository]
    if prerelease:
        command.insert(-2, "--prerelease")
    run(command)


def synchronize_stable_branch() -> None:
    current = os.environ["CURRENT_BRANCH"]
    prerelease_branch = os.environ["PRERELEASE_BRANCH"]
    repository = os.environ["GH_REPO"]
    if current != os.environ["STABLE_BRANCH"]:
        return
    if not run(["git", "ls-remote", "--heads", "origin", prerelease_branch]).stdout.strip():
        return
    run(["git", "fetch", "origin", prerelease_branch])
    ancestor = run(["git", "merge-base", "--is-ancestor", "HEAD", f"origin/{prerelease_branch}"], check=False)
    if ancestor.returncode == 0:
        return
    listed = run([
        "gh", "pr", "list",
        "--repo", repository,
        "--base", prerelease_branch,
        "--head", current,
        "--json", "number",
        "--jq", "length",
    ]).stdout.strip()
    if listed == "0":
        run([
            "gh", "pr", "create",
            "--repo", repository,
            "--base", prerelease_branch,
            "--head", current,
            "--title", f"chore: synchronize {current} into {prerelease_branch}",
            "--body", f"Stable release commits must be merged back into `{prerelease_branch}`.",
        ])


def main() -> int:
    prerelease_tag = os.environ["PRERELEASE_TAG"]
    current = os.environ["CURRENT_BRANCH"]
    stable = os.environ["STABLE_BRANCH"]
    prerelease_branch = os.environ["PRERELEASE_BRANCH"]
    version_file = os.environ["VERSION_FILE"]
    repository = os.environ["GH_REPO"]

    if prerelease_tag not in {"alpha", "beta", "rc"}:
        fail("prerelease_tag must be alpha, beta, or rc.")
    if current not in {stable, prerelease_branch}:
        fail(f"Branch '{current}' is neither {stable} nor {prerelease_branch}.")

    planned = plan()
    if planned["action"] == "skip":
        notice(planned["reason"])
        write_outputs("", False, False, True)
        return 0

    version = planned["version"]
    is_prerelease = bool(planned["prerelease"])
    subjects = Path(os.environ["RUNNER_TEMP"]) / "release-subjects.txt"
    subjects.write_text("".join(f"{line}\n" for line in planned.get("commits", [])), encoding="utf-8")

    existing = tag_commit(version)
    head = run(["git", "rev-parse", "HEAD"]).stdout.strip()
    if existing and existing != head:
        fail(f"Tag {version} already exists on another commit and cannot be moved.")

    created = False
    subject = run(["git", "log", "-1", "--format=%s"]).stdout.strip()
    if existing == head and existing:
        notice(f"Tag {version} already points at this commit.")
    elif subject != f"chore(release): {version} [skip ci]":
        apply_version(version, version_file)
        run(["git", "add", version_file, "CHANGELOG.md"])
        staged = run(["git", "diff", "--cached", "--quiet"], check=False)
        if staged.returncode == 0:
            notice(f"Version files already match {version}")
        else:
            run(["git", "commit", "-m", f"chore(release): {version} [skip ci]"])
            pushed = run(["git", "push", "origin", f"HEAD:{current}"], check=False)
            if pushed.returncode != 0:
                fail(f"Could not push the release commit. Allow the release identity to update {current}.")
            created = True

    head = run(["git", "rev-parse", "HEAD"]).stdout.strip()
    existing = tag_commit(version)
    if existing and existing != head:
        fail(f"Tag {version} already exists on another commit and cannot be moved.")
    if not existing:
        if remote_tag_exists(version):
            fail(f"Tag {version} already exists on another commit and cannot be moved.")
        run(["git", "tag", "-a", version, "-m", f"chore(release): {version} [skip ci]"])
        run(["git", "push", "origin", f"refs/tags/{version}"])
        created = True

    create_release(version, is_prerelease, repository)
    synchronize_stable_branch()
    write_outputs(version, created, is_prerelease, False)

    summary = Path(os.environ["GITHUB_STEP_SUMMARY"])
    with summary.open("a", encoding="utf-8") as handle:
        handle.write(
            "### Tag and GitHub Release\n\n"
            "| Field | Value |\n"
            "|-------|-------|\n"
            f"| Tag | `{version}` |\n"
            f"| Created this run | `{str(created).lower()}` |\n"
            f"| Prerelease | `{str(is_prerelease).lower()}` |\n"
        )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ValueError as exc:
        print(f"::error::{exc}")
        sys.exit(1)
