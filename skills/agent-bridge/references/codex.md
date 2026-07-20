# Peer notes: Codex

- **Invocation:** `codex exec --json` with `danger-full-access` (it can edit files and use
  the network) and `--skip-git-repo-check`. Output is a JSONL event stream
  (`thread.started` / `turn.*` / `item.*`), rendered live by the bridge.
- **Progress signal:** Codex shows work as `· exec:` / `· tool:` / `· search:` action lines
  rather than a thinking-token counter. Gaps between events are it reasoning — that's
  normal, not a hang.
- **Effort:** set via `-c model_reasoning_effort=…`; the bridge maps canonical levels onto
  Codex's (`low`/`medium`/`high`/`xhigh`), with `max`→`xhigh` — its top reasoning tier.
- **Model:** set via `-m`; the bridge's tiers map to the GPT-5.6 family —
  `fast`→`gpt-5.6-luna`, `standard`→`gpt-5.6-terra`, `max`→`gpt-5.6-sol`. Luna is no toy:
  it out-scores Terra on Terminal-Bench, so `fast` is a solid coding tier. These are
  versioned IDs — bump the `model_map` in `adapters/codex.json` when a new generation
  ships. No `--model` → the user's `~/.codex/config.toml` default. Switching model
  mid-session (on resume) works but Codex warns it may hurt performance — pick the tier
  when a thread starts, or reset first.
- **Resume:** sessions resume by `thread_id`; the bridge persists it for you per thread
  (`main` unless you pass `--thread`), so same-chat, same-thread follow-ups continue it.
- **Reasoning text** only appears when reasoning summaries are enabled; by default you'll
  see its actions and the final answer (the last `agent_message`).
- **Good for:** a fast independent second opinion, focused implementation, and red-teaming
  another agent's output.
