#!/usr/bin/env python3
"""Deterministic JSONL Pi peer. No Pi binary, credentials, model, or network.

PI_TEST_MODE selects normal, early_settle, slow_ack, reject, provider_error,
hold, exit, or handled. PI_TEST_TRANSCRIPT records argv/cwd and both directions.
"""
import heapq
import json
import os
import select
import sys
import time

mode = os.environ.get("PI_TEST_MODE", "normal")
transcript = os.environ["PI_TEST_TRANSCRIPT"]
sequence = 0
pending = []
count = 0
active = None
models = [
    {"provider": "offline-fixture", "id": "reasoner", "name": "Reasoner", "reasoning": True},
    {"provider": "offline-fixture", "id": "plain", "name": "Plain", "reasoning": False},
]
model = models[0]
thinking = "medium"
state_reads = 0


def record(value):
    with open(transcript, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(value, ensure_ascii=False) + "\n")


def emit(value):
    global active
    if value.get("type") == "agent_settled":
        active = None
    record({"direction": "out", "record": value})
    sys.stdout.write(json.dumps(value, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def response(request, data=None, error=None):
    value = {"type": "response", "id": request["id"],
             "command": request["type"], "success": error is None}
    if error is not None:
        value["error"] = error
    elif data is not None:
        value["data"] = data
    return value


def later(delay, value):
    global sequence
    sequence += 1
    heapq.heappush(pending, (time.monotonic() + delay, sequence, value))


def assistant(reason, text):
    return {"role": "assistant", "content": [{"type": "text", "text": text}],
            "api": "test", "provider": "offline-fixture", "model": "deterministic",
            "usage": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0,
                      "totalTokens": 0, "cost": {"input": 0, "output": 0,
                      "cacheRead": 0, "cacheWrite": 0, "total": 0}},
            "stopReason": reason, "timestamp": count}


def finish(delay=0, reason="stop"):
    message = assistant(reason, "FINAL answer %d" % count)
    if reason == "error":
        message["errorMessage"] = "fixture provider failed"
    later(delay, {"type": "message_end", "message": message})
    later(delay, {"type": "agent_end", "messages": [message], "willRetry": False})
    later(delay, {"type": "agent_settled"})


record({"direction": "start", "argv": sys.argv[1:], "cwd": os.getcwd(),
        "pid": os.getpid(), "mode": mode})
# Binary os.read + LF framing avoids Python's buffered readline/select mismatch.
buffer = b""
while True:
    now = time.monotonic()
    while pending and pending[0][0] <= now:
        _, _, value = heapq.heappop(pending)
        if value is None:
            sys.stderr.write("fixture unexpected exit\n")
            sys.stderr.flush()
            sys.exit(7)
        emit(value)
    timeout = max(0, pending[0][0] - time.monotonic()) if pending else None
    ready, _, _ = select.select([sys.stdin], [], [], timeout)
    if not ready:
        continue
    chunk = os.read(sys.stdin.fileno(), 65536)
    if not chunk:
        break
    buffer += chunk
    while b"\n" in buffer:
        line, buffer = buffer.split(b"\n", 1)
        request = json.loads(line)
        record({"direction": "in", "record": request})
        kind = request["type"]
        if kind == "get_state":
            state_reads += 1
            if mode == "readback_error" and state_reads > 1:
                emit(response(request, error="fixture state readback failed"))
            else:
                emit(response(request, {"sessionId": "fixture-%d" % os.getpid(),
                                       "model": model, "thinkingLevel": thinking,
                                       "isStreaming": active is not None, "messageCount": count * 2}))
        elif kind == "get_available_models":
            if mode == "discovery_error":
                emit(response(request, error="fixture discovery failed"))
            else:
                emit(response(request, {"models": [] if mode == "empty_models" else models}))
        elif kind == "get_available_thinking_levels":
            levels = ["off", "minimal", "low", "medium", "high", "xhigh"] if model["reasoning"] else ["off"]
            emit(response(request, {"levels": levels}))
        elif kind in ("set_model", "set_thinking_level"):
            if mode == "settings_reject":
                emit(response(request, error="fixture settings rejected"))
            else:
                if kind == "set_model":
                    model = next(m for m in models if m["id"] == request["modelId"] and m["provider"] == request["provider"])
                    thinking = "medium" if model["reasoning"] else "off"
                else:
                    thinking = request["level"] if model["reasoning"] else "off"
                reply = response(request, model if kind == "set_model" else None)
                if mode in ("settings_timeout", "settings_slow"):
                    later(0.4, reply)
                else:
                    emit(reply)
        elif kind == "prompt":
            record({"direction": "prompt_settings", "record": {"model": model, "thinking": thinking}})
            count += 1
            if mode == "reject":
                emit(response(request, error="fixture rejected prompt"))
                continue
            if mode == "handled":
                emit(response(request, {"disposition": "handled"}))
                continue
            active = request
            emit({"type": "agent_start"})
            user = {"role": "user", "content": request["message"], "timestamp": count}
            emit({"type": "message_start", "message": user})
            emit({"type": "message_end", "message": user})
            emit({"type": "message_start", "message": assistant("pending", "")})
            emit({"type": "message_update", "assistantMessageEvent": {
                "type": "text_delta", "contentIndex": 0, "delta": "DRAFT delta (not final)"}})
            if mode == "exit":
                later(0.02, None)
            elif mode == "early_settle":
                finish()
                later(0.4, response(request, {"disposition": "started"}))
            elif mode == "slow_ack":
                later(0.4, response(request, {"disposition": "started"}))
                finish(0.45)
            else:
                emit(response(request, {"disposition": "started"}))
                if mode != "hold":
                    finish(0.02, "error" if mode == "provider_error" else "stop")
        elif kind == "clear_queue":
            # Delayed reply makes the required clear_queue-before-abort ordering observable.
            later(0.03, response(request, {"steering": ["discard me"], "followUp": []}))
        elif kind == "abort":
            pending.clear()
            if active:
                finish(reason="aborted")
                active = None
            later(0, response(request))
        else:
            emit(response(request, error="unsupported fixture request: " + kind))
