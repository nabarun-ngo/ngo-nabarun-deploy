# reusable-event-dispatch

Source: [`.github/workflows/reusable-event-dispatch.yml`](../../.github/workflows/reusable-event-dispatch.yml)

Publishes one release fact from an application repository to this repository. It reports that a release exists. It does not deploy. Operators run [ops-deploy-backend](ops-deploy-backend.md) or [ops-deploy-frontend](ops-deploy-frontend.md).

Use this instead of hand-writing `gh api ... /dispatches` in each application repository, so the payload contract lives in one place.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `tag_name` | required | Bare semver tag, no `v` prefix |
| `prerelease` | required | Boolean; must agree with `tag_name` |
| `platform_repository` | `nabarun-ngo/deploy-platform` | Repository that consumes the event |
| `event_type` | `Release-Created` | `repository_dispatch` event type |
| `source_repository` | calling repository | Application the release belongs to |
| `source_ref` | calling ref name | Branch the release was created from |

The job fails when `tag_name` is not bare semver or when `prerelease` disagrees with the tag, so the error points at the caller rather than at the consumer.

## Secrets

| Secret | Required |
|--------|----------|
| `DISPATCH_TOKEN` | Always. `GITHUB_TOKEN` cannot dispatch into another repository |

## Outputs

| Output | Meaning |
|--------|---------|
| `published` | `"true"` when the event was accepted |

## How the client consumes it

Chain it after [reusable-ci-tag-release](reusable-ci-tag-release.md) and publish only when a tag was actually created. The event does not deploy anything:

```yaml
jobs:
  tag_release:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-tag-release.yml@main
    with:
      templates_repository: YOUR_ORG/deploy-platform
      version_file: package.json
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      TEMPLATES_TOKEN: ${{ secrets.TEMPLATES_TOKEN }}

  publish_release_event:
    needs: tag_release
    if: needs.tag_release.outputs.created == 'true'
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-event-dispatch.yml@main
    with:
      tag_name: ${{ needs.tag_release.outputs.tag }}
      prerelease: ${{ needs.tag_release.outputs.prerelease == 'true' }}
    secrets:
      DISPATCH_TOKEN: ${{ secrets.DEPLOY_PLATFORM_TOKEN }}
```
