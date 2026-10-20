#!/usr/bin/env bash
# Local iteration: stamp the service worker, serve the folder, and (optionally) put it behind real
# HTTPS so an iPhone can reach it before you deploy.
#
#   ./scripts/dev.sh              # http://localhost:8080 — desktop testing only
#   ./scripts/dev.sh --tunnel     # also prints a throwaway https://<random>.trycloudflare.com URL
#
# iOS blocks the camera on a plain http:// LAN address, so a phone must reach the app over real
# HTTPS. The tunnel URL works but changes every time it restarts — treat it as a smoke test only.
# The stable install is the Pages URL from ./scripts/deploy.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/build-stamp.sh
PORT="${PORT:-8080}"

if [ "${1:-}" = "--tunnel" ]; then
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found — brew install cloudflared"; exit 1
  fi
  ( cloudflared tunnel --url "http://localhost:$PORT" 2>&1 \
    | sed -n 's/.*https:\/\/\([a-z0-9-]*\)\.trycloudflare\.com.*/CLOUDFLARE https:\/\/\1.trycloudflare.com/p' & )
fi

echo "serving $PWD at http://localhost:$PORT  (ctrl-c to stop)"
exec /usr/bin/python3 tools/serve.py "$PORT"
