# reusable-ci-publish

Source: [`.github/workflows/reusable-ci-publish.yml`](../../.github/workflows/reusable-ci-publish.yml)

Reusable **Changesets** pipeline. Three jobs:

1. **version** — open a Version Packages PR, or if no pending changesets, read semver from `version_file`.
2. **npm** — only if `publish_to_npm` and version is already in git. Runs `publish_command` exactly as the caller passed it (stable vs beta is the caller’s choice).
3. **tags_and_releases** — only if `create_tags_and_releases` and version is ready. Git tag and GitHub Release use the **bare** version (`1.4.0`, no `v` prefix).

Does not auto-deploy. Does not invent versions from conventional commits.

## Who calls it

- Library repos (for example web-toolkit): npm on, tags off.
- App repos after packages are split: npm off, tags on. Apps install libraries from npmjs.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `node_version` | `22` | Node.js |
| `working_directory` | `.` | Install / Changesets cwd |
| `npm_scope` | empty | `setup-node` scope |
| `version_command` | `npm run version-packages` | Changesets version |
| `publish_to_npm` | `true` | Run the npm job |
| `publish_command` | `npm run release` | Publish command (caller chooses latest vs beta) |
| `create_tags_and_releases` | `false` | Git tag + GitHub Release |
| `version_file` | `package.json` | Semver source for tags |
| `changeset_title` / `changeset_commit` | `chore: version packages` | Version PR |
| `use_gh_env` | `false` | Bind jobs to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

## Secrets

| Secret | Required |
|--------|----------|
| `GH_TOKEN` | Always (pass `secrets.GITHUB_TOKEN`) |
| `NPM_TOKEN` | When `publish_to_npm` is true |

## How the client consumes it — library (npm)

`.github/workflows/release.yml` in the package repo. On `stage`, run once: `npx changeset pre enter beta` and commit `.changeset/pre.json`.

```yaml
name: Release

on:
  push:
    branches: [main, stage]

jobs:
  publish:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-publish.yml@main
    with:
      node_version: '22'
      working_directory: '.'
      npm_scope: '@web-toolkit'
      version_command: 'npm run version-packages'
      publish_to_npm: true
      publish_command: ${{ github.ref_name == 'main' && 'npm run release' || 'npm run release:beta' }}
      create_tags_and_releases: false
      # use_gh_env: true
      # gh_env: prod
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## How the client consumes it — app (tags only)

`.github/workflows/release.yml` in the app repo. One private app package. Deploy later via ops against tag `1.4.0` or `1.4.0-beta.2`.

```yaml
name: Release

on:
  push:
    branches: [main, stage]

jobs:
  release:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-publish.yml@main
    with:
      node_version: '22'
      version_command: 'npm run version-packages'
      version_file: package.json
      publish_to_npm: false
      create_tags_and_releases: true
      # use_gh_env: true
      # gh_env: prod
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
