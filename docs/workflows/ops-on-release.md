# ops-on-release

Source: [`.github/workflows/ops-on-release.yml`](../../.github/workflows/ops-on-release.yml)

Decides whether a published release is deployed. Application repositories do not send a deploy instruction. They send a release fact, and this workflow applies the policy.

Trigger: `repository_dispatch` type `Release-Created`.

## Event contract

| Field | Meaning |
|-------|---------|
| `repository` | Application repository, `owner/name` |
| `tag_name` | Bare semver tag that was just created |
| `prerelease` | `true` or `false`; must agree with the tag |
| `ref` | Branch the release was created from |

There is no `manifest_name` and no `target_environment`. This repository matches `repository` to `source.repository` in [config/manifests](../../config/manifests).

## Decision

| Release | Result |
|---------|--------|
| Prerelease tag for a Google App Engine manifest | Deploy that tag to stage |
| Stable tag | Record it and skip. Production stays a manual run of [ops-deploy-backend](ops-deploy-backend.md) |
| Repository with no manifest, or a non-GAE manifest | Record it and skip |
| Repository matching several manifests, none of them App Engine | Record it and skip; no manifest name is reported |
| `prerelease` does not match the tag | Fail |
| Several App Engine manifests share the repository | Fail |

One repository may own several manifests — `ngo-nabarun-fe` builds both frontend apps. Because the only automatic path is a prerelease tag on an App Engine manifest, the match is narrowed to App Engine manifests first, and sharing a repository is only ambiguous when more than one of them deploys to App Engine. A repository with exactly one App Engine manifest resolves to it even when other manifests on another platform share the repository.

The `prerelease`/tag agreement check runs before any manifest is read, so a malformed payload fails the same way regardless of which manifests match.

Stage deploy uses [reusable-deploy-gae-node](reusable-deploy-gae-node.md) and the GitHub Environment `stage`. [Trigger-Deploy-Backend](ops-deploy-backend.md) remains the explicit deploy request, including every production deploy.

## How an application publishes it

Call [reusable-ci-release-event](reusable-ci-release-event.md) after [reusable-ci-tag-release](reusable-ci-tag-release.md) reports `created=true`. That workflow owns the payload shape, so application repositories do not hand-write the dispatch:

```yaml
  publish_release_event:
    needs: tag_release
    if: needs.tag_release.outputs.created == 'true'
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-release-event.yml@main
    with:
      tag_name: ${{ needs.tag_release.outputs.tag }}
      prerelease: ${{ needs.tag_release.outputs.prerelease == 'true' }}
    secrets:
      DISPATCH_TOKEN: ${{ secrets.DEPLOY_PLATFORM_TOKEN }}
```

The equivalent raw call is:

```bash
gh api --method POST -H "Accept: application/vnd.github+json" \
  /repos/YOUR_ORG/deploy-platform/dispatches \
  -f event_type=Release-Created \
  -f 'client_payload[repository]=YOUR_ORG/ngo-nabarun-be' \
  -f 'client_payload[tag_name]=1.4.0-beta.1' \
  -f 'client_payload[prerelease]=true' \
  -f 'client_payload[ref]=develop'
```

`GITHUB_TOKEN` from the application repository cannot dispatch into this repository. Store a token that can create dispatches here as `DEPLOY_PLATFORM_TOKEN` in the application repository.
