# Peer notes: Claude Code

- **Invocation:** `claude -p` headless, `--dangerously-skip-permissions` (full auto), streamed
  as `stream-json`.
- **Effort:** `--effort low|medium|high|xhigh|max`; the bridge sets it per call (default `high`)
  and passes `max` through unchanged — so Claude is your peer for genuinely hard, max-effort work.
- **Model:** `--model top` → `fable`, Claude's strongest. The CLI natively accepts
  `fable` / `opus` / `sonnet` as aliases, so those pass through as-is; the cheapest
  that's still strong at coding is `sonnet`.
- **Heartbeats:** at high effort Claude reasons for one to a few minutes before and between
  actions, emitting `· thinking… ~Nk tokens` heartbeats. A climbing count means it's alive
  and working — don't kill it mid-think. Worry only if the stream goes fully silent (no new
  heartbeat, no action) for a long stretch.
- **Resume:** sessions resume by `session_id`; the bridge persists it for you per thread
  (`main` unless you pass `--thread`), so follow-ups in the same chat and thread continue
  the same Claude session automatically.
- **Good for:** large self-contained implementation, careful multi-file refactors, and
  thorough correctness/edge-case reviews.
