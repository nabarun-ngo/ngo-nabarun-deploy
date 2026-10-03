# reusable-deploy-gae-node

Source: [`.github/workflows/reusable-deploy-gae-node.yml`](../../.github/workflows/reusable-deploy-gae-node.yml)

Build, optional migrate, deploy a Node.js service to Google App Engine. Manifest fields are passed in as inputs (usually from [resolve-manifest](../../.github/actions/resolve-manifest/action.yml) after [reusable-setup-context](reusable-setup-context.md)).

Migrate and deploy jobs bind to a GitHub Environment when `use_gh_env` is true (default). The build job does not.

## Who calls it

[ops-deploy-backend](ops-deploy-backend.md). Application repos do not call this directly.

## Inputs (environment)

| Input | Default | Meaning |
|-------|---------|---------|
| `use_gh_env` | `true` | Bind migrate/deploy to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

Logical target (`stage` / `prod`) remains `target_environment`.

## How the client consumes it

Do not `uses:` this from an app repo. Operators run **Ops — Deploy Backend (GAE)**, or send `repository_dispatch` type `Trigger-Deploy-Backend`. That caller resolves the manifest and invokes this reusable:

```yaml
jobs:
  deploy:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-deploy-gae-node.yml@main
    with:
      # ... manifest fields ...
      ref: ${{ needs.resolve_ref.outputs.ref }}
      use_gh_env: true
      gh_env: ${{ needs.resolve_env.outputs.gh_env }}
      target_environment: stage
```

For a new backend, add `config/manifests/<name>.json` with `"platform": "gae"` and extend the ops caller’s manifest `choice` list. See [platform setup](../platform.md).

## How a deploy moves

GitHub Actions compiles the app. App Engine does not clone the application repository. `gcloud app deploy` uploads the staged bundle, and Cloud Build’s source is that upload.

```text
caller (ops-deploy-backend)
  → build job
       checkout app at ref
       npm ci + build command
       stage deploy-bundle
       upload GitHub artifact gae-bundle-<app>-<run id>
  → migrate job (only when database.migrate is true; GitHub Environment)
       download the same artifact
       doppler run -- <db command>
  → deploy job (GitHub Environment)
       download the same artifact
       render app.yaml into the bundle
       append DOPPLER_TOKEN when the Doppler CLI is bundled
       gcloud app deploy app.yaml --no-promote --version run-<run id>
            upload bundle to gs://staging.<project>.appspot.com/ae/...
            Cloud Build fetches that object (step "fetch")
            Node.js buildpack runs npm ci
            new version exists at 0% traffic
       poll <versionUrl><health path> until HTTP 200
       gcloud app services set-traffic <service> --splits <version>=1
```

Stage and prod both wait on a GitHub Environment. The build job does not. A failed migration does not start `gcloud app deploy`. A failed health check leaves the new version at 0% traffic.

## What is in the uploaded bundle

[`stage-node-artifact`](../../.github/actions/stage-node-artifact/stage-bundle.sh) writes `deploy-bundle/` from the GitHub Actions build, not from a second clone inside Cloud Build.

| Path | Source |
|------|--------|
| `dist/` | `outputPath` after the build command (`nest build` for the backend) |
| `package.json`, `package-lock.json` | app directory |
| `prisma/`, `prisma.config.ts` | `bundleIncludes` |
| `start.sh` | [`config/platforms/gae/start.sh`](../../config/platforms/gae/start.sh) |
| `bin/doppler` | downloaded when `bundleCli` is true |
| `app.yaml` | rendered in the deploy job from [`app.yaml.tpl`](../../config/platforms/gae/app.yaml.tpl) |

`src/`, `tsconfig.json`, and `nest-cli.json` are not uploaded. Production `node_modules` are installed into the bundle for the migration job, then omitted from the App Engine upload: with no `.gcloudignore`, `gcloud` generates one that ignores `node_modules/`. Cloud Build runs `npm ci` again (`NODE_ENV=development`, so devDependencies are present for the image build).

`start.sh` starts `node dist/main.js`, wrapped in `doppler run` when `bin/doppler` and `DOPPLER_TOKEN` are both present.

## Cloud Build and `npm run build`

The `nodejs24` buildpack runs `npm run build` whenever `package.json` has a `build` script, unless `GOOGLE_NODE_RUN_SCRIPTS` is set. The backend script is `npm run clean && npm run generate:db && nest build`. `clean` deletes `dist/`, then Prisma generate needs `DATABASE_URL`, which Cloud Build does not have. That fails the deploy even though GitHub Actions already compiled `dist/`.

[`app.yaml.tpl`](../../config/platforms/gae/app.yaml.tpl) sets this under `build_env_variables`, which is build time, not the runtime `env_variables` block:

```yaml
build_env_variables:
  GOOGLE_NODE_RUN_SCRIPTS: ""
```

After that, the Cloud Build log should show `npm ci` and should not show `Running "npm run build"`. Cloud Build still runs: it installs dependencies and packages the uploaded `dist/` into the App Engine version. It does not compile the Nest app.

`NODE_ENV: "production"` in `env_variables` is the Node runtime mode for both stage and prod. It is not the deploy target. Stage versus prod is the App Engine service (`gaeService`) and the Doppler config (`stg` or `prd`).

## Where a failure shows up

| Symptom | Look at |
|---------|---------|
| Install or `nest build` failed | GitHub Actions build job. No Cloud Build yet. |
| Migration failed | GitHub Actions migrate job. No `gcloud app deploy`. |
| Template or credentials failed | Deploy job, before a Cloud Build id. |
| Cloud Build step `fetch` | `gs://staging.<project>.appspot.com/ae/.../manifest.json`. That object is the bundle, not GitHub. |
| `Running "npm run build"` then `DATABASE_URL` or missing `src/` | `GOOGLE_NODE_RUN_SCRIPTS` was not in the rendered `app.yaml`. The buildpack deleted `dist/` and tried to compile again. |
| Health check timeout | Version `run-<run id>` exists at 0% traffic. Traffic was not moved. |
| Promote failed | Same: version exists, previous version still serves. |
