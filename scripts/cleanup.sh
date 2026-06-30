#!/usr/bin/env bash
# cleanup.sh — wipe ALL agent-bridge session state (every project, chat, peer, and log).
#
# agent-bridge stores its chat sessions + transcripts in a home-rooted folder (default
# ~/.agent-bridge), outside your repos. This removes that whole store — handy to reclaim
# space or start clean. It does NOT touch the installed skill or any of your repos, only
# saved bridge history. (For finer scopes, bridge.sh has `reset` and `reset --all`.)
#
# Usage:
#   bash scripts/cleanup.sh        # show what will go, then confirm
#   bash scripts/cleanup.sh -y     # skip the prompt (for automation)
#
# Honors AGENT_BRIDGE_STATE_DIR — the same override bridge.sh uses.
set -eo pipefail

STATE_ROOT="${AGENT_BRIDGE_STATE_DIR:-$HOME/.agent-bridge}"

# Never let an empty or misconfigured override aim rm at something catastrophic.
case "$STATE_ROOT" in
  ""|"/"|"$HOME"|"$HOME/")
    echo "cleanup: refusing to wipe '$STATE_ROOT' — that's not an agent-bridge store." >&2
    exit 1 ;;
esac

if [ ! -d "$STATE_ROOT" ]; then
  echo "cleanup: nothing to do — $STATE_ROOT does not exist."
  exit 0
fi

size="$(du -sh "$STATE_ROOT" 2>/dev/null | cut -f1 || true)"
projects=0
[ -d "$STATE_ROOT/projects" ] && projects="$(find "$STATE_ROOT/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || true)"
echo "agent-bridge store: $STATE_ROOT  (${projects:-?} project(s), ${size:-?} on disk)"

case "${1:-}" in
  -y|--yes|--force) ;;   # skip the prompt
  *)
    printf "Remove ALL agent-bridge sessions and logs? [y/N] "
    read -r reply || reply=""
    case "$reply" in
      y|Y|yes|YES) ;;
      *) echo "cleanup: aborted — nothing removed."; exit 0 ;;
    esac ;;
esac

rm -rf "$STATE_ROOT"
echo "cleanup: removed $STATE_ROOT — freed ${size:-?}."
