# Green Guard AI — Architecture

How the five cloud features fit together, what they cost, and where the
honest limits are.

---

## The shape of it

```
                         ┌──────────────────────────┐
                         │   Flutter app (Android)   │
                         │  one binary, four roles   │
                         └────────────┬─────────────┘
                                      │
      ┌───────────────┬───────────────┼───────────────┬────────────────┐
      │               │               │               │                │
 ┌────▼────┐   ┌──────▼─────┐   ┌─────▼─────┐   ┌─────▼──────┐  ┌──────▼──────┐
 │ TFLite  │   │OpenWeather │   │ Firestore │   │    OSM     │  │  Firebase   │
 │on-device│   │  Map API   │   │  (Spark)  │   │map tiles   │  │    Auth     │
 └─────────┘   └────────────┘   └─────┬─────┘   └────────────┘  └─────────────┘
                                      │
                         ┌────────────┴─────────────┐
                         │                          │
                  ┌──────▼──────┐          ┌────────▼────────┐
                  │ Flutter Web │          │ Python pipeline │
                  │  dashboard  │          │ export + retrain│
                  │  (officers) │          │   (offline)     │
                  └─────────────┘          └─────────────────┘
```

Detection still runs **entirely on-device**. Everything added is additive: with
no signal the app scans, diagnoses and saves history exactly as before.

---

## Roles

One app binary. The `role` field on the user document decides what the third
navigation tab shows.

| Role | Third tab | Can do |
|---|---|---|
| `farmer` | My Cases | Scan, see own history, request expert review |
| `agronomist` | Review Queue | Rule on cases — **only if `verified: true`** |
| `officer` | Dashboard | State surveillance, set intervention status |
| `admin` | Dashboard | Everything, plus promote and verify users |

A role alone never grants power: an agronomist must also be `verified` by an
admin before they can rule on a case, enforced in the UI *and* in
`firestore.rules`. Client-side checks are a convenience, not a control.

---

## Data model

| Collection | Written by | Read by | Purpose |
|---|---|---|---|
| `users/{uid}` | self (limited), admin | all signed-in | profile, role, verification |
| `scans/{id}` | farmer; verdict fields by agronomist | all signed-in | the core record |
| `district_stats/{district}` | clients, atomic increments | all signed-in | map + dashboard rollup |
| `model_feedback/{scanId}` | agronomist on verdict | officers, admin | training samples |
| `interventions/{id}` | officers | all signed-in | department response |
| `model_releases/{version}` | **Admin SDK only** | all signed-in | OTA model updates |

`scans` is deliberately one document doing four jobs — map point, review
subject, dashboard statistic, and training sample. Splitting it would create
dual-write consistency problems for no benefit.

### Privacy

Precise farm coordinates **never leave the device**. `LocationService` keeps
full precision locally for the weather lookup and rounds to 2 decimal places
(~1.1 km) before anything is written to Firestore. The public map is aggregated
to district level and cannot be used to locate a specific field.

---

## Feature notes

### 1. Weather risk (`risk_engine.dart`)

Each disease in `disease_kb.dart` carries an `InfectionWindow` — the
temperature band, humidity threshold and sustained duration that published
extension thresholds say the pathogen needs. The engine walks the 3-hourly
forecast, marks slices inside the window, and looks for unbroken runs long
enough to matter.

Score = 0.40 × infection windows + 0.25 × longest wet stretch + 0.20 ×
temperature fit + 0.15 × rainfall. Weights are named constants so they can be
argued with and tuned against real outbreaks.

Potato late blight additionally honours the **Hutton Criteria** (two
consecutive days, min temp ≥ 10 °C, ≥ 6 h at RH ≥ 90%), the published standard
that blight warning services use.

**The honest limitation:** infection is driven by *leaf wetness*, which no free
weather API reports. We approximate it from relative humidity — the standard
substitution in extension tools, but an approximation. It will miss dew forming
on a clear cold night at moderate RH, and overcall a humid but windy day where
leaves stay dry. This is an advisory that tells a farmer when to go and look,
not a prediction that disease will occur. That caveat is stated in the app, not
just here.

### 2. Hotspot map

`flutter_map` + OpenStreetMap tiles: no API key, no billing account, no
per-load cost. Graduated circles rather than a true choropleth — district
boundary polygons would need a GeoJSON topology in assets, and at state zoom a
graduated circle reads just as clearly.

`hotspotScore` combines case volume with *prevalence* and decays with age.
Raw case count alone would just draw a population map — the districts with the
most farmers would always look worst regardless of actual disease pressure.
A notifiable disease floors the score at 45 regardless of volume.

**The cold-start problem is real.** A live outbreak map needs live users. Until
there are farmers scanning, the map is empty. `HotspotService.seedDemoData()`
writes a plausible state-wide picture for demos; every seeded row carries
`isDemo: true`, is labelled wherever it surfaces, and can be filtered out or
removed with `clearDemoData()`. Run that before any real pilot.

### 3. Expert validation

Farmer submits → case enters a queue ordered **oldest-first** (newest-first
would let a trickle of new cases permanently bury the ones nearest the
deadline) → verified agronomist rules → verdict returns to the farmer and
becomes a training sample.

Verdicts are written in a **transaction** so two agronomists opening the same
case cannot both file a ruling.

**The 24-hour window is a tracked target, not a guarantee.** Software can queue
a case, show a countdown, flag breaches and mark a case expired. It cannot make
a human answer. This feature is only as real as the agronomists actually
recruited to staff it — KVK officers, agri-university staff.
`ExpertService.queueHealth()` exists so that is measured rather than assumed,
and the dashboard says plainly when the queue is under-staffed.

### 4. Officer dashboard

Same codebase, two entry points:

- `lib/main.dart` — the mobile app (dashboard is a role-gated tab)
- `lib/main_web.dart` — browser dashboard only

The split exists because `tflite_flutter` binds the native runtime through
`dart:ffi`, which does not exist on web. Officers never run inference, so the
web build simply never imports `TfService`.

Intervention tracking is keyed by **district + disease**, not by individual
scan — an officer intervenes in a place against a pathogen, not in one farmer's
photo.

### 5. Learning loop

```
agronomist verdict
  → model_feedback document (image + AI label + expert label + model version)
  → export_feedback.py    (Firestore → ImageFolder tree, marks exportedAt)
  → retrain.py            (merge with base, retrain, GATE)
  → model_releases doc
  → ModelUpdateService    (phones download, verify, swap)
```

Two things that make this honest rather than decorative:

**The promotion gate.** A candidate must beat the incumbent on a held-out split
by at least 0.5 percentage points before it can be published. A candidate that
fails is saved as `candidate_rejected.h5` and **not** released. Shipping a worse
model to farmers is worse than shipping no update.

**Corrections are merged, never trained on alone.** Fine-tuning on 50
corrections causes catastrophic forgetting. They are folded into the base
dataset and oversampled ×3.

**What this does NOT mean:** the model does not learn on the device and does not
improve by itself. Expert verdicts accumulate, a human runs a retrain, the gate
decides, and only then does a release appear.

**Where the real gain is.** `retrain.py` replaces the original 3-conv-from-
scratch CNN with a **MobileNetV3-Small backbone pretrained on ImageNet**. At
this data scale that single change will produce a far larger accuracy gain than
any amount of feedback collected in the first year. Under a few hundred expert
samples the feedback's value is *diagnostic* — `export_feedback.py` reports
exactly which classes the model gets wrong — not corrective. Meaningful gains
from feedback need roughly a few hundred samples per weak class, which is many
months of real usage.

---

## Free-tier constraints and what they cost

Everything runs on the Firebase **Spark (free)** plan. Consequences:

| No Cloud… | Consequence | Mitigation in code |
|---|---|---|
| Functions | No server-side aggregation | Clients increment `district_stats` atomically |
| Functions | No FCM push | Firestore realtime listeners for in-app notification |
| Scheduler | No cron to expire cases | `expireOverdueCases()` runs when a reviewer opens the queue |
| Storage | No image bucket | 640 px JPEG q70 (~60–90 KB) as base64 in the scan doc |

**The one genuinely soft spot:** because clients maintain `district_stats`, the
rules must let any signed-in user increment those counters. A malicious user
could inflate a district's case count. This is deliberate and documented at the
top of `firestore.rules` — moving `_bumpDistrictStat` into a Cloud Function
triggered by the scan write closes it, and is the first thing to do on
upgrading to Blaze.

Offline behaviour is not an afterthought: Firestore disk persistence is enabled
before any read or write, `saveScan` returns as soon as the write is queued
locally rather than waiting on the server, and the weather service falls back
to a location-checked disk cache. A farmer on a dead connection still gets an
instant result screen and this morning's advisory.

---

## A correctness fix made along the way

The original `tf_service.dart` derived severity from **model confidence**:

```dart
else if (confidence > 85) severity = "Severe";
```

Confidence measures how sure the *classifier* is, not how sick the *plant* is.
A crisp photo of a mildly infected leaf read as "Severe"; a blurry photo of a
dying one read as "Mild". Since expert validation and the learning loop both
assume the diagnosis is trustworthy, this was load-bearing.

Now `confidence` is model certainty and `ThreatLevel` comes from the knowledge
base — two separate things, shown separately, with a low-certainty result
explicitly telling the farmer not to spend money on it yet.

Also fixed: `List.filled(16, 0.0)` hardcoded the class count. Output size is
now derived from the label map, and labels are sorted numerically (JSON key
order is not guaranteed, and `"10"` sorts before `"2"` as a string — which
would have silently mislabelled every prediction after a retrain).

---

## Accessibility note on the severity palette

The obvious palette for risk is a traffic light. It was measured with the
validator and it fails: amber, orange and red are adjacent hues, and under
deuteranopia or protanopia neighbouring pairs collapsed to a perceptual
distance of 0.7–2.6 (OKLab ΔE ×100, against a floor of 8). A red-green
colourblind officer — roughly 1 in 12 men — could not have told a moderate
district from a severe one.

Severity is an *ordered* scale, so it now uses the colour treatment ordered
data takes: **one hue, light to dark** (L 0.788 / 0.682 / 0.573 / 0.439,
strictly decreasing). Lightness carries the ordering, which survives every form
of colour vision deficiency and greyscale printing. Green is kept out of the
ramp and reserved for "healthy — no disease found", so "green means fine" still
holds. Every use site pairs the colour with a text label.
