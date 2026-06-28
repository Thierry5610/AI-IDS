#!/usr/bin/env python3
"""Async TCP connect-scanner (portscan training tool, distinct from nmap).

A pure-python asyncio connect scan: it opens a real TCP connection to each port and
immediately closes it. Against responsive fleet hosts every probe completes a handshake
(open port) or gets a SYN+RST (closed port), so every probe is a >=2 packet flow that
reaches the classifier, exactly like the nmap -sT path but from a different tool with a
different timing/concurrency fingerprint (diversity for the held-out-tool split).

Randomizes the port set and concurrency per run so repeated windows are not identical.
Prints TOOL / START_EPOCH / END_EPOCH like the other attack scripts. No em dashes.

Usage: pyscan.py --target <ip> [--ports N] [--concurrency N] [--timeout S] [--seed N]
"""
import argparse
import asyncio
import random
import time


async def probe(ip, port, timeout, sem):
    async with sem:
        try:
            fut = asyncio.open_connection(ip, port)
            reader, writer = await asyncio.wait_for(fut, timeout=timeout)
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            return True
        except Exception:
            return False


async def run(ip, ports, concurrency, timeout):
    sem = asyncio.Semaphore(concurrency)
    tasks = [probe(ip, p, timeout, sem) for p in ports]
    results = await asyncio.gather(*tasks)
    return sum(1 for r in results if r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--ports", type=int, default=2000,
                    help="how many distinct ports to probe")
    ap.add_argument("--concurrency", type=int, default=0,
                    help="0 = pick a random value per run")
    ap.add_argument("--timeout", type=float, default=1.0)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--range", default="1-10000",
                    help="port universe lo-hi to sample from")
    args = ap.parse_args()

    seed = args.seed or int(time.time())
    rnd = random.Random(seed)
    lo, hi = (int(x) for x in args.range.split("-"))
    universe = list(range(lo, hi + 1))
    n = min(args.ports, len(universe))
    ports = rnd.sample(universe, n)
    # always include the live service ports so some probes complete a full handshake
    for p in (22, 80, 3306, 53):
        if p not in ports:
            ports.append(p)
    rnd.shuffle(ports)
    concurrency = args.concurrency or rnd.choice([100, 200, 400, 800])

    print(f"TOOL pyscan target={args.target} ports={len(ports)} "
          f"concurrency={concurrency} timeout={args.timeout} seed={seed} range={args.range}")
    print(f"START_EPOCH {int(time.time())}")
    opened = asyncio.run(run(args.target, ports, concurrency, args.timeout))
    print(f"pyscan: {opened} open of {len(ports)} probed")
    print(f"END_EPOCH {int(time.time())}")


if __name__ == "__main__":
    main()
