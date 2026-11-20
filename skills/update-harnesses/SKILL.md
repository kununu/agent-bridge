---
name: update-harnesses
description: Update the agent CLIs (Claude Code, Codex, agy/Gemini) to their latest versions. Optionally name which ones, e.g. /update-harnesses codex agy
disable-model-invocation: true
---

# update-harnesses

Run the script next to this file, passing the CLIs the user named, if any (`gemini` is `agy`):

```
bash <this skill's dir>/update-harnesses.sh [claude|codex|agy ...]
```

Updates can take minutes, so give the command a timeout of at least 10 minutes.

Report the script's closing summary. For a failed CLI, include the error from its output. A CLI
that was running during its update, including the one you run in, needs a restart to use
the new version; say so when that applies.
