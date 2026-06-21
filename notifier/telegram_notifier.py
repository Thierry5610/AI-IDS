#!/usr/bin/env python3
"""
telegram_notifier.py — pages supervised attack alerts to Telegram.

Standalone consumer of the ids:attacks Redis stream. Uses a consumer GROUP so that:
  - alerts already in the stream before first start are skipped (group created at $),
  - a restart resumes from the last UN-ACKED alert instead of re-paging history,
  - a send failure leaves the alert pending, so it is retried on the next start.
Each alert is formatted and POSTed to the Telegram Bot API over stdlib urllib
(no extra deps). Decoupled from the sensor — needs only Redis + two env credentials.

Env:
  TELEGRAM_BOT_TOKEN     (required)  BotFather token
  TELEGRAM_CHAT_ID       (required)  destination chat id
  REDIS_URL              redis://127.0.0.1:6379/0
  IDS_ATTACKS_STREAM     ids:attacks
  IDS_NOTIFIER_GROUP     telegram
  IDS_NOTIFIER_CONSUMER  <hostname>

Run (venv with redis installed; no root/bcc):
  TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy python3 telegram_notifier.py
"""
import json
import os
import signal
import socket
import sys
import time
import urllib.request
import urllib.error

import redis

REDIS_URL = os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0")
STREAM    = os.environ.get("IDS_ATTACKS_STREAM", "ids:attacks")
GROUP     = os.environ.get("IDS_NOTIFIER_GROUP", "telegram")
CONSUMER  = os.environ.get("IDS_NOTIFIER_CONSUMER", socket.gethostname())
TOKEN     = os.environ.get("TELEGRAM_BOT_TOKEN")
CHAT_ID   = os.environ.get("TELEGRAM_CHAT_ID")
BLOCK_MS  = 5000
BATCH     = 10
API_URL   = "https://api.telegram.org/bot{token}/sendMessage"


def format_alert(payload: dict) -> str:
    pred  = payload.get("prediction") or {}
    ident = payload.get("identity") or {}
    agr   = payload.get("agreement") or {}
    expl  = payload.get("explanation") or {}
    top   = (expl.get("top_features") or [{}])[0] if expl else {}
    lines = ["AI-IDS ALERT — supervised attack",
             f"{pred.get('label','?')}  (conf {pred.get('confidence',0):.2f})"]
    if ident:
        lines.append(f"{ident.get('src_ip')}:{ident.get('src_port')} -> "
                     f"{ident.get('dst_ip')}:{ident.get('dst_port')}  proto {ident.get('protocol')}")
    lines.append(f"model {payload.get('source_model','?')}   "
                 f"agree {agr.get('agreeing','?')}/{agr.get('total','?')}")
    if top.get("feature"):
        lines.append(f"top factor: {top['feature']} ({top.get('direction','')})")
    if payload.get("flow_id"):
        lines.append(f"flow {payload['flow_id']}")
    if payload.get("timestamp"):
        lines.append(payload["timestamp"])
    return "\n".join(lines)


def send_telegram(text: str, timeout: int = 10) -> bool:
    body = json.dumps({"chat_id": CHAT_ID, "text": text}).encode()
    req = urllib.request.Request(API_URL.format(token=TOKEN), data=body,
                                 headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            ok = json.loads(r.read()).get("ok", False)
            if not ok:
                print("[notifier] telegram responded not-ok (leaving alert pending)")
            return ok
    except urllib.error.URLError as e:
        print(f"[notifier] telegram send failed: {e} (leaving alert pending)")
        return False


def ensure_group(r) -> None:
    try:
        r.xgroup_create(STREAM, GROUP, id="$", mkstream=True)
        print(f"[notifier] created group '{GROUP}' on {STREAM} at $ — only new alerts page")
    except redis.ResponseError as e:
        if "BUSYGROUP" in str(e):
            print(f"[notifier] group '{GROUP}' already on {STREAM}")
        else:
            raise


def handle(r, msg_id, fields) -> None:
    raw = fields.get("data")
    try:
        payload = json.loads(raw)
    except (TypeError, ValueError):
        print(f"[notifier] unparseable payload {msg_id}; acking to skip")
        r.xack(STREAM, GROUP, msg_id)
        return
    if send_telegram(format_alert(payload)):
        r.xack(STREAM, GROUP, msg_id)
    # on failure: do NOT ack -> stays pending, retried on next start


def drain_pending(r) -> int:
    """Re-deliver this consumer's un-acked alerts from a previous crash/failed send."""
    resp = r.xreadgroup(GROUP, CONSUMER, {STREAM: "0"}, count=BATCH)
    n = 0
    for _stream, msgs in resp or []:
        for msg_id, fields in msgs:
            handle(r, msg_id, fields)
            n += 1
    if n:
        print(f"[notifier] re-processed {n} pending alert(s) from a previous run")
    return n


def main() -> None:
    if not TOKEN or not CHAT_ID:
        sys.exit("ERROR: set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID")
    r = redis.Redis.from_url(REDIS_URL, decode_responses=True,
                             socket_timeout=BLOCK_MS / 1000 + 5)
    ensure_group(r)
    drain_pending(r)

    stop = {"v": False}
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *a: stop.__setitem__("v", True))
    print(f"[notifier] paging {STREAM} -> Telegram chat {CHAT_ID}. Ctrl-C to stop.")

    while not stop["v"]:
        try:
            resp = r.xreadgroup(GROUP, CONSUMER, {STREAM: ">"}, count=BATCH, block=BLOCK_MS)
        except redis.TimeoutError:
            continue                       # idle: blocking read elapsed with no new alerts
        except redis.ConnectionError as e:
            print(f"[notifier] redis connection lost: {e}; retrying in 2s")
            time.sleep(2)
            continue
        for _stream, msgs in resp or []:
            for msg_id, fields in msgs:
                handle(r, msg_id, fields)
    print("[notifier] stopped.")


if __name__ == "__main__":
    main()
