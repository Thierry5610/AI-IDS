# Beehive AI-IDS: Frontend + Traffic Harness Handoff

Resume-work context for two completed workstreams: the React dashboard (all 7 pages)
and the benign traffic capture harness. Engineering notes, locations, gotchas, and next
steps. No em dashes by convention.

This complements the existing backend handoffs in `docs/architecture/`
(`INFERENCE_SERVICE_HANDOFF.md`, `SENSOR_HANDOFF.md`, `ALERTING_HANDOFF.md`) and the
locked context in `CLAUDE.md` + `docs/context/project-decisions.md`.

---

## 0. Environment gotchas (read first, these will bite)

- **Repo path moved.** The project lives on an external NTFS drive that auto-mounts with
  a numeric suffix. It was `/media/thierry/TempStorage/AI-IDS`, then remounted as
  `/media/thierry/TempStorage1/AI-IDS`. After any reboot, confirm the real path before
  running anything:
  ```bash
  for p in /media/thierry/TempStorage*/AI-IDS; do echo "$p:"; git -C "$p" rev-parse --is-inside-work-tree 2>/dev/null && echo "  (git repo)"; done
  ```
  Use whichever path is a git repo. Everything below uses `<repo>` for that path.
- **NTFS exec bits are unreliable.** Invoke shell scripts as `bash path/script.sh` rather
  than `./script.sh`. The generators are already called via `bash` from `simulate.sh`.
- **No passwordless sudo** in some shells. `tcpdump` and host `ethtool` need sudo; the
  sudo-less capture path (containerized tcpdump) exists for that reason (see Harness).
- **Docker can get wedged.** After the remount, `docker stop/kill/rm` returned
  `permission denied` from the daemon even with sudo, although the container processes
  were normal (state `Ss`, not frozen or paused). A reboot clears it. If you do not want
  to reboot: `sudo kill -9 $(docker inspect -f '{{.State.Pid}}' <names>)` then
  `docker compose down -v`.

---

## 1. Git state

- Branch `main`. As of this handoff, **ahead of `origin/main` by 3 commits** (push them):
  - `0ebc4cc` frontend: single-scroll shell, topology node sizing + force declutter, nav icons
  - `2834f98` traffic-harness: benign capture fleet + pcap-to-features pipeline
  - `ace75b1` traffic-harness: disable offload inside container netns too (capture fidelity)
  All earlier dashboard commits are already on origin.
- All commits are authored as the repo owner. No AI co-author trailers anywhere (history
  was cleaned), and no AI references in tracked files.
- **Intentionally NOT committed / tracked:**
  - `frontend/vite.config.js` has a local-only change (honor a `PORT` env var for the
    preview tool). Leave it uncommitted unless you want it.
  - `.claude/` is gitignored (local tooling).
  - `CLAUDE.md` and `docs/` are untracked by choice.
  - `traffic-harness/data/` is gitignored (pcaps and matrices never committed).

To push: `cd <repo> && git push origin main` (run from your own terminal; CI/sandbox has
no git credentials).

---

## 2. Frontend dashboard (frontend/)

### Status: all 7 pages built and verified

Overview (pre-existing) plus Alerts, Topology, Models, Flows, Research, Settings. 1:1 with
the rail nav.

### Stack
React 18, Vite 5, React Router 6, Zustand. Plain CSS (no Tailwind). Design tokens in
`src/styles/tokens.css`, shared shell/components in `src/styles/shell.css`, base in
`src/styles/globals.css`, plus per-component CSS files next to their components.

### Data flow (live)
- `src/providers/LiveDataProvider.jsx` opens two SSE streams once at app root via
  `src/lib/stream.js` (exponential-backoff reconnect):
  `/stream/attacks` (event `attack`) and `/stream/anomalies` (event `anomaly`).
- Vite dev proxy (`vite.config.js`): `/stream/*` to the bridge on `localhost:8001`,
  `/api/*` to the inference service on `localhost:8000` (prefix stripped).
- Stores: `src/store/alertStore.js` (200-item ring, newest first) and
  `src/store/anomalyStore.js` (500-item ring). Every page reads these; no per-page stream
  setup. The bridge replays stream history from id `0` on connect, so a fresh page load
  repopulates from Redis.

### Alert payload shape (what the UI consumes)
Each store item is the full `/predict` response enriched with `identity`. Key fields:
`prediction {label, label_index, confidence}`, `identity {src_ip, src_port, dst_ip,
dst_port, protocol}`, `source_model`, `is_attack`, `model_votes` (4 supervised
`{label,label_index,confidence}` + `autoencoder {anomaly_score, threshold, is_anomalous}`),
`agreement {consensus, agreeing, total}`, `explanation {top_features:[{feature, value,
shap_value, direction}]}` (may be null), `timestamp`, `flow_id`. Full contract in
`docs/architecture/INFERENCE_SERVICE_HANDOFF.md`.

### Page map (src/pages and their components)
- **Overview.jsx**: KPI row, live alert feed (`components/alerts/AlertLogStream.jsx`),
  ensemble gauge (`components/charts/EnsembleGauge.jsx`), radar
  (`components/charts/RadarChart.jsx`), bubble cluster, detection trend
  (`components/charts/TrendChart.jsx`, time-windowed to the last 60 minutes), status strip.
- **Alerts.jsx** + `components/alerts/AlertsTable.{jsx,css}`: filterable attack table,
  severity pills, verdict/consensus, inline top-SHAP chip with expandable per-row detail
  (full top_features + model votes), text search, live-page-1 / freeze pagination.
- **Topology.jsx** + `components/topology/TopologyGraph.{jsx,css}`,
  `lib/topology.js`, `constants/hosts.js`: passive typed graph via `react-force-graph-2d`
  (added dependency). Nodes are hosts (type inferred from observed dst ports), edges are
  src to dst flows. 2-way toggle Attacks/Anomalies, curved edges with a soft glow pulse,
  galaxy backdrop, node-detail side panel. Force tuning lives in a useEffect
  (`charge.strength(-180).distanceMax(220)`, `link.distance(60)`).
- **Models.jsx** + `components/models/{ModelCard,VoteMatrix}.jsx`, `lib/modelStats.js`:
  five-model comparison from live votes (win distribution, per-model cards, AE card,
  recent-decisions vote matrix). Live behavioral only, no fabricated metrics.
- **Flows.jsx** + `components/flows/FlowTape.{jsx,css}`, `lib/flows.js`: dense live tape
  merging both streams, class filter + search, danger vs warning kept visually distinct.
- **Research.jsx** + `components/research/ScoreHistogram.jsx`: frames the AE cross-dataset
  finding (the reported ~75% benign false-positive rate) plus a live AE score histogram vs
  the 0.0726 threshold and the supervised vs AE contrast.
- **Settings.jsx**: read-only config and live ingest status (threshold, model roster,
  streams/buffers, pipeline).

### Design and motion
- VIGIL dark theme: true-black base, single lime accent, hairline borders. Tokens in
  `tokens.css` including the motion easing tokens (`--ease-out`, `--ease-in-out`,
  `--ease-drawer`).
- Micro-interaction pass (Emil-Kowalski standards): press feedback (`scale(0.97)`,
  140ms) on buttons/pills/rail/toggle, a subtle one-time per-page card entrance
  (`bee-rise`), reduced-motion honored. All transform/opacity only, sub-300ms.
- Two deliberate, owner-approved deviations from the otherwise-flat rule, both scoped to
  Topology: the edge glow pulse and the galaxy backdrop. Documented in code so they are
  not "flattened" back. Card `backdrop-filter` blur was kept by choice.

### Scroll model (do not regress)
Single scroll container. `globals.css` sets `html, body { height:100%; overflow:hidden }`
and `#root { height:100% }`; `shell.css` sets `.app { height:100% }` and
`.main { height:100%; overflow-y:auto }`. The `#root { height:100% }` rule is essential:
without it the height chain breaks and the page cannot scroll at all. `background-attachment:
fixed` was removed (it repainted the gradient on every scroll frame). The `html { zoom:1.25 }`
scale is intentional.

### How to run the dashboard
```bash
# Redis (used by the bridge; restart-persistent)
docker run -d --name ids-redis --restart unless-stopped -p 6379:6379 redis:7-alpine  # if not already running
# Bridge (SSE fan-out), its own venv, port 8001
cd <repo>/bridge && .venv/bin/uvicorn main:app --port 8001 --host 127.0.0.1
# Frontend dev server, port 5173
cd <repo>/frontend && npm run dev
# Inference service (optional; only needed for /api routes, not for SSE)
cd <repo>/inference-service && .venv/bin/uvicorn app.main:app --port 8000
```
Open http://localhost:5173. The dashboard populates from whatever is in the two Redis
streams (the bridge replays history on connect).

### Seeding synthetic data (for demos/screenshots)
The supervised models stay silent on benign live traffic (the transfer-failure finding),
so to make the dashboard look live, publish synthetic events to Redis with current
timestamps and full `model_votes` (the ensemble gauge reads the latest alert's votes, so
omitting them leaves it idle). Spread attack timestamps across the last 60 minutes so the
Detection Trend shows a curve. Use any redis client to `XADD ids:attacks * data '<json>'`
matching the payload shape above; `XADD ids:anomalies * data '<json>'` for anomalies.

---

## 3. Traffic capture harness (traffic-harness/)

### Purpose
Build a local benign baseline to retrain the AE on this network's "normal" (the AE
currently flags ~75% of local benign traffic because its baseline is CICIDS2017, a
different domain). This task produces the dataset only; it does not retrain the AE and
does not modify the frozen backend.

### Status: built, run end to end, validated
Deliverable produced: `traffic-harness/data/X_benign_local.npy`, shape **(10219, 56)**,
float32, benign only. 10,219 flows across the 5 canonical ports (22, 53, 80, 443, 3306).
Validation passed: packet length max 1448 (wire-sized), no NaN/inf, Init Win shows -1,
features in the dataset magnitude band.

### Layout
```
traffic-harness/
  docker-compose.yml         # 6 services on bridge network ids-net (pinned tags)
  services/web|db|ssh|dns|client/   # Dockerfiles, nginx conf, init.sql, dnsmasq.conf
  generators/                # gen_web/ssh/db/dns.sh + simulate.sh orchestrator
  capture/                   # find_bridge.sh, capture.sh (sudo), capture_docker.sh (sudo-less), to_features.sh
  tools/dump_features.py     # pcap -> 56-feature matrix via the frozen sensor (read-only)
  data/                      # gitignored: pcaps + matrices land here
  README.md
```

### The fleet (6 containers on ids-net)
- `web` nginx (80, 443 self-signed; 1KB/50KB/2MB assets), `db` mariadb (3306, seeded
  `labdb.events`, labuser/labpass), `ssh` openssh (22, labuser/labpass), `dns` dnsmasq
  (53 udp). These are passive targets.
- `client` and `attacker`: tools boxes that run the generators. In this phase the attacker
  runs the SAME benign generators (its normal behavior must be in the baseline). Nothing
  malicious in this harness.

### How to run a capture
```bash
cd <repo>/traffic-harness
docker compose up -d --build                 # fleet on ids-net
docker compose ps                            # wait for db healthy
# Capture (two options). 900 = seconds; pick a duration that yields >=5000 flows.
bash capture/capture.sh 900 &                # host tcpdump, needs sudo
#   or, when sudo is unavailable:
bash capture/capture_docker.sh 900 benign.pcap &   # containerized tcpdump
# Drive benign traffic from BOTH boxes for the same duration
docker compose exec -T client   bash /gen/simulate.sh 900 &
docker compose exec -T attacker bash /gen/simulate.sh 900 &
wait
# pcap -> matrix, then validate
bash capture/to_features.sh data/<your>.pcap
( cd ../ebpf-sensor && .venv/bin/python validate_sensor.py "$(pwd)/../traffic-harness/data/<your>.pcap" )
docker compose down -v                       # teardown
```

### Critical fidelity gotcha: NIC offload (already fixed in the scripts)
Capturing container traffic on a virtual bridge with segmentation/receive offload on
(TSO, GSO, GRO) makes tcpdump record 64 KB super-segments instead of wire-sized frames.
That inflates packet-length and byte-rate features badly (packet length max ~65160 instead
of ~1500, Flow Bytes/s ~1.2 billion). Offload must be disabled in THREE places: the bridge,
its host-side veths, AND each container eth0 (TCP segmentation happens at the sender eth0,
not the veth peer). Both capture scripts now do all three (host side via sudo ethtool or a
host-net NET_ADMIN container; container side via a container-netns NET_ADMIN helper, since
the service images do not ship ethtool). After a capture, confirm with validate_sensor that
packet length max is at or below ~1500.

### Known, expected residual
`Flow Bytes/s` runs higher than CICIDS2017 (mean ~12.7M vs ~326k) because the containerized
fleet transfers at loopback speed, so flows complete faster than on a real WAN. This is a
genuine property of the local lab, not a unit or definition bug, and it is the "normal" the
AE should learn for this environment. Not a blocker.

### How the matrix is built (frozen sensor consumed read-only)
`tools/dump_features.py` imports `run_pcap` and `FEATURE_ORDER` from
`ebpf-sensor/sensor/flow_features.py` (frozen) and collects every emitted flow into a
matrix in training feature order. It runs under `ebpf-sensor/.venv` (dpkt, numpy, pandas)
with the sensor on PYTHONPATH. `to_features.sh` wires this up.

---

## 4. Deliverables and locations

| Item | Path | Notes |
|---|---|---|
| Benign baseline matrix | `<repo>/traffic-harness/data/X_benign_local.npy` (+ `.csv`) | (10219, 56) float32. **Gitignored, local only. BACK IT UP.** |
| Harness source | `<repo>/traffic-harness/` | committed |
| Dashboard | `<repo>/frontend/` | committed |

The matrix is not in git (data/ is ignored) and is not on GitHub. Copy it somewhere safe,
for example `cp <repo>/traffic-harness/data/X_benign_local.npy ~/X_benign_local.npy`.

---

## 5. Next steps

1. **Reboot if Docker is wedged**, then `cd <repo>/traffic-harness && docker compose down -v`
   to remove the fleet cleanly.
2. **Push** the 3 local commits: `cd <repo> && git push origin main`.
3. **Back up** `X_benign_local.npy` (it is local only).
4. **AE recalibration (separate task, not started).** Consume `X_benign_local.npy` to:
   - refit the AE `StandardScaler` on these benign rows (replaces `ae_scaler.pkl` for the
     local-baseline variant),
   - retrain or recalibrate the AE on this local normal,
   - recompute the anomaly threshold from this benign reconstruction-error distribution
     (95th to 99th percentile). Do not reuse 0.0726, that value belongs to CICIDS2017.
   `ebpf-sensor/calibrate_threshold.py` is a likely starting point. Keep the original
   frozen artifacts intact; produce new local-baseline artifacts alongside. Note: the
   original ~75% cross-dataset finding stays reported as the dissertation headline; this
   local baseline is a deployment-time improvement, not a replacement of that result.

---

## 6. Locked decisions and constraints (do not relitigate)

- **Backend frozen at `c02552c`** (`inference-service/`, `ebpf-sensor/sensor/`). Consume as
  read-only tools; never edit.
- **danger vs warning are distinct and never merged.** danger = supervised `is_attack`
  (stream `ids:attacks`, pages Telegram). warning = AE `is_anomalous` (stream
  `ids:anomalies`, dashboard/research only, never pages).
- **AE threshold 0.0726 is fixed for the original system.** The ~75% cross-dataset benign
  false-positive rate is the reported headline finding, not a defect.
- **Design system:** VIGIL dark, single lime accent, near-square radius, hairline borders.
  The two Topology motion deviations (glow pulse, galaxy) are deliberate and approved.
- **No fabricated numbers** anywhere in the UI (dissertation integrity). Live-derived or
  documented-as-reported only.
