#!/usr/bin/env bash
# bridge.sh — delegate a task to a PEER coding agent from whatever agent you're in.
#
# One generic dispatcher for an any-to-any agent bridge. It auto-detects which agent is
# calling (SELF) and that conversation's id, resolves the requested peer's adapter, runs
# the peer headless, streams its work live, and keeps ONE peer session per conversation so
# follow-ups continue where they left off.
#
# State lives in a global, home-rooted store keyed by project — mirroring how Claude
# (~/.claude/projects) and Codex (~/.codex) keep their own session history OUT of your repos:
#   ~/.agent-bridge/projects/<project-slug>/<self>/<chat>/<peer>/{session,logs}
#                                            <self>/<chat>/meta.json
# <self> is recorded because a chat id is an opaque UUID — you can't tell from it which agent
# was primary. Override the root with AGENT_BRIDGE_STATE_DIR (e.g. to keep logs inside a repo).
#
# Usage:
#   bash bridge.sh agents                # list peer agents you can call (everyone but you)
#   bash bridge.sh <peer> "task"         # delegate to <peer>, stream it live
#   bash bridge.sh <peer> reset          # clear this chat's session with <peer>
#   bash bridge.sh reset                 # clear this chat's sessions with all peers
#   bash bridge.sh reset --all           # clear ALL of this project's bridge state (every chat/agent)
#   bash bridge.sh -h | --help           # print usage and exit
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADAPTER_DIR="$SCRIPT_DIR/adapters"

# GUI-launched callers (the desktop apps, IDEs) run this in a non-interactive shell that
# does NOT source ~/.zshrc / ~/.zprofile, so CLIs installed in ~/.local/bin or Homebrew can
# be missing from PATH (the classic "command not found"). Re-add the usual spots so the
# peer CLIs, python3, and node resolve no matter how we were launched.
export PATH="$PATH:$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin:$HOME/.codex/bin"

# --- who am I (SELF), and what's this conversation's id (CHAT)? --------------------
# Each host exposes its conversation id under a different env var, but they all mean the
# same thing: "this chat". Probe the known hosts; allow explicit overrides; otherwise fall
# back to a single shared "default" chat (e.g. when run by hand from a plain terminal).
SELF="${BRIDGE_SELF:-}"
CHAT="${BRIDGE_THREAD_ID:-}"
if [ -n "${CODEX_THREAD_ID:-}" ]; then
  SELF="${SELF:-codex}";  CHAT="${CHAT:-$CODEX_THREAD_ID}"
elif [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  SELF="${SELF:-claude}"; CHAT="${CHAT:-$CLAUDE_CODE_SESSION_ID}"
fi
SELF="${SELF:-unknown}"
CHAT="${CHAT:-default}"

# --- where state lives: global store, keyed by project / primary agent / chat -------
STATE_ROOT="${AGENT_BRIDGE_STATE_DIR:-$HOME/.agent-bridge}"
# Anchor on the git repo root so the project slug is stable no matter which subdir we're
# invoked from; fall back to $PWD outside a repo.
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$PWD"
# Claude-style slug: the absolute path with every non-alphanumeric run turned into a dash.
PROJECT_SLUG="$(printf '%s' "$PROJECT_ROOT" | tr -c '[:alnum:]' '-' | sed 's/--*/-/g')"
PROJECT_DIR="$STATE_ROOT/projects/$PROJECT_SLUG"
CHAT_DIR="$PROJECT_DIR/$SELF/$CHAT"

list_peers() {   # every adapter basename except SELF
  local f name
  for f in "$ADAPTER_DIR"/*.json; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .json)"
    [ "$name" = "$SELF" ] && continue
    echo "$name"
  done
}

usage() {
  cat <<'EOF'
agent-bridge — delegate a task to a peer coding agent from whatever agent you're in.

Usage:
  bash bridge.sh agents                        list peer agents you can call (everyone but you)
  bash bridge.sh <peer> "task"                 delegate to <peer>, streamed live
  bash bridge.sh <peer> --effort <lvl> "task"  set reasoning effort, then delegate
  bash bridge.sh <peer> reset                  clear this chat's session with <peer>
  bash bridge.sh reset                         clear this chat's sessions with all peers
  bash bridge.sh reset --all                   clear ALL of this project's bridge state
  bash bridge.sh -h | --help                   print this help and exit

Effort levels (for --effort): low | medium | high | xhigh | max  (default: high).
Each peer maps these onto its own scale; the run header shows the level actually applied.

Env overrides:
  <PEER>_BIN=/path/to/cli     point at a peer CLI not on PATH (e.g. CLAUDE_BIN, CODEX_BIN)
  AGENT_BRIDGE_EFFORT=<lvl>   default effort when --effort is omitted (default: high)
  AGENT_BRIDGE_STATE_DIR=DIR  where sessions + logs live (default: ~/.agent-bridge)
  AGENT_BRIDGE_MAX_DEPTH=N    max A→B→A delegation depth before refusing (default: 5)
EOF
}

# --- optional reasoning effort -------------------------------------------------------
# Peers run at a reasoning/thinking level (default high). The calling agent maps the user's
# words ("think hard", "quick and rough") to a canonical level; each adapter then maps that
# to its own term (Claude's --effort, Codex's model_reasoning_effort). Pull `--effort <level>`
# out here so the rest stays positional — agents / reset / "<task>" are untouched.
EFFORT="${AGENT_BRIDGE_EFFORT:-high}"
PASS_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    --effort)   shift; EFFORT="${1:-}"
                [ -z "$EFFORT" ] && { echo "agent-bridge: --effort needs a level (low|medium|high|max)" >&2; exit 1; } ;;
    --effort=*) EFFORT="${1#--effort=}" ;;
    *)          PASS_ARGS+=("$1") ;;
  esac
  shift
done
set -- "${PASS_ARGS[@]}"

# ----------------------------------------------------------- subcommands: agents/reset
CMD1="${1:-}"

if [ "$CMD1" = "agents" ]; then
  echo "agent-bridge · you are: $SELF · chat: ${CHAT:0:8} · project: $PROJECT_ROOT"
  peers="$(list_peers)"
  if [ -z "$peers" ]; then
    echo "peers you can call: (none found in $ADAPTER_DIR)"
  else
    echo "peers you can call:"
    echo "$peers" | sed 's/^/  - /'
  fi
  echo "state: $CHAT_DIR"
  exit 0
fi

if [ "$CMD1" = "reset" ]; then
  if [ "${2:-}" = "--all" ]; then
    rm -rf "$PROJECT_DIR"
    echo "agent-bridge: cleared ALL bridge sessions for project $PROJECT_ROOT."
  else
    rm -rf "$CHAT_DIR"
    echo "agent-bridge: cleared this chat's peer sessions (you=$SELF, chat ${CHAT:0:8})."
  fi
  exit 0
fi

# --------------------------------------------------------------------- delegate to peer
TARGET="$CMD1"
if [ -z "$TARGET" ]; then
  usage >&2
  exit 1
fi

ADAPTER_FILE="$ADAPTER_DIR/$TARGET.json"
if [ ! -f "$ADAPTER_FILE" ]; then
  echo "agent-bridge: no adapter for '$TARGET'. Run: bash bridge.sh agents" >&2
  exit 1
fi
if [ "$TARGET" = "$SELF" ]; then
  echo "agent-bridge: refusing to delegate to '$TARGET' — that's you. Pick a peer (bash bridge.sh agents)." >&2
  exit 1
fi

# `<peer> reset` clears just this chat's session with that peer.
if [ "${2:-}" = "reset" ]; then
  rm -rf "$CHAT_DIR/$TARGET"
  echo "agent-bridge: cleared this chat's session with $TARGET (you=$SELF, chat ${CHAT:0:8})."
  exit 0
fi

PROMPT="${2:-}"
if [ -z "$PROMPT" ]; then
  echo "usage: bash bridge.sh $TARGET \"task for $TARGET\"" >&2
  exit 1
fi

# --- loop guard ---------------------------------------------------------------------
# Any-to-any + installed-in-every-agent can recurse (A asks B to review, B asks A, ...).
# Carry depth + the caller chain in the child env and refuse past a bound. A peer that is
# itself the bridge will see these and stop. Also lets a peer detect it was bridge-invoked.
DEPTH="$(( ${AGENT_BRIDGE_DEPTH:-0} + 1 ))"
MAXD="${AGENT_BRIDGE_MAX_DEPTH:-5}"
CHAIN="${AGENT_BRIDGE_CHAIN:+$AGENT_BRIDGE_CHAIN>}$SELF"
if [ "$DEPTH" -gt "$MAXD" ]; then
  echo "agent-bridge: delegation depth $DEPTH exceeds max $MAXD (chain: $CHAIN>$TARGET). Refusing to recurse." >&2
  exit 1
fi
export AGENT_BRIDGE_DEPTH="$DEPTH"
export AGENT_BRIDGE_CHAIN="$CHAIN"
export AGENT_BRIDGE_INVOKED_BY="$SELF"

# --- session state for (this project, this primary, this chat, this peer) -----------
THREAD_DIR="$CHAT_DIR/$TARGET"
mkdir -p "$THREAD_DIR/logs"
SESSION_FILE="$THREAD_DIR/session"
LOG="$THREAD_DIR/logs/$TARGET-$(date +%Y%m%d-%H%M%S).jsonl"
ERRLOG="${LOG%.jsonl}.stderr"   # peer's stderr — kept out of the live view, surfaced only on failure
META_FILE="$CHAT_DIR/meta.json"

# Self-describing metadata for this chat (best-effort; never blocks the run).
python3 "$SCRIPT_DIR/meta.py" "$META_FILE" "$PROJECT_ROOT" "$SELF" "$CHAT" "$TARGET" "$PROMPT" 2>/dev/null || true

MODE="new"; SID=""
if [ -f "$SESSION_FILE" ]; then
  MODE="resume"; SID="$(cat "$SESSION_FILE")"
fi

# Build argv + read adapter fields (BIN, STREAM_FORMAT, SID_KEY, ARGS) in one shot. The
# helper shlex-quotes everything, so the eval is safe even with a hostile prompt/sid.
ADAPTER_SH="$(python3 "$SCRIPT_DIR/adapter.py" "$ADAPTER_FILE" "$MODE" "$PROMPT" "$SID" "$EFFORT")" || {
  echo "agent-bridge: failed to read adapter '$TARGET' ($ADAPTER_FILE)." >&2
  exit 1
}
eval "$ADAPTER_SH"

# --- resolve the peer CLI: <TARGET>_BIN override, then PATH, then common install spots
OVERRIDE_VAR="$(printf '%s' "$TARGET" | tr '[:lower:]-' '[:upper:]_')_BIN"
eval "OVERRIDE_VAL=\"\${$OVERRIDE_VAR:-}\""
BIN_PATH="$OVERRIDE_VAL"
if [ -z "$BIN_PATH" ]; then
  if command -v "$BIN" >/dev/null 2>&1; then
    BIN_PATH="$(command -v "$BIN")"
  else
    for d in "$HOME/.local/bin" "$HOME/.claude/local" "/opt/homebrew/bin" \
             "/usr/local/bin" "$HOME/.npm-global/bin" "$HOME/.codex/bin"; do
      [ -x "$d/$BIN" ] && { BIN_PATH="$d/$BIN"; break; }
    done
  fi
fi
if [ -z "$BIN_PATH" ]; then
  echo "agent-bridge: can't find the '$BIN' CLI for peer '$TARGET' on PATH or the usual spots." >&2
  echo "  Install it, or rerun with ${OVERRIDE_VAR}=/path/to/$BIN." >&2
  exit 127
fi

# Show the requested level; add the peer's mapped term when it differs (e.g. Codex caps max→high).
EFFORT_DISP="$EFFORT"
[ -n "${PEER_EFFORT:-}" ] && [ "$PEER_EFFORT" != "$EFFORT" ] && EFFORT_DISP="$EFFORT→$PEER_EFFORT"
echo "▶ agent-bridge · $SELF → $TARGET · chat ${CHAT:0:8} · effort $EFFORT_DISP · $([ "$MODE" = resume ] && echo 'resuming session' || echo 'new session')$([ "$DEPTH" -gt 1 ] && echo " · chain $CHAIN")"

# Run the peer's full harness, streamed live:
#   stdout -> log (pure JSONL: source of truth + where we read the session id back)
#          -> render (readable live view of the reasoning, not just the final line)
#   stderr -> sidecar file, kept out of the live view (it's mostly chatter like codex's
#             "reading additional input from stdin"); surfaced below only if the peer fails.
# stdin <- /dev/null: the task is passed as an argv, and some peers (e.g. codex exec) will
# otherwise block "reading additional input from stdin" when launched from a pipe.
set +e
"$BIN_PATH" "${ARGS[@]}" < /dev/null 2>"$ERRLOG" \
  | tee "$LOG" \
  | python3 "$SCRIPT_DIR/render.py" --format "$STREAM_FORMAT"
status=${PIPESTATUS[0]}     # the peer's own exit code (not tee's or render's)
set -e

# Process-level failures (crashes, bad flags) land on stderr, not in the JSON stream the
# renderer reads — so surface the stderr sidecar if the peer exited non-zero.
if [ "$status" -ne 0 ] && [ -s "$ERRLOG" ]; then
  echo "── $TARGET stderr (exit $status) ──" >&2
  cat "$ERRLOG" >&2
fi

# Persist the peer's session id even if it errored partway: it's emitted early in the
# stream, so a partial log still carries it. The next call resumes the work-in-progress.
if [ -n "$SID_KEY" ]; then
  # `|| true`: an empty/sid-less log makes grep exit 1, which pipefail+set -e would turn into
  # a spurious script failure that masks the peer's real exit status. Tolerate "no match".
  NEWSID="$(grep -o "\"$SID_KEY\":\"[^\"]*\"" "$LOG" | tail -n1 | sed "s/.*\"$SID_KEY\":\"\([^\"]*\)\".*/\1/" || true)"
  [ -n "$NEWSID" ] && echo "$NEWSID" > "$SESSION_FILE"
fi

exit "$status"
