#!/usr/bin/env bash
# Beehive v2 training-data collection driver.
#
# Captures a diverse, correctly-labeled flow dataset for the four supervised classes
# (benign / portscan / dos / bruteforce) by driving real tools against the live fleet and
# converting each capture to the 56-feature matrix through the FROZEN sensor. Per spec:
#  - >=3 tools per attack class, one reserved as a held-out tool (tagged holdout=true).
#  - per-flow provenance: every window carries class + tool + config + window_id + holdout.
#  - reuses the sanctioned capture path (offload disabled) and the frozen feature dump.
#  - resume-safe: a window whose matrix already exists is skipped, so the (hours-long) run
#    survives interruption and the drive remount.
#
# Collection does NOT need the inference service. No host sudo required (sudo-less netshoot
# offload + containerized tcpdump). No em dashes anywhere.
set -euo pipefail

# ---- 0. context (derive repo dynamically; the drive remounts under a shifting suffix) ----
SELF="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$SELF" rev-parse --show-toplevel)"
TH="$REPO/traffic-harness"
SENSOR="$REPO/ebpf-sensor"
PY="$SENSOR/.venv/bin/python"
NET="nicolaka/netshoot:v0.13"
COLLECT_IMAGE="${COLLECT_IMAGE:-ids-harness-collect:1}"
SENSOR_COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"

DATA_DIR="$TH/data/collect"
PCAP_DIR="$DATA_DIR/pcaps"
MANIFEST="$DATA_DIR/manifest.jsonl"
mkdir -p "$DATA_DIR" "$PCAP_DIR"
LOG="$DATA_DIR/run_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# Tunables (scale the run without editing the plan). Defaults aim at the spec targets.
BENIGN_WINDOWS="${BENIGN_WINDOWS:-6}"     # number of benign sessions (temporal spread)
BENIGN_DUR="${BENIGN_DUR:-600}"           # seconds per benign session
ATTACKER_CTR="collect-atk-$$"

# SMOKE=1 runs a fast one-window-per-tool pass (short params) over the SAME run_window /
# fire machinery as the full run, to prove capture -> matrix -> fidelity -> manifest works
# and that every tool emits real multi-packet flows. It is NOT the full collection.
SMOKE="${SMOKE:-0}"
if [ "$SMOKE" = 1 ]; then
  BENIGN_WINDOWS=1; BENIGN_DUR="${BENIGN_DUR_SMOKE:-20}"
  DATA_DIR="$TH/data/collect_smoke"; PCAP_DIR="$DATA_DIR/pcaps"
  MANIFEST="$DATA_DIR/manifest.jsonl"; mkdir -p "$PCAP_DIR"
fi

echo "=========================================="
echo "AI-IDS Collection driver"
echo "REPO=$REPO"
echo "DATA_DIR=$DATA_DIR"
echo "COLLECT_IMAGE=$COLLECT_IMAGE  SENSOR_COMMIT=$SENSOR_COMMIT"
echo "BENIGN_WINDOWS=$BENIGN_WINDOWS BENIGN_DUR=${BENIGN_DUR}s"
echo "=========================================="

# ---- 1. prereqs ----
docker image inspect "$COLLECT_IMAGE" >/dev/null 2>&1 \
  || { echo "FATAL: $COLLECT_IMAGE missing. Build services/attacker/Dockerfile.collect first." >&2; exit 1; }
for c in web ssh db; do
  docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true \
    || { echo "FATAL: fleet container '$c' not running. docker compose up -d." >&2; exit 1; }
done
[ -x "$PY" ] || { echo "FATAL: sensor venv python missing at $PY" >&2; exit 1; }

# ---- 2. attacker container + identities ----
docker rm -f "$ATTACKER_CTR" >/dev/null 2>&1 || true
# Mount collect/ live (tools + wordlists) so script edits are picked up without an image
# rebuild; the image still bakes a copy for portability. /attacks and /gen are mounted too.
docker run -d --name "$ATTACKER_CTR" --network ids-net \
  -v "$TH/generators:/gen:ro" -v "$TH/attacks:/attacks:ro" -v "$TH/collect:/collect:ro" \
  "$COLLECT_IMAGE" sleep infinity >/dev/null
trap 'docker rm -f "$ATTACKER_CTR" >/dev/null 2>&1 || true' EXIT
ip_of() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"; }
ATK_IP="$(ip_of "$ATTACKER_CTR")"
WEB_IP="$(ip_of web)"; SSH_IP="$(ip_of ssh)"; DB_IP="$(ip_of db)"
CLIENT_IP="$(ip_of client 2>/dev/null || true)"
echo "[ips] attacker=$ATK_IP web=$WEB_IP ssh=$SSH_IP db=$DB_IP client=${CLIENT_IP:-none}"

# ---- 3. tool availability (graceful gate; record skips) ----
SKIPS_FILE="$DATA_DIR/tool_skips.txt"; : > "$SKIPS_FILE"
have() { docker exec "$ATTACKER_CTR" bash -lc "command -v $1 >/dev/null 2>&1"; }
record_skip() { echo "$1" >> "$SKIPS_FILE"; echo "[skip] $1"; }
declare -A TOOL_OK
for t in nmap rustscan slowhttptest hydra medusa ncrack ab patator; do
  if have "$t"; then TOOL_OK[$t]=1; else TOOL_OK[$t]=0; record_skip "$t not installed in $COLLECT_IMAGE"; fi
done
# python tools live in /collect/tools or /attacks, gauge by file presence
docker exec "$ATTACKER_CTR" test -f /collect/tools/pyscan.py && TOOL_OK[pyscan]=1 || { TOOL_OK[pyscan]=0; record_skip "pyscan.py missing"; }
docker exec "$ATTACKER_CTR" test -f /collect/tools/hulk.py && TOOL_OK[hulk]=1 || { TOOL_OK[hulk]=0; record_skip "hulk.py missing"; }
docker exec "$ATTACKER_CTR" test -f /attacks/goldeneye.py && TOOL_OK[goldeneye]=1 || { TOOL_OK[goldeneye]=0; record_skip "goldeneye.py missing"; }
echo "[tools] $(for k in "${!TOOL_OK[@]}"; do echo -n "$k=${TOOL_OK[$k]} "; done)"

# ---- 4. bridge + offload disable (sudo-less netshoot pattern) ----
BR="$("$TH/capture/find_bridge.sh")"
echo "[bridge] $BR"
IFACES="$(printf '%s ' "$BR"; ip -o link | awk -v b="$BR" '$0 ~ ("master " b)' | awk -F': ' '{print $2}' | sed 's/@.*//' | tr '\n' ' ')"
docker run --rm --network host --cap-add NET_ADMIN -e IFACES="$IFACES" "$NET" \
  sh -c 'for ifc in $IFACES; do ethtool -K "$ifc" tso off gso off gro off 2>/dev/null || true; done' || true
for c in web ssh db dns client attacker "$ATTACKER_CTR"; do
  docker run --rm --net "container:$c" --cap-add NET_ADMIN "$NET" \
    ethtool -K eth0 tso off gso off gro off >/dev/null 2>&1 || true
done
echo "[offload] disabled."

# ---- capture + convert + label one window ----
# args: <window_id> <class> <tool> <holdout 0|1> <config> <bpf-filter> <cap-seconds> <fire...>
run_window() {
  local wid="$1" cls="$2" tool="$3" hold="$4" cfg="$5" filt="$6" cap="$7"; shift 7
  local npy="$DATA_DIR/$wid.X.npy" csv="$DATA_DIR/$wid.X.csv" ids="$DATA_DIR/$wid.ids.jsonl"
  local pcap="$PCAP_DIR/$wid.pcap"
  echo; echo "=== WINDOW $wid  class=$cls tool=$tool holdout=$hold ==="

  # Resume: a window whose matrix already exists is done.
  if [ -f "$npy" ]; then
    echo "[skip] $wid already has a matrix"
    return 0
  fi

  # Unique capture-container name so a snap-docker wedge never blocks the next window.
  local cap_ctr="colcap-$$-$wid"
  docker rm -f "$cap_ctr" >/dev/null 2>&1 || true
  docker run -d --name "$cap_ctr" --network host --cap-add NET_RAW --cap-add NET_ADMIN \
    -v "$PCAP_DIR:/out" "$NET" \
    timeout "$cap" tcpdump -i "$BR" -w "/out/$wid.pcap" -s 0 "$filt" >/dev/null
  sleep 1
  local t0; t0="$(date +%s)"
  echo "--- firing: $* ---"
  "$@" || true
  local t1; t1="$(date +%s)"
  sleep 3                                   # let flows flush before stopping capture
  docker stop "$cap_ctr" >/dev/null 2>&1 || true
  docker rm -f "$cap_ctr" >/dev/null 2>&1 || true

  # pcap -> 56-feature matrix (+ identities) via the FROZEN sensor
  PYTHONPATH="$SENSOR" "$PY" "$TH/eval/dump_attack_features.py" \
    "$pcap" "$npy" "$csv" "$ids" || true

  # fidelity gate on the resulting matrix
  local fid_json fid_rc flows fidelity
  fid_json="$("$PY" "$TH/collect/fidelity_gate.py" "$csv" 2>/dev/null || true)"
  fid_rc=$?
  [ -n "$fid_json" ] || fid_json='{"fidelity":"fail","flows":0,"reason":"no matrix"}'
  flows="$(echo "$fid_json" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("flows",0))' 2>/dev/null || echo 0)"
  fidelity="$(echo "$fid_json" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("fidelity","fail"))' 2>/dev/null || echo fail)"
  echo "[fidelity] $fid_json"
  if [ "$fidelity" != "pass" ]; then
    echo "[WARN] window $wid FAILED fidelity; it is recorded but excluded from the dataset"
  fi

  # append manifest row (python builds the JSON to keep quoting safe)
  "$PY" - "$MANIFEST" "$wid" "$cls" "$tool" "$hold" "$cfg" "$t0" "$t1" "$flows" "$fidelity" "$fid_json" <<'PY'
import json, sys
man, wid, cls, tool, hold, cfg, t0, t1, flows, fidelity, fid_json = sys.argv[1:12]
try:
    fid = json.loads(fid_json)
except Exception:
    fid = {}
row = {
    "window_id": wid, "class": cls, "tool": tool, "holdout": hold in ("1", "true", "True"),
    "config": cfg, "start": int(t0), "end": int(t1), "flows": int(flows),
    "fidelity": fidelity, "pkt_len_max": fid.get("pkt_len_max"),
    "flow_bps_max": fid.get("flow_bps_max"),
}
with open(man, "a") as fh:
    fh.write(json.dumps(row) + "\n")
PY
  echo "[manifest] $wid: flows=$flows fidelity=$fidelity"
}

# fire helpers (exec a tool inside the attacker container)
fire_atk()  { docker exec "$ATTACKER_CTR" "$@"; }
fire_sh()   { docker exec "$ATTACKER_CTR" bash "$1" "${@:2}"; }            # /attacks/*.sh
fire_col()  { docker exec "$ATTACKER_CTR" bash "/collect/tools/$1" "${@:2}"; }
fire_colpy(){ docker exec "$ATTACKER_CTR" python3 "/collect/tools/$1" "${@:2}"; }

want() { [ "${TOOL_OK[$1]:-0}" = "1" ]; }   # is a tool usable?

# Running per-class flow total (fidelity=pass only) from the manifest. Drives the plan so
# we stop a class once it reaches its target instead of wildly overshooting (scans/floods
# emit flows very fast) and keep benign >= combined attack volume.
class_total() {
  "$PY" - "$MANIFEST" "$1" <<'PY'
import json, sys
c = sys.argv[2]; tot = 0
try:
    for line in open(sys.argv[1]):
        line = line.strip()
        if not line:
            continue
        r = json.loads(line)
        if r.get("class") == c and r.get("fidelity") == "pass":
            tot += int(r.get("flows", 0))
except FileNotFoundError:
    pass
print(tot)
PY
}
need_more() { [ "$(class_total "$1")" -lt "$2" ]; }   # is a class still under its target?

# Per-class flow targets (override via env to scale the run).
BENIGN_TARGET="${BENIGN_TARGET:-40000}"
PORTSCAN_TARGET="${PORTSCAN_TARGET:-12000}"
DOS_TARGET="${DOS_TARGET:-12000}"
BRUTE_TARGET="${BRUTE_TARGET:-6000}"
BENIGN_MAX="${BENIGN_MAX:-16}"

P="host $ATK_IP and host"
D="host $ATK_IP and host $WEB_IP"
B="host $ATK_IP and host $SSH_IP"
SRC_FILTER="host $ATK_IP"
[ -n "${CLIENT_IP:-}" ] && SRC_FILTER="host $ATK_IP or host $CLIENT_IP"

# ================= BENIGN (generators on, NO attack process) =================
# Clean generator sessions, generators on BOTH client and attacker (per spec), capture
# scoped to those source hosts so the window is benign by construction. The bulk of the
# dataset. Target-driven: keep adding sessions (temporal variation) until >= BENIGN_TARGET.
benign_window() {
  local i="$1" cap; cap=$((BENIGN_DUR + 15))
  local wid; wid="$(printf 'b%02d_benign_generators' "$i")"
  [ -n "${CLIENT_IP:-}" ] && docker exec -d client bash /gen/simulate.sh "$BENIGN_DUR" || true
  run_window "$wid" benign generators 0 "simulate ${BENIGN_DUR}s session=$i" \
    "$SRC_FILTER" "$cap" fire_atk bash /gen/simulate.sh "$BENIGN_DUR"
}
if [ "$SMOKE" = 1 ]; then
  benign_window 1
else
  i=1
  while [ "$(class_total benign)" -lt "$BENIGN_TARGET" ] && [ "$i" -le "$BENIGN_MAX" ]; do
    benign_window "$i"; i=$((i + 1))
  done
fi

# ================= SMOKE: one short window per tool, then stop =================
if [ "$SMOKE" = 1 ]; then
  P="host $ATK_IP and host"; D="host $ATK_IP and host $WEB_IP"; B="host $ATK_IP and host $SSH_IP"
  want nmap     && run_window s_ps_nmap   portscan nmap   0 "smoke nmap 1-2000" "$P $WEB_IP" 90 \
                    fire_atk nmap -sT -p1-2000 -T4 --max-retries 1 "$WEB_IP"
  want pyscan   && run_window s_ps_pyscan portscan pyscan 0 "smoke pyscan 400" "$P $WEB_IP" 90 \
                    fire_colpy pyscan.py --target "$WEB_IP" --ports 400 --range 1-2000 --seed 11
  want rustscan && run_window s_ps_rust   portscan rustscan 1 "smoke rustscan 1-10000" "$P $WEB_IP" 90 \
                    fire_col scan_rustscan.sh --target "$WEB_IP" --seed 0
  want goldeneye&& run_window s_dos_ge    dos goldeneye 0 "smoke goldeneye 12s" "$D" 40 \
                    fire_sh /attacks/02_dos_hulk.sh --target "$WEB_IP" --duration 12 --workers 30
  want hulk     && run_window s_dos_hulk  dos hulk 0 "smoke hulk 12s" "$D" 40 \
                    fire_colpy hulk.py --target "$WEB_IP" --duration 12 --seed 31
  want ab       && run_window s_dos_ab    dos ab 0 "smoke ab seed0" "$D" 90 \
                    fire_col dos_ab.sh --target "$WEB_IP" --seed 0
  want slowhttptest && run_window s_dos_slow dos slowhttptest 1 "smoke slowloris 20s" "$D" 40 \
                    fire_sh /attacks/03_slowloris.sh --target "$WEB_IP" --duration 20 --conns 150
  want patator  && run_window s_bf_patator bruteforce patator 0 "smoke patator 1000 t4" "$B" 120 \
                    fire_col brute_patator.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_1000.txt --threads 4
  want medusa   && run_window s_bf_medusa bruteforce medusa 0 "smoke medusa 1000 t4" "$B" 120 \
                    fire_col brute_medusa.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_1000.txt --tasks 4
  want ncrack   && run_window s_bf_ncrack bruteforce ncrack 1 "smoke ncrack 1000 holdout" "$B" 150 \
                    fire_col brute_ncrack.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_1000.txt --seed 4
fi

# ================= FULL attack plan (skipped in SMOKE) =================
# Pattern per class: run ONE window of each trained tool unconditionally (guarantees the
# >=3-distinct-tools requirement), then add top-up windows ONLY while still under target
# (need_more), then always run the held-out tool. Scans and floods emit flows fast, so a
# single bounded window per tool usually already meets the target; top-ups cover thin yields.
if [ "$SMOKE" != 1 ]; then

# ----- PORTSCAN (train: nmap, pyscan ; holdout: rustscan) -----
want nmap   && run_window p01_portscan_nmap_web   portscan nmap   0 "nmap -sT -p1-10000 -T4 web" "$P $WEB_IP" 240 \
                 fire_atk nmap -sT -p1-10000 -T4 --max-retries 1 "$WEB_IP"
want pyscan && run_window p02_portscan_pyscan_web portscan pyscan 0 "pyscan 3000 web" "$P $WEB_IP" 200 \
                 fire_colpy pyscan.py --target "$WEB_IP" --ports 3000 --range 1-20000 --seed 11
want pyscan && need_more portscan "$PORTSCAN_TARGET" && run_window p03_portscan_pyscan_db portscan pyscan 0 "pyscan 5000 db" "$P $DB_IP" 220 \
                 fire_colpy pyscan.py --target "$DB_IP" --ports 5000 --range 1-20000 --seed 22
want nmap   && need_more portscan "$PORTSCAN_TARGET" && run_window p04_portscan_nmap_ssh portscan nmap 0 "nmap -sT -p1-10000 -T3 ssh" "$P $SSH_IP" 220 \
                 fire_atk nmap -sT -p1-10000 -T3 --max-retries 1 "$SSH_IP"
want rustscan && run_window p90_portscan_rustscan_h portscan rustscan 1 "rustscan holdout web 1-10000" "$P $WEB_IP" 200 \
                 fire_col scan_rustscan.sh --target "$WEB_IP" --seed 0

# ----- DOS (train: goldeneye, hulk, ab ; holdout: slowhttptest) -----
want goldeneye && run_window d01_dos_goldeneye dos goldeneye 0 "goldeneye 12s w50" "$D" 60 \
                    fire_sh /attacks/02_dos_hulk.sh --target "$WEB_IP" --duration 12 --workers 50
want hulk      && run_window d02_dos_hulk dos hulk 0 "hulk 1s w20" "$D" 40 \
                    fire_colpy hulk.py --target "$WEB_IP" --duration 1 --workers 20 --seed 31
want ab        && run_window d03_dos_ab dos ab 0 "ab 4000 reqs" "$D" 120 \
                    fire_col dos_ab.sh --target "$WEB_IP" --reqs 4000 --seed 1
want goldeneye && need_more dos "$DOS_TARGET" && run_window d04_dos_goldeneye_b dos goldeneye 0 "goldeneye 20s w80" "$D" 70 \
                    fire_sh /attacks/02_dos_hulk.sh --target "$WEB_IP" --duration 20 --workers 80
want hulk      && need_more dos "$DOS_TARGET" && run_window d05_dos_hulk_b dos hulk 0 "hulk 6s" "$D" 40 \
                    fire_colpy hulk.py --target "$WEB_IP" --duration 6 --seed 47
want slowhttptest && run_window d90_dos_slowloris_h dos slowhttptest 1 "slowloris holdout 60s c500" "$D" 100 \
                    fire_sh /attacks/03_slowloris.sh --target "$WEB_IP" --duration 60 --conns 500

# ----- BRUTEFORCE (train: patator, medusa ; holdout: ncrack) -----
# With sshd MaxAuthTries=1 each password attempt is its own connection, so flows scale with
# attempts (~0.5 flow/attempt measured: a 1000-list yields ~520 flows, a 5000-list ~2600).
# hydra is NOT used here: it hangs on the per-attempt disconnect. patator is the volume
# driver, medusa adds a second trained fingerprint. Diversity comes from wordlist length and
# thread count across windows; the target-driven loop stops once BRUTE_TARGET is reached.
want patator && run_window f01_brute_patator_5k_t4 bruteforce patator 0 "patator 5000 t4" "$B" 300 \
                  fire_col brute_patator.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_5000.txt --threads 4
want medusa  && run_window f02_brute_medusa_1k_t4  bruteforce medusa 0 "medusa 1000 t4" "$B" 300 \
                  fire_col brute_medusa.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_1000.txt --tasks 4
want patator && need_more bruteforce "$BRUTE_TARGET" && run_window f03_brute_patator_5k_t6 bruteforce patator 0 "patator 5000 t6" "$B" 300 \
                  fire_col brute_patator.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_5000.txt --threads 6
want medusa  && need_more bruteforce "$BRUTE_TARGET" && run_window f04_brute_medusa_5k_t8 bruteforce medusa 0 "medusa 5000 t8" "$B" 400 \
                  fire_col brute_medusa.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_5000.txt --tasks 8
want patator && need_more bruteforce "$BRUTE_TARGET" && run_window f05_brute_patator_2k_t8 bruteforce patator 0 "patator 2000 t8" "$B" 300 \
                  fire_col brute_patator.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_1000.txt --threads 8
want patator && need_more bruteforce "$BRUTE_TARGET" && run_window f06_brute_patator_5k_t10 bruteforce patator 0 "patator 5000 t10" "$B" 300 \
                  fire_col brute_patator.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_5000.txt --threads 10
want ncrack  && run_window f90_brute_ncrack_5k_h bruteforce ncrack 1 "ncrack 5000 holdout" "$B" 400 \
                  fire_col brute_ncrack.sh --target "$SSH_IP" --wordlist /collect/wordlists/passwords_5000.txt --seed 4
fi   # end FULL attack plan

# ---- per-class running totals from the manifest (warn on thin classes) ----
echo; echo "=== per-class flow totals (fidelity=pass only) ==="
"$PY" - "$MANIFEST" <<'PY'
import json, sys
from collections import defaultdict
tot = defaultdict(int); tools = defaultdict(set)
targets = {"benign":40000,"portscan":12000,"dos":12000,"bruteforce":6000}
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    r=json.loads(line)
    if r.get("fidelity")=="pass":
        tot[r["class"]]+=int(r.get("flows",0)); tools[r["class"]].add(r["tool"])
for c in ("benign","portscan","dos","bruteforce"):
    t=targets[c]; n=tot[c]; mark="OK" if n>=t else "THIN"
    print(f"  {c:11s} {n:8d} / {t:<7d} [{mark}]  tools={sorted(tools[c])}")
PY

echo; echo "Collection windows complete. Next: assemble + validate (collect/finish.sh)."
echo "Log: $LOG"
