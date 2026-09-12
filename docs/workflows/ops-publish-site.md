# ops-publish-site

Source: [`.github/workflows/ops-publish-site.yml`](../../.github/workflows/ops-publish-site.yml)

Publishes [`docs/index.html`](../index.html) only to the `gh-pages` root (`keep_files` so Allure history is preserved). Markdown under `docs/workflows/` stays in git for the README; it is not copied to Pages. Shares a `gh-pages` concurrency group with the Allure report job so the two writers do not race.

Triggers: push to `main` when `docs/**` or this workflow changes; `workflow_dispatch`.

## How to consume

Edit `docs/index.html` (or this workflow) on `main`. No `uses:` from app repos. Enable Pages as in [platform setup](../platform.md).
