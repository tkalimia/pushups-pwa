#!/usr/bin/env bash
# Build stamp + commit + push to GitHub Pages. Safe to re-run after every phase.
#   ./scripts/deploy.sh -m "phase 1: counter core"
# Optional: REPO_NAME=whatever PRIVATE=1 ./scripts/deploy.sh -m "..."
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_NAME="${REPO_NAME:-pushups-pwa}"
MSG="update"
while [ $# -gt 0 ]; do
  case "$1" in
    -m) MSG="${2:-update}"; shift 2 ;;
    *) echo "ignoring arg: $1"; shift ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "gh not found — brew install gh && gh auth login"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }

USER_LOGIN="$(gh api user -q .login)"
GIT_AUTHOR=()
if ! git config --get user.email >/dev/null 2>&1; then
  GIT_AUTHOR=(-c "user.name=${USER_LOGIN}" -c "user.email=${USER_LOGIN}@users.noreply.github.com")
fi

[ -d .git ] || git init -q -b main
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"

if ! git remote get-url origin >/dev/null 2>&1; then
  if gh repo view "$USER_LOGIN/$REPO_NAME" >/dev/null 2>&1; then
    echo "reusing existing repo $USER_LOGIN/$REPO_NAME"
  else
    echo "creating repo $USER_LOGIN/$REPO_NAME ($([ "${PRIVATE:-0}" = "1" ] && echo private || echo public))"
    if [ "${PRIVATE:-0}" = "1" ]; then
      gh repo create "$REPO_NAME" --private --source=. --description "Camera pushup counter PWA" >/dev/null
    else
      gh repo create "$REPO_NAME" --public --source=. --description "Camera pushup counter PWA" >/dev/null
    fi
  fi
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$USER_LOGIN/$REPO_NAME.git"

bash tools/build-stamp.sh

if ! gh api "repos/$USER_LOGIN/$REPO_NAME/pages" >/dev/null 2>&1; then
  echo "enabling GitHub Pages (branch $BRANCH, /)"
  printf '{"source":{"branch":"%s","path":"/"},"message":"enable pages"}' "$BRANCH" \
    | gh api --method POST "repos/$USER_LOGIN/$REPO_NAME/pages" --input - >/dev/null \
    || echo "  (could not enable Pages automatically — turn it on at Settings ▸ Pages, branch $BRANCH, folder /)"
fi

git add -A
if git diff --cached --quiet; then
  echo "nothing new to commit"
else
  git "${GIT_AUTHOR[@]+"${GIT_AUTHOR[@]}"}" commit -q -m "$MSG"
  echo "committed: $MSG"
fi
git push -q -u origin "$BRANCH"

URL="https://$USER_LOGIN.github.io/$REPO_NAME/"
echo
echo "pushed — waiting for Pages to serve $URL"
for _ in $(seq 1 24); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$URL" || echo 000)
  if [ "$code" = "200" ]; then echo "LIVE  $URL"; exit 0; fi
  sleep 5
done
echo "last status $code — Pages can take a couple of minutes. Check with:"
echo "  gh api repos/$USER_LOGIN/$REPO_NAME/pages"
echo "  $URL"
