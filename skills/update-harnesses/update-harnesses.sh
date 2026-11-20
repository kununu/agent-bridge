#!/usr/bin/env bash
# update-harnesses.sh — update the agent CLIs to their latest versions.
#
# Usage:
#   update-harnesses.sh                 # claude, codex, agy
#   update-harnesses.sh codex agy       # just these
#
# A CLI that isn't installed is skipped; a failed update doesn't stop the rest.
# Exits non-zero only if an installed CLI failed to update.

HARNESSES=(claude codex agy)  # keep in sync with skills/agent-bridge/scripts/adapters/
[ $# -gt 0 ] && HARNESSES=("$@")

# No TTY (run by an agent): an update that prompts should fail, not hang.
[ -t 0 ] || exec </dev/null

version() { "$1" --version 2>/dev/null | head -n1; }

summary=()
failed=0
for bin in "${HARNESSES[@]}"; do
  echo "── $bin"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "not installed, skipping"
    summary+=("$bin: not installed, skipped")
    continue
  fi
  before="$(version "$bin")"
  if "$bin" update; then
    after="$(version "$bin")"
    if [ "$before" = "$after" ]; then
      summary+=("$bin: up to date ($after)")
    else
      summary+=("$bin: $before → $after")
    fi
  else
    summary+=("$bin: FAILED (exit $?)")
    failed=1
  fi
  echo
done

echo "── summary"
printf '%s\n' "${summary[@]}"
exit "$failed"
