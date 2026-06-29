#!/usr/bin/env bash
# ask-codex.sh — hand a task to Codex, stream the work, keep one session.
# Mirror of ask-claude.sh, for when you flip roles (Claude drives, Codex executes/reviews),
# or when the driver just wants a second opinion from Codex.
# Usage: bash ask-codex.sh "your task for Codex"
set -eo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SESSION_FILE="$ROOT/.codex-session"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/codex-$(date +%Y%m%d-%H%M%S).jsonl"

if [ -z "$1" ]; then
  echo "usage: bash ask-codex.sh \"task for Codex\"" >&2
  exit 1
fi
PROMPT="$1"

# Full access (edits + network), no approval prompts. Stream raw JSONL to screen + log.
if [ -f "$SESSION_FILE" ]; then
  codex exec --json --sandbox danger-full-access --skip-git-repo-check \
    resume "$(cat "$SESSION_FILE")" "$PROMPT" | tee "$LOG"
else
  codex exec --json --sandbox danger-full-access --skip-git-repo-check \
    "$PROMPT" | tee "$LOG"
fi

# Remember the session (Codex calls it a thread) for the next call.
SID="$(grep -o '"thread_id":"[^"]*"' "$LOG" | tail -n1 | sed 's/.*"thread_id":"\([^"]*\)".*/\1/')"
if [ -n "$SID" ]; then
  echo "$SID" > "$SESSION_FILE"
fi
