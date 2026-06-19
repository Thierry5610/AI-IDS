#!/usr/bin/env python3
"""
emitter.py — sends flow feature vectors to the inference-service /predict endpoint.

Decoupled from capture: submit() only enqueues (non-blocking), and a background worker
thread does the HTTP POSTs, so inference latency never stalls the eBPF ring-buffer loop
or drops packets. Stdlib only (urllib) so it needs no extra install under system Python.

Stage 4a surfaces predictions to stdout. Stage 4b will swap _handle() to push alerts
onto Redis Streams (and add flow identity).
"""
import json
import queue
import threading
import urllib.request
import urllib.error
from datetime import datetime, timezone


class PredictEmitter:
    def __init__(self, url="http://127.0.0.1:8000/predict", maxsize=2000, timeout=3.0):
        self.url = url
        self.timeout = timeout
        self.q: queue.Queue = queue.Queue(maxsize=maxsize)
        self.stats = {"sent": 0, "attacks": 0, "anomalies": 0,
                      "benign": 0, "dropped": 0, "errors": 0}
        self._stop = threading.Event()
        self._warned = False
        self._t = threading.Thread(target=self._worker, daemon=True)

    def start(self):
        self._t.start()

    def submit(self, features: dict, flow_id: str = None):
        """Non-blocking. Drops (and counts) if the queue is full rather than stalling capture."""
        try:
            self.q.put_nowait((features, flow_id))
        except queue.Full:
            self.stats["dropped"] += 1

    def stop(self):
        self._stop.set()           # exit promptly; any still-queued flows are dropped
        self._t.join(timeout=3)

    # -- internals ----------------------------------------------------------
    def _post(self, features, flow_id):
        body = {"features": features,
                "timestamp": datetime.now(timezone.utc).isoformat()}
        if flow_id:
            body["flow_id"] = flow_id
        req = urllib.request.Request(
            self.url, data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            return json.loads(r.read())

    def _worker(self):
        while not self._stop.is_set():
            try:
                features, flow_id = self.q.get(timeout=0.2)
            except queue.Empty:
                continue
            try:
                self._handle(self._post(features, flow_id))
                self.stats["sent"] += 1
            except urllib.error.URLError as e:
                self.stats["errors"] += 1
                if not self._warned:
                    print(f"[emitter] cannot reach {self.url}: {e}\n"
                          f"[emitter] is the inference service up?  "
                          f"(cd inference-service && uvicorn app.main:app --port 8000)")
                    self._warned = True
            except Exception as e:
                self.stats["errors"] += 1
                if not self._warned:
                    print(f"[emitter] unexpected error: {e!r}")
                    self._warned = True
            finally:
                self.q.task_done()

    def _handle(self, resp: dict):
        pred = resp.get("prediction") or {}
        agr = resp.get("agreement") or {}
        ae = (resp.get("model_votes") or {}).get("autoencoder") or {}

        if resp.get("is_attack"):
            self.stats["attacks"] += 1
            print(f"ALERT    {str(pred.get('label')):22} conf={pred.get('confidence', 0):.2f}  "
                  f"src={resp.get('source_model')}  "
                  f"agree={agr.get('agreeing')}/{agr.get('total')}")
        elif ae.get("is_anomalous"):
            # supervised models say benign, autoencoder disagrees -> possible zero-day
            self.stats["anomalies"] += 1
            print(f"ANOMALY  (autoencoder)         score={ae.get('anomaly_score', 0):.4f}  "
                  f"thr={ae.get('threshold')}")
        else:
            self.stats["benign"] += 1
