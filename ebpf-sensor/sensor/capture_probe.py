#!/usr/bin/env python3
"""
capture_probe.py — stage-3a plumbing test for the eBPF sensor.

Goal: prove the eBPF toolchain works on THIS machine before building the real
per-packet extractor. It attaches a socket-filter program to one interface,
extracts the 5-tuple of every IPv4 TCP/UDP packet in the kernel, pushes it through
a BPF ring buffer, and prints it in userspace.

This is NOT the real sensor. It captures no payload/length/flags/timing yet — only
enough to confirm: program compiles, attaches, sees both directions, and the
ring-buffer transport delivers records. Once this prints a live stream of flows,
stage 3b swaps this body for the full PacketMeta extractor feeding FlowManager.

Run (needs root; uses SYSTEM python, which has bcc — not the venv):
    sudo /usr/bin/python3 sensor/capture_probe.py wlp1s0
"""
import sys
import socket
import struct
from bcc import BPF

BPF_TEXT = r"""
#include <bcc/proto.h>

struct pkt_t {
    u32 src_ip;
    u32 dst_ip;
    u16 src_port;
    u16 dst_port;
    u8  protocol;
};

BPF_RINGBUF_OUTPUT(events, 8);   // 8 pages

int capture(struct __sk_buff *skb) {
    u8 *cursor = 0;

    struct ethernet_t *eth = cursor_advance(cursor, sizeof(*eth));
    if (eth->type != 0x0800)        // IPv4 only for now
        return 0;

    struct ip_t *ip = cursor_advance(cursor, sizeof(*ip));

    struct pkt_t pkt = {};
    pkt.src_ip   = ip->src;         // bcc/proto.h returns host byte order
    pkt.dst_ip   = ip->dst;
    pkt.protocol = ip->nextp;

    // NOTE: assumes no IP options (hlen == 5). The real extractor will honor ip->hlen.
    if (ip->nextp == 6) {           // TCP
        struct tcp_t *tcp = cursor_advance(cursor, sizeof(*tcp));
        pkt.src_port = tcp->src_port;
        pkt.dst_port = tcp->dst_port;
    } else if (ip->nextp == 17) {   // UDP
        struct udp_t *udp = cursor_advance(cursor, sizeof(*udp));
        pkt.src_port = udp->sport;
        pkt.dst_port = udp->dport;
    } else {
        return 0;
    }

    events.ringbuf_output(&pkt, sizeof(pkt), 0);
    return 0;                        // passive sniff; real traffic is unaffected
}
"""

PROTO = {6: "TCP", 17: "UDP"}


def fmt_ip(host_order_u32: int) -> str:
    # bcc/proto.h hands back host byte order; pack big-endian to get dotted quad.
    # If addresses print byte-reversed, change ">I" to "<I".
    return socket.inet_ntoa(struct.pack(">I", host_order_u32 & 0xFFFFFFFF))


def main(iface: str) -> None:
    b = BPF(text=BPF_TEXT)
    fn = b.load_func("capture", BPF.SOCKET_FILTER)
    BPF.attach_raw_socket(fn, iface)

    count = {"n": 0}

    def on_event(ctx, data, size):
        e = b["events"].event(data)
        count["n"] += 1
        print(f"{PROTO.get(e.protocol, e.protocol):3}  "
              f"{fmt_ip(e.src_ip)}:{e.src_port:<5}  ->  "
              f"{fmt_ip(e.dst_ip)}:{e.dst_port}")

    b["events"].open_ring_buffer(on_event)
    print(f"capturing on {iface} ... generate some traffic (curl / ping). Ctrl-C to stop.\n")
    try:
        while True:
            b.ring_buffer_poll(timeout=100)
    except KeyboardInterrupt:
        print(f"\nstopped. {count['n']} packets seen.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: sudo /usr/bin/python3 sensor/capture_probe.py <interface>")
        print("  (find yours with:  ip route get 8.8.8.8 | grep -oP 'dev \\K\\S+')")
        sys.exit(1)
    main(sys.argv[1])
