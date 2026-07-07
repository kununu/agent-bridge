# agent-bridge

Have **any AI coding agent drive another as a peer** — to implement, review, or red-team — without copy-pasting between two chat windows.

Talk to whichever agent you prefer (Claude Code, Codex, …). When you say *"ask Codex to implement this"* or *"have Claude review this diff"*, the bridge briefs the peer, runs it on your own subscription via the peer's **real CLI** (so it keeps its full toolset), streams the work back live, then verifies it and reports. You watch and steer between rounds — you're never the messenger.

It's **one [agent-skill](https://agentskills.io)** installed into every agent you use. The skill is generic: it auto-detects which agent it's running inside and offers the others as peers — so the *same* skill makes the bridge a two-way (and N-way) street.

## Requirements

- **The peer's CLI**, installed and logged in (e.g. `claude`, `codex`) — the bridge runs the agent you delegate *to* through its real CLI. The agent you *drive* needs no CLI of its own; it can be any app that loads the skill (a terminal CLI **or** a desktop/IDE app).
- **`python3`** on PATH — the bridge's scripts use it.
- **Node / `npx`** — only to install the skill (below).

**Available agents** live in [`skills/agent-bridge/scripts/adapters/`](skills/agent-bridge/scripts/adapters) — one JSON per supported peer; that directory *is* the current list.

## Install

With the [`skills`](https://skills.sh) CLI, install/update the skill into each agent you want bridged:

```
npx skills add kununu/agent-bridge -g -a claude-code codex # -g installs into all projects;
```

## Structure

```
skills/agent-bridge/
├── SKILL.md          # when to delegate + how to brief a peer (the host agent reads this)
├── references/       # per-peer notes, loaded on demand when you target that peer
│   ├── claude.md
│   └── codex.md
└── scripts/
    ├── bridge.sh     # dispatcher: detect who you are → resolve the peer → run it → stream → persist the session
    ├── render.py     # normalize each peer's native stream (Claude stream-json, Codex JSONL, …) → one readable view
    ├── adapter.py    # read a peer adapter → build its argv
    ├── meta.py       # write a self-describing meta.json per chat in the session store
    └── adapters/     # one small JSON per peer — adding an agent = dropping a file here
        ├── claude.json
        └── codex.json
```

**The idea: one generic dispatcher + tiny per-peer adapters.** `bridge.sh` detects which agent is calling and offers every adapter *except itself*. Everything peer-specific — the CLI command, how it resumes a session, its stream format — lives in `adapters/<peer>.json`; `render.py` turns each peer's native stream into one readable view. So **adding an agent is one adapter file, not a code change** — that's what keeps an N×N problem linear.

Sessions persist per conversation *thread* (new chat → fresh peer session; follow-ups continue it) in a home-rooted store (`~/.agent-bridge`), kept out of your repos the way `~/.claude` and `~/.codex` are. Parallel delegations to the same peer — e.g. helper subagents that all inherit the primary chat's id — each get their own lane via `--thread <label>`, with a per-thread lock so two runs can never share (or clobber) one session; plain usage stays on the default `main` thread. A depth guard stops runaway A→B→A recursion.
