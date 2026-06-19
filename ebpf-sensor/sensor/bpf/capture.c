// capture.c — eBPF socket-filter that extracts per-packet metadata for the AI-IDS sensor.
//
// Attached via BCC attach_raw_socket() to one interface (AF_PACKET vantage point — the
// same one tcpdump uses, which is what the aggregator was validated against). For every
// IPv4 TCP/UDP packet it emits a fixed record through a ring buffer; userspace (loader.py)
// turns each record into a PacketMeta and feeds the validated FlowManager.
//
// Field names are from bcc/proto.h v0.30.0 (hlen, tlen, nextp, offset, rcv_wnd, length).

#include <bcc/proto.h>

struct pkt_t {
    u64 ts_us;        // kernel monotonic time, microseconds
    u32 src_ip;       // host byte order (proto.h convention)
    u32 dst_ip;
    s32 window;       // TCP rcv_wnd; -1 for UDP (no window)
    u16 src_port;
    u16 dst_port;
    u16 payload_len;  // L4 payload bytes = ip.tlen - ip_hdr - l4_hdr
    u16 header_len;   // L4 header bytes (TCP offset*4, or 8 for UDP)
    u8  protocol;     // 6 TCP, 17 UDP
    u8  flags;        // FIN=1 SYN=2 RST=4 PSH=8 ACK=16 URG=32 ECE=64 CWR=128
};

BPF_RINGBUF_OUTPUT(events, 16);   // 16 pages

int capture(struct __sk_buff *skb) {
    u8 *cursor = 0;

    struct ethernet_t *eth = cursor_advance(cursor, sizeof(*eth));
    if (eth->type != 0x0800)          // IPv4 only
        return 0;

    struct ip_t *ip = cursor_advance(cursor, sizeof(*ip));
    if (ip->hlen != 5)                // skip IP-options packets (rare); keeps L4 offset fixed at 20
        return 0;

    u32 ihl  = ip->hlen * 4;          // 20
    u32 tlen = ip->tlen;              // IP total length

    struct pkt_t pkt = {};
    pkt.ts_us    = bpf_ktime_get_ns() / 1000;
    pkt.src_ip   = ip->src;
    pkt.dst_ip   = ip->dst;
    pkt.protocol = ip->nextp;

    if (ip->nextp == 6) {             // TCP
        struct tcp_t *tcp = cursor_advance(cursor, sizeof(*tcp));
        pkt.src_port  = tcp->src_port;
        pkt.dst_port  = tcp->dst_port;
        u32 thl       = tcp->offset * 4;
        pkt.header_len = thl;
        pkt.window     = tcp->rcv_wnd;
        int pl = (int)tlen - (int)ihl - (int)thl;
        pkt.payload_len = pl > 0 ? pl : 0;
        u8 f = 0;
        f |= tcp->flag_fin << 0;
        f |= tcp->flag_syn << 1;
        f |= tcp->flag_rst << 2;
        f |= tcp->flag_psh << 3;
        f |= tcp->flag_ack << 4;
        f |= tcp->flag_urg << 5;
        f |= tcp->flag_ece << 6;
        f |= tcp->flag_cwr << 7;
        pkt.flags = f;
    } else if (ip->nextp == 17) {     // UDP
        struct udp_t *udp = cursor_advance(cursor, sizeof(*udp));
        pkt.src_port   = udp->sport;
        pkt.dst_port   = udp->dport;
        pkt.header_len = 8;
        pkt.window     = -1;
        int pl = (int)tlen - (int)ihl - 8;
        pkt.payload_len = pl > 0 ? pl : 0;
        pkt.flags = 0;
    } else {
        return 0;
    }

    events.ringbuf_output(&pkt, sizeof(pkt), 0);
    return 0;                         // passive sniff; real traffic is unaffected
}
