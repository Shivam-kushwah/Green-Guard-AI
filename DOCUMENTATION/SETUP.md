# Green Guard AI — Setup

What you must do before the five cloud features work. Roughly 30 minutes.

---

## 1. Enable Firestore (required — everything depends on it)

The project `green-guard-efb41` already has Auth. It does **not** have a
database yet.

1. [Firebase console](https://console.firebase.google.com/) → your project
2. **Build → Firestore Database → Create database**
3. Choose **Production mode** (the rules below replace the defaults)
4. Location: **asia-south1 (Mumbai)** — lowest latency for Maharashtra users

Then deploy the rules:

```bash
npm install -g firebase-tools
firebase login
cd D:\Projects\Green-Guard-AI
firebase deploy --only firestore:rules
```

If `firebase init` asks, point it at the existing project and accept
`firestore.rules` as the rules file.

### Composite indexes

Firestore will ask for these the first time each query runs — the error in the
console log contains a direct "create index" link, which is the easiest path.
Click it for each of:

| Collection | Fields |
|---|---|
| `scans` | `uid` ASC, `createdAt` DESC |
| `scans` | `reviewStatus` ASC, `reviewRequestedAt` ASC |
| `scans` | `expertUid` ASC, `reviewedAt` DESC |
| `scans` | `district` ASC, `createdAt` DESC |

---

## 2. OpenWeatherMap key (feature 1)

1. Sign up at [openweathermap.org/api](https://openweathermap.org/api) — free,
   no card required
2. Copy the key from **My API keys**
3. A new key takes **1–2 hours to activate**; until then you get 401s

Run with it:

```bash
flutter run --dart-define=OWM_API_KEY=your_key_here
```

We use the free `/weather` and `/forecast` endpoints only. One Call 3.0 would
give hourly data and suit the risk engine better, but it requires a payment
method even inside its free allowance.

> A key compiled into an APK is extractable by anyone who unzips it. Fine for a
> demo; before public release the weather call should move behind a proxy.

---

## 3. Create the demo accounts (features 3 and 4)

Roles cannot be self-assigned — that is enforced in the rules, or any farmer
could promote themselves to agronomist and start ruling on cases. Set them by
hand in the Firestore console.

1. Sign in to the app with each Google account you want to use. That creates
   `users/{uid}` with `role: "farmer"`.
2. In the console, open `users/{uid}` and edit:

**For an agronomist** — both fields are required, the role alone is not enough:
```
role:           "agronomist"
verified:       true
qualification:  "M.Sc. Plant Pathology"
institution:    "KVK Kolhapur"
```

**For an officer:**
```
role:     "officer"
district: "Pune"
```

Restart is not needed — `Session` listens live and the navigation updates in
place.

---

## 4. Seed the map for a demo (feature 2)

A live outbreak map needs live users. For a demo:

**Profile tab → "Seed demo outbreak data"** (debug builds only — the control is
compiled out of release builds entirely).

This writes a plausible state-wide picture that follows real Maharashtra crop
geography — red rot in the sugarcane belt, rusts in the wheat districts. Every
row carries `isDemo: true`, is labelled wherever it appears, and the dashboard
can filter it out.

**Before any real pilot, run "Clear demo data".** No seeded number should ever
reach an officer's dashboard unlabelled.

---

## 5. Officer web dashboard (feature 4)

The web build needs its own Firebase registration — `google-services.json`
covers Android only.

1. Console → **Project settings → Your apps → Add app → Web**
2. Copy the config values, then:

```bash
cd CODE/frontend
flutter build web -t lib/main_web.dart --release \
  --dart-define=FB_API_KEY=... \
  --dart-define=FB_APP_ID=... \
  --dart-define=FB_SENDER_ID=... \
  --dart-define=FB_PROJECT_ID=green-guard-efb41

firebase deploy --only hosting
```

Build with the wrong entry point and it fails on `dart:ffi` — that is expected.
`-t lib/main_web.dart` is not optional; see ARCHITECTURE.md.

If the config is missing the page renders an explicit error telling you which
defines to pass, rather than an opaque Firebase exception.

---

## 6. Learning loop (feature 5)

Only worth running once agronomists have ruled on a meaningful number of cases.

### Export what the experts labelled

```bash
pip install firebase-admin pillow tensorflow

# Console → Project settings → Service accounts → Generate new private key
# Save as serviceAccountKey.json (already gitignored — it is a full-access key)

cd CODE/Model-Training
python export_feedback.py --creds serviceAccountKey.json \
                          --out ../../DATA-SET/Feedback --dry-run
```

`--dry-run` reports what would be exported without writing or marking anything.
It also prints **where the model is going wrong**, which is the useful output
long before there is enough data to retrain on.

Drop `--dry-run` to actually export.

### Retrain

```bash
python retrain.py --base ../../DATA-SET --feedback ../../DATA-SET/Feedback
```

This swaps the from-scratch CNN for a MobileNetV3 backbone, merges the
corrections with the base dataset, and **refuses to publish unless the
candidate beats the incumbent** on a held-out split. A rejected candidate is
saved for inspection and not released. That is the system working correctly.

### Ship it

1. Upload `plant_disease_model.tflite` somewhere publicly readable
2. Add a document to `model_releases` using the fields in `release.json`, plus
   a `url`
3. Phones pick it up via `ModelUpdateService` — no app-store release needed

If the class list changed, copy the new `class_mapping.json` into
`assets/model/` **and add every new class to `lib/data/disease_kb.dart`**. The
knowledge-base test fails until you do, which is deliberate — a class with no
agronomic facts would reach a farmer with no treatment advice.

---

## Verify

```bash
cd CODE/frontend
flutter analyze     # expect 0 errors
flutter test        # expect 57 passing
flutter run --dart-define=OWM_API_KEY=your_key
```

## Checklist

- [ ] Firestore created in asia-south1
- [ ] `firebase deploy --only firestore:rules`
- [ ] Composite indexes created (follow the console links)
- [ ] OWM key obtained and activated
- [ ] One agronomist account with `verified: true`
- [ ] One officer account
- [ ] Demo data seeded (and a plan to clear it)
- [ ] Web app registered if the browser dashboard is needed
