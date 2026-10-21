#!/usr/bin/env bash
# Give the blocked-camera screen a way OUT, not just a lecture.
#
# iOS withholds getUserMedia from a web app launched from its Home Screen icon (WebKit bug 185448,
# still open). Nothing in the app can change that — the only working path is a Safari tab. So when
# we detect the dead end we now offer two one-tap exits:
#
#   • "Open in Safari" — a target=_blank link, which is the documented way to break out of a
#     standalone web app on iOS.
#   • "Copy address" — the fallback that cannot fail: it puts the URL on the clipboard so it can be
#     pasted into Safari once, after which a Safari favorite makes it a single tap forever.
#
# Both are only added in standalone mode; in a Safari tab the camera normally works and the card
# would be noise. Every action is a real 44px control, brass as a solid fill (a bright hue only
# survives as a fill on a near-black surface, per the palette rules).
#
#   bash scripts/safari-handoff.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, sys

def sub(path, old, new, count=1):
    p = pathlib.Path(path)
    text = p.read_text()
    if new in text and old not in text:
        print(f'skip (already applied): {path}')
        return
    if text.count(old) != count:
        sys.exit(f'FAIL {path}: anchor found {text.count(old)}x, expected {count}\n---\n{old}\n---')
    p.write_text(text.replace(old, new))
    print(f'patched {path}')

sub('css/app.css',
""".camoff ol{margin:0;padding-left:18px;font-size:13px;line-height:1.55;text-align:left}""",
""".camoff ol{margin:0;padding-left:18px;font-size:13px;line-height:1.55;text-align:left}
/* the two exits from the standalone dead end */
.camoff .act{display:flex;gap:8px;flex-wrap:wrap;justify-content:center}
.camoff .act a,.camoff .act button{display:inline-flex;align-items:center;justify-content:center;
  min-height:44px;padding:0 16px;border-radius:12px;border:0;font:600 14px/1 var(--ui);text-decoration:none}
.camoff .act .primary{background:var(--brass-fill);color:var(--on-brass)}
.camoff .act .ghost{background:transparent;color:var(--porcelain);box-shadow:inset 0 0 0 1px rgba(233,238,234,.3)}
.camoff .addr{font-size:12px;line-height:1.4;color:var(--porcelain);word-break:break-all;max-width:32ch}""")

sub('js/views/train.js',
"""    els.camoff.append(h3, ol);
    els.pillText.textContent = 'camera blocked';
  }""",
"""    els.camoff.append(h3, ol);
    if (isStandalone()) appendSafariExits();
    els.pillText.textContent = 'camera blocked';
  }

  /* The Home Screen icon can never have the camera, so the screen has to hand him to Safari
     rather than explain Apple's policy at him. stopPropagation because a tap here is a button
     press, not the wake gesture the preview overlay listens for. */
  function appendSafariExits() {
    const url = location.href.split('#')[0] + '#/train';
    const row = document.createElement('div');
    row.className = 'act';
    const link = document.createElement('a');
    link.className = 'primary';
    link.textContent = 'Open in Safari';
    link.href = url;
    link.target = '_blank';
    link.rel = 'noopener';
    link.addEventListener('click', (e) => e.stopPropagation());
    const copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'ghost';
    copy.textContent = 'Copy address';
    copy.addEventListener('click', (e) => {
      e.stopPropagation();
      const fallback = () => {
        const addr = document.createElement('div');
        addr.className = 'addr';
        addr.textContent = url;
        els.camoff.append(addr);
        copy.remove();
      };
      if (navigator.clipboard?.writeText) {
        navigator.clipboard.writeText(url).then(() => { copy.textContent = 'Copied — paste in Safari'; }, fallback);
      } else fallback();
    });
    row.append(link, copy);
    els.camoff.append(row);
  }""")

print('done')
PY
