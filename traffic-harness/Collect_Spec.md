# Beehive v2: Training Data Collection (Claude Code spec)

Collect a substantial, diverse, correctly labeled flow dataset to train local supervised
models. Volume is necessary but not sufficient: overfitting is prevented by diversity, so
this harness enforces multiple tools per class and randomized parameters per tool, and
preserves the source tool per flow so a held-out-tool test is possible later. No em dashes.

---

## 0. Non-negotiables

- **Frozen, read-only:** do not edit `inference-service/app/` or `ebpf-sensor/sensor/`.
  New code lives in `traffic-harness/collect/`. Build the feature matrix only through the
  frozen sensor (`tools/dump_features.py` / `capture/to_features.sh`), never by
  reimplementing it.
- **Resolve the repo path first** (drive remounts with a numeric suffix):
  ```bash
  for p in /media/thierry/TempStorage*/AI-IDS; do
    git -C "$p" rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo "$p"; done
  ```
- **Reuse the existing capture path** (`capture/capture_docker.sh duration outfile`), which
  already disables NIC offload in all three places. Re-assert the fidelity gate after every
  capture: packet length max at or below ~1500, no Flow Bytes/s in the billions. Abort a
  window that fails it.
- **Preserve per-flow provenance.** Every flow row carries `class` AND `tool` AND `window_id`.
  This is mandatory: the held-out-tool split at train time depends on it.
- Scripts: `set -euo pipefail`, single-quoted heredocs, resume support, a validation block.

---

## 1. Label scheme

Four supervised classes. DoS variants collapse into one `dos` class; the `tool` column keeps
the variant for the held-out split. Web and infiltration are **excluded** from the supervised
set (they collapse under local training per the literature; the autoencoder owns them).

| label | class       |
|-------|-------------|
| 0     | benign      |
| 1     | portscan    |
| 2     | dos         |
| 3     | bruteforce  |

**Held-out rule:** reserve one tool per attack class, captured but tagged `holdout=true`,
never used for training. It is the only honest generalization test.

---

## 2. Attack tool matrix (against responsive fleet hosts: web .10, ssh .11, db .12)

Run each tool with the listed parameter configs (randomize timing, ranges, concurrency, and
target across runs to spread the distribution). Install tools into the attacker container;
gate gracefully: if a tool will not install, skip it, warn, and record the skip in the
manifest. Do not abort the run on one missing tool. Drop hydra's `-f` (it stopped at n=5
before).

| class      | tools (aim for >=3 usable)                          | param variation                               | hold out |
|------------|-----------------------------------------------------|-----------------------------------------------|----------|
| portscan   | nmap `-sT`, rustscan, a python async connect-scanner| timing T2/T3/T4, port ranges 1-1k / full / random subsets, vary target | rustscan |
| dos        | GoldenEye, hulk, slowhttptest (`-H`/`-X`/`-B`), `ab`| workers, sockets, rate, duration; mix slow and volumetric | slowhttptest |
| bruteforce | hydra, ncrack (or patator/medusa), one more if available | wordlist size (200 / 1000+), `-t` concurrency, drop `-f` | ncrack |

Connect-scan only (snap nmap cannot raw-SYN). Application-layer DoS only (a raw SYN flood is
single-packet flows the sensor drops). Hit live services so flows complete with >=2 packets.

---

## 3. Benign collection (clean, this is half the dataset)

- Drive the existing generators (`generators/simulate.sh`, web/ssh/db/dns) from the client
  and attacker boxes, with **no attack process running** in any window. The earlier 36%
  control FP came from attacker tooling contaminating a benign window; do not repeat it.
- Multiple sessions of several minutes each, across different times, to capture temporal
  variation rather than one long homogeneous block.
- Target benign volume at least equal to the combined attack volume so the classes are not
  degenerately imbalanced.

---

## 4. The driver (`traffic-harness/collect/run_collection.sh`)

Per window:
1. Set `class`, `tool`, `config`, `window_id` (unique, timestamped), `holdout` flag.
2. For attack windows: quiesce benign generators so the capture is attacker-to-target only,
   every flow in it is that class by construction. For benign windows: generators on, no attack.
3. Start `capture_docker.sh <dur> data/collect/<window_id>.pcap`, scoped to the relevant hosts.
4. Fire the tool with its config (attack) or wait out the duration (benign).
5. Stop capture. Assert the fidelity gate.
6. Convert to matrix via `to_features.sh`. Tag every row with `class,tool,window_id,holdout`.
7. Append the per-window result to `data/collect/manifest.jsonl` (class, tool, config, target,
   start/end epoch, flow count, fidelity pass/fail, holdout).

Resume support: skip any `window_id` whose matrix already exists. The full run is long
(many windows, hours); it must survive interruption and the drive remount.

---

## 5. Volume and balance targets (raise windows for any thin class)

- benign: aim >= 40k flows across multiple clean sessions.
- portscan: >= 12k flows (scans emit many tiny flows fast; easy to reach).
- dos: >= 12k flows across the volumetric and slow tools.
- bruteforce: >= 6k flows (thinner per run; add wordlist length and windows to reach it).

If a class falls short, add windows and configs, do not pad by re-running one config (that
inflates count without diversity).

---

## 6. Dataset assembly and output contract (Kaggle-ready)

Assemble all matrices into a single labeled set in the 56-feature training order
(`FEATURE_ORDER` from the frozen sensor). Write to `traffic-harness/collect/dataset/`:

- `X.npy` float32, shape (N, 56), feature order = `FEATURE_ORDER`.
- `y.npy` int, the class label per row.
- `meta.csv` one row per flow: `tool, window_id, holdout, class_name` (the provenance the
  held-out-tool split needs).
- `label_map.json`: `{0:benign,1:portscan,2:dos,3:bruteforce}`.
- `dataset.csv`: the 56 features + class + tool + holdout, one combined table for inspection.
- `dataset_manifest.json`: per-class and per-tool flow counts, total N, class balance, the
  list of held-out tools, fidelity-gate pass rate, capture date, sensor commit.

---

## 7. Validation gate (run before declaring done)

- No NaN/inf in `X.npy`; packet length max plausible (<=~1500); Flow Bytes/s not in billions.
- Every row in `meta.csv` aligns 1:1 with `X.npy` / `y.npy` (same N, same order).
- Each attack class has >=3 distinct tools present, and each has exactly one held-out tool
  with zero rows leaking into the training tools.
- Print the final per-class and per-tool counts and the class balance.

---

## 8. Deliverables and backup

- `traffic-harness/collect/` (driver, tool scripts, assembly script).
- `traffic-harness/collect/dataset/` (the artifacts in Section 6).
- **Back up `dataset/` and the pcaps off the external drive immediately** (e.g.
  `~/aiids-eval-backup/v2-dataset/`). The matrices are not regenerable and the drive remounts.
- A short `COLLECTION_REPORT.md`: what tools ran, what was skipped and why, final counts,
  the held-out tools, and the fidelity pass rate.

---

## 9. Scope notes (do not drift)

- Supervised classes are benign, portscan, dos, bruteforce only. Web and infiltration are
  out of the supervised set by decision; capture them separately only if you want AE-side
  evaluation data, labeled and stored apart, never mixed into `y.npy`.
- The held-out tool per class is reserved and never trained on. Training and the in-domain
  vs cross-tool evaluation are the next task, not this one. This task produces the dataset.