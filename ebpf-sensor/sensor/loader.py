#!/usr/bin/env python3
"""
loader.py — live AI-IDS sensor: eBPF capture -> FlowManager -> inference /predict.

Loads sensor/bpf/capture.c, attaches it to one interface, turns each ring-buffer record
into a PacketMeta fed to the validated FlowManager, and submits every completed flow to
the inference service through the (threaded, non-blocking) PredictEmitter.

Run (root; SYSTEM python, which has bcc). Start the inference service first:
    # terminal 1:
    cd ../inference-service && source .venv/bin/activate && uvicorn app.main:app --port 8000
    # terminal 2:
    sudo /usr/bin/python3 sensor/loader.py wlp1s0
"""
import os
import sys
import time

from bcc import BPF

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sensor.flow_features import PacketMeta, FlowManager
from sensor.emitter import PredictEmitter

SWEEP_EVERY_S = 2.0
HEARTBEAT_EVERY_S = 10.0
INFERENCE_URL = os.environ.get("INFERENCE_URL", "http://127.0.0.1:8000/predict")


def main(iface: str) -> None:
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bpf", "capture.c")
    b = BPF(src_file=src)
    fn = b.load_func("capture", BPF.SOCKET_FILTER)
    BPF.attach_raw_socket(fn, iface)

    emitter = PredictEmitter(url=INFERENCE_URL)
    emitter.start()

    pkts = {"n": 0}

    def on_flow(feat: dict) -> None:
        emitter.submit(feat)

    mgr = FlowManager(on_flow)

    def on_event(ctx, data, size):
        e = b["events"].event(data)
        pkts["n"] += 1
        mgr.add_packet(PacketMeta(
            ts_us=e.ts_us,
            src_ip=e.src_ip, dst_ip=e.dst_ip,         # ints are fine as flow-key components
            src_port=e.src_port, dst_port=e.dst_port,
            protocol=e.protocol,
            payload_len=e.payload_len, header_len=e.header_len,
            window=e.window, flags=e.flags,
        ))

    b["events"].open_ring_buffer(on_event)
    print(f"sensor live on {iface} -> {INFERENCE_URL}")
    print("ALERT lines = supervised attack; ANOMALY lines = autoencoder zero-day path.")
    print("Generate traffic. Ctrl-C to stop.\n")

    last_sweep = last_beat = time.monotonic()
    try:
        while True:
            b.ring_buffer_poll(timeout=200)
            now = time.monotonic()
            if now - last_sweep >= SWEEP_EVERY_S:
                mgr.sweep(time.monotonic_ns() // 1000)
                last_sweep = now
            if now - last_beat >= HEARTBEAT_EVERY_S:
                s = emitter.stats
                print(f"[+{int(now - last_beat)}s] pkts={pkts['n']} "
                      f"sent={s['sent']} attacks={s['attacks']} anomalies={s['anomalies']} "
                      f"benign={s['benign']} queued={emitter.q.qsize()} "
                      f"dropped={s['dropped']} errors={s['errors']}")
                last_beat = now
    except KeyboardInterrupt:
        print("\ndraining...")
        mgr.flush()
        emitter.stop()
        s = emitter.stats
        print(f"stopped. packets={pkts['n']} | sent={s['sent']} "
              f"attacks={s['attacks']} anomalies={s['anomalies']} benign={s['benign']} "
              f"dropped={s['dropped']} errors={s['errors']}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: sudo /usr/bin/python3 sensor/loader.py <interface>")
        sys.exit(1)
    main(sys.argv[1])
