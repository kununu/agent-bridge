#!/usr/bin/env python3
"""Create/update a per-chat meta.json so the opaque UUID dirs in the bridge store are
self-describing — you can see which project, which primary agent, and what was last asked
without opening any transcript.

Usage: meta.py <meta_file> <project_path> <primary> <chat> <peer> <prompt>

Best-effort by design: any failure is swallowed (exit 0) so it can never block a delegation.
"""
import sys
import os
import json
from datetime import datetime, timezone


def main():
    if len(sys.argv) < 7:
        return 0
    meta_file, project_path, primary, chat, peer, prompt = sys.argv[1:7]
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
    data["last_prompt"] = prompt[:200] + "…" if len(prompt) > 200 else prompt

    peers = data.get("peers", [])
    if peer not in peers:
        peers.append(peer)
    data["peers"] = peers

    try:
        with open(meta_file, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
