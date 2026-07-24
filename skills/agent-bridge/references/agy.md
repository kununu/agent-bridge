# Peer notes: agy (Antigravity CLI — Google's Gemini CLI successor)

- **Invocation:** `agy --print` headless with `--dangerously-skip-permissions` (full auto),
  streamed as `--output-format stream-json` (undocumented in `agy --help` but real — verify
  it still works after agy updates). Print mode starts with no workspace and would work in
  its own scratch dir, so the bridge anchors it with `--add-dir <cwd>`.
- **Progress signal:** narration and `· tool:` action lines as it works. Gaps between
  events are it thinking — normal, not a hang.
- **Effort:** `--effort low|medium|high`; the bridge maps `xhigh`/`max` down to `high`,
  agy's top tier (the run header shows the mapping).
- **Model:** `--model top` (and the short names `gemini` / `flash`) → `gemini-3.6-flash`,
  the current lineup's strongest; effort picks its high/medium/low variant. Older lineups
  (3.5 flash, 3.1 pro) are outdated — don't offer them unprompted, though exact IDs the
  user insists on pass through verbatim. With no model the user's own agy default applies.
- **Resume:** conversations resume by conversation id (`--conversation`); the bridge
  persists it per thread (`main` unless you pass `--thread`), so same-chat, same-thread
  follow-ups continue automatically. An id agy doesn't know is silently ignored (fresh
  conversation) — trust the bridge's stored one.
- **Images & browser:** it genuinely generates images (a native `generate_image` tool —
  AI imagery, not code-drawn) and can drive a browser (open pages, click, screenshot).
  Ask for generated files to be saved into the workspace root, or they land in its
  internal brain dir.
- **Good for:** a second opinion from a different model family, great for image generation, and
  cross-checking another agent's output with fresh eyes. Bad at solving complex
  problems or coding.
