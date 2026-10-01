#!/usr/bin/env python3
"""Release planning for library and application repositories."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


COMMIT_RE = re.compile(
    r"^(?P<type>fix|feat|docs|chore|ci)"
    r"(?:\([^\r\n)]+\))?(?P<breaking>!)?: (?P<description>\S.*)$"
)
VERSION_RE = re.compile(
    r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<tag>alpha|beta|rc)\.(?P<num>[1-9]\d*))?$"
)
CHANGESET_BUMP_RE = re.compile(
    r"^['\"]?(?P<package>.+?)['\"]?\s*:\s*(?P<bump>patch|minor|major)\s*$"
)
BUMP_RANK = {"patch": 1, "minor": 2, "major": 3}
TYPE_BUMP = {"fix": "patch", "feat": "minor", "docs": None, "chore": None, "ci": None}


def parse_commit(message: str) -> dict:
    """Classify one commit or pull request title."""
    normalized = message.replace("\r\n", "\n").strip()
    subject = normalized.split("\n", 1)[0].strip()
    if (
        subject.startswith("Merge ")
        or subject.startswith("chore(release):")
        or "[skip ci]" in subject
        or "[skip actions]" in subject
    ):
        return {"ignored": True, "valid": True, "subject": subject, "bump": None}
    match = COMMIT_RE.fullmatch(subject)
    if not match:
        return {"ignored": False, "valid": False, "subject": subject, "bump": None}
    breaking = match.group("breaking") == "!" or any(
        line.startswith("BREAKING CHANGE:") or line.startswith("BREAKING-CHANGE:")
        for line in normalized.split("\n")[1:]
    )
    bump = "major" if breaking else TYPE_BUMP[match.group("type")]
    return {
        "ignored": False,
        "valid": True,
        "subject": subject,
        "type": match.group("type"),
        "bump": bump,
    }


def highest_bump(commits: list[dict]) -> str | None:
    best = None
    for commit in commits:
        bump = commit.get("bump")
        if bump and (best is None or BUMP_RANK[bump] > BUMP_RANK[best]):
            best = bump
    return best


def parse_version(value: str) -> dict:
    match = VERSION_RE.fullmatch(value.strip())
    if not match:
        raise ValueError(
            f"Unsupported version '{value}'. Expected X.Y.Z or X.Y.Z-(alpha|beta|rc).N with N starting at 1."
        )
    return {
        "major": int(match.group("major")),
        "minor": int(match.group("minor")),
        "patch": int(match.group("patch")),
        "tag": match.group("tag"),
        "num": int(match.group("num")) if match.group("num") else None,
    }


def format_stable(version: dict) -> str:
    return f"{version['major']}.{version['minor']}.{version['patch']}"


def version_sort_key(value: str) -> tuple:
    parsed = parse_version(value)
    return (
        parsed["major"],
        parsed["minor"],
        parsed["patch"],
        1 if parsed["tag"] is None else 0,
        parsed["num"] or 0,
    )


def apply_bump(version: dict, bump: str) -> dict:
    major, minor, patch = version["major"], version["minor"], version["patch"]
    if bump == "major":
        return {"major": major + 1, "minor": 0, "patch": 0, "tag": None, "num": None}
    if bump == "minor":
        return {"major": major, "minor": minor + 1, "patch": 0, "tag": None, "num": None}
    if bump == "patch":
        return {"major": major, "minor": minor, "patch": patch + 1, "tag": None, "num": None}
    raise ValueError(f"Unknown bump '{bump}'")


def line_bump(last_stable: dict, beta_base: dict) -> str:
    if beta_base["major"] > last_stable["major"]:
        return "major"
    if beta_base["minor"] > last_stable["minor"]:
        return "minor"
    return "patch"


def releasable_subjects(commits: list[dict]) -> list[str]:
    return [commit["subject"] for commit in commits if commit.get("bump")]


def select_baseline(payload: dict) -> str | None:
    """Return the tag whose history has already been released."""
    branch = payload["branch"]
    stable_branch = payload.get("stable_branch", "main")
    prerelease_branch = payload.get("prerelease_branch", "develop")
    tag_name = payload.get("prerelease_tag", "beta")
    last_stable = parse_version(payload["last_stable"])
    merged = [parse_version(value) for value in payload.get("merged_tags", [])]
    if branch == prerelease_branch:
        if not merged:
            return None
        return format_version(max(merged, key=lambda item: version_sort_key(format_version(item))))
    betas = [
        item
        for item in merged
        if item["tag"] == tag_name
        and version_sort_key(format_stable(item)) > version_sort_key(format_stable(last_stable))
    ]
    if betas:
        return format_version(max(betas, key=lambda item: version_sort_key(format_version(item))))
    stables = [item for item in merged if item["tag"] is None]
    if not stables:
        return None
    return format_version(max(stables, key=lambda item: version_sort_key(format_version(item))))


def plan_release(payload: dict) -> dict:
    """Plan one application release from tags and commits since the latest tag."""
    branch = payload["branch"]
    stable_branch = payload.get("stable_branch", "main")
    prerelease_branch = payload.get("prerelease_branch", "develop")
    tag_name = payload.get("prerelease_tag", "beta")
    if tag_name not in {"alpha", "beta", "rc"}:
        raise ValueError("prerelease_tag must be alpha, beta, or rc")
    if branch not in {stable_branch, prerelease_branch}:
        raise ValueError(
            f"Branch '{branch}' is neither {stable_branch} nor {prerelease_branch}"
        )

    explicit = str(payload.get("explicit_version") or "").strip()
    if explicit.startswith("v"):
        explicit = explicit[1:]
    if explicit:
        parsed = parse_version(explicit)
        prerelease = parsed["tag"] is not None
        if branch == prerelease_branch and not prerelease:
            raise ValueError(f"{prerelease_branch} can only create beta releases")
        if branch == stable_branch and prerelease:
            raise ValueError(f"{stable_branch} can only create stable releases")
        return {
            "action": "release",
            "version": explicit,
            "prerelease": prerelease,
            "commits": [],
        }

    commits = [parse_commit(message) for message in payload.get("commits", [])]
    invalid = [commit["subject"] for commit in commits if not commit["valid"]]
    if invalid:
        raise ValueError("Invalid commit titles: " + "; ".join(invalid))
    new_bump = highest_bump(commits)
    last_stable = parse_version(payload["last_stable"])
    if last_stable["tag"]:
        raise ValueError("last_stable must be a stable X.Y.Z version")

    merged = [parse_version(value) for value in payload.get("merged_tags", [])]
    latest = max(merged, key=lambda item: version_sort_key(format_version(item)), default=None)
    if branch == prerelease_branch:
        if new_bump is None:
            return {"action": "skip", "reason": "No releasable commits since the latest tag"}
        if latest and latest["tag"] == tag_name and BUMP_RANK[new_bump] <= BUMP_RANK[line_bump(last_stable, latest)]:
            version = f"{format_stable(latest)}-{tag_name}.{latest['num'] + 1}"
        else:
            version = f"{format_stable(apply_bump(last_stable, new_bump))}-{tag_name}.1"
        return {
            "action": "release",
            "version": version,
            "prerelease": True,
            "commits": releasable_subjects(commits),
        }

    betas = [
        item
        for item in merged
        if item["tag"] == tag_name and version_sort_key(format_stable(item)) > version_sort_key(format_stable(last_stable))
    ]
    best_beta = max(betas, key=lambda item: version_sort_key(format_version(item)), default=None)
    if new_bump is None and best_beta is not None:
        return {
            "action": "release",
            "version": format_stable(best_beta),
            "prerelease": False,
            "commits": [f"Promote {format_version(best_beta)}"],
        }
    if new_bump is None:
        return {"action": "skip", "reason": "No releasable commits since the latest stable tag"}
    base = best_beta if best_beta is not None else last_stable
    version = format_stable(apply_bump(base, new_bump))
    return {"action": "release", "version": version, "prerelease": False, "commits": releasable_subjects(commits)}


def format_version(version: dict) -> str:
    stable = format_stable(version)
    if version["tag"] is None:
        return stable
    return f"{stable}-{version['tag']}.{version['num']}"


def update_changelog(existing: str, version: str, subjects: list[str]) -> str:
    lines = [f"## {version}", ""]
    if subjects:
        lines.extend(f"- {subject}" for subject in subjects)
    else:
        lines.append(f"- Release {version}")
    lines.append("")
    section = "\n".join(lines)
    text = existing.strip()
    if not text:
        return f"# Changelog\n\n{section}"
    if text.startswith("# "):
        heading, _, rest = text.partition("\n")
        return f"{heading}\n\n{section}{rest.lstrip()}"
    return f"{section}{text}"


def set_package_version(text: str, version: str) -> str:
    updated, count = re.subn(
        r'("version"\s*:\s*")[^"]+"',
        rf'\g<1>{version}"',
        text,
        count=1,
    )
    if count != 1:
        raise ValueError("package.json does not contain a version field")
    return updated


def parse_changeset_bumps(text: str) -> list[str]:
    if not text.lstrip().startswith("---"):
        return []
    parts = text.split("---", 2)
    if len(parts) < 3:
        return []
    bumps = []
    for line in parts[1].splitlines():
        match = CHANGESET_BUMP_RE.match(line.strip())
        if match:
            bumps.append(match.group("bump"))
    return bumps


def validate_pull_request(payload: dict) -> dict[str, list[str]]:
    """Return release-policy findings for one pull request as {"errors": [...], "warnings": [...]}.

    The pull request title is what actually becomes the release/changelog
    entry and is trivially editable in the GitHub UI with no history rewrite,
    so an invalid title is a hard error. Individual raw commit messages
    (`wip`, `fix typo`, ...) commonly do not follow the convention and fixing
    them requires an amend/rebase + force-push; they are reported as warnings
    so they are visible without blocking the merge. Only the title and the
    changeset bump (when not skipped) determine the release version, so
    warning-only commits do not affect that calculation.
    """
    errors = []
    warnings = []
    title = parse_commit(payload.get("title") or "")
    if not title["valid"]:
        errors.append(
            "Pull request title must be a conventional commit: "
            "fix:, feat:, feat!:, docs:, chore:, or ci:."
        )
    commits = [parse_commit(message) for message in payload.get("commits", [])]
    for commit in commits:
        if not commit["valid"]:
            warnings.append(
                f"Invalid commit title: {commit['subject']} (not a release blocker; "
                "only the pull request title needs to be a conventional commit)"
            )
    if payload.get("skip_changeset"):
        return {"errors": errors, "warnings": warnings}

    bump = highest_bump([title, *commits])
    changeset_bumps = []
    for changeset in payload.get("changesets", []):
        changeset_bumps.extend(parse_changeset_bumps(changeset))
    declared = highest_bump([{"bump": bump_name, "valid": True} for bump_name in changeset_bumps])
    packages_changed = bool(payload.get("packages_changed"))

    if bump is None and declared is not None:
        errors.append("docs:, chore:, and ci: changes cannot include a release changeset")
    elif bump is not None and packages_changed and declared is None:
        errors.append(
            "Package changes require a changeset that declares patch, minor, or major"
        )
    elif bump is not None and declared is not None and declared != bump:
        errors.append(
            f"Changeset bump '{declared}' does not match conventional commit bump '{bump}'"
        )
    return {"errors": errors, "warnings": warnings}


def report_pull_request_findings(result: dict[str, list[str]]) -> int:
    """Print a validate_pull_request()/check_pull_request_from_env() result and return an exit code.

    Warnings are visible but never fail the job; only errors do.
    """
    for warning in result.get("warnings", []):
        print(f"::warning::{warning}")
    errors = result.get("errors", [])
    if errors:
        for error in errors:
            print(f"::error::{error}")
        return 1
    print("Release commit policy passed")
    return 0


def parse_commit_log(blob: str) -> list[str]:
    """Split a `git log --format=%B%x1f` blob into individual commit messages."""
    return [item.strip("\n") for item in blob.split("\x1f") if item.strip()]


def commits_since(base_ref: str) -> list[str]:
    """Commit messages reachable from HEAD but not from origin/<base_ref>."""
    blob = subprocess.check_output(
        ["git", "log", "--format=%B%x1f", f"origin/{base_ref}..HEAD"], text=True
    )
    return parse_commit_log(blob)


def read_changesets(working_directory: str) -> list[str]:
    """Contents of every pending Changeset file under <working_directory>/.changeset."""
    changeset_dir = Path(working_directory or ".") / ".changeset"
    if not changeset_dir.is_dir():
        return []
    return [
        path.read_text(encoding="utf-8")
        for path in sorted(changeset_dir.glob("*.md"))
        if path.name != "README.md"
    ]


def check_pull_request_from_env() -> dict[str, list[str]]:
    """Validate the current pull request using BASE_REF/PR_TITLE/etc. from the environment.

    Callers that only enforce the conventional-commit title (not the changeset
    bump, e.g. application repos) can leave SKIP_CHANGESET/PACKAGES_CHANGED/
    WORKING_DIRECTORY unset; the defaults reproduce that narrower check.
    """
    base_ref = os.environ["BASE_REF"]
    payload = {
        "title": os.environ.get("PR_TITLE", ""),
        "commits": commits_since(base_ref),
        "changesets": read_changesets(os.environ.get("WORKING_DIRECTORY", ".")),
        "packages_changed": os.environ.get("PACKAGES_CHANGED") == "true",
        "skip_changeset": os.environ.get("SKIP_CHANGESET", "true") == "true",
    }
    return validate_pull_request(payload)


def iter_package_json(root: Path) -> list[Path]:
    return [
        path
        for path in root.rglob("package.json")
        if "node_modules" not in path.parts
    ]


def public_versions(root: Path) -> list[dict]:
    """Return publishable packages. Private packages and nameless workspace roots are omitted."""
    found = []
    for path in iter_package_json(root):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        name = data.get("name")
        version = data.get("version")
        if data.get("private") is True or not name or not version:
            continue
        found.append({"name": name, "version": str(version), "path": str(path)})
    return found


def assert_library_versions(root: Path, *, prerelease: bool, tag: str) -> None:
    """Fail when develop would publish a stable version or main would publish a beta."""
    pattern = (
        rf"^\d+\.\d+\.\d+-{re.escape(tag)}\.[1-9]\d*$"
        if prerelease
        else r"^\d+\.\d+\.\d+$"
    )
    errors = []
    for package in public_versions(root):
        if not re.fullmatch(pattern, package["version"]):
            expected = f"{tag}.N starting at 1" if prerelease else "stable X.Y.Z"
            errors.append(f"{package['name']}@{package['version']} is not a {expected} release")
    if errors:
        raise ValueError("; ".join(errors))


def skip_if_already_published(root: Path) -> bool:
    """True when every public package version in <root> is already on npm."""
    packages = public_versions(root)
    if not packages:
        return True
    for package in packages:
        spec = f"{package['name']}@{package['version']}"
        result = subprocess.run(
            ["npm", "view", spec, "version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode != 0:
            return False
    return True


def verify_dist_tag(root: Path, tag: str) -> None:
    """Fail unless npm's `tag` dist-tag matches the local version for every public package."""
    for package in public_versions(root):
        seen = None
        for _ in range(3):
            raw = subprocess.check_output(
                ["npm", "view", package["name"], "dist-tags", "--json"], text=True
            )
            seen = json.loads(raw).get(tag)
            if seen == package["version"]:
                break
            time.sleep(2)
        if seen != package["version"]:
            raise ValueError(
                f"{package['name']} {tag} dist-tag is {seen}, expected {package['version']}"
            )


def shift_initial_prerelease(root: Path, tag: str) -> list[str]:
    """Move Changesets' initial X.Y.Z-tag.0 versions to X.Y.Z-tag.1."""
    package_files = iter_package_json(root)
    versions = []
    for path in package_files:
        try:
            version = json.loads(path.read_text(encoding="utf-8")).get("version", "")
        except (OSError, json.JSONDecodeError):
            continue
        if re.fullmatch(rf"\d+\.\d+\.\d+-{re.escape(tag)}\.0", str(version)):
            versions.append(str(version))
    if not versions:
        return []

    candidates = []
    for pattern in ("package.json", "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "CHANGELOG.md"):
        candidates.extend(path for path in root.rglob(pattern) if "node_modules" not in path.parts)
    changed = []
    for path in sorted(set(candidates)):
        text = path.read_text(encoding="utf-8")
        updated = text
        for version in versions:
            updated = updated.replace(version, f"{version[:-1]}1")
        if updated != text:
            path.write_text(updated, encoding="utf-8")
            changed.append(str(path))
    return changed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    plan = commands.add_parser("plan")
    plan.add_argument("payload")
    baseline = commands.add_parser("baseline")
    baseline.add_argument("payload")
    validate = commands.add_parser("validate-pr")
    validate.add_argument("payload")
    apply = commands.add_parser("apply")
    apply.add_argument("--version", required=True)
    apply.add_argument("--version-file", required=True)
    apply.add_argument("--changelog", required=True)
    apply.add_argument("--subjects-file", required=True)
    shift = commands.add_parser("shift-prerelease")
    shift.add_argument("--root", required=True)
    shift.add_argument("--tag", required=True)
    commands.add_parser(
        "check-pr",
        help="Validate the current pull request from BASE_REF/PR_TITLE/etc. in the environment.",
    )
    skip_published = commands.add_parser("skip-if-published")
    skip_published.add_argument("--root", required=True)
    verify_tag = commands.add_parser("verify-dist-tag")
    verify_tag.add_argument("--root", required=True)
    verify_tag.add_argument("--tag", required=True)
    assert_versions = commands.add_parser("assert-versions")
    assert_versions.add_argument("--root", required=True)
    assert_versions.add_argument("--tag", required=True)
    assert_versions.add_argument("--prerelease", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "plan":
        result = plan_release(json.loads(Path(args.payload).read_text(encoding="utf-8")))
        print(json.dumps(result))
        return 0
    if args.command == "baseline":
        print(select_baseline(json.loads(Path(args.payload).read_text(encoding="utf-8"))) or "")
        return 0
    if args.command == "validate-pr":
        result = validate_pull_request(json.loads(Path(args.payload).read_text(encoding="utf-8")))
        return report_pull_request_findings(result)
    if args.command == "apply":
        version_path = Path(args.version_file)
        version_path.write_text(
            set_package_version(version_path.read_text(encoding="utf-8"), args.version),
            encoding="utf-8",
        )
        changelog_path = Path(args.changelog)
        subjects = [
            line
            for line in Path(args.subjects_file).read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        existing = changelog_path.read_text(encoding="utf-8") if changelog_path.exists() else ""
        changelog_path.write_text(
            update_changelog(existing, args.version, subjects) + "\n",
            encoding="utf-8",
        )
        return 0
    if args.command == "shift-prerelease":
        changed = shift_initial_prerelease(Path(args.root), args.tag)
        print(json.dumps(changed))
        return 0
    if args.command == "check-pr":
        result = check_pull_request_from_env()
        return report_pull_request_findings(result)
    if args.command == "skip-if-published":
        return 0 if skip_if_already_published(Path(args.root)) else 1
    if args.command == "verify-dist-tag":
        verify_dist_tag(Path(args.root), args.tag)
        print(f"dist-tag '{args.tag}' matches the published version for every package")
        return 0
    if args.command == "assert-versions":
        assert_library_versions(Path(args.root), prerelease=args.prerelease, tag=args.tag)
        print("Library package versions match the branch")
        return 0
    raise AssertionError(f"Unhandled command '{args.command}'")


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ValueError as exc:
        print(f"::error::{exc}", file=sys.stderr)
        sys.exit(1)
