# AI-IDS — Stage 4b (Alerting): Resume-Work Handoff

Purpose: enough context to resume in a fresh chat (next up: the React dashboard /
frontend). Engineering notes only, not defense prose. Companion to
`SENSOR_HANDOFF.md` and `INFERENCE_SERVICE_HANDOFF.md` (the upstream contract docs).

---

## Status

Stage 4b is **built, tested end-to-end, and committed**. Three steps, in order:

1. **Flow-identity refactor** — the forward 5-tuple now rides the alert path.
2. **Redis Streams fan-out** — isolated producer, two streams per the locked split.
3. **Telegram notifier** — standalone consumer of the supervised pager stream.

Full chain proven live: sensor flow → `/predict` → `publisher.publish_*` →
`ids:attacks` / `ids:anomalies` → notifier consumer group → Telegram message
(rendered with SHAP top factor + src→dst). A real Telegram alert was received.

Commits on `main` (ahead of `origin/main` until pushed):
- `e023295` — thread forward flow identity through flow_features → emitter; flow_id on /predict
- `ce684f1` — Redis Streams fan-out via isolated publisher.py; service untouched
- `b82603e` — pin redis in requirements
- (+ the notifier commit: `alerting: Telegram notifier for ids:attacks ...`)

The inference service was **not touched** in 4b (the `NOTE (step 4)` publish hook in
`app/main.py` is now moot — producer lives in the sensor, not the service — and is
left in place, unused).

---

## What changed / what's new

```
ebpf-sensor/sensor/
  flow_features.py   # +_ip_to_str(), Flow.identity(), 2-arg on_flow(feat, identity)
  emitter.py         # threads identity through submit→_post→_handle; _flow_id(); optional publisher
  loader.py          # constructs Publisher(), passes to emitter, reports redis state + pub stats
  publisher.py       # NEW — Redis Streams producer (isolated; no redis dep leaks into core)
notifier/
  telegram_notifier.py  # NEW — standalone consumer of ids:attacks -> Telegram (stdlib urllib)
  .env               # NEW, GITIGNORED — TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
ebpf-sensor/requirements.txt  # redis==8.0.0 now active (was a commented stale 5.2.1)
```

`emit()` and the 56-feature contract are byte-for-byte unchanged; `pytest` stays 7/7.
Identity is a **sibling** to the feature dict, never mixed into the 56 features.

---

## The alert/stream contract (what the dashboard consumes)

Two Redis Streams, fan-out by verdict (locked split):

| Stream         | Trigger                          | Pages? | Consumer(s)                    |
|----------------|----------------------------------|--------|--------------------------------|
| `ids:attacks`  | supervised `is_attack == true`   | YES    | Telegram notifier; dashboard   |
| `ids:anomalies`| autoencoder `is_anomalous == true` | NO   | dashboard / research view only |

Benign flows publish to neither stream.

**Message shape:** one Redis field, `data`, holding the JSON-encoded `/predict`
response enriched with `identity`:

```json
{ "data": "{ ...full /predict response..., \"identity\": {
    \"src_ip\": \"...\", \"src_port\": N, \"dst_ip\": \"...\", \"dst_port\": N, \"protocol\": 6
}}" }
```

`identity` is the **forward** 5-tuple (first-packet src→dst), not the canonical key.
`flow_id` (already in the response, echoed from the request) is
`"proto-src:sport-dst:dport"` — per-edge, greppable, not globally unique.

Streams are length-capped via `XADD ... MAXLEN ~ 10000` (approximate).

**Env (publisher, read by the sensor):**
`REDIS_URL` (`redis://127.0.0.1:6379/0`), `IDS_ATTACKS_STREAM` (`ids:attacks`),
`IDS_ANOMALIES_STREAM` (`ids:anomalies`), `IDS_STREAM_MAXLEN` (`10000`).

**Env (notifier):**
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` (required), `REDIS_URL`,
`IDS_ATTACKS_STREAM`, `IDS_NOTIFIER_GROUP` (`telegram`),
`IDS_NOTIFIER_CONSUMER` (hostname).

---

## How to run the alerting chain

```bash
# 0. Redis (Docker; survives reboots)
docker run -d --name ids-redis --restart unless-stopped -p 6379:6379 redis:7-alpine
docker exec ids-redis redis-cli ping            # -> PONG

# 1. inference service (venv)
cd inference-service && source .venv/bin/activate && uvicorn app.main:app --port 8000

# 2. Telegram notifier (venv; NO root/bcc needed)
cd notifier && set -a; source .env; set +a && python3 telegram_notifier.py

# 3. live sensor (SYSTEM python, root — bcc + redis both required there)
cd ebpf-sensor && sudo /usr/bin/python3 sensor/loader.py wlp1s0
```

Sensor startup prints `redis: -> ids:attacks (attacks) | ids:anomalies (anomalies)`
and the heartbeat gains `pub=Na/Nn skip=N puberr=N`.

**Exercising the pager:** supervised models stay silent on benign live traffic (the
transfer-failure finding), so `ids:attacks` rarely fires naturally. To prove the
pager, publish a synthetic attack while the notifier runs:

```bash
cd ebpf-sensor   # venv
python3 - <<'PY'
from sensor.publisher import Publisher
Publisher().publish_attack({
  "is_attack": True, "flow_id": "6-10.0.0.9:4444-10.0.0.1:22", "timestamp": "now",
  "prediction": {"label": "PortScan", "confidence": 0.97}, "source_model": "xgboost",
  "agreement": {"agreeing": 4, "total": 4},
  "explanation": {"top_features": [{"feature": "Flow Bytes/s", "direction": "increases"}]},
  "identity": {"src_ip":"10.0.0.9","src_port":4444,"dst_ip":"10.0.0.1","dst_port":22,"protocol":6}})
PY
```

`ids:anomalies` DOES fill on ordinary traffic (AE flags ~75% of local-benign — the
domain-shift finding). Inspect: `docker exec ids-redis redis-cli XLEN ids:anomalies`.

---

## Gotchas already solved (don't re-hit)

- **Forward orientation.** `flow_key()` canonicalizes (sorts endpoints) so both
  directions hash to one flow; reading src/dst off the key flips ~half of flows.
  `Flow.identity()` reads the **stored first-packet** src/dst instead. `Flow.__init__`
  now stores `dst_ip`/`dst_port` (it already stored forward `src`). Verified: the
  initiator stays src even when the responder sends more packets.
- **IP representation differs by front-end.** pcap (dpkt) → 4 packed **bytes**; eBPF
  (bcc/proto.h) → host-byte-order **u32 int**. `_ip_to_str()` handles both:
  `inet_ntoa(bytes)` or `inet_ntoa(struct.pack(">I", int))`. `">I"` confirmed correct
  (matches the working `capture_probe.fmt_ip`).
- **redis installed in BOTH interpreters.** `loader.py` runs as root system python
  (`sudo /usr/bin/python3`, where bcc lives) → `sudo /usr/bin/pip3 install --break-system-packages redis`.
  The notifier + smoke tests run in the venv → `pip install redis`. Same split as bcc.
- **Blocking-read crash (RESP3 + redis-py 8).** `XREADGROUP ... BLOCK 5000` on an idle
  stream raised `redis.TimeoutError` when the connection's `socket_timeout` ≤ block
  (Docker-forwarded connections set a finite one). Fix in the notifier:
  `socket_timeout = BLOCK_MS/1000 + 5` (server's idle reply wins the race) **and**
  `except redis.TimeoutError: continue` (idle is normal, not fatal). Reproduced and
  fixed against real redis-py 8.0.0.
- **requirements.txt stale.** `redis` was a commented `# redis==5.2.1`; made active as
  `redis==8.0.0` (matches what's installed) so clones/Docker actually install it.
- **Secrets.** `.env` is gitignored; load with `set -a; source .env; set +a`. Tokens
  never go in git or chat. (VS Code auto-runs the venv `activate` in new terminals via
  `python.terminal.activateEnvironment` — cosmetic noise, harmless.)

---

## Locked decisions (don't relitigate)

- **Producer = emitter-side** (`publisher.py`). Inference service stays frozen. The
  emitter routes the split off the response it already gets back (`is_attack`,
  `model_votes.autoencoder.is_anomalous`).
- **Split:** supervised `is_attack` → `ids:attacks` (pages); AE `is_anomalous` →
  `ids:anomalies` (research/dashboard only, **never pages**). AE threshold stays
  `0.0726`; report the ~75% local FP as the finding. Supervised retrain off the table.
- **Telegram via stdlib `urllib`** (raw Bot API POST). No `python-telegram-bot` — it's
  async + heavyweight for a one-way pager.
- **Notifier consumer semantics:** consumer group created at `$` (alerts already in the
  stream before first start are skipped); **ack on successful send only**; a failed send
  leaves the alert pending so a restart re-pages it (at-least-once, no silent drops).
- Redis Streams over Kafka.

---

## Deferred / not built (conscious gaps)

- **Auth: none anywhere.** `/predict` is open; no dashboard login. Deferred until AFTER
  the first frontend page is integrated end-to-end. Planned cheapest-sane version:
  a shared API token the sensor sends and the service checks, plus dashboard login.
  **Mandatory before any Azure/public deploy** — don't expose an open `/predict`.
- **In-app notifications: not built.** They are the dashboard's live alert feed — a
  THIRD consumer of the same two streams (a small FastAPI WebSocket/SSE bridge tailing
  Redis → browser). Same consumer pattern as the notifier, different sink.
- **No benign/"flows" stream.** Only the two alert streams exist. If the topology/Flows
  page needs all flows (not just alerts), that's a clean additive third stream later.
- **Topology — passive vs active.** PASSIVE typed nodes (infer host type from observed
  ports/IPs in the identity payload: `:25→mail`, `:3306→db`, `:443→web`) is IN scope
  for the dashboard. ACTIVE auto-provisioning (UI adds a node → a container is spawned
  and wired in) is **future work, after v1 ships end-to-end** — off-thesis (DevOps
  orchestration, not detection) and a scope explosion. Do not tailor code toward it.

---

## NEXT: React dashboard / frontend

The dashboard is the next component and consumes both streams.

- **Bridge service (new):** a small FastAPI app with a WebSocket or SSE endpoint that
  tails `ids:attacks` + `ids:anomalies` and pushes to the React client. Reuse the
  notifier's consumer-group pattern (fan to socket instead of Telegram). This is also
  what powers "in-app notifications."
- **Design direction (locked):** the **Matrix** skill from typeui.sh — dark-only
  `#0B0C14`, single green accent `#2DB58A`, Space Mono everywhere, near-square 2px
  radius, hairline borders, flat (NO glow/grain/shadow/glass/3D-tilt). Full tokens at
  `https://www.typeui.sh/design-skills/matrix`; application doc `ARGUS_FRONTEND_SKILL_matrix.md`.
  The superseded "cockpit" direction (emerald, Hanken Grotesk, grain, tilt) must not
  return.
- **Page plan:** Overview first, then Topology, Alerts, Flows, Models, Research/AE,
  Settings (~11 pages / 7 sections).
- **Featured element:** the concentric **ensemble consensus gauge** — one arc per model
  as nested rings; rings closing the circle = model agreement. Confirmed for the final
  product. The topology view is a pan/zoom canvas (three.js / real graph engine, not
  hand-rolled SVG).
- **Naming/logo:** insect-inspired direction. Note: the Telegram bot was named
  **BeeHive** (`BeeHiveIDSBot`) — a candidate project name has effectively surfaced;
  worth confirming alongside the first page build + logo exploration.

Open the frontend chat with this doc + `ARGUS_FRONTEND_SKILL_matrix.md` + the inference
service / sensor handoffs in project knowledge.
