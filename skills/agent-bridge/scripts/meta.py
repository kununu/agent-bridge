#!/usr/bin/env python3
"""Create/update a per-chat meta.json so the opaque UUID dirs in the bridge store are
self-describing — you can see which project, which primary agent, and what was last asked
without opening any transcript.

Usage: meta.py <meta_file> <project_path> <primary> <chat> <peer> <prompt> [thread]

Best-effort by design: any failure is swallowed (exit 0) so it can never block a delegation.
Concurrent delegations (parallel threads) may interleave updates; the atomic replace below
guarantees the file is always valid JSON, but between two simultaneous writers the last one
wins — acceptable for a purely descriptive summary.
"""
import sys
import os
import json
import tempfile
from datetime import datetime, timezone


def main():
    if len(sys.argv) < 7:
        return 0
    meta_file, project_path, primary, chat, peer, prompt = sys.argv[1:7]
    thread = sys.argv[7] if len(sys.argv) > 7 else ""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    data = {}
    if os.path.exists(meta_file):
        try:
            with open(meta_file) as f:
                data = json.load(f)
        except Exception:
            data = {}

    data.setdefault("created", now)
    data["project_path"] = project_path
    data["primary"] = primary
    data["chat"] = chat
    data["updated"] = now
    data["last_peer"] = peer
    if thread:
        data["last_thread"] = thread
    data["last_prompt"] = prompt[:200] + "…" if len(prompt) > 200 else prompt

    peers = data.get("peers", [])
    if peer not in peers:
        peers.append(peer)
    data["peers"] = peers

    # Write to a temp file in the same directory, then atomically replace, so a reader
    # (or a concurrent writer) never sees a half-written meta.json.
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(
            dir=os.path.dirname(meta_file) or ".", prefix=".meta.", suffix=".tmp"
        )
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, meta_file)
    except Exception:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
