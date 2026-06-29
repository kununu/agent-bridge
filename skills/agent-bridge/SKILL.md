---
name: agent-bridge
description: >-
  Delegate real coding work to Claude Code as a peer agent, or use Claude as an
  independent reviewer or adversarial red-team. Trigger when the user says "use
  agent bridge", "delegate to Claude", "have Claude implement/build/fix this",
  "get Claude to review/critique", "ask Claude", or otherwise hands a task off to
  Claude. Claude runs its full harness (read, write, edit, shell, search) in auto
  mode and streams its reasoning and actions back live. Do NOT trigger for normal
  work the user wants you (Codex) to do yourself.
---

# agent-bridge — delegate to Claude Code

You (Codex) are the lead engineer. **Claude Code** is a strong peer you can hand
self-contained work to. It runs its own full harness in auto mode, so it can take
real, meaty work and run it to completion — building, testing, and verifying its
own output before reporting back.

## How to delegate

Run this from the **project root** (where you're already working):

```
bash "$HOME/.agents/skills/agent-bridge/scripts/ask-claude.sh" "your task for Claude"
```

- It **streams Claude's reasoning and actions live** — read it as it runs. Claude's
  final answer comes after the `── claude done ──` marker.
- It keeps **one Claude session per Codex conversation, automatically** — a new Codex
  chat starts a fresh Claude session; within this chat, every call continues the same one.
  So write follow-ups as continuations ("the parser you wrote drops trailing numbers — fix
  it and rerun the tests"), not as fresh, re-explained tasks. (Keyed on `CODEX_THREAD_ID`,
  under `./.agent-bridge/threads/<thread>/` — you don't manage any of this.)
- Each run's full transcript is saved under that thread's `logs/`.
- If Claude gets confused, or the user asks to start fresh with Claude, reset and retry —
  see **Starting Claude over** below.

## Brief Claude like the capable engineer it is

- **Hand it substantial chunks, not micro-steps.** A whole feature, a module, a
  refactor, a real debugging task. Do not break work into tiny one-function asks —
  that wastes round-trips and badly underuses it. Assume it can own a meaty,
  well-scoped piece end to end and verify its own work before reporting back.
- **Give complete context up front:** the goal, the files that matter, constraints,
  and how to know it succeeded (which tests, expected behavior). The more complete
  the brief, the bigger the chunk Claude can take.
- **State the scope clearly** so it neither overreaches nor stops short.

## Three ways to use Claude — pick what fits

1. **Implementer** — give it the work; let it build, test, and report.
2. **Independent reviewer** — fresh eyes on something you or it wrote:
   "Review the changes in X for correctness and edge cases; be specific."
3. **Adversarial red-team** — have it try to break a design or find the worst
   failure: "Find inputs where this parser returns the wrong answer."

For reviews, ask pointed questions and judge the critique on its merits — push back
when you disagree, take it when it's right. Two strong models disagreeing is the point.

## Starting Claude over

Claude's session persists per project, so by default you continue it. But if Claude gets
stuck or confused, or the user says anything like *"start a new Claude session and try
again"*, **run the reset yourself and then re-issue the task** — the user should not have
to type any command:

```
bash "$HOME/.agents/skills/agent-bridge/scripts/ask-claude.sh" reset
```

That clears **this Codex conversation's** Claude session; your next call starts Claude from
a clean slate. Other conversations' sessions are untouched.

## Your part of the loop

- After Claude reports, **verify independently** with your own tools (read the files,
  run the tests) before accepting. Don't rubber-stamp.
- If something's off, delegate the fix in the **same session**, or fix it yourself —
  your call.
- When it's done and verified, give the human a short summary: what was built, what
  you checked, and anything still open.
