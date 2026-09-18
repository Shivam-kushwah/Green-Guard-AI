"""
Pull expert-verified field photos out of Firestore into a training folder.

This is the first half of the learning loop. Every time an agronomist confirms
or corrects a diagnosis in the app, a document lands in `model_feedback`
carrying the photo and the expert's label. This script turns those documents
into an ImageFolder tree that retrain.py can consume.

Usage
-----
    pip install firebase-admin pillow
    python export_feedback.py --creds serviceAccountKey.json --out ../../DATA-SET/Feedback

    # Preview without writing or marking anything:
    python export_feedback.py --creds key.json --out ./tmp --dry-run

    # Re-export samples already used in a previous run:
    python export_feedback.py --creds key.json --out ./tmp --include-exported

Getting the credentials
-----------------------
Firebase console -> Project settings -> Service accounts -> Generate new
private key. That file is a full-access admin credential: keep it out of git.
`.gitignore` already covers *serviceAccountKey*.json.

What it writes
--------------
    <out>/
        corrections/          <- expert overturned the AI. The valuable ones.
            potato_late_blight/
            wheat_yellow_rust/
        confirmations/        <- expert agreed. Needed to measure precision.
            corn_rust/
        manifest.json         <- provenance for every exported image

Samples are marked `exportedAt` in Firestore once written, so the same photo is
not silently counted twice across retrains. --dry-run skips that.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    sys.exit(
        "firebase-admin is not installed.\n"
        "    pip install firebase-admin pillow"
    )

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is not installed.\n    pip install pillow")


COLLECTION = "model_feedback"


def slugify(species: str, disease: str) -> str:
    """Match the DiseaseInfo.key format used by the app."""
    return f"{species}_{disease}".lower().replace(" ", "_")


def connect(creds_path: str):
    if not os.path.exists(creds_path):
        sys.exit(f"Credentials file not found: {creds_path}")
    cred = credentials.Certificate(creds_path)
    firebase_admin.initialize_app(cred)
    return firestore.client()


def export(args) -> int:
    db = connect(args.creds)

    query = db.collection(COLLECTION)
    if not args.include_exported:
        # Only samples no previous retrain has consumed.
        query = query.where("exportedAt", "==", None)

    docs = list(query.limit(args.limit).stream())
    if not docs:
        print("No new expert-labelled samples to export.")
        print(
            "The loop fills up as agronomists rule on cases - if this is "
            "empty, the bottleneck is reviewer capacity, not this script."
        )
        return 0

    corrections_dir = os.path.join(args.out, "corrections")
    confirmations_dir = os.path.join(args.out, "confirmations")

    manifest = []
    label_counts = Counter()
    correction_counts = Counter()
    skipped = 0
    written = 0

    for doc in docs:
        d = doc.to_dict() or {}

        image_b64 = d.get("imageBase64")
        if not image_b64:
            skipped += 1
            continue

        true_species = d.get("trueSpecies")
        true_disease = d.get("trueDisease")
        if not true_species or not true_disease:
            # An expert verdict with no label is unusable as ground truth.
            skipped += 1
            continue

        is_correction = bool(d.get("isCorrection"))
        label = slugify(true_species, true_disease)

        root = corrections_dir if is_correction else confirmations_dir
        target_dir = os.path.join(root, label)

        try:
            raw = base64.b64decode(image_b64)
            img = Image.open(io.BytesIO(raw)).convert("RGB")
        except Exception as e:  # noqa: BLE001 - one bad row must not stop the run
            print(f"  ! could not decode {doc.id}: {e}")
            skipped += 1
            continue

        filename = f"{doc.id}.jpg"
        if not args.dry_run:
            os.makedirs(target_dir, exist_ok=True)
            img.save(os.path.join(target_dir, filename), "JPEG", quality=92)

        label_counts[label] += 1
        if is_correction:
            correction_counts[d.get("aiLabel", "unknown")] += 1
        written += 1

        manifest.append(
            {
                "id": doc.id,
                "file": os.path.join(
                    "corrections" if is_correction else "confirmations",
                    label,
                    filename,
                ),
                "trueLabel": label,
                "aiLabel": d.get("aiLabel"),
                "aiConfidence": d.get("aiConfidence"),
                "isCorrection": is_correction,
                "modelVersion": d.get("modelVersion"),
                "district": d.get("district"),
                "expertUid": d.get("expertUid"),
                "expertInstitution": d.get("expertInstitution"),
                "imageSize": list(img.size),
            }
        )

    if not args.dry_run:
        os.makedirs(args.out, exist_ok=True)
        with open(
            os.path.join(args.out, "manifest.json"), "w", encoding="utf-8"
        ) as f:
            json.dump(
                {
                    "exportedAt": datetime.now(timezone.utc).isoformat(),
                    "count": len(manifest),
                    "samples": manifest,
                },
                f,
                indent=2,
            )

        # Mark consumed only after everything is safely on disk.
        batch = db.batch()
        stamp = datetime.now(timezone.utc)
        for i, doc in enumerate(docs, start=1):
            batch.update(doc.reference, {"exportedAt": stamp})
            if i % 400 == 0:  # Firestore caps a batch at 500 writes.
                batch.commit()
                batch = db.batch()
        batch.commit()

    # ---------------------------------------------------------------- report
    print()
    print("=" * 62)
    print(f"  Exported {written} expert-labelled samples"
          f"{' (DRY RUN - nothing written)' if args.dry_run else ''}")
    if skipped:
        print(f"  Skipped {skipped} unusable rows (no image or no label)")
    print("=" * 62)

    total_corrections = sum(correction_counts.values())
    print(f"\n  Corrections : {total_corrections}")
    print(f"  Confirmations: {written - total_corrections}")

    if written:
        agreement = (written - total_corrections) / written
        print(f"\n  Model agreed with the expert on {agreement:.0%} of cases.")
        print("  (This is accuracy on real field photos, which is the number")
        print("   that matters - not the accuracy on the curated test split.)")

    if correction_counts:
        print("\n  Where the model is going wrong (its label -> how often):")
        for ai_label, n in correction_counts.most_common(10):
            print(f"    {ai_label:<34} {n}")

    print("\n  Samples per true label:")
    thin = []
    for label, n in sorted(label_counts.items(), key=lambda kv: -kv[1]):
        print(f"    {label:<34} {n}")
        if n < 20:
            thin.append(label)

    if thin:
        print(
            "\n  NOTE: these classes have under 20 samples, which is far too "
            "few\n  to move a classifier. They will be merged with the base "
            "dataset\n  rather than trained on alone:"
        )
        for label in thin:
            print(f"    - {label}")

    print(f"\n  Next: python retrain.py --feedback {args.out}\n")
    return written


def main():
    p = argparse.ArgumentParser(
        description="Export expert-verified samples from Firestore."
    )
    p.add_argument("--creds", required=True, help="Service account JSON path")
    p.add_argument("--out", required=True, help="Output folder")
    p.add_argument(
        "--limit", type=int, default=5000, help="Max samples to pull"
    )
    p.add_argument(
        "--include-exported",
        action="store_true",
        help="Also re-export samples already used in a previous retrain",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would be exported without writing or marking",
    )
    args = p.parse_args()
    export(args)


if __name__ == "__main__":
    main()
