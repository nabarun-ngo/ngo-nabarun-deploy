# ops-publish-site

Source: [`.github/workflows/ops-publish-site.yml`](../../.github/workflows/ops-publish-site.yml)

Publishes every `docs/*.html` file to the `gh-pages` root: the portal [`docs/index.html`](../index.html) and the [deployment setup guide](../deployment-setup-guide.html). The job fails if either of those two is missing. `keep_files` preserves the Allure history on the same branch. Markdown under `docs/workflows/` stays in git for the README; it is not copied to Pages. Shares a `gh-pages` concurrency group with the Allure report job so the two writers do not race.

Triggers: push to `main` when `docs/**` or this workflow changes; `workflow_dispatch`.

## How to consume

Edit `docs/index.html`, `docs/deployment-setup-guide.html` (or this workflow) on `main`. No `uses:` from app repos. Enable Pages as in [platform setup](../platform.md#github-pages).
