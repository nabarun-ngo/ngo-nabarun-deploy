#!/bin/sh
# GAE container entrypoint.
# When Doppler CLI is bundled (deploy.secrets.bundleCli: true), this wrapper
# injects secrets as environment variables before handing control to Node.
# When Doppler is not bundled, it falls through to plain Node execution.

set -e

DOPPLER_BIN="bin/doppler"

if [ -f "$DOPPLER_BIN" ] && [ -n "$DOPPLER_TOKEN" ]; then
  echo "[start.sh] Doppler CLI found. Resolving runtime secrets..."
  exec "$DOPPLER_BIN" run \
    --project="$DOPPLER_PROJECT" \
    --config="$DOPPLER_CONFIG" \
    --token="$DOPPLER_TOKEN" \
    -- node dist/main.js
else
  echo "[start.sh] Running without Doppler (using pre-injected environment variables)."
  exec node dist/main.js
fi
