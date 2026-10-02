# Peer notes: Claude Code

- **Invocation:** `claude -p` headless, `--dangerously-skip-permissions` (full auto), streamed
  as `stream-json`.
- **Effort:** `--effort low|medium|high|xhigh|max`; the bridge sets it per call (default `high`)
  and passes `max` through unchanged.
- **Model:** `--model top` → `fable`, Claude's strongest. `fable` / `opus` / `sonnet` are CLI
  aliases for the latest of each and pass through as-is (an outdated CLI can resolve an
  alias to an older model). The cheapest that's still strong at coding is `sonnet`.
- **Heartbeats:** at high effort Claude reasons for one to a few minutes before and between
  actions, emitting `· thinking… ~Nk tokens` heartbeats. A climbing count means it's alive
  and working — don't kill it mid-think. Worry only if the stream goes fully silent (no new
  heartbeat, no action) for a long stretch.
- **Resume:** sessions resume by `session_id`; the bridge persists it for you per thread
  (`main` unless you pass `--thread`), so follow-ups in the same chat and thread continue
  the same Claude session automatically.
- **Good for:** large self-contained implementation, front-end & tasteful work, planning and solving complex problems, and thorough correctness/edge-case reviews.
