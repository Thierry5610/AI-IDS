"""
Redis XREAD tailing consumer (broadcast / fan-out).

Each SSE connection calls stream_events() independently and gets its OWN
cursor — so EVERY connected client receives EVERY message. This is the
correct model for a dashboard.

(The previous group-consumer approach used competing consumers: a message
went to only one connection, so a second browser tab would see nothing.)

No acking, no consumer groups. Starts at "0" to replay recent history on
connect, then tails live.
"""
import json
import os
import redis.asyncio as aioredis

REDIS_URL      = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")
BLOCK_MS       = 5_000
SOCKET_TIMEOUT = BLOCK_MS / 1000 + 5


async def stream_events(stream: str, start_id: str = "0"):
    """Async generator: yields JSON strings or None (heartbeat tick).

    start_id "0"  → replay all retained history then tail
    start_id "$"  → live only (skip history)
    """
    r = await aioredis.from_url(
        REDIS_URL,
        socket_timeout=SOCKET_TIMEOUT,
        decode_responses=True,
    )

    cursor = start_id
    while True:
        try:
            results = await r.xread({stream: cursor}, count=20, block=BLOCK_MS)
        except aioredis.TimeoutError:
            yield None
            continue
        except Exception:
            yield None
            continue

        if not results:
            yield None
            continue

        for _, messages in results:
            for msg_id, fields in messages:
                cursor = msg_id                  # advance this connection's cursor
                raw = fields.get("data", "{}")
                try:
                    json.loads(raw)
                except json.JSONDecodeError:
                    continue
                yield raw
