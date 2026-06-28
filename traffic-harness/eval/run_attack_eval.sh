#!/usr/bin/env bash
# Instrument A: offline attack vote table.
#
# Per attack: disable NIC offload (bridge + veths + container eth0, sudo-less via
# netshoot NET_ADMIN containers, the capture_docker.sh pattern), capture an
# attacker-to-target scoped pcap on the ids-net bridge, fire ONE attack from a tooled
# attacker container, convert the pcap to the 56-feature matrix through the FROZEN
# sensor, POST every flow to /predict, and tabulate the full votes. Also runs one
# benign control window. Produces per-flow JSONL, summary.csv/md and a manifest.
#
# Fidelity: fleet containers idle (command: sleep infinity) so benign is naturally
# quiet during attack windows; we attack responsive hosts so flows complete (>=2 pkts);
# offload is disabled so tcpdump records wire-sized frames. No host sudo required.
# No em dashes anywhere.
set -euo pipefail

# ---- 0. context (derive repo dynamically; the drive remounts under a shifting path) ----
SELF="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$SELF" rev-parse --show-toplevel)"
TH="$REPO/traffic-harness"
SENSOR="$REPO/ebpf-sensor"
INFERENCE_URL="${INFERENCE_URL:-http://127.0.0.1:8000}"
# /predict is CPU-bound (5 models + SHAP per request, ~19 req/s, no client-side
# concurrency gain). Cap flows scored per window at MAX_FLOWS via uniform sampling so a
# pathological window (a -p- portscan emits ~65k near-identical probes) does not dominate
# the run. The full pcap and 56-feature matrix are still saved for every window.
MAX_FLOWS="${MAX_FLOWS:-3000}"
AE_THRESHOLD_EXPECT="0.379194"
SENSOR_COMMIT="c02552c"
NET="nicolaka/netshoot:v0.13"
ATTACK_IMAGE="ids-harness-attacker:1"
# Unique per run: a previously-wedged eval container (snap-docker can refuse to kill one
# left by a hard-killed run) must never block a fresh run on a name conflict.
EVAL_CTR="attacker-eval-$$"
STAMP="$(date +%Y%m%d_%H%M%S)"
# OUTDIR can be pointed at an existing dir to RESUME: windows whose .flows.jsonl already
# exist are skipped, so an aborted run can be finished without recapturing good windows.
OUTDIR="${OUTDIR:-$TH/eval/results/$STAMP}"
mkdir -p "$OUTDIR"
LOG="$OUTDIR/run.log"
exec > >(tee -a "$LOG") 2>&1

echo "=========================================="
echo "AI-IDS Attack Eval (Instrument A)  $STAMP"
echo "REPO=$REPO"
echo "OUTDIR=$OUTDIR"
echo "INFERENCE_URL=$INFERENCE_URL"
echo "=========================================="

# ---- 1. prereqs (tolerate empty / non-JSON, fail loud with the raw body) ----
echo "[prereq] inference /health ..."
health_body="$(curl -sS --max-time 10 "$INFERENCE_URL/health" || true)"
if [ -z "$health_body" ]; then
  echo "[prereq] FATAL: empty /health response. Is serve_local.py up on $INFERENCE_URL ?" >&2
  exit 1
fi
echo "  raw: $health_body"
echo "$health_body" | python3 -c 'import sys,json; r=json.load(sys.stdin); sys.exit(0 if r.get("status")=="ok" else 1)' \
  || { echo "[prereq] FATAL: /health status not ok" >&2; exit 1; }
echo "  health: ok"

echo "[prereq] AE threshold smoke /predict ..."
# Build a zero-vector request over the exact 56 feature names through the sensor.
smoke_json="$(PYTHONPATH="$SENSOR" "$SENSOR/.venv/bin/python" - <<'PY'
import json
from sensor.flow_features import FEATURE_ORDER
print(json.dumps({"features": {k: 0.0 for k in FEATURE_ORDER}, "flow_id": "smoke"}))
PY
)"
pred_body="$(printf '%s' "$smoke_json" | curl -sS --max-time 15 -H 'Content-Type: application/json' -d @- "$INFERENCE_URL/predict" || true)"
[ -n "$pred_body" ] || { echo "[prereq] FATAL: empty /predict response" >&2; exit 1; }
AE_THRESHOLD="$(echo "$pred_body" | python3 -c 'import sys,json; print(json.load(sys.stdin)["model_votes"]["autoencoder"]["threshold"])')"
echo "  AE threshold reported: $AE_THRESHOLD (expect ~$AE_THRESHOLD_EXPECT)"
# Numeric compare with tolerance: the service returns the full float (0.3791940212...),
# so an exact string match would false-alarm on the correct local baseline.
if ! awk -v a="$AE_THRESHOLD" -v b="$AE_THRESHOLD_EXPECT" 'BEGIN{exit !(a-b<1e-5 && b-a<1e-5)}'; then
  echo "[prereq] WARNING: AE threshold is not the local baseline ~$AE_THRESHOLD_EXPECT." >&2
  echo "[prereq] If this is ~0.0726 you are serving the ORIGINAL baseline, not serve_local.py." >&2
fi

echo "[prereq] attack image ..."
docker image inspect "$ATTACK_IMAGE" >/dev/null 2>&1 \
  || { echo "[prereq] FATAL: $ATTACK_IMAGE missing. Build it first." >&2; exit 1; }

echo "[prereq] fleet up (web, ssh, db) ..."
for c in web ssh db; do
  docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true \
    || { echo "[prereq] FATAL: container '$c' not running. docker compose up -d." >&2; exit 1; }
done
echo "[prereq] all checks passed."

# ---- 2. attacker container + identities ----
docker rm -f "$EVAL_CTR" >/dev/null 2>&1 || true
docker run -d --name "$EVAL_CTR" --network ids-net \
  -v "$TH/generators:/gen:ro" "$ATTACK_IMAGE" sleep infinity >/dev/null
ip_of() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"; }
ATTACKER_IP="$(ip_of "$EVAL_CTR")"
WEB_IP="$(ip_of web)"; SSH_IP="$(ip_of ssh)"; CLIENT_IP="$(ip_of client 2>/dev/null || true)"
echo "[ips] attacker=$ATTACKER_IP web=$WEB_IP ssh=$SSH_IP client=${CLIENT_IP:-none}"

# ---- 3. bridge + offload disable (sudo-less netshoot pattern) ----
BR="$("$TH/capture/find_bridge.sh")"
echo "[bridge] $BR"
echo "[offload] disabling tso/gso/gro on bridge + veths + container eth0 ..."
IFACES="$(printf '%s ' "$BR"; ip -o link | awk -v b="$BR" '$0 ~ ("master " b)' | awk -F': ' '{print $2}' | sed 's/@.*//' | tr '\n' ' ')"
docker run --rm --network host --cap-add NET_ADMIN -e IFACES="$IFACES" "$NET" \
  sh -c 'for ifc in $IFACES; do ethtool -K "$ifc" tso off gso off gro off 2>/dev/null || true; done' || true
for c in web ssh db dns client attacker "$EVAL_CTR"; do
  docker run --rm --net "container:$c" --cap-add NET_ADMIN "$NET" \
    ethtool -K eth0 tso off gso off gro off >/dev/null 2>&1 || true
done
echo "[offload] done."

# ---- capture + score one window ----
# args: <name> <bpf-filter> <duration-cap> <fire-command...>
TOOLS_JSON="$OUTDIR/tools.json"; echo "{}" > "$TOOLS_JSON"
MANIFEST_ATTACKS="$OUTDIR/.attacks.jsonl"; : > "$MANIFEST_ATTACKS"

run_window() {
  local name="$1" filt="$2" cap="$3"; shift 3
  local pcap="$OUTDIR/$name.pcap"
  echo; echo "=== WINDOW: $name (filter: $filt) ==="

  # Resume: if this window already produced flows in OUTDIR, skip it.
  if [ -s "$OUTDIR/$name.flows.jsonl" ]; then
    echo "[skip] $name already scored ($(grep -c . "$OUTDIR/$name.flows.jsonl") flows)"
    return 0
  fi

  # Unique capture-container name: snap-docker intermittently refuses to kill a host-net
  # NET_RAW tcpdump container, wedging the fixed name. A per-window name means a wedged
  # leftover never blocks the next window.
  local cap_ctr="evcap-$$-$name"
  docker rm -f "$cap_ctr" >/dev/null 2>&1 || true
  docker run -d --name "$cap_ctr" --network host --cap-add NET_RAW --cap-add NET_ADMIN \
    -v "$OUTDIR:/out" "$NET" \
    timeout "$cap" tcpdump -i "$BR" -w "/out/$name.pcap" -s 0 "$filt" >/dev/null
  sleep 1
  local t0; t0="$(date +%s)"
  echo "--- firing: $* ---"
  "$@" || true
  local t1; t1="$(date +%s)"
  sleep 3                                  # let flows finish before flush
  docker stop "$cap_ctr" >/dev/null 2>&1 || true
  docker rm -f "$cap_ctr" >/dev/null 2>&1 || true

  # pcap -> 56-feature matrix (+ identities) via the FROZEN sensor
  PYTHONPATH="$SENSOR" "$SENSOR/.venv/bin/python" \
    "$TH/eval/dump_attack_features.py" "$pcap" \
    "$OUTDIR/$name.X.npy" "$OUTDIR/$name.X.csv" "$OUTDIR/$name.ids.jsonl" || true

  if [ -s "$OUTDIR/$name.X.csv" ]; then
    python3 "$TH/eval/score_flows.py" --csv "$OUTDIR/$name.X.csv" \
      --identities "$OUTDIR/$name.ids.jsonl" --attack "$name" \
      --url "$INFERENCE_URL/predict" --out "$OUTDIR/$name.flows.jsonl" \
      --max-flows "$MAX_FLOWS" || true
  else
    echo "[warn] no feature rows for $name (empty/short capture)"
    : > "$OUTDIR/$name.flows.jsonl"
  fi
  printf '{"attack":"%s","start":%s,"end":%s}\n' "$name" "$t0" "$t1" >> "$MANIFEST_ATTACKS"
}

# convenience: fire an attack script inside the attacker container
fire() { docker exec "$EVAL_CTR" bash "/attacks/$1" "${@:2}"; }

# ---- 4. benign control window (generators on, no attack) ----
if [ -n "${CLIENT_IP:-}" ]; then
  run_window "00_benign_control" "host $CLIENT_IP" 75 \
    docker exec client bash /gen/simulate.sh 60
else
  echo "[warn] client container not up; running benign control from attacker box"
  run_window "00_benign_control" "host $ATTACKER_IP" 75 \
    docker exec "$EVAL_CTR" bash /gen/simulate.sh 60
fi

# ---- 5. attack windows ----
run_window "01_portscan"  "host $ATTACKER_IP and host $WEB_IP" 180 fire 01_portscan.sh  --target "$WEB_IP"
run_window "02_dos_hulk"  "host $ATTACKER_IP and host $WEB_IP" 90  fire 02_dos_hulk.sh  --target "$WEB_IP" --duration 30
run_window "03_slowloris" "host $ATTACKER_IP and host $WEB_IP" 120 fire 03_slowloris.sh --target "$WEB_IP" --duration 60
run_window "04_ssh_brute" "host $ATTACKER_IP and host $SSH_IP" 120 fire 04_ssh_brute.sh --target "$SSH_IP"
run_window "05_web_attack" "host $ATTACKER_IP and host $WEB_IP" 180 fire 05_web_attack.sh --target "$WEB_IP"

# collect tool/flags lines (TOOL ...) emitted by each attack from the run log
python3 - "$LOG" "$TOOLS_JSON" <<'PY'
import json, re, sys
log, out = sys.argv[1], sys.argv[2]
tools, cur = {}, None
for line in open(log, errors="ignore"):
    m = re.search(r"WINDOW: (\S+)", line)
    if m: cur = m.group(1)
    t = re.search(r"^TOOL (.+)$", line.strip())
    if t and cur: tools[cur] = t.group(1)
json.dump(tools, open(out, "w"), indent=2)
PY

# ---- 6. summary table ----
python3 "$TH/eval/tabulate.py" --indir "$OUTDIR" --tools "$TOOLS_JSON" \
  --out-csv "$OUTDIR/summary.csv" --out-md "$OUTDIR/summary.md"

# ---- 7. manifest ----
python3 - "$OUTDIR" "$ATTACKER_IP" "$WEB_IP" "$SSH_IP" "$AE_THRESHOLD" "$SENSOR_COMMIT" "$STAMP" <<'PY'
import glob, json, os, subprocess, sys
outdir, atk, web, ssh, ae, commit, stamp = sys.argv[1:8]
def digest(img):
    try:
        return subprocess.check_output(["docker","image","inspect","-f","{{index .RepoDigests 0}}",img],
                                       stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return img
attacks = []
p = os.path.join(outdir, ".attacks.jsonl")
if os.path.exists(p):
    attacks = [json.loads(l) for l in open(p) if l.strip()]
tools = {}
tp = os.path.join(outdir, "tools.json")
if os.path.exists(tp): tools = json.load(open(tp))
windows = {}
for mp in glob.glob(os.path.join(outdir, "*.flows.meta.json")):
    m = json.load(open(mp))
    windows[m["attack"]] = m
man = {
    "stamp": stamp, "attacker_ip": atk, "targets": {"web": web, "ssh": ssh},
    "ae_threshold": ae, "sensor_commit": commit,
    "attacks": attacks, "tools": tools, "windows": windows,
    "images": {c: digest(c) for c in
               ["ids-harness-web:1","ids-harness-ssh:1","ids-harness-attacker:1"]},
}
json.dump(man, open(os.path.join(outdir,"manifest.json"),"w"), indent=2)
print("[manifest] wrote", os.path.join(outdir,"manifest.json"))
PY

# ---- 8. cleanup + validation ----
docker rm -f "$EVAL_CTR" >/dev/null 2>&1 || true

echo; echo "=== VALIDATION ==="
fail=0
[ -s "$OUTDIR/summary.csv" ] || { echo "FAIL: summary.csv empty"; fail=1; }
[ -s "$OUTDIR/summary.md" ]  || { echo "FAIL: summary.md empty";  fail=1; }
[ -s "$OUTDIR/manifest.json" ] || { echo "FAIL: manifest.json empty"; fail=1; }
scored_total=0
for f in "$OUTDIR"/*.flows.jsonl; do
  [ -e "$f" ] || continue
  n="$(grep -c . "$f" 2>/dev/null || echo 0)"
  echo "  $(basename "$f"): $n flows"
  scored_total=$((scored_total + n))
done
[ "$scored_total" -gt 0 ] || { echo "FAIL: zero flows scored across all windows"; fail=1; }
echo "  total flows scored: $scored_total"
echo; echo "Results in: $OUTDIR"
echo "Back up now:  cp -r '$OUTDIR' ~/aiids-eval-backup/   # drive remounts, pcaps not regenerable"
[ "$fail" -eq 0 ] && echo "VALIDATION: PASS" || { echo "VALIDATION: FAIL"; exit 1; }
