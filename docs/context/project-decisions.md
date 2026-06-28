# Project Decisions & Context

The context that isn't evident from the source code — semantic decisions, research framing,
scope boundaries, and hard-won lessons. Read this before making non-obvious calls. Where this
conflicts with older planning docs, **this file wins** (the project evolved past several early
decisions; see "Superseded decisions" at the end).

---

## 1. Semantic decisions (locked)

### danger vs warning
Two distinct alert classes that must never be merged:
- **`danger`** — a supervised `is_attack` verdict from the four supervised models. Pages
  Telegram. This is the operational, "wake someone up" signal.
- **`warning`** — an autoencoder `is_anomalous` verdict. Goes to the dashboard / research view
  only. **Never pages.** It is a research/observability signal, not an operational one.

The autoencoder threshold is **0.0726** (95th-percentile benign reconstruction error) and is
**fixed**. Do not make it adaptive for the original system.

### Model roles
Five models total. The four supervised (RF, XGBoost, LightGBM, CNN-LSTM) emit a label +
confidence and vote on the verdict; the highest-confidence prediction sets the alert class.
The autoencoder is anomaly-only — it emits a reconstruction-error score compared against the
fixed threshold, never a class label. All four supervised models consume **raw unscaled
features**; only the autoencoder uses `StandardScaler` (`ae_scaler.pkl`).

---

## 2. Research framing (this is the thesis's spine)

### The headline finding
Cross-dataset transfer fails significantly: trained on CICIDS2017, the autoencoder flags
**~75% of benign traffic as anomalous** when evaluated cross-domain (at the 0.0726 threshold).
**This is the dissertation's headline finding, not a defect.** Frame it as a reported research
result everywhere — in writing, in the dashboard's research view, and in the defense.

### It's a data problem, not an architecture problem
The domain gap between datasets is the cause. Docker simulation does not close it. A supervised
retrain to "fix" the AE is **off the table** for the original system — doing so would erase the
finding. The whole point is to demonstrate and characterise the gap, not paper over it.

### Project positioning
Framed as a **software-engineering and cloud-native systems project** that addresses an AI +
cybersecurity research problem — not a networking project. The contribution is the combination
of (a) a five-model comparative study, (b) cross-dataset generalisation testing (which most
published IDS papers skip), (c) SHAP explainability on every alert, and (d) a fully deployed
end-to-end live pipeline rather than a notebook.

---

## 3. Architecture decisions & rationale

- **Backend frozen at `c02552c`.** Inference service + eBPF sensor + alerting (Redis Streams
  fan-out + Telegram) are validated and complete. Treat as immutable.
- **New stream producers live in the emitter (`publisher.py`), not the inference service.**
  The inference service stays frozen; anything that needs to emit a new stream does so from the
  emitter side.
- **Redis over Kafka** at this scale. Consumer-group semantics for the notifier are
  at-least-once with ack-on-send.
- **Bridge uses XREAD per connection (broadcast), NOT a shared consumer group.** A shared group
  = competing consumers = each message delivered to only one client, so a second browser tab
  sees nothing. The dashboard needs fan-out: every connected client receives every event. Each
  SSE connection tails the stream independently from `"0"` (replays recent history, then live).
- **Passive typed topology is in scope; active/auto-provisioning is explicit future work.**
  Host type is inferred from observed ports in the alert identity payload (`:25`→mail,
  `:3306`→db, `:443`→web, etc.). Do NOT write code toward DevOps orchestration / auto-
  provisioning — it's a scope explosion and off-thesis.
- **Topology view** should use a real graph engine (e.g. three.js / force-graph) for pan/zoom,
  not hand-rolled SVG (a prior SVG mock was buggy). It is one mode inside the dashboard, not a
  standalone product.

---

## 4. Design direction (locked)

Matrix-derived (from typeui.sh). Authoritative token spec is in `docs/design/VIGIL-THEME-SKILL.md`.

- Dark-only canvas, single accent, near-square small radius, hairline borders only.
- **Explicitly flat: no glow, no grain, no shadows, no glassmorphism, no 3D tilt-parallax.**
  These are anti-patterns here. Do not reintroduce retired "cockpit-era" tokens (the old
  emerald accent, Hanken Grotesk / IBM Plex Mono pairing, 8px radius, film grain/glow/3D tilt).
- Terminal / order-book-influenced dense data surfaces.
- The **concentric ensemble consensus gauge** — one SVG arc per model as nested rings, model
  agreement visible as the rings closing the circle — is a confirmed featured element of the
  final product.
- KPI cards follow the VIGIL spec exactly: uppercase letter-spaced labels, the icon top-right,
  generous label→value spacing, delta pill at the bottom. Featured (accent) card uses muted-dark
  label + dark delta pill, not full black.
- Insect-based naming/logo exploration is ongoing (Beehive is the codename; a wasp-style outline
  mark with a stinger in the accent colour was cited as a reference aesthetic — sharp, mechanical).
  3–5 name/icon options to be proposed when logo work begins. Until a logo is chosen, use the
  existing VIGIL mark with the product name "Beehive".

---

## 5. Scope boundaries

**In scope:** five-model comparative study; CICIDS2017 primary with UNSW-NB15 cross-dataset
evaluation; SHAP on all models; eBPF sensor; FastAPI inference; Redis Streams alerting; Telegram
notifications; React dashboard (7 pages); MLflow tracking; Docker; Terraform/Azure deploy;
passive typed topology.

**Out of scope / future work:** active or auto-provisioning topology (DevOps orchestration);
supervised retrain to close the AE domain gap (would erase the finding); GNN/GCN as a fourth
comparison model (stretch goal only, after core models stable).

**Auth** (shared API token sensor→inference + dashboard login) is deferred until the first
frontend page is integrated end-to-end, but is **mandatory before any Azure/public deployment** —
an open `/predict` must not be exposed on a public IP.

---

## 6. Hard-won technical lessons

- **docx-js:** the `highlight` property on `TextRun` causes validation failure (emits
  `highlightCs`). Use `color` + `bold` + `italics` for placeholder text instead. Paragraph-level
  borders also fail validation.
- **redis-py 8.0.0:** a bare `redis.TimeoutError` on idle streams is a normal idle condition, not
  a crash. Set `socket_timeout = BLOCK_MS/1000 + 5` and catch it explicitly.
- **bash heredocs for CSS/JSX:** always use single-quoted terminators (`'EOF'`) so `$` and
  template literals aren't interpolated. A dropped closing backtick-semicolon in a CSS template
  literal causes esbuild "Unterminated string literal". Validate with esbuild before shipping.
  (Largely irrelevant once working in Claude Code with direct file edits, but kept for reference.)
- **Frontend `.gitignore` matters:** `node_modules/` must be ignored per-package. A missing
  `frontend/.gitignore` once caused the whole dependency tree to be committed.
- **Component/CSS class names must stay in sync.** A real bug shipped because a component used
  `.log-top` / `.log-rail` classes that didn't exist in the stylesheet. When adding a component,
  confirm every class it references exists in CSS.

---

## 7. Environment & tooling

- **Monorepo:** `/media/thierry/TempStorage/AI-IDS/`, public GitHub repo `Thierry5610/AI-IDS`,
  default branch `main`.
- **Hardware:** Ubuntu (kernel 6.8.0-65-generic), Intel i7-6600U dual-core, 16GB RAM, no CUDA;
  WiFi interface `wlp1s0`.
- **Python envs:** system Python (`/usr/bin/python3`) for the eBPF sensor (bcc isn't available in
  a venv); a `.venv` (Python 3.13) at `inference-service/.venv` for everything else; a separate
  `.venv` in `bridge/`.
- **Pinned deps of note:** `shap==0.52.0`, `redis==8.0.0`, `xgboost 3.2.0`.
- **Training:** Kaggle (free GPU, CICIDS2017 hosted). **Deploy:** Azure for Students ($100 credit,
  no card, hard spending cap). **Tracking:** MLflow. **Persistence:** TimescaleDB. **Containers:**
  Docker. **IaC:** Terraform.
- **Telegram:** stdlib `urllib` only (no external library). `.env` in `notifier/` is gitignored
  (bot token + chat id).

---

## 8. Dissertation

- Structure mirrors NGUEPI GNETEDEM Paterson's B.Eng submission from the same department: five
  chapters (General Introduction; Literature Review; Analysis and Design; Implementation and
  Results; Conclusion and Further Works).
- APA author-year citations, chapter-based figure numbering, A4 / Times New Roman 12pt / 1.5 line
  spacing / justified body. No fabricated citations — real, verifiable papers only.
- Completed: Ch.1, Ch.2 (five verified APA refs), Ch.3 (six figure placeholders). Remaining:
  Ch.4 (Implementation and Results), Ch.5 (Conclusion and Further Works), then master-file merge
  and a formatting pass.
- Toolchain: Node `docx` library, validated with `/mnt/skills/public/docx/scripts/office/validate.py`,
  converted to PDF via `soffice --headless --convert-to pdf`.

---

## 9. Superseded decisions (older docs may still say these — they are WRONG now)

If you read an older planning doc in the repo, these early decisions have changed:

| Old doc says | Current truth |
|---|---|
| Three models (RF, XGBoost, CNN-LSTM) | **Five** — adds LightGBM and the Autoencoder |
| Topology auto-builds / dynamic from live traffic | **Passive typed topology only**; active provisioning is future work |
| Oracle Cloud Frankfurt for the Docker stack | Deploy target is **Azure for Students**; Oracle is not the current plan |
| Backend still in active development | Backend is **frozen** at `c02552c` |
| Dashboard described loosely | Seven fixed pages, 1:1 with the rail nav; design locked to Matrix/VIGIL |

When in doubt, this file and `CLAUDE.md` are the source of truth over any older `.md` in the repo.
