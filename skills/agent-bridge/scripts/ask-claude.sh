#!/usr/bin/env bash
# ask-claude.sh — delegate a task to Claude Code from whatever project you're in.
# Streams Claude's work live; keeps ONE Claude session PER CODEX THREAD, so each Codex
# conversation maps 1:1 to its own Claude session (state under ./.agent-bridge/threads/<id>/).
# Falls back to a single "default" thread when CODEX_THREAD_ID isn't set (e.g. run by hand).
#
# Usage:
#   bash ask-claude.sh "your task for Claude"
#   bash ask-claude.sh reset        # clear THIS Codex thread's Claude session
#   bash ask-claude.sh reset --all  # clear every thread's session for this project
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"   # the skill's scripts/ dir (render.py lives here)
STATE_DIR="$PWD/.agent-bridge"                # per-project state, in the repo you're in

# One Claude session per Codex thread. CODEX_THREAD_ID is injected by Codex (app/CLI/IDE);
# when it's absent, everything collapses to a single "default" thread.
THREAD="${CODEX_THREAD_ID:-default}"
THREAD_DIR="$STATE_DIR/threads/$THREAD"

if [ "$1" = "reset" ]; then
  if [ "${2:-}" = "--all" ]; then
    rm -rf "$STATE_DIR"
    echo "agent-bridge: cleared ALL Claude sessions for $(basename "$PWD")."
  else
    rm -rf "$THREAD_DIR"
    echo "agent-bridge: cleared this Codex thread's Claude session (${THREAD:0:8})."
  fi
  exit 0
fi

if [ -z "${1:-}" ]; then
  echo "usage: bash ask-claude.sh \"task for Claude\"   (reset | reset --all)" >&2
  exit 1
fi
PROMPT="$1"

mkdir -p "$THREAD_DIR/logs"
SESSION_FILE="$THREAD_DIR/session"
LOG="$THREAD_DIR/logs/claude-$(date +%Y%m%d-%H%M%S).jsonl"

# Continue this Codex thread's Claude conversation across calls, if one exists.
RESUME=""
if [ -f "$SESSION_FILE" ]; then
  RESUME="--resume $(cat "$SESSION_FILE")"
fi

echo "▶ agent-bridge · codex-thread ${THREAD:0:8} · $([ -n "$RESUME" ] && echo 'resuming Claude session' || echo 'new Claude session')"

# Full Claude Code harness, auto mode, MAX reasoning effort, streamed live.
#   raw NDJSON -> log (source of truth + where we read the session id back)
#   readable   -> screen / caller (Codex sees the reasoning, not just the final line)
set +e
claude -p "$PROMPT" $RESUME \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --verbose \
  --effort max \
  | tee "$LOG" \
  | python3 "$SCRIPT_DIR/render.py"
status=${PIPESTATUS[0]}     # Claude's own exit code (not tee's or render's)
set -e

# Persist the session id even if Claude errored partway: it's emitted in the very first
# (init) event, so a partial log still carries it. This lets the next call resume the
# work-in-progress instead of starting over.
SID="$(grep -o '"session_id":"[^"]*"' "$LOG" | tail -n1 | sed 's/.*"session_id":"\([^"]*\)".*/\1/')"
if [ -n "$SID" ]; then
  echo "$SID" > "$SESSION_FILE"
fi

exit "$status"
