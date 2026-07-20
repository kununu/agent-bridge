#!/usr/bin/env python3
"""Read a peer adapter (JSON) and emit shell assignments the dispatcher evals.

Usage:
    adapter.py <adapter.json> <new|resume> <prompt> [sid] [effort] [model] [model_resolved]

Emits shell-safe assignments (values quoted with shlex so a hostile prompt or
session id can't break out of the eval):

    BIN=<peer cli name>
    STREAM_FORMAT=<format passed to render.py>
    SID_KEY=<json key carrying the resumable session id>
    ARGS=( ...argv for the chosen mode, with {prompt}/{sid}/{effort}/{model} substituted... )

Keeping argv construction here (rather than in bash) lets each peer express its own
shape — e.g. Codex puts `resume <sid>` positionally before the prompt, while Claude
takes `--resume <sid>` as a flag — without the dispatcher knowing anything peer-specific.
The same goes for reasoning effort: the dispatcher passes one canonical level (high by
default), and each adapter's `effort_map` translates it to that peer's own term.

Model is optional and works like effort with two twists. There is no default: when no model
is requested, the `{model_args}` placeholder element in the cmd template is dropped entirely,
no model flag reaches the peer, and its CLI's own configured default applies. And unlike
effort, a value missing from `model_map` is passed through verbatim — model names are
open-ended, so a brand-new ID must work the day it ships, before any map knows it.
model_resolved=1 marks a model the bridge inherited from a thread's stored (already
resolved) choice: it skips `model_map`, so a map entry that happens to match a stored ID
can never silently remap a pinned thread.
"""
import sys
import json
import re
import shlex


def main():
    if len(sys.argv) < 4:
        sys.stderr.write("usage: adapter.py <adapter.json> <new|resume> <prompt> [sid] [effort] [model] [model_resolved]\n")
        return 2

    path, mode, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
    sid = sys.argv[4] if len(sys.argv) > 4 else ""
    effort = sys.argv[5] if len(sys.argv) > 5 else ""
    model = sys.argv[6] if len(sys.argv) > 6 else ""
    model_resolved = len(sys.argv) > 7 and sys.argv[7] == "1"

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

    # 'top' or a short name -> this peer's model ID; anything not in the map passes through
    # verbatim (model names are open-ended — a brand-new model must work unmapped). An
    # already-resolved model (inherited from the thread's store) skips the map entirely.
    if not model:
        peer_model = ""
    elif model_resolved:
        peer_model = model
    else:
        peer_model = (adapter.get("model_map") or {}).get(model, model)
    model_args = adapter.get("model_args")
    if model and not (isinstance(model_args, list) and model_args):
        sys.stderr.write(f"adapter.py: this peer has no 'model_args' — ignoring model '{model}'\n")
        peer_model = ""
    elif peer_model and not any("{model}" in str(m) for m in model_args):
        # PEER_MODEL non-empty must mean the peer received THAT model; model_args that
        # never interpolate it (e.g. ["--fixed-model"]) would display/store a lie.
        sys.stderr.write(f"adapter.py: 'model_args' has no '{{model}}' placeholder — ignoring model '{model}'\n")
        peer_model = ""

    args = []
    model_args_used = False
    for el in template:
        # The placeholder element expands to the peer's model flag(s) — or to nothing,
        # so an omitted model sends no flag and the peer CLI's own default applies.
        if str(el) == "{model_args}":
            model_args_used = True
            if peer_model:
                args.extend(str(m) for m in model_args)
            continue
        args.append(str(el))
    # A template without the placeholder never sends the model — report PEER_MODEL as empty
    # so the bridge neither displays nor stores a model the peer didn't receive.
    if peer_model and not model_args_used:
        sys.stderr.write(f"adapter.py: '{key}' has no '{{model_args}}' placeholder — ignoring model '{model}'\n")
        peer_model = ""
    # Single-pass substitution: replacement values are never rescanned for placeholders,
    # so a prompt containing '{sid}' — or a hostile model name like '{prompt}' — stays literal
    # (chained .replace() calls would re-expand tokens inside earlier substitutions).
    subs = {"{sid}": sid, "{effort}": peer_effort, "{model}": peer_model, "{prompt}": prompt}
    args = [re.sub(r"\{(?:sid|effort|model|prompt)\}", lambda m: subs[m.group(0)], a) for a in args]

    out = [
        f"BIN={shlex.quote(str(adapter.get('bin', '')))}",
        f"STREAM_FORMAT={shlex.quote(str(adapter.get('stream_format', 'raw')))}",
        f"SID_KEY={shlex.quote(str(adapter.get('sid_key', '')))}",
        f"PEER_EFFORT={shlex.quote(peer_effort)}",   # the level actually applied (after mapping)
        f"PEER_MODEL={shlex.quote(peer_model)}",     # the model actually applied ('' = CLI default)
        "ARGS=(" + " ".join(shlex.quote(a) for a in args) + ")",
    ]
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
