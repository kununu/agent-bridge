---
name: agent-bridge
description: >-
  Delegate real coding work to a peer AI agent (such as Claude Code or Codex) that runs its
  own full harness, or use that peer as an independent reviewer or adversarial red-team.
  Trigger when the user says "use agent bridge", "ask <another agent>", "delegate to
  <agent>", "have <agent> implement/build/fix this", "get <agent> to review/critique",
  "get a second opinion", or otherwise hands work to a different agent than the one they're
  talking to. The bridge auto-detects which agent you are and offers the others as peers, so
  the same instructions work whichever agent you are running inside. Do NOT trigger for
  normal work the user wants you to do yourself.
compatibility: >-
  Requires python3 and the peer agent's CLI (e.g. claude, codex) installed and logged in.
---

# agent-bridge — delegate to a peer coding agent

You are the lead engineer. Through the bridge you can hand self-contained work to a **peer
coding agent** — another full agent (e.g. Claude Code or Codex) running its own harness in
auto mode, so it can take real, meaty work and run it to completion: building, testing, and
verifying its own output before reporting back.

The bridge **auto-detects which agent you are** and which peers you can call — you never
delegate to yourself, and the same skill works whichever agent is driving.

## Who can I call?

```
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" agents
```

Lists the peers available on this machine (everyone except you). Pick one as `<peer>` in the
commands below. For a specific peer's quirks, read `references/<peer>.md` in this skill.

## How to delegate

Run this from the **project root** (where you're already working):

```
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" <peer> "your task for the peer"
```

- It **streams the peer's reasoning and actions live** — read it as it runs.
- Each run's full transcript is saved under that peer's `logs/`. State lives in a global store
  at `~/.agent-bridge/projects/<project>/<you>/<chat>/<peer>/<thread>/`; you don't manage any
  of it. The thread defaults to `main` — you only name threads when running peers in parallel
  (see **Parallel delegations** below).
- If the peer gets confused, or the user asks to start fresh, reset and retry — see
  **Starting a peer over** below.

Read **Gotchas** below before your first run — most "it looks stuck" moments are the peer thinking.

## Gotchas

- **Thinking looks like hanging — it isn't.** Before its first action, and between actions, a
  peer often reasons for one to a few minutes. Some peers emit `· thinking… ~Nk tokens`
  heartbeats with a climbing count; others show steady `· exec:` / `· tool:` action lines.
  That is the peer working. **Do not interrupt, kill, or restart it while output is flowing** —
  step in only if the stream goes fully silent for a long stretch.
- **The peer's final answer comes after the `── <peer> done ──` marker.** Everything before it
  is live reasoning and actions; read the stream, but treat the post-marker text as the answer.
- **Sessions persist per conversation, per peer, per thread.** A new chat starts a fresh peer
  session; within this chat, every call to the same peer (on the same thread — `main` unless
  you name one) continues the same one. Write follow-ups as continuations ("the parser you
  wrote drops trailing numbers — fix it and rerun the tests"), not as fresh, re-explained tasks.
- **One run at a time per thread.** If a delegation fails immediately with "already has a run
  in progress", another run is live on that thread — wait for it, or use your own `--thread`
  label. (After a crash the stale lock is detected and cleared automatically.)

## Reasoning effort

The peer runs at a reasoning level — **`high` by default**. To run it harder or lighter, pass
`--effort`:

```
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" <peer> --effort <level> "your task"
```

Levels are `low` · `medium` · `high` · `xhigh` · `max` (low → fast and cheap, max → think as hard
as possible). **Translate what the user asks into the nearest level** — e.g. *"think hard / be
thorough"* → `high` or `xhigh`; *"go all out"* → `max`; *"quick / rough / don't overthink it"* →
`low`. If the user says nothing about effort, omit the flag (you get `high`). You always pass these
canonical levels; the bridge maps each to the peer's own setting (some peers cap lower — that's
expected, and shown in the run header).

## Model

On a fresh thread the bridge sends **no model flag** — the peer runs on whatever its own
CLI is configured to use (a thread that already pinned a model reuses it — see below).
That's the right call whenever the user doesn't bring up models. Pick one only when the
user names a model or clearly asks for a capability (*"strongest"*, *"cheapest"*):

```
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" <peer> --model <model> "your task"
```

`--model` takes one peer-independent value — `top`, the peer's strongest coding model — or
a model's short name (e.g. `sonnet`, `luna`); each peer's lineup lives in
`references/<peer>.md`, and the adapter translates the name into the peer CLI's own model
argument. Anything it doesn't recognize is passed to the peer CLI verbatim, so exact or
brand-new model IDs work too. **Normalize the user's wording yourself**: *"Claude's best model"* → `--model top`;
*"codex tera"* (typo) → `--model terra`; *"codex's cheapest"* → the cheapest model named in
that peer's reference notes.

**Model and effort are independent knobs**: `--model` picks the model, `--effort` how hard
it reasons. Words like *"quick"*, *"thorough"*, *"don't overthink"* move **effort only** —
don't infer a cheaper model from them unless the user also expresses a model or cost
preference.

**An explicit model sticks to the thread.** Once you pass `--model`, follow-ups on that
thread reuse the same model automatically — don't repeat the flag. Passing a different
model later switches the thread (the header spells out `switching model old→new`). A reset
clears the choice along with the session.

## Parallel delegations (threads)

By default all your calls to a peer share **one** session — that's what makes follow-ups work.
But if several delegations to the same peer run **at the same time** (e.g. you spawn helper
subagents that each call the bridge), they must not share that session: subagents inherit your
chat id, so without separation they'd resume each other's context and overwrite each other's
state. Give each parallel lane its own thread label:

```
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" <peer> --thread worker-1 "task A"
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" <peer> --thread worker-2 "task B"
```

- **When you spawn helper subagents that delegate, put a unique `--thread <label>` in the
  exact command you hand each helper** — the helper can't tell on its own that it's one of many.
- Labels are yours to choose — `worker-1`, `review`, `tests` (must start with a letter or digit).
- Each thread is its own persistent peer session — follow-ups on the same label continue it.
- A helper that needs a clean slate should reset **only its own lane** —
  `<peer> reset --thread <its-label>` — never a bare `<peer> reset`, which clears every
  thread's session for that peer.

## Brief the peer like the capable engineer it is

- **Hand it substantial chunks, not micro-steps.** A whole feature, a module, a refactor, a
  real debugging task. Don't break work into tiny one-function asks — that wastes round-trips
  and badly underuses it. Assume it can own a meaty, well-scoped piece end to end and verify
  its own work before reporting back.
- **Give complete context up front:** the goal, the files that matter, constraints, and how
  to know it succeeded (which tests, expected behavior). The more complete the brief, the
  bigger the chunk it can take.
- **State the scope clearly** so it neither overreaches nor stops short.

## Three ways to use a peer — pick what fits

1. **Implementer** — give it the work; let it build, test, and report.
2. **Independent reviewer** — fresh eyes on something you or it wrote:
   "Review the changes in X for correctness and edge cases; be specific."
3. **Adversarial red-team** — have it try to break a design or find the worst failure:
   "Find inputs where this parser returns the wrong answer."

For reviews, ask pointed questions and judge the critique on its merits — push back when you
disagree, take it when it's right. Two strong models disagreeing is the point.

## Starting a peer over

A peer's session persists per conversation, so by default you continue it. But if it gets
stuck or confused, or the user says anything like *"start a new session and try again"*,
**run the reset yourself and then re-issue the task** — the user shouldn't have to type any
command:

```
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" <peer> reset                    # this peer, all threads
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" <peer> reset --thread <label>   # one thread only
bash "$HOME/.agents/skills/agent-bridge/scripts/bridge.sh" reset                           # every peer, this chat
```

Your next call starts that peer from a clean slate. Other conversations are untouched.
A reset refuses while an affected delegation is live, so it won't wipe a run mid-flight — but
don't reset while you're spawning parallel helpers, as a brand-new thread can still slip through.

## Your part of the loop

- After the peer reports, **verify independently** with your own tools (read the files, run
  the tests) before accepting. Don't rubber-stamp.
- If something's off, delegate the fix in the **same session**, or fix it yourself — your call.
- When it's done and verified, give the human a short summary: what was built, what you
  checked, and anything still open.
