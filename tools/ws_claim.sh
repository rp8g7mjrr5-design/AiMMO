#!/usr/bin/env bash
# One run per stream at a time. A claim is a branch `claim/<stream>` on GitHub. Its tip is a tiny
# empty commit whose message says what the run is doing and whose date says when it took it;
# "release" pushes a commit whose message starts with "free" (the session's git proxy refuses
# branch deletes). Every push uses --force-with-lease against the tip it just read, so if two
# runs start together only one push can win; the other sees BUSY.
#
#   tools/ws_claim.sh take    <stream> "<what this run is doing>"   # exit 0 = yours, 3 = busy
#   tools/ws_claim.sh note    <stream> "<what this run is doing>"   # refresh it during a long run
#   tools/ws_claim.sh release <stream>
#   tools/ws_claim.sh status  <stream>
#
# Needs no clone of the game, so run it before cloning:
#   bash <(gh api repos/rp8g7mjrr5-design/ZombAi/contents/tools/ws_claim.sh -H "Accept: application/vnd.github.raw") take qa "starting"
# A claim older than AIMMO_CLAIM_STALE_MIN minutes (default 150) belongs to a run that died, and
# the next run takes it over.
set -uo pipefail
REPO=${AIMMO_REPO:-rp8g7mjrr5-design/ZombAi}
URL=${AIMMO_REPO_URL:-https://github.com/$REPO}
STALE_MIN=${AIMMO_CLAIM_STALE_MIN:-150}
cmd=${1:?take|note|release|status}
stream=${2:?stream name}
ref="refs/heads/claim/$stream"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.name "aimmo-$stream"
git -C "$work" config user.email "aimmo-$stream@users.noreply.github.com"

remote_sha() { git -C "$work" ls-remote "$URL" "$ref" | cut -f1; }
new_commit() { # $1 = message
  git -C "$work" commit-tree "$(git -C "$work" hash-object -t tree -w /dev/null)" -m "$1"
}
info() { # prints "<age minutes> <message>" of the current claim, or nothing
  local s d m
  s=$(remote_sha); [ -n "$s" ] || return 1
  d=$(gh api "repos/$REPO/commits/$s" --jq .commit.committer.date 2>/dev/null) || return 1
  m=$(gh api "repos/$REPO/commits/$s" --jq .commit.message 2>/dev/null | head -1)
  echo "$(( ( $(date -u +%s) - $(date -u -d "$d" +%s) ) / 60 )) $m"
}
push_lease() { # $1 = new sha, $2 = expected old sha ("" = must not exist)
  git -C "$work" push -q --force-with-lease="$ref:$2" "$URL" "$1:$ref" 2>/dev/null
}

case "$cmd" in
  take)
    sha=$(new_commit "claim $stream: ${3:-run}")
    if push_lease "$sha" ""; then echo "CLAIMED claim/$stream"; exit 0; fi
    old=$(remote_sha)
    if i=$(info); then
      age=${i%% *}; msg=${i#* }
      if [ "${msg#free}" != "$msg" ] && push_lease "$sha" "$old"; then
        echo "CLAIMED claim/$stream"; exit 0
      fi
      if [ "${msg#free}" = "$msg" ] && [ "$age" -ge "$STALE_MIN" ] && push_lease "$sha" "$old"; then
        echo "CLAIMED claim/$stream (took over a stale claim: $msg, $age min old)"; exit 0
      fi
      echo "BUSY: ${i#* } ($age min ago)"; exit 3
    fi
    echo "BUSY: claim/$stream exists but could not be read"; exit 3 ;;
  note)
    old=$(remote_sha)
    sha=$(new_commit "claim $stream: ${3:-run}")
    push_lease "$sha" "$old" && echo "NOTED claim/$stream" ;;
  release)
    old=$(remote_sha)
    [ -n "$old" ] || { echo "RELEASED claim/$stream"; exit 0; }
    push_lease "$(new_commit "free $stream: released ${3:-}")" "$old" && echo "RELEASED claim/$stream" ;;
  status)
    if i=$(info) && [ "${i#* free}" = "$i" ]; then echo "HELD: ${i#* } (${i%% *} min ago)"; else echo "FREE"; fi ;;
  *) echo "unknown command $cmd" >&2; exit 2 ;;
esac
