"""
flow_features.py — CICFlowMeter-faithful flow feature aggregator for the AI-IDS sensor.

This reproduces the 56-feature contract the inference service expects, matching the
*Engelen / Distrinet "improved" CICFlowMeter* (https://github.com/GintsEngelen/CICFlowMeter),
which is the tool that generated the dhoogla/cicids2017 parquet the models trained on.

Design:
  - This module is the SOURCE-AGNOSTIC aggregation core. It ingests per-packet metadata
    (PacketMeta) and emits the 56-feature dict. Today it's fed by a pcap (dpkt, see __main__);
    later the exact same core is fed by the eBPF ring buffer. The aggregation math is where
    100% of the fidelity risk lives, so it is isolated here and validated on replayable pcaps
    before eBPF is ever attached.

Verified against the Engelen fork source (not memory):
  - "Packet length" = L4 PAYLOAD bytes (ip.total_len - ip_hdr - l4_hdr). A bare SYN/ACK = 0.
  - Flow Duration, all IAT, Active, Idle are in MICROSECONDS.
  - Rates (Bytes/s, Packets/s) divide by duration_us / 1_000_000.
  - Down/Up Ratio = TRUE float division bwd/fwd  (Engelen fix; stock CICFlowMeter floors it).
  - Std / Variance are SAMPLE statistics (n-1 denominator), matching Apache SummaryStatistics.
  - Fwd Seg Size Min = min forward TCP header length (doff*4), not payload.
  - Fwd Act Data Packets = count of forward packets with payload >= 1.
  - Init Fwd/Bwd Win Bytes = TCP window of the FIRST fwd / first bwd packet (default below).
  - Flag counts are per-packet counts across the whole flow; "CWE" == the CWR bit.
  - TCP flow terminates on MUTUAL FIN (both directions) or RST; else on 120s timeout. UDP: timeout.

VERSION-SENSITIVE KNOBS (confirm against your X_test_sample.npy before trusting fidelity):
  - INIT_WIN_DEFAULT: this fork initializes to 0. The original CIC CSVs used -1. Check columns
    "Init Fwd Win Bytes" / "Init Bwd Win Bytes" in your data and set accordingly.
  - Active/Idle: the fork comments out endActiveIdleTime, so these are 0 for any flow without a
    >5s intra-flow gap. Confirm most X_test_sample rows have Active Mean == Idle Mean == 0.
"""

from __future__ import annotations
import math
from dataclasses import dataclass, field
from typing import Callable, Dict, Optional

# ---------------------------------------------------------------------------
# Constants / knobs
# ---------------------------------------------------------------------------
FLOW_TIMEOUT_US     = 120_000_000   # 120 s
ACTIVITY_TIMEOUT_US = 5_000_000     # 5 s
INIT_WIN_DEFAULT    = -1            # no-window value for UDP / unidirectional flows (confirmed from X_test_sample)
MIN_PACKETS_TO_EMIT = 2             # single-packet flows -> degenerate (inf rates); dropped in cleaning

# TCP flag bit masks
FIN, SYN, RST, PSH, ACK, URG, ECE, CWR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

# The 56 features in EXACT contract order. emit() returns a dict keyed by these strings.
FEATURE_ORDER = [
    "Protocol", "Flow Duration", "Total Fwd Packets", "Total Backward Packets",
    "Fwd Packets Length Total", "Bwd Packets Length Total",
    "Fwd Packet Length Max", "Fwd Packet Length Min", "Fwd Packet Length Mean", "Fwd Packet Length Std",
    "Bwd Packet Length Max", "Bwd Packet Length Min", "Bwd Packet Length Mean", "Bwd Packet Length Std",
    "Flow Bytes/s", "Flow Packets/s",
    "Flow IAT Mean", "Flow IAT Std", "Flow IAT Max", "Flow IAT Min",
    "Fwd IAT Mean", "Fwd IAT Std", "Fwd IAT Min",
    "Bwd IAT Total", "Bwd IAT Mean", "Bwd IAT Std", "Bwd IAT Max", "Bwd IAT Min",
    "Fwd Packets/s", "Bwd Packets/s",
    "Packet Length Min", "Packet Length Max", "Packet Length Mean", "Packet Length Std", "Packet Length Variance",
    "FIN Flag Count", "SYN Flag Count", "RST Flag Count", "PSH Flag Count",
    "ACK Flag Count", "URG Flag Count", "CWE Flag Count", "ECE Flag Count",
    "Down/Up Ratio", "Init Fwd Win Bytes", "Init Bwd Win Bytes",
    "Fwd Act Data Packets", "Fwd Seg Size Min",
    "Active Mean", "Active Std", "Active Max", "Active Min",
    "Idle Mean", "Idle Std", "Idle Max", "Idle Min",
]
assert len(FEATURE_ORDER) == 56


# ---------------------------------------------------------------------------
# Running statistics — mirrors Apache Commons Math SummaryStatistics
# (Welford for numerical stability; sample variance with n-1 denominator)
# ---------------------------------------------------------------------------
class Stat:
    __slots__ = ("n", "mean", "_m2", "min", "max", "sum")

    def __init__(self):
        self.n = 0
        self.mean = 0.0
        self._m2 = 0.0
        self.min = math.inf
        self.max = -math.inf
        self.sum = 0.0

    def add(self, x: float) -> None:
        self.n += 1
        self.sum += x
        d = x - self.mean
        self.mean += d / self.n
        self._m2 += d * (x - self.mean)
        if x < self.min:
            self.min = x
        if x > self.max:
            self.max = x

    # SummaryStatistics returns NaN for empty; 0 variance for n==1.
    def get_mean(self) -> float:
        return self.mean if self.n > 0 else float("nan")

    def get_min(self) -> float:
        return self.min if self.n > 0 else float("nan")

    def get_max(self) -> float:
        return self.max if self.n > 0 else float("nan")

    def get_var(self) -> float:
        if self.n == 0:
            return float("nan")
        if self.n == 1:
            return 0.0
        return self._m2 / (self.n - 1)

    def get_std(self) -> float:
        v = self.get_var()
        return math.sqrt(v) if v == v else float("nan")  # nan-safe


# ---------------------------------------------------------------------------
# Per-packet metadata (whatever the source — pcap or eBPF — must provide)
# ---------------------------------------------------------------------------
@dataclass
class PacketMeta:
    ts_us: int            # timestamp in microseconds
    src_ip: bytes
    dst_ip: bytes
    src_port: int
    dst_port: int
    protocol: int         # 6 TCP, 17 UDP
    payload_len: int      # L4 payload bytes
    header_len: int       # L4 header bytes (TCP doff*4, or 8 for UDP)
    window: int           # TCP window (0 if N/A)
    flags: int            # TCP flag bits (0 for UDP)


def flow_key(m: PacketMeta):
    """Direction-independent key: both directions of a connection map to the same flow."""
    a = (m.src_ip, m.src_port)
    b = (m.dst_ip, m.dst_port)
    lo, hi = (a, b) if a <= b else (b, a)
    return (m.protocol, lo, hi)


# ---------------------------------------------------------------------------
# Flow
# ---------------------------------------------------------------------------
class Flow:
    def __init__(self, first: PacketMeta):
        # Direction is fixed by the first packet: fwd = src->dst of that packet.
        self.src_ip, self.src_port = first.src_ip, first.src_port
        self.protocol = first.protocol

        self.start_us = first.ts_us
        self.last_us = first.ts_us

        self.fwd_count = 0
        self.bwd_count = 0
        self.fwd_bytes = 0
        self.bwd_bytes = 0

        self.fwd_pkt = Stat()
        self.bwd_pkt = Stat()
        self.flow_len = Stat()

        self.flow_iat = Stat()
        self.fwd_iat = Stat()
        self.bwd_iat = Stat()
        self._last_seen = None
        self._last_fwd = None
        self._last_bwd = None

        self.flag_total = {"FIN": 0, "SYN": 0, "RST": 0, "PSH": 0,
                           "ACK": 0, "URG": 0, "CWR": 0, "ECE": 0}

        self.init_fwd_win = INIT_WIN_DEFAULT
        self.init_bwd_win = INIT_WIN_DEFAULT
        self._seen_fwd = False
        self._seen_bwd = False

        self.min_seg_fwd: Optional[int] = None
        self.act_data_fwd = 0

        # Active/Idle
        self.start_active = first.ts_us
        self.end_active = first.ts_us
        self.active = Stat()
        self.idle = Stat()

        # Termination bookkeeping
        self.fwd_fin = 0
        self.bwd_fin = 0
        self.rst_seen = False

        self._add_directionless(first, is_first=True)
        self._add_directional(first)

    def is_forward(self, m: PacketMeta) -> bool:
        return m.src_ip == self.src_ip and m.src_port == self.src_port

    # --- update ------------------------------------------------------------
    def _update_active_idle(self, ts: int) -> None:
        if (ts - self.end_active) > ACTIVITY_TIMEOUT_US:
            if (self.end_active - self.start_active) > 0:
                self.active.add(self.end_active - self.start_active)
            self.idle.add(ts - self.end_active)
            self.start_active = ts
            self.end_active = ts
        else:
            self.end_active = ts

    def _add_directionless(self, m: PacketMeta, is_first: bool = False) -> None:
        self.last_us = m.ts_us
        self.flow_len.add(m.payload_len)
        if self._last_seen is not None:
            self.flow_iat.add(m.ts_us - self._last_seen)
        self._last_seen = m.ts_us
        if not is_first:
            self._update_active_idle(m.ts_us)
        # flag counts (per-packet, whole flow)
        f = m.flags
        if f & FIN: self.flag_total["FIN"] += 1
        if f & SYN: self.flag_total["SYN"] += 1
        if f & RST: self.flag_total["RST"] += 1
        if f & PSH: self.flag_total["PSH"] += 1
        if f & ACK: self.flag_total["ACK"] += 1
        if f & URG: self.flag_total["URG"] += 1
        if f & CWR: self.flag_total["CWR"] += 1
        if f & ECE: self.flag_total["ECE"] += 1
        # termination bookkeeping
        if f & RST:
            self.rst_seen = True

    def _add_directional(self, m: PacketMeta) -> None:
        fwd = self.is_forward(m)
        if m.flags & FIN:
            if fwd: self.fwd_fin += 1
            else:   self.bwd_fin += 1
        if fwd:
            self.fwd_count += 1
            self.fwd_bytes += m.payload_len
            self.fwd_pkt.add(m.payload_len)
            if m.payload_len >= 1:
                self.act_data_fwd += 1
            self.min_seg_fwd = (m.header_len if self.min_seg_fwd is None
                                else min(self.min_seg_fwd, m.header_len))
            if not self._seen_fwd:
                self.init_fwd_win = m.window
                self._seen_fwd = True
            if self._last_fwd is not None:
                self.fwd_iat.add(m.ts_us - self._last_fwd)
            self._last_fwd = m.ts_us
        else:
            self.bwd_count += 1
            self.bwd_bytes += m.payload_len
            self.bwd_pkt.add(m.payload_len)
            if not self._seen_bwd:
                self.init_bwd_win = m.window
                self._seen_bwd = True
            if self._last_bwd is not None:
                self.bwd_iat.add(m.ts_us - self._last_bwd)
            self._last_bwd = m.ts_us

    def add(self, m: PacketMeta) -> None:
        self._add_directionless(m)
        self._add_directional(m)

    # --- termination -------------------------------------------------------
    def is_terminated(self) -> bool:
        if self.rst_seen:
            return True
        if self.fwd_fin > 0 and self.bwd_fin > 0:   # mutual FIN exchange
            return True
        return False

    def timed_out(self, ts_us: int) -> bool:
        return (ts_us - self.start_us) > FLOW_TIMEOUT_US

    # --- emit --------------------------------------------------------------
    # NOTE: the Engelen fork COMMENTS OUT endActiveIdleTime, so there is no final
    # active-burst add and no trailing-idle add at flow close. Active/Idle are
    # populated ONLY by intra-flow gaps > ACTIVITY_TIMEOUT_US during packet processing
    # (see _update_active_idle). Any flow without a >5s gap therefore has
    # Active == Idle == 0 across all eight features. There is intentionally no
    # finalize() step. (Sanity check: in X_test_sample.npy most rows should have
    # Active Mean == Idle Mean == 0.)
    def emit(self) -> Dict[str, float]:
        dur = self.last_us - self.start_us
        dur_s = dur / 1_000_000.0
        total_pkts = self.fwd_count + self.bwd_count

        def stat4(s: Stat):
            if s.n > 0:
                return s.get_max(), s.get_min(), s.get_mean(), s.get_std()
            return 0.0, 0.0, 0.0, 0.0

        fmax, fmin, fmean, fstd = stat4(self.fwd_pkt)
        bmax, bmin, bmean, bstd = stat4(self.bwd_pkt)

        # Flow IAT: always >=1 sample for emitted (>=2 pkt) flows.
        fiat_mean = self.flow_iat.get_mean() if self.flow_iat.n > 0 else 0.0
        fiat_std  = self.flow_iat.get_std()  if self.flow_iat.n > 0 else 0.0
        fiat_max  = self.flow_iat.get_max()  if self.flow_iat.n > 0 else 0.0
        fiat_min  = self.flow_iat.get_min()  if self.flow_iat.n > 0 else 0.0

        # Fwd/Bwd IAT only defined with >1 packet in that direction (else 0).
        if self.fwd_count > 1:
            fw_mean, fw_std, fw_min = self.fwd_iat.get_mean(), self.fwd_iat.get_std(), self.fwd_iat.get_min()
        else:
            fw_mean = fw_std = fw_min = 0.0
        if self.bwd_count > 1:
            bw_tot = self.bwd_iat.sum
            bw_mean, bw_std = self.bwd_iat.get_mean(), self.bwd_iat.get_std()
            bw_max, bw_min = self.bwd_iat.get_max(), self.bwd_iat.get_min()
        else:
            bw_tot = bw_mean = bw_std = bw_max = bw_min = 0.0

        if self.flow_len.n > 0:
            plmin, plmax, plmean, plstd = self.flow_len.get_min(), self.flow_len.get_max(), self.flow_len.get_mean(), self.flow_len.get_std()
            plvar = self.flow_len.get_var()
        else:
            plmin = plmax = plmean = plstd = plvar = 0.0

        act = (self.active.get_mean(), self.active.get_std(), self.active.get_max(), self.active.get_min()) \
            if self.active.n > 0 else (0.0, 0.0, 0.0, 0.0)
        idl = (self.idle.get_mean(), self.idle.get_std(), self.idle.get_max(), self.idle.get_min()) \
            if self.idle.n > 0 else (0.0, 0.0, 0.0, 0.0)

        down_up = (self.bwd_count / self.fwd_count) if self.fwd_count > 0 else 0.0  # Engelen: true division
        flow_bytes_s = (self.fwd_bytes + self.bwd_bytes) / dur_s if dur_s > 0 else 0.0
        flow_pkts_s = total_pkts / dur_s if dur_s > 0 else 0.0

        vals = [
            self.protocol, dur, self.fwd_count, self.bwd_count,
            self.fwd_bytes, self.bwd_bytes,
            fmax, fmin, fmean, fstd,
            bmax, bmin, bmean, bstd,
            flow_bytes_s, flow_pkts_s,
            fiat_mean, fiat_std, fiat_max, fiat_min,
            fw_mean, fw_std, fw_min,
            bw_tot, bw_mean, bw_std, bw_max, bw_min,
            self.fwd_count / dur_s if dur_s > 0 else 0.0,
            self.bwd_count / dur_s if dur_s > 0 else 0.0,
            plmin, plmax, plmean, plstd, plvar,
            # dataset stores these as 0/1 presence (binarized in dhoogla cleaning), NOT counts
            int(self.flag_total["FIN"] > 0), int(self.flag_total["SYN"] > 0), int(self.flag_total["RST"] > 0), int(self.flag_total["PSH"] > 0),
            int(self.flag_total["ACK"] > 0), int(self.flag_total["URG"] > 0), int(self.flag_total["CWR"] > 0), int(self.flag_total["ECE"] > 0),
            down_up, self.init_fwd_win, self.init_bwd_win,
            self.act_data_fwd, (self.min_seg_fwd if self.min_seg_fwd is not None else 0),
            act[0], act[1], act[2], act[3],
            idl[0], idl[1], idl[2], idl[3],
        ]
        return dict(zip(FEATURE_ORDER, vals))


# ---------------------------------------------------------------------------
# Flow manager — keying, direction, termination, emit callback
# ---------------------------------------------------------------------------
class FlowManager:
    def __init__(self, on_flow: Callable[[Dict[str, float]], None],
                 min_packets: int = MIN_PACKETS_TO_EMIT):
        self.flows: Dict[object, Flow] = {}
        self.on_flow = on_flow
        self.min_packets = min_packets

    def _close(self, key, flow: Flow) -> None:
        if (flow.fwd_count + flow.bwd_count) >= self.min_packets:
            dur = flow.last_us - flow.start_us
            if dur > 0:  # drop degenerate zero-duration flows (would yield inf rates; cleaned out of dataset)
                self.on_flow(flow.emit())
        self.flows.pop(key, None)

    def add_packet(self, m: PacketMeta) -> None:
        key = flow_key(m)
        flow = self.flows.get(key)
        if flow is None:
            self.flows[key] = Flow(m)
            return
        if flow.timed_out(m.ts_us):          # 120s timeout -> close old, start new
            self._close(key, flow)
            self.flows[key] = Flow(m)
            return
        flow.add(m)
        if flow.is_terminated():             # mutual FIN or RST
            self._close(key, flow)

    def flush(self) -> None:
        for key in list(self.flows.keys()):
            self._close(key, self.flows[key])

    def sweep(self, now_us: int) -> None:
        """Live-operation helper: emit and drop flows whose age exceeds the flow timeout.

        In batch (pcap) mode flush() handles end-of-input. A live sensor has no end, so
        flows that go silent (UDP, or TCP without a clean mutual FIN) would otherwise sit
        unemitted until their *next* packet trips the timeout in add_packet. Call this
        periodically with a monotonic clock (time.monotonic_ns()//1000), which shares the
        CLOCK_MONOTONIC base with the kernel's bpf_ktime_get_ns() packet timestamps.
        """
        for key in list(self.flows.keys()):
            if (now_us - self.flows[key].start_us) > FLOW_TIMEOUT_US:
                self._close(key, self.flows[key])


# ---------------------------------------------------------------------------
# pcap front-end (validation source; later swapped for the eBPF ring buffer)
# ---------------------------------------------------------------------------
def run_pcap(path: str, on_flow: Callable[[Dict[str, float]], None]) -> int:
    import dpkt
    mgr = FlowManager(on_flow)
    count = 0
    with open(path, "rb") as fh:
        try:
            pcap = dpkt.pcap.Reader(fh)
        except ValueError:
            fh.seek(0)
            pcap = dpkt.pcapng.Reader(fh)
        for ts, buf in pcap:
            try:
                eth = dpkt.ethernet.Ethernet(buf)
            except Exception:
                continue
            ip = eth.data
            if not isinstance(ip, dpkt.ip.IP):
                continue
            ihl = ip.hl * 4
            l4 = ip.data
            if isinstance(l4, dpkt.tcp.TCP):
                proto, hdr, win, flags = 6, l4.off * 4, l4.win, l4.flags
            elif isinstance(l4, dpkt.udp.UDP):
                proto, hdr, win, flags = 17, 8, -1, 0   # UDP has no window -> -1
            else:
                continue
            payload = max(0, ip.len - ihl - hdr)
            mgr.add_packet(PacketMeta(
                ts_us=int(round(ts * 1_000_000)),
                src_ip=ip.src, dst_ip=ip.dst,
                src_port=l4.sport, dst_port=l4.dport,
                protocol=proto, payload_len=payload, header_len=hdr,
                window=win, flags=flags,
            ))
            count += 1
    mgr.flush()
    return count


if __name__ == "__main__":
    import sys, json
    if len(sys.argv) != 2:
        print("usage: python flow_features.py <capture.pcap>")
        sys.exit(1)
    flows = []
    n = run_pcap(sys.argv[1], flows.append)
    print(f"packets read: {n}   flows emitted: {len(flows)}")
    if flows:
        print(json.dumps(flows[0], indent=2))
