# Benign Traffic Capture Harness

Builds a local container fleet that performs a wide variety of benign activity, then
captures that traffic and turns it into the exact 56-feature vectors the autoencoder
consumes. The output is a benign-only training dataset (`data/X_benign_local.npy`) plus a
repeatable capture procedure.

This harness does NOT retrain the autoencoder and does NOT modify the frozen backend
(`inference-service/`, `ebpf-sensor/sensor/`). It consumes the sensor as a read-only tool.
Benign traffic only: no scans, floods, or exploits anywhere.

## Fleet

On a dedicated user-defined bridge network `ids-net`:

- `web`: nginx on 80 and 443 (self-signed), assets of 1 KB, 50 KB, 2 MB.
- `db`: mariadb on 3306, seeded `labdb.events`, user `labuser` / `labpass`.
- `ssh`: openssh on 22, user `labuser` / `labpass`.
- `dns`: dnsmasq on 53 udp, answers a few local lab names.
- `client` and `attacker`: tools boxes that run the benign generators. In this phase the
  attacker only does benign client activity, so its normal behavior is in the baseline.

## Run

```bash
cd traffic-harness

# 1. Bring up the fleet.
docker compose up -d --build

# 2. Start the capture for the chosen duration (seconds). Two options:
#    a) host tcpdump (needs sudo):
./capture/capture.sh 900 &
#    b) sudo-less, capture inside a host-network container:
./capture/capture_docker.sh 900 &

# 3. Drive benign activity from BOTH boxes for the same duration.
docker compose exec -T client   bash /gen/simulate.sh 900 &
docker compose exec -T attacker bash /gen/simulate.sh 900 &
wait

# 4. Aggregate the pcap into the 56-feature matrix.
./capture/to_features.sh data/<your_capture>.pcap

# 5. Validate against the dataset distributions (from the sensor root, in its venv).
( cd ../ebpf-sensor && .venv/bin/python validate_sensor.py "$(pwd)/../traffic-harness/data/<your_capture>.pcap" )
```

Start the capture first, then the generators, for the same duration. Capture benign only.

## Capture fidelity (offload)

Capturing container traffic on a virtual bridge has one gotcha: NIC segmentation and
receive offload (TSO, GSO, GRO) make tcpdump record 64 KB super-segments instead of
wire-sized frames. That inflates packet-length and byte-rate features and breaks fidelity
against the dataset (validate_sensor would show packet lengths far above 1500 and
Flow Bytes/s orders of magnitude high). Both capture scripts disable offload on the
bridge and its veths before recording (best effort, needs privileges). After a capture,
confirm with validate_sensor that packet lengths sit at or below about 1500 and the
length/rate columns share the dataset magnitude band. If they do not, offload was still
on somewhere on the path; disable it and recapture before using the matrix.

## Output

- `data/<timestamp>.pcap`: the raw benign capture.
- `data/X_benign_local.npy`: the benign feature matrix in training feature order.
- `data/X_benign_local.csv`: the same, for inspection.

`data/` is gitignored. Keep the matrix, remove large pcaps when no longer needed.

## Teardown

```bash
docker compose down -v
```

## Handoff (separate task)

A later task consumes `data/X_benign_local.npy` to refit the AE scaler on these benign
rows, recalibrate the AE on this local normal, and recompute the anomaly threshold from
this benign reconstruction-error distribution (for example the 95th to 99th percentile).
Do not reuse 0.0726, that value belonged to CICIDS2017.
