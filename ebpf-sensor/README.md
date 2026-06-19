# ebpf-sensor

Live network sensor for the AI-IDS. It captures traffic, assembles it into
bidirectional flows, and emits the exact 56-feature vector the **inference-service**
expects — so the two services speak the same feature contract.

## Why the feature math is delicate

The models were trained on features produced by the **Engelen / Distrinet "improved"
CICFlowMeter** (the generator behind the `dhoogla/cicids2017` parquet). This sensor must
reproduce that tool's exact definitions and units, not an approximation, because the
models learned raw magnitudes. The aggregation core in `sensor/flow_features.py` is
pinned to that fork's source:

- packet "length" = L4 **payload** bytes (a bare SYN/ACK is 0)
- Flow Duration / IAT / Active / Idle in **microseconds**
- sample (n-1) standard deviation and variance
- Down/Up Ratio = **true** float division `bwd/fwd`
- TCP flow ends on **mutual FIN** or RST (else 120 s timeout)
- Active/Idle populated **only** by intra-flow gaps > 5 s (no final-burst add)

The authoritative contract (all 56 names, order, units, label map) lives in
`inference-service/INFERENCE_SERVICE_HANDOFF.md`.

## Build order — validate before going live

eBPF capture is added **last**. First we prove the aggregation math on replayable
pcaps, because that is where all the fidelity risk lives:

1. Aggregator core — `sensor/flow_features.py` (done; fed by pcap today)
2. Validate against the training distribution — `validate_sensor.py` + `X_test_sample.npy`
3. eBPF capture layer feeding the same `PacketMeta` records
4. Emit flows to Redis Streams / inference-service `/predict`

## Setup

    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements-dev.txt

## Validate

    # 1. confirm the two version knobs against your own data (no pcap needed)
    python3 check_knobs.py

    # 2. capture a small pcap (any traffic works for a first run)
    #    find your bridge first:  ip link | grep -E 'docker|br-'
    sudo tcpdump -i docker0 -w test.pcap -c 2000

    # 3. run the aggregator over the capture
    python3 sensor/flow_features.py test.pcap

    # 4. regression tests
    python3 -m pytest -q

## eBPF & Docker notes (stage 3+)

This service cannot be containerized like the others. eBPF needs kernel privileges and
BTF, so the eventual Dockerfile will require `--privileged` (or `CAP_BPF` +
`CAP_NET_ADMIN`), host networking, and a mounted `/sys/kernel/btf`; the container kernel
must match the host. eBPF tooling is installed via system packages, not pip:

    sudo apt install bpfcc-tools python3-bpfcc linux-headers-$(uname -r)

The Dockerfile is deferred until the capture layer exists, so it can be written against
the real privilege and BTF requirements rather than guessed.
