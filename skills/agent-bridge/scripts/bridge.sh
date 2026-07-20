#!/usr/bin/env bash
# bridge.sh — delegate a task to a PEER coding agent from whatever agent you're in.
#
# One generic dispatcher for an any-to-any agent bridge. It auto-detects which agent is
# calling (SELF) and that conversation's id, resolves the requested peer's adapter, runs
# the peer headless, streams its work live, and keeps ONE peer session per conversation
# *thread* so follow-ups continue where they left off. Threads exist so parallel helper
# subagents (which all inherit the primary's chat id) don't clobber each other's peer
# session: each helper delegates under its own --thread label; plain use stays on 'main'.
#
# State lives in a global, home-rooted store keyed by project — mirroring how Claude
# (~/.claude/projects) and Codex (~/.codex) keep their own session history OUT of your repos:
#   ~/.agent-bridge/projects/<project-slug>/<self>/<chat>/<peer>/<thread>/{session,logs}
#                                            <self>/<chat>/meta.json
# <self> is recorded because a chat id is an opaque UUID — you can't tell from it which agent
# was primary. Override the root with AGENT_BRIDGE_STATE_DIR (e.g. to keep logs inside a repo).
#
# Usage:
#   bash bridge.sh agents                    # list peer agents you can call (everyone but you)
#   bash bridge.sh <peer> "task"             # delegate to <peer>, stream it live
#   bash bridge.sh <peer> --thread L "task"  # same, on a separate thread (own peer session)
#   bash bridge.sh <peer> reset              # clear this chat's sessions with <peer> (all threads)
#   bash bridge.sh <peer> reset --thread L   # clear just thread L with <peer>
#   bash bridge.sh reset                     # clear this chat's sessions with all peers
#   bash bridge.sh reset --all               # clear ALL of this project's bridge state (every chat/agent)
#   bash bridge.sh -h | --help               # print usage and exit
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
  bash bridge.sh <peer> --model <model> "task" pick the peer's model, then delegate
  bash bridge.sh <peer> --thread <label> "task"  delegate on a separate thread (own peer session)
  bash bridge.sh <peer> reset                  clear this chat's sessions with <peer> (all threads)
  bash bridge.sh <peer> reset --thread <label> clear just that thread with <peer>
  bash bridge.sh reset                         clear this chat's sessions with all peers
  bash bridge.sh reset --all                   clear ALL of this project's bridge state
  bash bridge.sh -h | --help                   print this help and exit

Effort levels (for --effort): low | medium | high | xhigh | max  (default: high).
Each peer maps these onto its own scale; the run header shows the level actually applied.

Models (for --model): 'top' = the peer's strongest coding model; short names (sol, luna, …)
resolve via the peer's model_map; any other value is passed to the peer CLI verbatim, so
brand-new models work before the map knows them. An explicit --model persists per thread:
follow-ups reuse it until you pass a different one (reset clears it). Omitted on a fresh
thread: no model flag is sent and the peer CLI's own configured default applies.

Threads (for --thread): each label keeps its own peer session under this chat (default: main).
Use one label per parallel helper so concurrent delegations don't share a session. Labels
start with a letter/digit, then letters, digits, '.', '_', '-'. A '--' ends option parsing
(use it when the task text itself starts with a dash).

Env overrides:
  <PEER>_BIN=/path/to/cli     point at a peer CLI not on PATH (e.g. CLAUDE_BIN, CODEX_BIN)
  AGENT_BRIDGE_EFFORT=<lvl>   default effort when --effort is omitted (default: high)
  AGENT_BRIDGE_THREAD=<label> thread for delegations when --thread is omitted (default: main);
                              does NOT scope resets — narrowing a reset takes the explicit flag
  AGENT_BRIDGE_STATE_DIR=DIR  where sessions + logs live (default: ~/.agent-bridge)
  AGENT_BRIDGE_MAX_DEPTH=N    max A→B→A delegation depth before refusing (default: 5)
EOF
}

# --- optional reasoning effort + model + thread ---------------------------------------
# Peers run at a reasoning/thinking level (default high). The calling agent maps the user's
# words ("think hard", "quick and rough") to a canonical level; each adapter then maps that
# to its own term (Claude's --effort, Codex's model_reasoning_effort). Model is mapped the
# same way ('top' or a short name → the peer's model ID) but has NO default: when unset the
# bridge sends no model flag and the peer CLI's own default applies — unless this thread
# already stored an explicit choice (see MODEL_FILE below). Pull `--effort <level>`,
# `--model <model>` and `--thread <label>` out here so the rest stays positional — agents /
# reset / "<task>" are untouched. A thread is an independent lane to a peer within this
# chat: parallel helper subagents inherit the primary's chat id, so without distinct labels
# they'd share (and clobber) one peer session.
EFFORT="${AGENT_BRIDGE_EFFORT:-high}"
MODEL=""
THREAD="${AGENT_BRIDGE_THREAD:-main}"
# THREAD_SET is set by the --thread flag ONLY: it scopes `<peer> reset` down to one thread,
# and an *inherited* AGENT_BRIDGE_THREAD must never silently change what a reset deletes —
# the env var picks your delegation lane, the flag states reset intent.
THREAD_SET=""
PASS_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    # Separated values must not look like flags: a missing value would otherwise swallow
    # the next option and silently run the wrong task ('--model --thread review "task"'
    # would run model '--thread' on thread 'main' with prompt 'review'). The '=' forms
    # remain a parse-level escape hatch — the bridge passes a dash-leading value through,
    # though the peer CLI's own parser may still reject it.
    --effort)   shift; EFFORT="${1:-}"
                case "$EFFORT" in ''|-*) echo "agent-bridge: --effort needs a level (low|medium|high|max)" >&2; exit 1;; esac ;;
    --effort=*) EFFORT="${1#--effort=}"
                [ -z "$EFFORT" ] && { echo "agent-bridge: --effort needs a level (low|medium|high|max)" >&2; exit 1; } ;;
    --model)    shift; MODEL="${1:-}"
                case "$MODEL" in ''|-*) echo "agent-bridge: --model needs 'top' or a model name" >&2; exit 1;; esac ;;
    --model=*)  MODEL="${1#--model=}"
                [ -z "$MODEL" ] && { echo "agent-bridge: --model needs 'top' or a model name" >&2; exit 1; } ;;
    --thread)   shift; THREAD="${1:-}"; THREAD_SET=1
                case "$THREAD" in ''|-*) echo "agent-bridge: --thread needs a label" >&2; exit 1;; esac ;;
    --thread=*) THREAD="${1#--thread=}"; THREAD_SET=1 ;;
    --)         shift; PASS_ARGS+=("$@"); break ;;   # everything after -- is positional (prompt may look like a flag)
    *)          PASS_ARGS+=("$1") ;;
  esac
  shift
done
set -- "${PASS_ARGS[@]}"

# The label becomes a directory name, so keep it to safe characters. Requiring an alnum
# first char kills three birds: no path hops (. / ..), no hidden dirs the reset globs and
# `ls` would miss (.review), and no flag-shaped labels from a swallowed option
# (`--thread --effort` would otherwise run with label '--effort').
case "$THREAD" in
  ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*)
    echo "agent-bridge: invalid thread label '$THREAD' — start with a letter/digit, then letters, digits, '.', '_', '-'." >&2
    exit 1 ;;
esac

# Each thread dir has a lock guarding the whole read-session -> run-peer -> write-session
# span: two runs on the same thread label would resume the same peer session concurrently
# and last-write each other's session id, so the loser fails fast instead. The lock is a
# symlink whose *target* is the holder's pid — creation and pid publication are one atomic
# syscall, so there is never a moment where the lock exists without an owner (a lock dir +
# pid file would have that gap, and a second run could mistake it for stale). A dead
# holder's lock is stale (crash, kill -9 — the EXIT trap never fired) and may be stolen.
# Resets take the same locks before deleting, so "is it busy?" and "keep it from starting"
# are one atomic step — a scan-then-delete would let a delegation start in between and be
# wiped mid-run.
take_lock() {   # $1 = thread dir; acquire its lock for this process
  local lock="$1/lock" pid
  ln -s "$$" "$lock" 2>/dev/null && return 0
  pid="$(readlink "$lock" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi   # live holder
  # Claim the stale lock by renaming it aside: rename is atomic, so of N contenders that
  # all saw it stale, exactly one mv succeeds. A plain rm+recreate here would let two
  # contenders interleave (B's rm deleting A's fresh lock) and both enter the run.
  if mv "$lock" "$lock.stale.$$" 2>/dev/null; then
    rm -f "$lock.stale.$$"
    ln -s "$$" "$lock" 2>/dev/null && return 0   # if this loses the re-take race, report busy
  fi
  return 1
}

# Lock every thread dir under $1 (they sit exactly $2 levels down) so a reset can delete
# the subtree: once all locks are held nothing can start on those labels, and the locks go
# down with the tree — no release needed. Any lock we can't take means a live delegation:
# release what we took (BUSY_DIR tells the caller which thread refused) and leave
# everything running.
lock_all_threads() {   # $1 = state subtree, $2 = depth of thread dirs below it
  LOCKED=(); BUSY_DIR=""
  local d l
  while IFS= read -r d; do
    if take_lock "$d"; then
      LOCKED+=("$d/lock")
    else
      BUSY_DIR="$d"
      for l in "${LOCKED[@]}"; do rm -f "$l"; done
      return 1
    fi
  done < <(find "$1" -mindepth "$2" -maxdepth "$2" -type d 2>/dev/null)
  return 0
}

# ----------------------------------------------------------- subcommands: agents/reset
CMD1="${1:-}"

if [ "$CMD1" = "agents" ]; then
  echo "agent-bridge · you are: $SELF · chat: ${CHAT:0:8} · thread: $THREAD · project: $PROJECT_ROOT"
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
  # Thread dirs sit at <self>/<chat>/<peer>/<thread> under the project, <peer>/<thread>
  # under a chat — lock them all, then the tree can go (locks are deleted with it).
  if [ "${2:-}" = "--all" ]; then
    if ! lock_all_threads "$PROJECT_DIR" 4; then
      echo "agent-bridge: a delegation is running right now ($BUSY_DIR) — not resetting. Retry when it finishes." >&2
      exit 1
    fi
    rm -rf "$PROJECT_DIR"
    echo "agent-bridge: cleared ALL bridge sessions for project $PROJECT_ROOT."
  else
    if ! lock_all_threads "$CHAT_DIR" 2; then
      echo "agent-bridge: a delegation is running right now ($BUSY_DIR) — not resetting. Retry when it finishes." >&2
      exit 1
    fi
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

# `<peer> reset` clears this chat's sessions with that peer — all threads, or just one when
# `--thread <label>` was passed (the flag, not the env var — see THREAD_SET above). It locks
# whatever it deletes first, so a reset can't yank state out from under a live delegation
# (nor one that starts mid-reset — it'll fail fast on the reset's own lock).
if [ "${2:-}" = "reset" ]; then
  if [ -n "$THREAD_SET" ]; then
    if [ -d "$CHAT_DIR/$TARGET/$THREAD" ] && ! take_lock "$CHAT_DIR/$TARGET/$THREAD"; then
      echo "agent-bridge: thread '$THREAD' with $TARGET is running right now — not resetting it." >&2
      exit 1
    fi
    rm -rf "$CHAT_DIR/$TARGET/$THREAD"
    echo "agent-bridge: cleared thread '$THREAD' with $TARGET (you=$SELF, chat ${CHAT:0:8})."
  else
    if ! lock_all_threads "$CHAT_DIR/$TARGET" 1; then
      echo "agent-bridge: thread '$(basename "$BUSY_DIR")' with $TARGET is running right now — not resetting. Retry when it finishes, or reset just an idle thread with --thread." >&2
      exit 1
    fi
    rm -rf "$CHAT_DIR/$TARGET"
    echo "agent-bridge: cleared this chat's sessions with $TARGET, all threads (you=$SELF, chat ${CHAT:0:8})."
  fi
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

# --- session state for (this project, this primary, this chat, this peer, this thread)
THREAD_DIR="$CHAT_DIR/$TARGET/$THREAD"
mkdir -p "$THREAD_DIR/logs"
SESSION_FILE="$THREAD_DIR/session"
MODEL_FILE="$THREAD_DIR/model"
# PID suffix: within one thread runs are serialized by the lock, but a same-second run
# right after a crash-steal could otherwise reuse the previous run's filename.
LOG="$THREAD_DIR/logs/$TARGET-$(date +%Y%m%d-%H%M%S)-$$.jsonl"
ERRLOG="${LOG%.jsonl}.stderr"   # peer's stderr — kept out of the live view, surfaced only on failure
META_FILE="$CHAT_DIR/meta.json"

# One live run per thread (see take_lock): take the lock before reading the session file,
# hold it until exit. A second run on this label fails fast and is pointed at --thread.
LOCK="$THREAD_DIR/lock"
if ! take_lock "$THREAD_DIR"; then
  echo "agent-bridge: thread '$THREAD' with $TARGET already has a run in progress (pid $(readlink "$LOCK" 2>/dev/null))." >&2
  echo "  Wait for it, or delegate on your own lane: bash bridge.sh $TARGET --thread <label> \"...\"" >&2
  exit 1
fi
trap 'rm -f "$LOCK"' EXIT

# Self-describing metadata for this chat (best-effort; never blocks the run).
python3 "$SCRIPT_DIR/meta.py" "$META_FILE" "$PROJECT_ROOT" "$SELF" "$CHAT" "$TARGET" "$PROMPT" "$THREAD" 2>/dev/null || true

MODE="new"; SID=""
if [ -f "$SESSION_FILE" ]; then
  MODE="resume"; SID="$(cat "$SESSION_FILE")"
fi

# An explicit --model sticks to the thread (stored resolved — 'gpt-5.6-sol', not 'top' —
# after a successful run, below): model-less follow-ups reuse it instead of silently
# falling back to the CLI default mid-session. A different explicit model switches the
# thread — allowed, shown in the header, re-stored on success.
MODEL_EXPLICIT="$MODEL"
STORED_MODEL=""
[ -f "$MODEL_FILE" ] && STORED_MODEL="$(cat "$MODEL_FILE")"
# An inherited model is ALREADY resolved — it must bypass model_map, or a future map entry
# matching a stored ID would silently remap a pinned thread (MODEL_RESOLVED tells adapter.py).
MODEL_RESOLVED=""
[ -z "$MODEL" ] && [ -n "$STORED_MODEL" ] && { MODEL="$STORED_MODEL"; MODEL_RESOLVED=1; }

# Build argv + read adapter fields (BIN, STREAM_FORMAT, SID_KEY, ARGS) in one shot. The
# helper shlex-quotes everything, so the eval is safe even with a hostile prompt/sid.
ADAPTER_SH="$(python3 "$SCRIPT_DIR/adapter.py" "$ADAPTER_FILE" "$MODE" "$PROMPT" "$SID" "$EFFORT" "$MODEL" "$MODEL_RESOLVED")" || {
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
# Braces before the arrow are load-bearing: without them bash 3.2 under a Latin-1-ish locale
# lexes the first byte of '→' (0xE2, a letter there) into the variable name and expands the
# whole thing to empty.
EFFORT_DISP="$EFFORT"
[ -n "${PEER_EFFORT:-}" ] && [ "$PEER_EFFORT" != "$EFFORT" ] && EFFORT_DISP="${EFFORT}→${PEER_EFFORT}"
# Model: keyed on PEER_MODEL — the model the peer actually receives — so a requested-but-
# ignored model (adapter without model support) never shows up as applied. Plain when
# inherited, 'top→gpt-5.6-sol' when the mapping changed the request, spelled out on a switch.
MODEL_DISP=""
if [ -n "${PEER_MODEL:-}" ]; then
  MODEL_DISP=" · model ${PEER_MODEL}"
  if [ -n "$MODEL_EXPLICIT" ] && [ -n "$STORED_MODEL" ] && [ "$PEER_MODEL" != "$STORED_MODEL" ]; then
    MODEL_DISP=" · switching model ${STORED_MODEL}→${PEER_MODEL}"
  elif [ "$PEER_MODEL" != "$MODEL" ]; then
    MODEL_DISP=" · model ${MODEL}→${PEER_MODEL}"
  fi
fi
echo "▶ agent-bridge · $SELF → $TARGET · chat ${CHAT:0:8} · thread $THREAD · effort $EFFORT_DISP$MODEL_DISP · $([ "$MODE" = resume ] && echo 'resuming session' || echo 'new session')$([ "$DEPTH" -gt 1 ] && echo " · chain $CHAIN")"

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
# Init first: the model-persist check below reads NEWSID as "the peer emitted a session id
# THIS run" — for a sid-key-less adapter it would otherwise leak in from the environment.
NEWSID=""
if [ -n "$SID_KEY" ]; then
  # `|| true`: an empty/sid-less log makes grep exit 1, which pipefail+set -e would turn into
  # a spurious script failure that masks the peer's real exit status. Tolerate "no match".
  NEWSID="$(grep -o "\"$SID_KEY\":\"[^\"]*\"" "$LOG" | tail -n1 | sed "s/.*\"$SID_KEY\":\"\([^\"]*\)\".*/\1/" || true)"
  # Write-then-rename so a reader never sees a torn/empty session file.
  if [ -n "$NEWSID" ]; then
    printf '%s\n' "$NEWSID" > "$SESSION_FILE.tmp.$$"
    mv -f "$SESSION_FILE.tmp.$$" "$SESSION_FILE"
  fi
fi

# Persist an explicit model choice once the peer actually ran with it: a clean exit, or a
# failed run that still emitted a session id — that session may have recorded partial work
# with the new model, so the stored model must follow it or the next model-less follow-up
# would silently switch back. Deliberate trade-off: a peer can emit its session id BEFORE
# the API rejects a bogus model (codex does), storing the bad name — but that fails loudly
# on the next call and heals via an explicit switch or reset, whereas not storing after
# partial work corrupts silently. Loud beats silent.
if [ -n "$MODEL_EXPLICIT" ] && [ -n "${PEER_MODEL:-}" ] && [ "$PEER_MODEL" != "$STORED_MODEL" ] \
   && { [ "$status" -eq 0 ] || [ -n "${NEWSID:-}" ]; }; then
  printf '%s\n' "$PEER_MODEL" > "$MODEL_FILE.tmp.$$"
  mv -f "$MODEL_FILE.tmp.$$" "$MODEL_FILE"
fi

exit "$status"
