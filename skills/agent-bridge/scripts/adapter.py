#!/usr/bin/env python3
"""Read a peer adapter (JSON) and emit shell assignments the dispatcher evals.

Usage:
    adapter.py <adapter.json> <new|resume> <prompt> [sid] [effort]

Emits four shell-safe assignments (values quoted with shlex so a hostile prompt or
session id can't break out of the eval):

    BIN=<peer cli name>
    STREAM_FORMAT=<format passed to render.py>
    SID_KEY=<json key carrying the resumable session id>
    ARGS=( ...argv for the chosen mode, with {prompt}/{sid}/{effort} substituted... )

Keeping argv construction here (rather than in bash) lets each peer express its own
shape — e.g. Codex puts `resume <sid>` positionally before the prompt, while Claude
takes `--resume <sid>` as a flag — without the dispatcher knowing anything peer-specific.
The same goes for reasoning effort: the dispatcher passes one canonical level (high by
default), and each adapter's `effort_map` translates it to that peer's own term.
"""
import sys
import json
import shlex


def main():
    if len(sys.argv) < 4:
        sys.stderr.write("usage: adapter.py <adapter.json> <new|resume> <prompt> [sid] [effort]\n")
        return 2

    path, mode, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
    sid = sys.argv[4] if len(sys.argv) > 4 else ""
    effort = sys.argv[5] if len(sys.argv) > 5 else ""

    try:
        with open(path) as f:
            adapter = json.load(f)
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"adapter.py: cannot read {path}: {exc}\n")
        return 2

    key = "cmd_resume" if mode == "resume" else "cmd_new"
    template = adapter.get(key)
    if not isinstance(template, list):
        sys.stderr.write(f"adapter.py: {path} is missing a '{key}' list\n")
        return 2

    # Map the requested canonical effort (low/medium/high/max) to THIS peer's own term —
    # each peer names its reasoning levels differently, so the mapping lives in the adapter.
    # Unknown level → the peer's 'high'; a peer without an effort_map just ignores effort.
    peer_effort = effort
    effort_map = adapter.get("effort_map") or {}
    if effort_map and effort:
        if effort in effort_map:
            peer_effort = effort_map[effort]
        else:
            peer_effort = effort_map.get("high", effort)
            sys.stderr.write(f"adapter.py: unknown effort '{effort}' for this peer, using '{peer_effort}'\n")

    args = []
    for el in template:
        # Substitute {sid} and {effort} before {prompt}, so tokens inside the user's prompt
        # are never re-expanded as fields.
        args.append(
            str(el).replace("{sid}", sid).replace("{effort}", peer_effort).replace("{prompt}", prompt)
        )

    out = [
        f"BIN={shlex.quote(str(adapter.get('bin', '')))}",
        f"STREAM_FORMAT={shlex.quote(str(adapter.get('stream_format', 'raw')))}",
        f"SID_KEY={shlex.quote(str(adapter.get('sid_key', '')))}",
        f"PEER_EFFORT={shlex.quote(peer_effort)}",   # the level actually applied (after mapping)
        "ARGS=(" + " ".join(shlex.quote(a) for a in args) + ")",
    ]
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
