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
- **Browser:** it can drive one (open pages, click, screenshot).
- **Good for:** a second opinion from a different model family, image generation (see below),
  and cross-checking another agent's output with fresh eyes. Bad at solving complex
  problems or coding.

## Image generation

Its `generate_image` tool makes real AI imagery, not code-drawn graphics, and this is one of
the main reasons to reach for agy. Roughly 25-40 s per image, so a batch of twelve is a
~12 minute run — brief it once for the whole batch rather than one image per delegation.

- **Files land in agy's brain dir, not your repo.** They go to
  `~/.gemini/antigravity-cli/brain/<conversation-id>/<ImageName>_<epoch>.png`. The bridge
  lists them under `── agy artifacts ──` when the run ends, so nothing is lost, but if you
  want them in the project you must **say so in the brief**: name the target directory and
  the exact filenames, and tell it to copy them there and `ls` to confirm. Any path in the
  repo works, not just the root.
- **Pass image prompts with `--task-file`, not as an argv.** Prompts are long and routinely
  contain `$` (`$12B`), quotes and parentheses; through a shell those are eaten silently.
- **Verify the images yourself; its own report is not evidence.** It will state that a set
  met every constraint when it did not (one run: two of three renders were the wrong person,
  reported as all three correct). Look at the files. It does usefully self-correct some
  renders mid-run, which is why the brain dir can hold more files than you asked for.
- **Say plainly what you want in frame.** Hedged phrasing gets hedged output: "a person
  resembling <name>" yields a generic stranger, where naming the subject directly renders
  the subject. Same for text in an image — state the exact strings allowed and that nothing
  else may appear, since extra lettering is the most common defect.
