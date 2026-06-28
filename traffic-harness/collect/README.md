# Beehive v2 Training Data Collection

Builds a diverse, correctly-labeled flow dataset for the four supervised classes
(benign / portscan / dos / bruteforce) by driving real tools against the live fleet and
converting every capture to the 56-feature matrix through the FROZEN sensor. Per-flow
provenance (class + tool + window_id + holdout) is preserved so a held-out-tool
generalization test is possible at train time.

This directory produces the **dataset only**. Training is the next task.

## Layout

- `run_collection.sh` -- the driver (capture -> frozen-sensor matrix -> fidelity gate ->
  manifest). Target-driven and resume-safe.
- `tools/` -- the added tool scripts (pyscan, hulk, dos_ab, brute_patator, brute_medusa,
  brute_ncrack, scan_rustscan). Reuses `../attacks/` for nmap (01), goldeneye (02),
  slowhttptest (03). hydra is NOT used: it hangs under sshd MaxAuthTries=1.
- `wordlists/` -- `passwords_{200,1000,5000}.txt` (each contains the real `labpass`).
- `fidelity_gate.py` -- per-window gate (pkt len <= 1500, Flow Bytes/s < 1e9).
- `assemble_dataset.py` -- stacks per-window matrices into `dataset/`.
- `validate_dataset.py` -- final gate (NaN/inf, alignment, >=3 tools + 1 holdout per class).
- `make_report.py` -- writes `COLLECTION_REPORT.md`.
- `finish.sh` -- assemble + validate + report + backup (one command).

## Prerequisites (already done in setup)

- Fleet up: `docker compose up -d` (web, db, ssh, dns, client, attacker on `ids-net`).
- Image built: `docker build -f services/attacker/Dockerfile.collect -t ids-harness-collect:1 .`
- sshd has `MaxAuthTries 1` so each brute password is its own connection (~1 flow/attempt).

## Run the collection (the long part, hours, resume-safe)

```bash
cd traffic-harness
bash collect/run_collection.sh            # or: nohup bash collect/run_collection.sh &
```

It is resume-safe: a window whose matrix already exists is skipped, so it survives
interruption and the drive remount. Re-running tops up any class still under target.

### Trained vs held-out tools
- portscan: train nmap + pyscan, hold out **rustscan**
- dos: train goldeneye + hulk + ab, hold out **slowhttptest**
- bruteforce: train patator + medusa, hold out **ncrack**

### Targets (override via env to scale)
`BENIGN_TARGET=40000 PORTSCAN_TARGET=12000 DOS_TARGET=12000 BRUTE_TARGET=6000`
benign session length: `BENIGN_DUR=600` (seconds), cap `BENIGN_MAX=16` sessions.

### Monitor progress
```bash
python3 - data/collect/manifest.jsonl <<'PY'
import json,sys
from collections import defaultdict
tot=defaultdict(int)
for l in open(sys.argv[1]):
    r=json.loads(l)
    if r.get("fidelity")=="pass": tot[r["class"]]+=r["flows"]
print(dict(tot))
PY
```

## Finish: assemble, validate, report, back up

```bash
bash collect/finish.sh
```

Writes `collect/dataset/` (X.npy, y.npy, meta.csv, label_map.json, dataset.csv,
dataset_manifest.json), validates it, writes `collect/COLLECTION_REPORT.md`, backs up the
(small) dataset to `~/aiids-eval-backup/v2-dataset/`, and gzips the pcaps in place on the
external drive (they are large and stay on the drive; root fs is tight).

## Notes / gotchas

- Collection does NOT need the inference service.
- snap-docker can refuse to stop a container ("permission denied", AppArmor) after a hard
  kill. Unique per-window container names mean a wedge never blocks the next window. A true
  wedge clears with `sudo snap restart docker` or a reboot.
- The drive remounts under a shifting path; every script derives the repo via `git`.
- SMOKE: `SMOKE=1 bash collect/run_collection.sh` runs one short window per tool into
  `data/collect_smoke/` to validate the pipeline without the full run.
