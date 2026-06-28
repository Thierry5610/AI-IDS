# Beehive — AI-based Network Intrusion Detection System

B.Eng dissertation project (Computer Engineering, University of Buea). An AI-driven
NIDS that compares five ML models on CICIDS2017 with cross-dataset evaluation,
SHAP explainability, an eBPF sensor, a FastAPI inference service, Redis Streams
alerting, Telegram notifications, and a React dashboard. "Beehive" is the current
product/codename.

---

## How to use this file

This is the lean root context. Heavier references live in `docs/` and should be read
**on demand**, not every turn:

- **Any frontend / UI / styling work** → read `docs/design/` first. `VIGIL-THEME-SKILL.md`
  is the branding/colour/radius bible and takes absolute precedence. `design-taste-frontend.md`
  governs layout, typography, spacing, and anti-slop rules. `emil-kowalski-motion.md` (+ the
  review/standards docs) govern framer-motion/tailwind transitions and easing only. The
  `docs/design/prototypes/*.html` files are the reference implementation — match them.
- **Backend / service work** → read the relevant handoff in `docs/architecture/`
  (inference service, sensor, alerting). The backend is FROZEN (see below).
- **Anything not obvious from the code** (semantics, research framing, scope boundaries,
  workflow preferences) → read `docs/context/project-decisions.md`. This carries the
  chat-derived context that isn't visible in the source.

Read the design docs before writing any frontend code. Do not default to generic
SaaS/dashboard templates.

---

## Hard rules (do not violate)

1. **The backend is frozen** at commit `c02552c`. Inference service, eBPF sensor, and
   alerting layer (Redis Streams fan-out + Telegram notifier) are validated and complete.
   Do not modify them. New stream producers live in the emitter (`publisher.py`), never in
   the inference service.
2. **Design system is Matrix-derived and explicitly flat.** Dark canvas, single lime/green
   accent, near-square radius, hairline borders. NO glow, grain, shadows, glassmorphism, or
   3D tilt unless a prototype shows it. Full token spec in `docs/design/VIGIL-THEME-SKILL.md`.
   Do not reintroduce retired tokens.
3. **`danger` vs `warning` are distinct and must not be merged.** `danger` = supervised
   `is_attack` verdict → pages Telegram. `warning` = autoencoder `is_anomalous` → dashboard /
   research view only, never paged. The AE threshold (0.0726) is fixed.
4. **Child of the research framing:** the autoencoder's high benign false-positive rate on
   cross-dataset transfer (~75%) is the dissertation's headline FINDING, not a defect. Frame
   it that way everywhere. The AE threshold stays fixed for the original system.
5. **No fabricated citations** in any dissertation work. Real, verifiable papers only.

---

## Architecture (current)

```
eBPF sensor ──▶ publisher.py ──▶ Redis Streams ──┬─▶ ids:attacks   ──▶ notifier (Telegram)
   (frozen)      (emitter)        (frozen)        │                  └─▶ bridge /stream/attacks (SSE)
                                                  └─▶ ids:anomalies ──▶ bridge /stream/anomalies (SSE)
inference-service (FastAPI, frozen) — RF · XGBoost · LightGBM · CNN-LSTM · Autoencoder
bridge/   — FastAPI SSE fan-out adaptor (XREAD per connection, broadcast to all clients)
frontend/ — React + Vite, CSS modules, Zustand, React Router
```

**Five models** (the four supervised produce label + confidence votes; the AE produces an
anomaly score vs the fixed threshold): Random Forest, XGBoost, LightGBM, CNN-LSTM, Autoencoder.
All four supervised models use raw unscaled features; only the AE uses StandardScaler.

**Frozen** = inference-service, ebpf-sensor, notifier. **Active build** = frontend (Overview
page done; Topology, Alerts, Flows, Models, Research, Settings remaining).

---

## Frontend conventions

- Seven pages map 1:1 to the rail nav: Overview, Topology, Alerts, Flows, Models, Research, Settings.
- Styling is plain CSS (no Tailwind). Global stylesheets in `frontend/src/styles/`:
  `tokens.css` (design tokens, verbatim from the theme skill), `globals.css` (reset + ambient),
  `shell.css` (layout + shared component classes). Per-component CSS lives next to the component.
- Live data: `bridge` SSE → `LiveDataProvider` mounts both streams once at app root →
  Zustand ring-buffer stores (`alertStore` 200, `anomalyStore` 500) → pages read the stores.
- The **concentric ensemble consensus gauge** (one ring per model; rings closing = consensus)
  is a confirmed featured element.
- Topology is a passive, typed graph: host type inferred from observed ports in the alert
  identity payload (`:25`→mail, `:3306`→db, `:443`→web). Active/auto-provisioning topology is
  explicit future work — do NOT write code toward it.

---

## Working preferences

- Direct and terse. One issue at a time. Targeted edits over rewrites. Honest assessment over
  optimism. Push back on insufficient or recycled work.
- Validate before presenting: parse JSX/CSS (esbuild) and check Python imports before claiming
  something works.
- Transactional momentum: proceed through steps without waiting for review between each, unless
  a decision genuinely needs the user.
- For the dissertation: one chapter per document, merged at the end. APA author-year citations,
  chapter-based figure numbering, A4 / Times New Roman 12pt / 1.5 spacing / justified.

---

## Repo layout

```
inference-service/   FROZEN — FastAPI + 5 models + SHAP
ebpf-sensor/         FROZEN — eBPF capture + feature extraction + publisher.py
notifier/            FROZEN — Redis → Telegram pager
bridge/              SSE fan-out adaptor (Redis XREAD → browser)
frontend/            React + Vite dashboard
scripts/             setup / utility scripts
docs/                design bible, architecture handoffs, project decisions  ← read on demand
```
