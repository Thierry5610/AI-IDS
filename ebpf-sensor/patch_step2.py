#!/usr/bin/env python3
"""
patch_step2.py — stage 4b, step 2: Redis Streams fan-out from the emitter.

Adds sensor/publisher.py (new), wires an optional Publisher through emitter._handle
(supervised is_attack -> attacks stream; AE is_anomalous -> anomalies stream), and
constructs/threads it in loader.py. The inference service is NOT touched. Redis is
optional: if the package is missing or the server is down, alerts still print and
capture is unaffected.

Transactional: every edit is asserted to match exactly once and staged in memory;
nothing is written unless all edits pass. Safe to re-run (detects applied tree).

Usage:  python3 patch_step2.py [SENSOR_DIR]
"""
import sys, os, py_compile

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/thierry/TempStorage/AI-IDS/ebpf-sensor"

PUBLISHER_SRC = '''#!/usr/bin/env python3
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
'''

EDITS = [
    # ---- emitter.py: accept an optional publisher ------------------------
    ("sensor/emitter.py",
     '    def __init__(self, url="http://127.0.0.1:8000/predict", maxsize=2000, timeout=3.0):\n        self.url = url\n        self.timeout = timeout\n',
     '    def __init__(self, url="http://127.0.0.1:8000/predict", maxsize=2000, timeout=3.0, publisher=None):\n        self.url = url\n        self.timeout = timeout\n        self.publisher = publisher\n'),

    # ---- emitter.py: publish on the two alert branches -------------------
    ("sensor/emitter.py",
     '            print(f"ALERT    {str(pred.get(\'label\')):22} conf={pred.get(\'confidence\', 0):.2f}  "\n'
     '                  f"src={resp.get(\'source_model\')}  "\n'
     '                  f"agree={agr.get(\'agreeing\')}/{agr.get(\'total\')}{who}")\n',
     '            print(f"ALERT    {str(pred.get(\'label\')):22} conf={pred.get(\'confidence\', 0):.2f}  "\n'
     '                  f"src={resp.get(\'source_model\')}  "\n'
     '                  f"agree={agr.get(\'agreeing\')}/{agr.get(\'total\')}{who}")\n'
     '            if self.publisher:\n'
     '                self.publisher.publish_attack({**resp, "identity": identity})\n'),

    ("sensor/emitter.py",
     '            print(f"ANOMALY  (autoencoder)         score={ae.get(\'anomaly_score\', 0):.4f}  "\n'
     '                  f"thr={ae.get(\'threshold\')}{who}")\n',
     '            print(f"ANOMALY  (autoencoder)         score={ae.get(\'anomaly_score\', 0):.4f}  "\n'
     '                  f"thr={ae.get(\'threshold\')}{who}")\n'
     '            if self.publisher:\n'
     '                self.publisher.publish_anomaly({**resp, "identity": identity})\n'),

    # ---- loader.py: import, construct, thread, report --------------------
    ("sensor/loader.py",
     "from sensor.flow_features import PacketMeta, FlowManager\nfrom sensor.emitter import PredictEmitter\n",
     "from sensor.flow_features import PacketMeta, FlowManager\nfrom sensor.emitter import PredictEmitter\nfrom sensor.publisher import Publisher\n"),

    ("sensor/loader.py",
     "    emitter = PredictEmitter(url=INFERENCE_URL)\n    emitter.start()\n",
     "    publisher = Publisher()\n"
     "    if publisher.enabled:\n"
     "        print(f\"redis: -> {publisher.attacks_stream} (attacks) | {publisher.anomalies_stream} (anomalies)\")\n"
     "    else:\n"
     "        print(f\"redis: DISABLED ({publisher.disabled_reason}) -- alerts print only, capture unaffected\")\n"
     "    emitter = PredictEmitter(url=INFERENCE_URL, publisher=publisher)\n    emitter.start()\n"),

    ("sensor/loader.py",
     '                s = emitter.stats\n'
     '                print(f"[+{int(now - last_beat)}s] pkts={pkts[\'n\']} "\n'
     '                      f"sent={s[\'sent\']} attacks={s[\'attacks\']} anomalies={s[\'anomalies\']} "\n'
     '                      f"benign={s[\'benign\']} queued={emitter.q.qsize()} "\n'
     '                      f"dropped={s[\'dropped\']} errors={s[\'errors\']}")\n',
     '                s = emitter.stats\n'
     '                p = publisher.stats\n'
     '                print(f"[+{int(now - last_beat)}s] pkts={pkts[\'n\']} "\n'
     '                      f"sent={s[\'sent\']} attacks={s[\'attacks\']} anomalies={s[\'anomalies\']} "\n'
     '                      f"benign={s[\'benign\']} queued={emitter.q.qsize()} "\n'
     '                      f"dropped={s[\'dropped\']} errors={s[\'errors\']}  "\n'
     '                      f"pub={p[\'attacks\']}a/{p[\'anomalies\']}n skip={p[\'skipped\']} puberr={p[\'errors\']}")\n'),
]

SENTINEL_FILE = "sensor/publisher.py"


def main():
    if not os.path.isdir(BASE):
        sys.exit(f"ERROR: {BASE} not found. Pass the ebpf-sensor dir as arg 1.")
    if os.path.exists(os.path.join(BASE, SENTINEL_FILE)):
        sys.exit("Already applied (sensor/publisher.py exists). Nothing to do.")

    staged = {}
    for rel, old, new in EDITS:
        path = os.path.join(BASE, rel)
        text = staged.get(path)
        if text is None:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        n = text.count(old)
        if n != 1:
            sys.exit(f"ERROR: anchor matched {n}x (need 1) in {rel}:\n---\n{old}\n---")
        staged[path] = text.replace(old, new, 1)

    # requirements.txt: append redis if absent (safe regardless of contents)
    req = os.path.join(BASE, "requirements.txt")
    rtext = open(req, encoding="utf-8").read() if os.path.exists(req) else ""
    if "redis" not in rtext:
        if rtext and not rtext.endswith("\n"):
            rtext += "\n"
        staged[req] = rtext + "redis>=5\n"

    # write new file
    pub_path = os.path.join(BASE, SENTINEL_FILE)
    with open(pub_path, "w", encoding="utf-8") as fh:
        fh.write(PUBLISHER_SRC)
    py_compile.compile(pub_path, doraise=True)
    print(f"created  {SENTINEL_FILE}")

    for path, text in staged.items():
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        if path.endswith(".py"):
            py_compile.compile(path, doraise=True)
        print(f"patched  {os.path.relpath(path, BASE)}")

    print(f"\nOK — publisher created, {len(staged)} files patched, all compile.")


if __name__ == "__main__":
    main()
