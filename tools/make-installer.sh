#!/usr/bin/env bash
# Emit scripts/install-phase1.sh: one self-contained bash script that recreates the whole app from
# scratch (heredocs for text, curl for binaries). Keeps the paste-able artifact and the repo in sync.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="scripts/install-phase1.sh"
TMP="$(mktemp)"

FILES=$(find . -type f \
  ! -path './.git/*' ! -path './vendor/*' ! -path './models/*' ! -path './fonts/*' ! -path './icons/*' \
  ! -name 'sw.js' ! -name 'precache.txt' ! -name 'stamp.txt' ! -name 'base-url' ! -name 'install-phase1.sh' \
  ! -name '.DS_Store' ! -name '*.mov' ! -name '*.mp4' \
  | sed 's|^\./||' | sort)

{
  echo '#!/usr/bin/env bash'
  echo '# Pushups PWA — phase 1 installer. Self-contained: writes every source file, then downloads'
  echo '# the MediaPipe wasm + pose models + fonts and generates the icons. Re-runnable; overwrites'
  echo '# only files inside the app folder. Nothing here touches your saved sets (they live on the phone).'
  echo 'set -euo pipefail'
  echo 'ROOT="${1:-$HOME/Projects/pushups}"'
  echo 'mkdir -p "$ROOT"; cd "$ROOT"'
  echo 'umask 022'
  echo

  for f in $FILES; do
    dir=$(dirname "$f")
    if [ "$dir" = "." ]; then
      echo "mkdir -p ."
    else
      echo "mkdir -p '$dir'"
    fi
    marker="__EOF_${f//[^A-Za-z0-9]/_}__"
    echo "cat > '$f' <<'$marker'"
    cat "$f"
    echo "$marker"
    echo
  done

  echo 'chmod +x tools/*.sh scripts/*.py tools/make-icons.py 2>/dev/null || true'
  echo 'chmod +x tools/*.py 2>/dev/null || true'
  echo 'bash tools/fetch-assets.sh'
  echo 'echo "/pushups-pwa/" > tools/base-url'
  echo 'bash tools/build-stamp.sh'
  echo 'echo'
  echo 'echo "Phase 1 written to $ROOT"'
  echo 'echo "Next: ./scripts/deploy.sh -m \"phase 1: counter core\""'
} > "$TMP"

mv "$TMP" "$OUT"
chmod +x "$OUT"
lines=$(wc -l < "$OUT" | tr -d ' ')
bytes=$(wc -c < "$OUT" | tr -d ' ')
echo "scripts/install-phase1.sh: $lines lines, $bytes bytes, $(echo "$FILES" | wc -l | tr -d ' ') files embedded"
