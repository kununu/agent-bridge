# Peer notes: Codex

- **Invocation:** `codex exec --json` with `danger-full-access` (it can edit files and use
  the network) and `--skip-git-repo-check`. Output is a JSONL event stream
  (`thread.started` / `turn.*` / `item.*`), rendered live by the bridge.
- **Progress signal:** Codex shows work as `· exec:` / `· tool:` / `· search:` action lines
  rather than a thinking-token counter. Gaps between events are it reasoning — that's
  normal, not a hang.
- **Effort:** set via `-c model_reasoning_effort=…`; the bridge maps canonical levels onto
  Codex's (`low`/`medium`/`high`/`xhigh`), with `max`→`xhigh` — its top reasoning tier.
- **Model:** set via `-m`; `--model top` → `gpt-5.6-sol`, and the short names `sol` /
  `terra` / `luna` resolve to their full GPT-5.6 IDs. The cheapest that's still solid at
  coding is `luna`. A mid-thread model switch makes Codex print an `· error:`-labeled
  warning in the stream — informational, the run continues.
- **Resume:** sessions resume by `thread_id`; the bridge persists it for you per thread
  (`main` unless you pass `--thread`), so same-chat, same-thread follow-ups continue it.
- **Reasoning text** only appears when reasoning summaries are enabled; by default you'll
  see its actions and the final answer (the last `agent_message`).
- **Good for:** a fast independent second opinion, focused implementation, and red-teaming
  another agent's output.
