#!/usr/bin/env python3
"""Render a peer agent's headless event stream (NDJSON on stdin) as readable live output.

One renderer, several peer formats — pick with `--format`:
  * claude-stream-json : Claude Code's `--output-format stream-json`
  * codex-jsonl        : Codex's `exec --json` event stream
  * raw                : passthrough (one line per event), the safe fallback

Robust by design: anything a renderer doesn't recognize is skipped (or, in raw mode,
printed verbatim), and the dispatcher always keeps the unmodified stream in the thread's
logs/ as the source of truth. Every format ends with a `── <peer> done ──` marker followed
by the peer's final answer, so the calling agent can reliably find where the answer begins.
"""
import sys
import json
import time

_TTY = sys.stdout.isatty()
_BEAT_EVERY = 5.0   # min seconds between thinking heartbeats when piped (non-TTY)


def show(s, end="\n"):
    sys.stdout.write(s + end)
    sys.stdout.flush()


def fmt_tok(n):
    return f"~{n / 1000:.1f}k tokens" if n >= 1000 else f"~{n} tokens"


def trim(s, n=220):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[:n] + " ..."


# --------------------------------------------------------------------------- Claude
def render_claude():
    """Claude Code stream-json.

    Extended thinking (especially at --effort max) emits `system/thinking_tokens`
    heartbeats that carry a token count but no text. We surface those as a live
    "thinking…" line so the caller can see Claude is alive and working — without it a
    long thinking phase looks like a dead stream and gets killed mid-thought.

    The `result` event repeats the final assistant text, so we hold the most recent text
    block back instead of printing it inline — the final answer then appears once, after
    the done-marker, rather than twice.
    """
    last_beat = 0.0
    inplace_open = False   # a live (carriage-return) "thinking…" line is open — TTY only
    pending = None         # newest assistant text block, deferred (see docstring)

    def end_thinking_line():
        nonlocal inplace_open
        if inplace_open:
            sys.stdout.write("\n")
            sys.stdout.flush()
            inplace_open = False

    def flush_pending():
        nonlocal pending
        if pending is not None:
            show(pending)
            pending = None

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue

        t = e.get("type")
        st = e.get("subtype")

        if t == "system" and st == "init":
            end_thinking_line()
            last_beat = 0.0
            show(f"\n── claude session {e.get('session_id', '?')} · {e.get('model', '?')} ──")

        elif t == "system" and st == "thinking_tokens":
            tok = e.get("estimated_tokens", 0)
            if _TTY:
                sys.stdout.write(f"\r  · thinking… {fmt_tok(tok)}   ")
                sys.stdout.flush()
                inplace_open = True
            else:
                now = time.time()
                if now - last_beat >= _BEAT_EVERY:
                    show(f"  · thinking… {fmt_tok(tok)}")
                    last_beat = now

        elif t == "assistant":
            end_thinking_line()
            last_beat = 0.0   # next thinking phase should beat again immediately
            for b in e.get("message", {}).get("content", []):
                bt = b.get("type")
                if bt == "text":
                    txt = (b.get("text") or "").rstrip()
                    if txt:
                        flush_pending()
                        pending = txt   # hold it; the next block/event or `result` supersedes it
                elif bt == "tool_use":
                    flush_pending()
                    name = b.get("name", "tool")
                    inp = json.dumps(b.get("input", {}), ensure_ascii=False)
                    show(f"  · {name}: {trim(inp)}")

        elif t == "result":
            end_thinking_line()
            pending = None   # the held text block is what `result` repeats — drop it
            show("\n── claude done ──")
            show(e.get("result", "") or "")


# ---------------------------------------------------------------------------- Codex
def render_codex():
    """Codex `exec --json` event stream.

    Events: thread.started / turn.{started,completed,failed} / error, plus item.started +
    item.completed carrying an `item` (type: agent_message, reasoning, command_execution,
    file_change, mcp_tool_call, web_search). Codex narrates *between* steps as agent_message,
    and the final answer is just the last one — so we stream them live but hold the most
    recent back, printing the final answer once after the done-marker instead of twice.
    Fields beyond the common ones are best-effort and degrade to a compact line.
    """
    last_msg = ""
    pending = None        # newest agent_message, deferred so the FINAL one isn't doubled

    def flush_pending():
        nonlocal pending
        if pending is not None:
            show(pending)
            pending = None

    def fmt_item(it, started):
        itype = it.get("type", "item")
        if itype == "command_execution":
            if started:
                return f"  · exec: {trim(it.get('command', ''))}"
            st = it.get("status")
            return f"  · exec {st}" if st and st not in ("completed", "success") else ""
        if itype == "file_change":
            if started:
                return ""
            ch = it.get("changes") or it.get("files") or it.get("path") or ""
            if isinstance(ch, list):   # codex sends [{"path","kind"}, …]; show basenames, tolerate other shapes
                ch = ", ".join((c.get("path", "") if isinstance(c, dict) else str(c)).rsplit("/", 1)[-1] for c in ch)
            return f"  · edit: {trim(ch)}"
        if itype == "mcp_tool_call":
            if started:
                srv, name = it.get("server", ""), (it.get("tool") or it.get("name", ""))
                return f"  · tool: {srv}{'.' if srv else ''}{name}"
            return ""
        if itype == "web_search":
            return f"  · search: {trim(it.get('query', ''))}" if started else ""
        if itype in ("agent_message", "reasoning"):
            return ""   # handled inline by the caller
        if itype == "error":
            # e.g. "session was recorded with model X but is resuming with Y" — never drop these
            return f"  · error: {trim(it.get('message', ''))}"
        return f"  · {itype}" if started else ""

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue

        t = e.get("type")

        if t == "thread.started":
            show(f"\n── codex thread {e.get('thread_id', '?')} ──")
        elif t == "error":
            flush_pending()
            show(f"  · error: {trim(e.get('message') or json.dumps(e))}")
        elif t == "turn.failed":
            flush_pending()
            err = (e.get("error") or {}).get("message") or json.dumps(e.get("error", {}))
            show(f"  · turn failed: {trim(err)}")
            if not last_msg:
                last_msg = f"(codex turn failed: {err})"
        elif t == "item.started":
            out = fmt_item(e.get("item", {}), started=True)
            if out:
                flush_pending()
                show(out)
        elif t == "item.completed":
            it = e.get("item", {})
            itype = it.get("type")
            if itype == "agent_message":
                txt = (it.get("text") or "").rstrip()
                if txt:
                    flush_pending()   # the previous narration line is now superseded
                    pending = txt     # hold this one; if it's the last, it prints after the marker
                    last_msg = txt
            elif itype == "reasoning":
                txt = (it.get("text") or it.get("summary") or "").strip()
                if txt:
                    flush_pending()
                    show(f"  · reasoning: {trim(txt)}")
            else:
                out = fmt_item(it, started=False)
                if out:
                    flush_pending()
                    show(out)

    show("\n── codex done ──")
    show(last_msg)


# ------------------------------------------------------------------------------ raw
def render_raw():
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line:
            show(line)


_RENDERERS = {
    "claude-stream-json": render_claude,
    "codex-jsonl": render_codex,
    "raw": render_raw,
}


def main():
    fmt = "claude-stream-json"
    argv = sys.argv[1:]
    if "--format" in argv:
        i = argv.index("--format")
        if i + 1 < len(argv):
            fmt = argv[i + 1]
    _RENDERERS.get(fmt, render_raw)()


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # A downstream reader (pager, terminal, the calling agent) closed the stream
        # early. That's fine — exit quietly instead of dumping a traceback.
        try:
            sys.stdout.close()
        except Exception:
            pass
