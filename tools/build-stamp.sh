#!/usr/bin/env bash
# Regenerate sw.js from tools/sw.template.js with a fresh cache version + precache list.
set -euo pipefail
cd "$(dirname "$0")/.."

# Precache entries stay relative: the service worker lives next to index.html, so the browser
# resolves them against the app root wherever it is hosted (a Pages subpath or a domain root).

BUILD="$(date +%y%m%d%H%M)"
{ date -u +%FT%TZ; echo "$BUILD"; } > tools/stamp.txt

# The nosimd wasm pair is a desktop-Safari fallback, and pose_landmarker_full is an opt-in in
# Settings. Keeping all three out of the precache holds the phone's first download to ~11 MB;
# they are still cached permanently the first time they are used.
find . -type f \
  ! -path './.git/*' ! -name 'sw.js' ! -name 'serve.py' \
  ! -path './tools/*' ! -path './tests/*' ! -path './scripts/*' \
  ! -name '.DS_Store' ! -name '.*' ! -name '*.mov' ! -name 'config.json' \
  ! -name '*nosimd*' ! -name 'pose_landmarker_full.task' \
  | sed 's|^\./||' | sort > tools/precache.txt

/usr/bin/python3 - "$BUILD" <<'PY'
import pathlib, sys
build = sys.argv[1]
files = [f for f in pathlib.Path('tools/precache.txt').read_text().splitlines() if f.strip()]
items = ',\n  '.join('"%s"' % f for f in files)
tpl = pathlib.Path('tools/sw.template.js').read_text()
out = tpl.replace('__BUILD__', build).replace('__PRECACHE__', '[\n  %s\n]' % items)
pathlib.Path('sw.js').write_text(out)
print('sw.js stamped: build %s, %d files precached' % (build, len(files)))
PY
