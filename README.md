# agent-bridge

Have **Codex drive Claude Code** — as implementer, reviewer, or red-team — without
copy-pasting between two chat windows. Both run on your own subscriptions via their real
CLIs (so each keeps its full toolset), and Claude's reasoning streams back live while
Codex watches.

It's packaged as a **Codex skill**: you talk to Codex, and when you say *"use agent bridge
to …"* it briefs Claude, runs it, reads the streamed result, verifies, and reports back.

## Structure

```
skills/agent-bridge/
├── SKILL.md              # when to delegate + how to brief Claude (Codex reads this)
└── scripts/
    ├── ask-claude.sh     # runs `claude -p`, streams live, 1 session per Codex thread
    └── render.py         # makes Claude's JSON stream readable
sandbox/                  # throwaway task to try the loop end-to-end
```

`ask-claude.sh` keeps **one Claude session per Codex conversation** — keyed on
`CODEX_THREAD_ID` under `./.agent-bridge/threads/` — so a new Codex chat automatically gets
a fresh Claude session, while follow-ups in the same chat continue it.

## Install

For Codex, globally, with the [`skills`](https://skills.sh) CLI (assumes the repo is on GitHub):

```
npx skills add <owner>/agent-bridge -a codex -g     # -a codex: Codex only · -g: all projects
```

Re-run to update. Requires `claude` (logged in) and `python3` on PATH; in the Codex app,
open the project in local mode with full access.

## Workflow

1. Open your project in Codex and talk through the feature.
2. When you're ready, tell Codex: *"use agent bridge to implement X"* (or `$agent-bridge`).
3. Codex briefs Claude and hands off the chunk. Claude's reasoning and edits stream live
   in the same view — watch, or step away.
4. Claude finishes with a summary. Codex reads it, then checks the work itself — reads the
   diff, runs the tests.
5. If something's wrong, Codex follows up in the **same** Claude session ("X broke Y — fix
   it"); Claude fixes and reports. Repeat until it's right.
6. Codex gives you the verdict: what was built, what it verified, what's left.

You're never the messenger — the agents talk directly; you watch and steer between rounds.

Reset the current conversation's Claude session: `bash ~/.agents/skills/agent-bridge/scripts/ask-claude.sh reset` (add `--all` to clear every thread).
