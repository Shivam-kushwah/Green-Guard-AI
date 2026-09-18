# 🌱 Green-Guard-AI

### Crop disease detection and outbreak surveillance for Maharashtra

Green-Guard-AI detects plant leaf diseases on-device with a TensorFlow Lite
model, then adds the layer that makes a detection actually useful: weather-based
outbreak risk, a district-level hotspot map, expert confirmation by verified
agronomists, a surveillance dashboard for agriculture officers, and a feedback
loop from expert verdicts back into the model.

**Detection still runs entirely offline.** Every cloud feature degrades
gracefully — with no signal the app scans, diagnoses and saves history exactly
as it always did.

---

## 🚀 Features

**On-device detection**
- 🌿 Plant disease classification from camera or gallery
- ⚡ TensorFlow Lite inference, no internet required
- 📂 Local scan history (Hive)
- 🧠 Separate **model certainty** and **disease threat level** — a confident
  classifier and a dangerous disease are two different things, and a
  low-certainty result says so rather than inviting a wasted spray

**Weather risk forecasting**
- 🌦 5-day outbreak risk per disease, from OpenWeatherMap
- 📊 Scored against published infection thresholds — temperature band, humidity
  threshold, sustained hours — not invented numbers
- 🥔 Hutton Criteria for potato late blight, the official blight-warning trigger
- 💬 Explains *why* in plain language, and states its own limits

**Geospatial hotspot map**
- 🗺 District-level outbreak map for all 36 Maharashtra districts
- 🆓 OpenStreetMap tiles — no API key, no billing account
- 📈 Ranked by prevalence and recency, not raw case count
- 🔒 Farm coordinates rounded to ~1.1 km before upload; exact location never
  leaves the phone

**Expert validation**
- 👨‍🌾 Send a case to a verified agronomist
- ⏱ 24-hour target with a live countdown and breach tracking
- ✅ Confirm or correct, with advice returned to the farmer
- 📋 Queue health is measured, so under-staffing is visible rather than assumed

**Officer dashboard**
- 📊 State-wide case counts, infection rate, district coverage
- 📉 Disease trend over time, crop-wise breakdown, district ranking
- 🚨 Intervention worklist with status tracking per district and disease
- 🌐 Runs in a browser (Flutter Web) from the same codebase

**Learning loop**
- 🔁 Every expert verdict becomes a labelled training sample
- 🎯 Dashboard shows accuracy against expert ground truth on *real field
  photos*, not just the curated test split
- 🧪 Retraining pipeline with a **promotion gate** — a candidate that is not
  measurably better is never published
- 📲 Over-the-air model updates, no app-store release needed

---

## 📁 Project structure

```
Green-Guard-AI/
├── CODE/
│   ├── frontend/                 Flutter app (mobile + web dashboard)
│   │   ├── lib/
│   │   │   ├── config/           build-time configuration
│   │   │   ├── data/             disease knowledge base, district reference
│   │   │   ├── model/            domain models
│   │   │   ├── screens/          UI
│   │   │   ├── services/         inference, weather, risk, cloud, experts
│   │   │   ├── widgets/
│   │   │   ├── main.dart         mobile entry point
│   │   │   └── main_web.dart     officer dashboard entry point
│   │   └── test/                 57 tests
│   └── Model-Training/
│       ├── Model_Trainer.py      original from-scratch CNN
│       ├── export_feedback.py    Firestore → training folder
│       └── retrain.py            transfer learning + promotion gate
├── DOCUMENTATION/
│   ├── ARCHITECTURE.md           how it fits together, and the honest limits
│   └── SETUP.md                  what to configure before it works
├── firestore.rules               security rules
└── SampleTest/
```

---

## ⚡ Quick start

```bash
git clone https://github.com/Shivam-kushwah/Green-Guard-AI.git
cd Green-Guard-AI/CODE/frontend
flutter pub get
flutter run --dart-define=OWM_API_KEY=your_openweathermap_key
```

Detection works immediately. The cloud features need Firestore enabled and a
couple of accounts set up — **see [DOCUMENTATION/SETUP.md](DOCUMENTATION/SETUP.md)**
(about 30 minutes).

Officer dashboard in a browser:

```bash
flutter build web -t lib/main_web.dart --release \
  --dart-define=FB_API_KEY=... --dart-define=FB_APP_ID=... \
  --dart-define=FB_SENDER_ID=... --dart-define=FB_PROJECT_ID=green-guard-efb41
```

---

## 🧪 Tests

```bash
flutter test      # 57 passing
flutter analyze   # 0 errors
```

Covers the risk engine against real agronomic thresholds, hotspot scoring, SLA
arithmetic, review state transitions, intervention prioritisation, and
knowledge-base integrity. The KB test **fails deliberately** if the model is
retrained with a class that has no agronomic facts — a disease with no
treatment advice must not reach a farmer.

---

## 🌾 Dataset

Not in the repo (≈2 GB). Structure:

```
DATA-SET/
  Train/        Validation/
    CORN_Rust/    ...
    Potato_Late_Blight/
```

Current model: 16 classes across Corn, Potato, Sugarcane, Wheat, plus generic
healthy / powdery / rust.

---

## ⚠️ Known limits

Stated plainly, because a surveillance tool that oversells itself is worse than
one that does not exist:

- **Weather risk is an advisory, not a prediction.** Infection is driven by leaf
  wetness, which no free weather API measures; we approximate it from humidity.
- **The hotspot map needs users.** With none, it is empty. Demo data exists for
  presentations and is labelled as such everywhere it appears.
- **The 24-hour expert window is a target, not a guarantee.** Code cannot make a
  human answer. The feature is only as real as the agronomists recruited.
- **The model does not improve by itself.** Verdicts accumulate, a person runs a
  retrain, a gate decides. Meaningful gains from feedback need hundreds of
  samples per weak class — many months of real usage. The largest near-term
  accuracy gain comes from the transfer-learning architecture change in
  `retrain.py`, not from feedback volume.
- **Running on Firebase Spark (free).** District aggregates are maintained
  client-side, so a malicious user could inflate a case count. Documented in
  `firestore.rules`; fixed by moving to a Cloud Function on the Blaze plan.

---

## 📄 License

See [LICENSE](LICENSE).
