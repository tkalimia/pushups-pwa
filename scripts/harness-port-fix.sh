#!/usr/bin/env bash
# repcheck said "frames arrive, counter does not understand them" for a whole afternoon. Both
# halves of that sentence were lies: the frames were not from the clip.
#
# Every harness hard-codes a debug port (9333…9344) and none of them killed their Chrome on the
# failure path. So runs leaked — 32 headless browsers were alive, some for over an hour — and a
# leaked browser keeps holding the port. The next run's Chrome cannot bind it, exits quietly, and
# the CDP client's poll loop finds the OLD browser and drives that instead. The old one had no
# fake-device flag, so getUserMedia returned the MacBook's real camera: repcheck spent the
# afternoon filming Tal at his desk, which is exactly why landmark visibility read 35-44% where
# the same clip produces 98% through the file-replay path.
#
# Verified by pulling the pixels out of the video element (a room, a ceiling lamp, a person).
#
# Two fixes:
#   1. Chrome is asked for port 0 and the real port is read from DevToolsActivePort inside that
#      run's own profile directory — it cannot collide, because the file belongs to the profile.
#   2. Every harness kills its browser on every exit path, including the ones that throw.
#
#   bash scripts/harness-port-fix.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, re, sys

FILES = [
    'tools/audit.mjs', 'tools/shots.mjs', 'tools/trace.mjs', 'tools/repcheck.mjs',
    'tools/camfailcheck.mjs', 'tools/loopcheck.mjs',
    'scripts/trace-reps.sh', 'scripts/repcheck.sh', 'scripts/verify-failure-card.sh',
    'scripts/harden-camera-path.sh',
]

SLEEP_ANCHOR = r'const sleep = \(ms\) => new Promise\(\(r\) => setTimeout\(r, ms\)\);\n'
STDERR_ANCHOR = "chrome.stderr.on('data', (d) => { chromeErr += d.toString(); });"

def helper(var):
    return """// Chrome binds an ephemeral port and records it in its own profile directory. A hard-coded port
// is a race the previous run wins: the new Chrome cannot bind, and the CDP client attaches to the
// stale browser instead — different camera, different cache, different build, all invisible.
const readPort = async () => {
  for (let i = 0; i < 120; i++) {
    try {
      const line = readFileSync(join(%s, 'DevToolsActivePort'), 'utf8').trim().split('\\n')[0];
      if (Number(line) > 0) return Number(line);
    } catch (err) { void err; }
    await sleep(250);
  }
  return 0;
};
let CDP_PORT = 0;
""" % var

TEARDOWN = """
// A harness that exits through an exception used to leave its Chrome running for hours, holding a
// debug port and a camera. This runs on every path out, including the ones that throw.
const teardown = () => { try { chrome.kill('SIGKILL'); } catch (err) { void err; } };
process.on('exit', teardown);
process.on('uncaughtException', () => { teardown(); process.exit(1); });
process.on('SIGINT', () => { teardown(); process.exit(130); });
process.on('SIGTERM', () => { teardown(); process.exit(143); });
"""

def port_fix(name, text):
    inline = re.search(r"--user-data-dir=\$\{(mkdtempSync\(join\(tmpdir\(\), '[^']+'\)\))\}", text)
    named = re.search(r"const (profile|PROFILE|profileDir) = (mkdtempSync\([^)]*\))", text)
    if inline:
        text = text.replace(inline.group(0), '--user-data-dir=${PROFILE}')
        anchor = re.search(r'const chrome = spawn\(CHROME, \[', text)
        if not anchor:
            sys.exit(f'FAIL {name}: no spawn() anchor for the profile declaration')
        text = text[:anchor.start()] + 'const PROFILE = ' + inline.group(1) + ';\n' + text[anchor.start():]
        var = 'PROFILE'
    elif named:
        var = named.group(1)
    else:
        sys.exit(f'FAIL {name}: cannot find a user-data-dir to name')

    text = re.sub(r'--remote-debugging-port=\$\{PORT\}', '--remote-debugging-port=0', text)
    text = re.sub(r'const PORT = \d+;\n', '', text, count=1)

    anchor = re.search(SLEEP_ANCHOR, text)
    if not anchor:
        sys.exit(f'FAIL {name}: no sleep() anchor for the readPort helper')
    text = text[:anchor.end()] + helper(var) + '\n' + text[anchor.end():]

    fetch_re = re.compile(
        r'( *)const (\w+) = await \(await fetch\(`http://127\.0\.0\.1:\$\{PORT\}/json/list`\)\)\.json\(\);')
    if not fetch_re.search(text):
        sys.exit(f'FAIL {name}: no /json/list anchor')
    text = fetch_re.sub(
        lambda m: (m.group(1) + 'if (!CDP_PORT) CDP_PORT = await readPort();\n'
                   + m.group(1) + 'const ' + m.group(2)
                   + ' = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();'),
        text, count=1)
    if '${PORT}' in text:
        sys.exit(f'FAIL {name}: a ${{PORT}} reference survived')

    text = re.sub(r"import \{ ([^}]*?) \} from 'node:fs';",
                  lambda m: "import { " + (m.group(1) if 'readFileSync' in m.group(1)
                            else m.group(1).rstrip() + ', readFileSync') + " } from 'node:fs';",
                  text, count=1)
    if 'readFileSync' not in text:
        sys.exit(f'FAIL {name}: readFileSync import not added')
    return text

def teardown_fix(name, text):
    if STDERR_ANCHOR not in text or text.count(STDERR_ANCHOR) != 1:
        sys.exit(f'FAIL {name}: stderr anchor found {text.count(STDERR_ANCHOR)}x, expected 1')
    return text.replace(STDERR_ANCHOR, STDERR_ANCHOR + '\n' + TEARDOWN)

for name in FILES:
    p = pathlib.Path(name)
    if not p.exists():
        print(f'absent, skipped: {name}')
        continue
    text = p.read_text()
    before = text
    done = []
    if 'DevToolsActivePort' not in text:
        text = port_fix(name, text)
        done.append('port')
    if "'exit', teardown" not in text:
        text = teardown_fix(name, text)
        done.append('teardown')
    if not done:
        print(f'skip (already applied): {name}')
        continue
    if text == before:
        sys.exit(f'FAIL {name}: nothing changed')
    p.write_text(text)
    print(f'patched {name}: {", ".join(done)}')
PY

echo
echo 'live harness browsers after this run (should be none):'
ps -Ao pid,etime,command | grep '[h]eadless=new' | grep -Eo 'user-data-dir=[^ ]*' | head || true
