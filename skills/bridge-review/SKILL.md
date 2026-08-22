---
name: bridge-review
description: A peer agent reviews the current changes through agent-bridge, then verified findings get fixed. Name the peer after the command; defaults to Gemini.
disable-model-invocation: true
---

# bridge-review

A peer agent reviews the work, you decide what is real.

## 1. Pick the peer

The invocation names the peer: `/bridge-review gemini`, `/bridge-review codex`,
`/bridge-review claude`. With no peer named, never make assumptions, ask the human which one to use.

If this skill has a `references/<peer>.md`, read it. It records that peer's quirks. No file
means no quirks.

## 2. Send the review

Call the Skill tool with "agent-bridge" and delegate to the peer.

The brief carries the context the peer cannot see:

- Goal. What this change is for, so it can judge whether the code is the simplest way there.
- Gotchas. The things you discovered during implemenation that the peer should be aware of. If there are none, just skip this section.
- Scope. Which files or which diff to review, by path or commit range.
- Standards, both layers: the coding-standards skill, and this repo's own conventions in
  AGENTS.md, CLAUDE.md, local project skills and any standards docs. Where the two disagree, the repo wins.
- Ask: code quality, adherence to both layers of standards, best practices, the simplest code
  that reaches the goal, efficiency & performance.
- The output shape: for each finding, `file:line`, what breaks, and why it matters. Ranked, worst
  first.
- Review only. It reports findings and leaves the working tree as it found it.

## 3. Verify every finding

Never act on a finding you have not checked against the code, or verified some other way (e.g.
look up current documentation). How you check depends on the finding: read the file, run the
test, try the input, write and run temp script. A finding is real once you can name what breaks or what will break. If you cannot name it, it
is noise.

## 4. Fix or ask

Fix it yourself when the change is small and obvious:

- Cleanups that leave behavior identical: a standards violation, a code smell, the same logic
  written more simply.
- A real bug whose fix is clear and local, however serious it is.

Anything else goes in the summary instead of the diff: a fix that needs huge restructuring, or a
finding you are not sure about. Say what you would do and let the human decide.

Then report every finding, what you fixed, and what you left.
