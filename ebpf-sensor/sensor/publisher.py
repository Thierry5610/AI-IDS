#!/usr/bin/env python3
"""
publisher.py — Redis Streams producer for sensor alerts.

Isolated here so the capture/aggregation core (flow_features) and the inference
client (emitter) keep no hard Redis dependency, and so a missing redis package or a
down Redis server degrades to a no-op (alerts still print) instead of stalling
capture or crashing the live path.

Fan-out (locked split):
  supervised  is_attack     -> ATTACKS stream    (Telegram pages on this)
  autoencoder is_anomalous  -> ANOMALIES stream   (dashboard / research view only)

Each message is one Redis field, `data`, holding the JSON-encoded /predict response
enriched with the forward identity 5-tuple. Streams are length-capped (approx MAXLEN).
"""
import json
import os

try:
    import redis  # type: ignore
except Exception:           # package absent -> publisher runs disabled, capture unaffected
    redis = None

REDIS_URL      = os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0")
ATTACKS_STREAM = os.environ.get("IDS_ATTACKS_STREAM", "ids:attacks")
ANOM_STREAM    = os.environ.get("IDS_ANOMALIES_STREAM", "ids:anomalies")
STREAM_MAXLEN  = int(os.environ.get("IDS_STREAM_MAXLEN", "10000"))


class Publisher:
    def __init__(self, url=REDIS_URL, maxlen=STREAM_MAXLEN,
                 attacks_stream=ATTACKS_STREAM, anomalies_stream=ANOM_STREAM,
                 client=None):
        self.attacks_stream = attacks_stream
        self.anomalies_stream = anomalies_stream
        self.maxlen = maxlen
        self.stats = {"attacks": 0, "anomalies": 0, "errors": 0, "skipped": 0}
        self.disabled_reason = None
        self._warned = False
        self._r = client                       # injectable for tests
        if self._r is not None:
            return
        if redis is None:
            self.disabled_reason = "redis package not installed"
            return
        try:
            self._r = redis.Redis.from_url(url, socket_timeout=2, socket_connect_timeout=2)
            self._r.ping()
        except Exception as e:
            self._r = None
            self.disabled_reason = f"cannot reach Redis at {url}: {e}"

    @property
    def enabled(self) -> bool:
        return self._r is not None

    def publish_attack(self, payload: dict) -> None:
        self._xadd(self.attacks_stream, payload, "attacks")

    def publish_anomaly(self, payload: dict) -> None:
        self._xadd(self.anomalies_stream, payload, "anomalies")

    # -- internals ----------------------------------------------------------
    def _xadd(self, stream: str, payload: dict, counter: str) -> None:
        if self._r is None:
            self.stats["skipped"] += 1
            return
        try:
            self._r.xadd(stream, {"data": json.dumps(payload, default=str)},
                         maxlen=self.maxlen, approximate=True)
            self.stats[counter] += 1
        except Exception as e:
            self.stats["errors"] += 1
            if not self._warned:
                print(f"[publisher] xadd to {stream} failed: {e!r} (capture continues)")
                self._warned = True
