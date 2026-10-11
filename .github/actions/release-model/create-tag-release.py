#!/usr/bin/env python3
"""Create one application git tag and GitHub Release.

No version/changelog commit is made and nothing is pushed to the branch.
The next version is computed from the latest tag reachable from the current
branch (``git tag --merged HEAD``), the commits made since that tag, and the
titles of the pull requests that introduced those commits. The highest bump
wins. The resulting tag is created on the current HEAD.

The calling workflow stages release_model.py on PYTHONPATH and checks out
the application repository (with full history and tags, e.g. ``fetch-depth: 0``)
before running this script.
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
DEFAULT_LAST_STABLE = "0.0.0"
MAX_PULL_REQUEST_TITLE_LOOKUPS = 100


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
    """Release tags reachable from HEAD, i.e. tags that belong to this branch."""
    listed = run(["git", "tag", "--merged", "HEAD"]).stdout.splitlines()
    return [normalize_tag(tag) for tag in listed if TAG_RE.fullmatch(normalize_tag(tag))]


def tag_commit(version: str) -> str:
    result = run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{version}^{{}}"], check=False)
    return result.stdout.strip()


def remote_tag_exists(version: str) -> bool:
    result = run(["git", "ls-remote", "--tags", "origin", f"refs/tags/{version}"], check=False)
    return bool(result.stdout.strip())


def history_range(baseline: str | None) -> str:
    if not baseline:
        return "HEAD"
    ref = baseline
    if run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{baseline}^{{}}"], check=False).returncode != 0:
        ref = f"v{baseline}"
    return f"{ref}..HEAD"


def commits_since(baseline: str | None) -> list[str]:
    log = run(["git", "log", "--format=%B%x1f", history_range(baseline)]).stdout
    return [item.strip("\n") for item in log.split("\x1f") if item.strip()]


def pull_request_titles(baseline: str | None) -> list[str]:
    """Titles of pull requests associated with commits since ``baseline``.

    Only the newest commits are looked up. Older titles are omitted with a
    notice; those commits still contribute through their own messages.
    """
    repository = os.environ["GH_REPO"]
    shas = [sha for sha in run(["git", "rev-list", history_range(baseline)]).stdout.split() if sha]
    if len(shas) > MAX_PULL_REQUEST_TITLE_LOOKUPS:
        notice(
            "Looking up pull request titles for the "
            f"{MAX_PULL_REQUEST_TITLE_LOOKUPS} newest commits. "
            "Older pull request titles are not included."
        )
        shas = shas[:MAX_PULL_REQUEST_TITLE_LOOKUPS]
    titles: list[str] = []
    seen: set[str] = set()
    for sha in shas:
        raw = run(
            [
                "gh",
                "api",
                "-H",
                "Accept: application/vnd.github+json",
                f"repos/{repository}/commits/{sha}/pulls",
                "--jq",
                ".[].title",
            ]
        ).stdout
        for title in raw.splitlines():
            cleaned = title.strip()
            if cleaned and cleaned not in seen:
                seen.add(cleaned)
                titles.append(cleaned)
    return titles


def fallback_version() -> str:
    """Version used as the starting point only when the branch has no stable tag yet."""
    version_file = os.environ.get("VERSION_FILE", "")
    if version_file and Path(version_file).is_file():
        try:
            data = json.loads(Path(version_file).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return DEFAULT_LAST_STABLE
        value = str(data.get("version") or "").strip()
        # Only a stable X.Y.Z value is usable as the starting point.
        if re.fullmatch(r"\d+\.\d+\.\d+", value):
            return value
    return DEFAULT_LAST_STABLE


def plan() -> dict:
    merged = merged_tags()
    stables = [tag for tag in merged if "-" not in tag]
    last_stable = max(stables, key=release_model.version_sort_key) if stables else fallback_version()
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
            baseline = release_model.select_baseline(payload)
            payload["commits"] = commits_since(baseline)
            payload["pull_request_titles"] = pull_request_titles(baseline)
        return release_model.plan_release(payload)
    except ValueError as exc:
        fail(str(exc))


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
    head = run(["git", "rev-parse", "HEAD"]).stdout.strip()

    existing = tag_commit(version)
    if existing and existing != head:
        fail(f"Tag {version} already exists on another commit and cannot be moved.")

    created = False
    if existing:
        notice(f"Tag {version} already points at this commit.")
    else:
        if remote_tag_exists(version):
            fail(f"Tag {version} already exists on another commit and cannot be moved.")
        run(["git", "tag", "-a", version, "-m", f"Release {version}"])
        run(["git", "push", "origin", f"refs/tags/{version}"])
        created = True

    create_release(version, is_prerelease, repository)
    synchronize_stable_branch()
    write_outputs(version, created, is_prerelease, False)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as handle:
            handle.write(
                "### Tag and GitHub Release\n\n"
                "| Field | Value |\n"
                "|-------|-------|\n"
                f"| Tag | `{version}` |\n"
                f"| Commit | `{head[:12]}` |\n"
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
