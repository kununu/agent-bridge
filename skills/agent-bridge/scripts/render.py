#!/usr/bin/env python3
"""Render Claude Code's stream-json (NDJSON on stdin) as readable live output.
Robust by design: anything it doesn't recognize is skipped, and the raw stream is
always kept in ./.agent-bridge/logs/ as the source of truth."""
import sys, json

def show(s, end="\n"):
    sys.stdout.write(s + end)
    sys.stdout.flush()

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue

        t = e.get("type")

        if t == "system" and e.get("subtype") == "init":
            show(f"\n── claude session {e.get('session_id','?')} · {e.get('model','?')} ──")

        elif t == "assistant":
            for b in e.get("message", {}).get("content", []):
                bt = b.get("type")
                if bt == "text":
                    txt = (b.get("text") or "").rstrip()
                    if txt:
                        show(txt)
                elif bt == "tool_use":
                    name = b.get("name", "tool")
                    inp = json.dumps(b.get("input", {}), ensure_ascii=False)
                    if len(inp) > 220:
                        inp = inp[:220] + " ..."
                    show(f"  · {name}: {inp}")

        elif t == "result":
            show("\n── claude done ──")
            show(e.get("result", "") or "")

if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # A downstream reader (pager, terminal, the calling agent) closed the
        # stream early. That's fine — exit quietly instead of dumping a traceback.
        try:
            sys.stdout.close()
        except Exception:
            pass
