"""
Regression tests for the flow feature aggregator.

These pin the version-sensitive behaviours that match the Engelen CICFlowMeter
(the generator behind the training data). Run from the ebpf-sensor/ root:

    python3 -m pytest -q
"""
from sensor.flow_features import PacketMeta, FlowManager, FEATURE_ORDER

A = b"\xc0\xa8\x00\x01"  # 192.168.0.1
B = b"\xc0\xa8\x00\x02"  # 192.168.0.2
SYN, ACK, PSH = 0x02, 0x10, 0x08


def _run(pkts):
    """pkts: list of (ts_us, src, dst, sport, dport, flags, payload, hdr, win)."""
    out = []
    mgr = FlowManager(lambda f, ident: out.append(f))
    for ts, s, d, sp, dp, fl, pl, hl, win in pkts:
        mgr.add_packet(PacketMeta(ts, s, d, sp, dp, 6, pl, hl, win, fl))
    mgr.flush()
    return out


def test_contract_shape():
    f = _run([
        (1_000_000, A, B, 5000, 80, SYN, 0, 32, 64240),
        (1_050_000, B, A, 80, 5000, SYN | ACK, 0, 32, 65535),
        (1_300_000, B, A, 80, 5000, ACK, 1460, 20, 65535),
    ])[0]
    assert list(f.keys()) == FEATURE_ORDER
    assert len(f) == 56


def test_packet_length_is_l4_payload():
    # bare SYN/ACK carry 0 payload -> Packet Length Min must be 0
    f = _run([
        (1_000_000, A, B, 5000, 80, SYN, 0, 32, 64240),
        (1_100_000, B, A, 80, 5000, SYN | ACK, 0, 32, 65535),
        (1_200_000, A, B, 5000, 80, PSH | ACK, 200, 20, 64240),
    ])[0]
    assert f["Packet Length Min"] == 0
    assert f["Fwd Packets Length Total"] == 200


def test_down_up_ratio_is_true_division():
    # 2 bwd / 3 fwd -> 0.6667 (Engelen true division, NOT floored to 0)
    f = _run([
        (1_000_000, A, B, 5000, 80, SYN, 0, 32, 64240),
        (1_050_000, B, A, 80, 5000, SYN | ACK, 0, 32, 65535),
        (1_100_000, A, B, 5000, 80, ACK, 0, 20, 64240),
        (1_200_000, A, B, 5000, 80, PSH | ACK, 200, 20, 64240),
        (1_300_000, B, A, 80, 5000, ACK, 1460, 20, 65535),
    ])[0]
    assert round(f["Down/Up Ratio"], 4) == 0.6667


def test_fwd_seg_size_min_is_header_length():
    f = _run([
        (1_000_000, A, B, 5000, 80, SYN, 0, 32, 64240),       # hdr 32 (SYN w/ options)
        (1_050_000, B, A, 80, 5000, SYN | ACK, 0, 32, 65535),
        (1_100_000, A, B, 5000, 80, PSH | ACK, 200, 20, 64240),  # hdr 20
    ])[0]
    assert f["Fwd Seg Size Min"] == 20


def test_active_idle_zero_without_gap():
    f = _run([
        (1_000_000, A, B, 5000, 80, PSH | ACK, 100, 20, 64240),
        (1_100_000, B, A, 80, 5000, ACK, 100, 20, 65535),
    ])[0]
    assert f["Active Mean"] == 0 and f["Idle Mean"] == 0


def test_active_idle_populated_with_gap():
    # 6.9 s gap > 5 s threshold: records the pre-gap burst (0.1 s) and the gap (6.9 s);
    # the trailing burst is intentionally dropped (dead endActiveIdleTime in the fork).
    f = _run([
        (1_000_000, A, B, 5000, 80, PSH | ACK, 100, 20, 64240),
        (1_100_000, B, A, 80, 5000, ACK, 100, 20, 65535),
        (8_000_000, A, B, 5000, 80, PSH | ACK, 100, 20, 64240),
        (8_100_000, B, A, 80, 5000, ACK, 100, 20, 65535),
    ])[0]
    assert f["Active Mean"] == 100000.0
    assert f["Idle Mean"] == 6900000.0


def test_flag_counts_are_binary():
    # The dataset stores flag features as 0/1 presence, not per-packet counts.
    # 5 packets all carrying ACK -> ACK Flag Count must be 1, not 5.
    f = _run([
        (1_000_000, A, B, 5000, 80, ACK, 0, 20, 64240),
        (1_100_000, B, A, 80, 5000, ACK, 0, 20, 65535),
        (1_200_000, A, B, 5000, 80, PSH | ACK, 100, 20, 64240),
        (1_300_000, B, A, 80, 5000, ACK, 100, 20, 65535),
        (1_400_000, A, B, 5000, 80, ACK, 0, 20, 64240),
    ])[0]
    assert f["ACK Flag Count"] == 1
    assert f["PSH Flag Count"] == 1
    assert f["RST Flag Count"] == 0
