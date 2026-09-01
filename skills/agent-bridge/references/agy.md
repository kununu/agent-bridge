# Peer notes: agy (Antigravity CLI — Google's Gemini CLI successor)

- **Invocation:** `agy --print` headless with `--dangerously-skip-permissions` (full auto),
  streamed as `--output-format stream-json` (undocumented in `agy --help` but real — verify
  it still works after agy updates). Print mode starts with no workspace and would work in
  its own scratch dir, so the bridge anchors it with `--add-dir <cwd>`.
- **Progress signal:** narration and `· tool:` action lines as it works. Gaps between
  events are it thinking — normal, not a hang.
- **Effort:** `--effort low|medium|high`; the bridge maps `xhigh`/`max` down to `high`,
  agy's top tier (the run header shows the mapping).
- **Model:** `--model top` (and the short names `gemini` / `flash`) → `gemini-3.7-flash`,
  the current lineup's strongest; effort picks its high/medium/low variant. Older lineups
  (3.6/3.5 flash, 3.1 pro) are outdated — don't offer them unprompted, though exact IDs the
  user insists on pass through verbatim. With no model the user's own agy default applies.
- **Resume:** conversations resume by conversation id (`--conversation`); the bridge
  persists it per thread (`main` unless you pass `--thread`), so same-chat, same-thread
  follow-ups continue automatically. An id agy doesn't know is silently ignored (fresh
  conversation) — trust the bridge's stored one.
- **Browser:** it can drive one (open pages, click, screenshot).
- **Good for:** a second opinion from a different model family, image generation (see below),
  and cross-checking another agent's output with fresh eyes. Bad at solving complex
  problems or coding.

## Image generation

Its `generate_image` tool makes real AI imagery, not code-drawn graphics, and this is one of
the main reasons to reach for agy.

- **Files land in agy's brain dir, not your repo.** They go to
  `~/.gemini/antigravity-cli/brain/<conversation-id>/<ImageName>_<epoch>.png`. The bridge
  lists them under `── agy artifacts ──` when the run ends; if you want them in the
  project, **say so in the brief**: name the target directory and the exact filenames, and
  tell it to copy them there and `ls` to confirm. Any path in the repo works, not just the
  root.
- **Pass image briefs with `--task-file`.** They're long, often several prompts at once,
  and full of characters a shell would mangle in an argv.
- **Look at the files, then let the user judge.** agy self-corrects some renders mid-run,
  so the brain dir can hold more files than you asked for — and its success report can
  still be wrong. Check the objective constraints yourself (exact text, no stray lettering,
  subject in frame); likeness and taste are the user's call — show them the images, don't
  relay agy's summary.
- **You'll usually author the prompts from the user's idea — but anything the user named
  (a subject, exact text, a style) is a constraint: keep it verbatim, don't soften it.**
  Hedging "X" into "resembling X" renders something else.
- **Be explicit about text in the image:** name the exact strings allowed, or say that no
  text may appear at all — unrequested lettering is the most common defect.
