# Attack Validation Runbook (Instrument A)

Self-generated attack evaluation against the frozen IDS, run 2026-06-27. All numbers below
are measured from a single labelled run (`traffic-harness/eval/results/20260627_203402/`,
backed up to `~/aiids-eval-backup/`). Nothing was tuned to make a result pass. No em dashes.

## Headline (the honest two-lane reading)

1. **Danger lane (supervised ensemble): completely silent. 0% fire on every attack family.**
   None of random_forest, xgboost, lightgbm, or cnn_lstm labelled a single one of the 7,160
   scored attack flows as anything but Benign. This is total cross-dataset transfer failure:
   the CICIDS-trained supervised models do not recognise any locally-generated attack.

2. **Warning lane (local AE): partial, and costly.** It separates port scan (100% anomalous)
   and slow-DoS (95.8%) cleanly, but **misses DoS Hulk (4.4%), SSH brute (0%) and the web
   attack (0%)**, and it false-alarms on **35.9% of benign control flows**. Lowering the
   threshold does not rescue the misses (see the sweep below): the missed families sit below
   even the p95 candidate, while benign FP stays ~36 to 40%.

So the result is not "the AE rescues the danger lane." It is: supervised transfer fails
entirely; the local AE gives partial coverage (volumetric scan and slow-DoS only) at a high
benign false-positive cost, and is blind to flood, brute force, and payload-level attacks on
this lab. Both directions are reported because both are findings.

## What was run

- Stack in deployment config: `ids-redis`, the inference service via
  `inference-service/scripts/serve_local.py` (local-baseline AE, threshold **0.379194**, the
  four supervised models from the original artifact dir), and the full benign fleet
  (`web ssh db dns client attacker`) on `ids-net`.
- Attacker toolchain layered additively on the benign client image
  (`traffic-harness/services/attacker/Dockerfile.attack` -> `ids-harness-attacker:1`): nmap,
  hydra, slowhttptest, dirb, sqlmap, and a compact GoldenEye flooder. The benign attacker
  image and the AE benign baseline were left untouched.
- Offline runner `traffic-harness/eval/run_attack_eval.sh`: per window it disables NIC offload
  (bridge + host veths + every container eth0, sudo-less via netshoot NET_ADMIN containers),
  captures an attacker-to-target scoped pcap on the `ids-net` bridge, fires one attack from the
  tooled container, converts the pcap to the 56-feature matrix through the FROZEN sensor
  (`ebpf-sensor/sensor/flow_features.py` via `eval/dump_attack_features.py`), and POSTs every
  flow to `/predict`, tabulating the full vote.
- Identities: attacker `172.20.0.10`, web `172.20.0.2`, ssh `172.20.0.4` (resolved at runtime
  via `docker inspect`, not hardcoded). Sensor frozen at `c02552c`.

## Fidelity gate (passed)

Per-window maxima from the 56-feature matrices:

| window | max packet length | max Flow Bytes/s | flows w/ Bytes/s > 1e9 |
|---|---|---|---|
| benign_control | 1448 | 2.35e8 | 0 |
| portscan | 0 (pure SYN/RST, no payload) | 0 | 0 |
| dos_hulk | 240 | 1.20e7 | 0 |
| slowloris | 321 | 2.02e6 | 0 |
| ssh_brute | 904 | 4.48e4 | 0 |
| web_attack | 614 | 2.41e6 | 0 |

Max packet length stays at or below ~1448 everywhere (no 65,160-byte super-segments) and no
flow has Bytes/s in the billions, so offload was genuinely disabled and the captures are
wire-faithful. The pipeline is trustworthy.

## Instrument A: the vote table

One row per window. `fireN%` = fraction of flows that model labels non-Benign.
`ensemble is_attack%` = fraction the danger lane would page. AE columns from the local AE.

| window | flows (scored/captured) | RF | XGB | LGBM | CNN-LSTM | ensemble is_attack% | AE anomalous% | median AE err | tool/flags |
|---|---|---|---|---|---|---|---|---|---|
| 00_benign_control | 557 / 557 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 35.9 | 0.043 | simulate.sh (web/ssh/db/dns) |
| 01_portscan | 3000 / 65529 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 100.0 | 1.150 | nmap -sT -p- -T4 172.20.0.2 |
| 02_dos_hulk | 3000 / 12466 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.4 | 0.030 | goldeneye http://172.20.0.2:80/ 30s x50 |
| 03_slowloris | 522 / 522 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 95.8 | 6.9e9 (degenerate, see note) | slowhttptest -c 500 -H -l 60 |
| 04_ssh_brute | 5 / 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.018 | hydra -l labuser -P passwords.txt ssh://172.20.0.4 |
| 05_web_attack | 76 / 76 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.022 | dirb + sqlmap probe 172.20.0.2:80 |

Mean AE error is reported in `summary.csv` but is heavily right-skewed (one held slowloris
connection drives the slowloris mean to ~9.6e9); the median column above is the honest central
tendency. Source data: per-flow JSONL in the results dir; CSV/markdown copies as
`summary.csv` / `summary.md`.

## Warning-lane (AE) analysis, with the Section 8 threshold sweep

Local AE threshold `0.379194` is the **p99** of the AE's own validation benign error (val FP
`0.0098`, i.e. ~1%). Candidates from `models/local_baseline/ae_threshold_local.json`:
p97.5 = 0.248, p95 = 0.091. Fraction of each window above each candidate:

| window | n | > 0.091 (p95) | > 0.248 (p97.5) | > 0.379 (p99) |
|---|---|---|---|---|
| benign_control | 557 | 39.9% | 36.3% | 35.9% |
| portscan | 3000 | 100.0% | 100.0% | 100.0% |
| dos_hulk | 3000 | 4.4% | 4.4% | 4.4% |
| slowloris | 522 | 96.0% | 95.8% | 95.8% |
| ssh_brute | 5 | 0.0% | 0.0% | 0.0% |
| web_attack | 76 | 6.6% | 0.0% | 0.0% |

Reading:
- **The sweep does not help.** Port scan and slowloris are already at ~100% at every
  threshold; DoS Hulk, SSH brute, and web attack are near 0% even at p95 (their errors cluster
  at medians 0.030 / 0.018 / 0.022, below 0.091). No threshold in this family separates the
  missed attacks from benign.
- **Benign FP does not improve and is high.** On a fresh, independent benign control window the
  AE flags 35.9% at p99 (and slightly more at lower thresholds), versus the ~1% the threshold
  was calibrated to on its own validation split. The local AE's benign FP generalises poorly
  off its training sample; on this control it is ~36%, not ~1%. This materially limits the
  warning lane's precision in the lab.
- **Slowloris detection is real but trivial.** Held 60s connections produce extreme-magnitude
  scaled features and therefore astronomically large reconstruction errors (median 6.9e9). The
  95.8% anomalous rate is genuine, but it reflects features far outside anything benign rather
  than a finely calibrated margin.

## Per-family verdict

| family | danger lane (supervised) | warning lane (local AE) |
|---|---|---|
| Port scan | missed (0%) | caught (100%), but benign control also 36% FP |
| DoS Hulk (HTTP flood) | missed (0%) | missed (4.4%): flood flows look benign at flow-stats level |
| Slow DoS (slowloris) | missed (0%) | caught (95.8%) via degenerate features |
| SSH brute | missed (0%) | missed (0%), thin sample (n=5) |
| Web attack (dir brute + SQLi) | missed (0%) | missed (0%), expected: payload invisible to flow features |

## Limitations (binding honesty)

- **Sampling.** /predict is CPU-bound (~19 req/s; 5 models + SHAP per request, no client-side
  concurrency gain). Windows over 3,000 flows (portscan 65,529; dos_hulk 12,466) were scored on
  a seeded uniform random sample of 3,000. Full pcaps and 56-feature matrices for all flows are
  saved. For near-identical 2-packet scan probes a 3,000 sample gives tight rate estimates.
- **SSH brute n=5.** hydra found the valid `labuser:labpass` on attempt 7 of 10 with `-f`
  (stop on first found), so only ~5 short sessions were emitted. This is too thin to
  characterise SSH-Patator; a faithful run needs many wrong-password attempts (drop `-f`,
  longer list). Reported as-is; not a basis for a strong SSH conclusion.
- **Benign control is one 60s window (557 flows).** The 35.9% FP is measured on this single
  independent sample, not a long benign baseline. It should be reconciled against the ~1%
  validation FP before drawing a final precision number, but it is a real signal that the AE's
  benign FP is far above target off its training sample.

## Instrument B (live danger-lane gate): NOT YET VALIDATED

The live release gate (real-time sensor on the bridge -> /predict -> `publisher.publish_attack`
-> `ids:attacks` -> Telegram) was **not run** this session: the eBPF sensor needs
`sudo python3 ebpf-sensor/sensor/loader.py <bridge>` and host sudo is interactive here. Given
the Instrument A result (supervised ensemble silent on every family), the danger lane would not
be expected to publish to `ids:attacks` for these stimuli anyway; if anything reaches Redis it
would be on `ids:anomalies` via the AE. **Current honest state: the danger lane is not yet
validated firing on a live local attack.**

## Reproduce

```bash
# stack: redis + serve_local (AE @ 0.379194) + fleet, then
cd <repo>/traffic-harness
docker build -f services/attacker/Dockerfile.attack -t ids-harness-attacker:1 .
MAX_FLOWS=3000 bash eval/run_attack_eval.sh        # writes results/<stamp>/
# resume an aborted run without recapturing good windows:
OUTDIR=<repo>/traffic-harness/eval/results/<stamp> MAX_FLOWS=3000 bash eval/run_attack_eval.sh
```

Manifest (`manifest.json`) records attacker/target IPs, per-window captured-vs-scored counts,
tool flags, AE threshold, and sensor commit for this run.
