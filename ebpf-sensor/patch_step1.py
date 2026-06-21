#!/usr/bin/env python3
"""
patch_step1.py — applies the flow-identity refactor (stage 4b, step 1) across the
ebpf-sensor. Transactional: every edit is computed in memory and asserted to match
exactly once; nothing is written unless ALL edits succeed. Safe to abort, safe to
re-run (it detects an already-applied tree and stops).

Usage:  python3 patch_step1.py [SENSOR_DIR]
        SENSOR_DIR defaults to the repo's ebpf-sensor/.
"""
import sys, os, py_compile

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/thierry/TempStorage/AI-IDS/ebpf-sensor"

# (relative path, old, new) — old strings copied verbatim from committed source.
EDITS = [
    # ---- flow_features.py -------------------------------------------------
    ("sensor/flow_features.py",
     "import math\nfrom dataclasses import dataclass, field",
     "import math\nimport socket\nimport struct\nfrom dataclasses import dataclass, field"),

    ("sensor/flow_features.py",
     "    lo, hi = (a, b) if a <= b else (b, a)\n    return (m.protocol, lo, hi)\n",
     "    lo, hi = (a, b) if a <= b else (b, a)\n    return (m.protocol, lo, hi)\n"
     "\n\n"
     "def _ip_to_str(ip) -> str:\n"
     "    \"\"\"Render a PacketMeta IP as a dotted quad, accepting either representation the\n"
     "    two front-ends produce: pcap (dpkt) gives 4 packed BYTES; the eBPF path gives a\n"
     "    host-byte-order u32 int (bcc/proto.h convention, same as capture_probe.fmt_ip).\"\"\"\n"
     "    if isinstance(ip, (bytes, bytearray)):\n"
     "        return socket.inet_ntoa(bytes(ip))\n"
     "    return socket.inet_ntoa(struct.pack(\">I\", int(ip) & 0xFFFFFFFF))\n"),

    ("sensor/flow_features.py",
     "        self.src_ip, self.src_port = first.src_ip, first.src_port\n        self.protocol = first.protocol",
     "        self.src_ip, self.src_port = first.src_ip, first.src_port\n        self.dst_ip, self.dst_port = first.dst_ip, first.dst_port\n        self.protocol = first.protocol"),

    ("sensor/flow_features.py",
     "    def is_forward(self, m: PacketMeta) -> bool:\n"
     "        return m.src_ip == self.src_ip and m.src_port == self.src_port\n",
     "    def is_forward(self, m: PacketMeta) -> bool:\n"
     "        return m.src_ip == self.src_ip and m.src_port == self.src_port\n"
     "\n"
     "    def identity(self) -> Dict[str, object]:\n"
     "        \"\"\"Forward 5-tuple (first-packet src->dst). NOT the canonical flow_key, which\n"
     "        sorts endpoints and would flip ~half of flows. Sibling to the feature dict;\n"
     "        never mixed into the 56-feature contract.\"\"\"\n"
     "        return {\n"
     "            \"src_ip\": _ip_to_str(self.src_ip),\n"
     "            \"src_port\": int(self.src_port),\n"
     "            \"dst_ip\": _ip_to_str(self.dst_ip),\n"
     "            \"dst_port\": int(self.dst_port),\n"
     "            \"protocol\": int(self.protocol),\n"
     "        }\n"),

    ("sensor/flow_features.py",
     "    def __init__(self, on_flow: Callable[[Dict[str, float]], None],\n                 min_packets: int = MIN_PACKETS_TO_EMIT):",
     "    def __init__(self, on_flow: Callable[[Dict[str, float], Dict[str, object]], None],\n                 min_packets: int = MIN_PACKETS_TO_EMIT):"),

    ("sensor/flow_features.py",
     "            if dur > 0:  # drop degenerate zero-duration flows (would yield inf rates; cleaned out of dataset)\n                self.on_flow(flow.emit())",
     "            if dur > 0:  # drop degenerate zero-duration flows (would yield inf rates; cleaned out of dataset)\n                self.on_flow(flow.emit(), flow.identity())"),

    ("sensor/flow_features.py",
     "def run_pcap(path: str, on_flow: Callable[[Dict[str, float]], None]) -> int:",
     "def run_pcap(path: str, on_flow: Callable[[Dict[str, float], Dict[str, object]], None]) -> int:"),

    ("sensor/flow_features.py",
     "    n = run_pcap(sys.argv[1], flows.append)",
     "    n = run_pcap(sys.argv[1], lambda f, ident: flows.append(f))"),

    # ---- emitter.py -------------------------------------------------------
    ("sensor/emitter.py",
     "    def submit(self, features: dict, flow_id: str = None):\n        \"\"\"Non-blocking. Drops (and counts) if the queue is full rather than stalling capture.\"\"\"\n        try:\n            self.q.put_nowait((features, flow_id))",
     "    def submit(self, features: dict, identity: dict = None):\n        \"\"\"Non-blocking. Drops (and counts) if the queue is full rather than stalling capture.\n        identity = forward 5-tuple dict from FlowManager (src/dst ip+port, protocol).\"\"\"\n        try:\n            self.q.put_nowait((features, identity))"),

    ("sensor/emitter.py",
     "    # -- internals ----------------------------------------------------------\n    def _post(self, features, flow_id):\n        body = {\"features\": features,\n                \"timestamp\": datetime.now(timezone.utc).isoformat()}\n        if flow_id:\n            body[\"flow_id\"] = flow_id",
     "    # -- internals ----------------------------------------------------------\n    def _post(self, features, identity):\n        body = {\"features\": features,\n                \"timestamp\": datetime.now(timezone.utc).isoformat()}\n        if identity:\n            body[\"flow_id\"] = _flow_id(identity)"),

    ("sensor/emitter.py",
     "                features, flow_id = self.q.get(timeout=0.2)\n            except queue.Empty:\n                continue\n            try:\n                self._handle(self._post(features, flow_id))",
     "                features, identity = self.q.get(timeout=0.2)\n            except queue.Empty:\n                continue\n            try:\n                self._handle(self._post(features, identity), identity)"),

    ("sensor/emitter.py",
     "    def _handle(self, resp: dict):\n        pred = resp.get(\"prediction\") or {}\n        agr = resp.get(\"agreement\") or {}\n        ae = (resp.get(\"model_votes\") or {}).get(\"autoencoder\") or {}\n",
     "    def _handle(self, resp: dict, identity: dict = None):\n        pred = resp.get(\"prediction\") or {}\n        agr = resp.get(\"agreement\") or {}\n        ae = (resp.get(\"model_votes\") or {}).get(\"autoencoder\") or {}\n        who = \"\"\n        if identity:\n            who = (f\"  {identity['src_ip']}:{identity['src_port']}\"\n                   f\"->{identity['dst_ip']}:{identity['dst_port']}\")\n"),

    ("sensor/emitter.py",
     "                  f\"agree={agr.get('agreeing')}/{agr.get('total')}\")",
     "                  f\"agree={agr.get('agreeing')}/{agr.get('total')}{who}\")"),

    ("sensor/emitter.py",
     "                  f\"thr={ae.get('threshold')}\")",
     "                  f\"thr={ae.get('threshold')}{who}\")"),

    ("sensor/emitter.py",
     "import urllib.error\nfrom datetime import datetime, timezone\n",
     "import urllib.error\nfrom datetime import datetime, timezone\n"
     "\n\n"
     "def _flow_id(identity: dict) -> str:\n"
     "    \"\"\"Stable, greppable per-edge id from the forward 5-tuple:\n"
     "    'proto-src:sport-dst:dport'. Per-edge, not globally unique (a recurring 5-tuple\n"
     "    reuses it) — fine for topology/attribution; the dashboard keys on the edge.\"\"\"\n"
     "    return (f\"{identity['protocol']}-{identity['src_ip']}:{identity['src_port']}\"\n"
     "            f\"-{identity['dst_ip']}:{identity['dst_port']}\")\n"),

    # ---- loader.py --------------------------------------------------------
    ("sensor/loader.py",
     "    def on_flow(feat: dict) -> None:\n        emitter.submit(feat)",
     "    def on_flow(feat: dict, ident: dict) -> None:\n        emitter.submit(feat, ident)"),

    # ---- harness adapters (features-only callers) -------------------------
    ("validate_sensor.py",
     "    n_pkts = run_pcap(pcap, flows.append)",
     "    n_pkts = run_pcap(pcap, lambda f, ident: flows.append(f))"),

    ("calibrate_threshold.py",
     "    run_pcap(pcap, lambda f: flows.append(f))",
     "    run_pcap(pcap, lambda f, ident: flows.append(f))"),

    ("tests/test_flow_features.py",
     "    mgr = FlowManager(out.append)",
     "    mgr = FlowManager(lambda f, ident: out.append(f))"),
]

SENTINEL = ("sensor/flow_features.py", "def identity(self) -> Dict[str, object]:")


def main():
    sf, marker = SENTINEL
    sp = os.path.join(BASE, sf)
    if not os.path.exists(sp):
        sys.exit(f"ERROR: {sp} not found. Pass the correct ebpf-sensor dir as arg 1.")
    if marker in open(sp, encoding="utf-8").read():
        sys.exit("Already applied (identity() present). Nothing to do.")

    staged = {}  # path -> text, computed in memory; only flushed if all edits pass
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

    for path, text in staged.items():
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        if path.endswith(".py"):
            py_compile.compile(path, doraise=True)
        print(f"patched  {os.path.relpath(path, BASE)}")

    print(f"\nOK — {len(staged)} files patched, all compile.")


if __name__ == "__main__":
    main()
