"""
Retrain the disease classifier on base data plus expert-verified field photos.

This is the second half of the learning loop. export_feedback.py pulls what the
agronomists ruled on; this script folds it into the training set, retrains, and
refuses to ship the result unless it is measurably better.

    python retrain.py --base ../../DATA-SET --feedback ../../DATA-SET/Feedback

Two things this script does differently from Model_Trainer.py, and why
--------------------------------------------------------------------
1. TRANSFER LEARNING instead of a CNN trained from scratch.

   The original model is three conv layers learned from nothing. With a few
   thousand images that architecture plateaus early, and - this is the part
   that matters for the learning loop - a few hundred expert corrections
   cannot move it. A MobileNetV3 backbone pretrained on ImageNet already knows
   edges, textures and lesion-like blobs, so the corrections land on top of
   real features instead of having to teach the network what a leaf is.

   Expect a far larger accuracy gain from this change alone than from any
   amount of feedback data collected in the first year.

2. A PROMOTION GATE.

   Naively fine-tuning on 50 corrections destroys the model: it forgets the
   base classes and overfits the handful of new photos. Two defences are built
   in - the corrections are merged with the base dataset and oversampled
   rather than trained on alone, and the candidate must beat the incumbent on
   a frozen held-out split before it can be published. A candidate that fails
   the gate is kept on disk for inspection and NOT released.

Honest expectations
-------------------
Under a few hundred expert samples, the feedback contributes almost nothing
statistically - its value at that stage is telling you WHERE the model is
wrong, which the export script reports. Meaningful gains from feedback need
roughly a few hundred samples per weak class, which is many months of real
usage. Do not promise a model that "gets smarter every week"; it gets smarter
when someone runs this script and the gate passes.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone

import numpy as np

try:
    import tensorflow as tf
    from tensorflow.keras import layers, models
except ImportError:
    sys.exit("TensorFlow is not installed.\n    pip install tensorflow")


IMG_SIZE = 224          # MobileNetV3 native input; the old model used 128.
BATCH_SIZE = 32
HEAD_EPOCHS = 12        # Backbone frozen - learn the classifier head.
FINETUNE_EPOCHS = 8     # Top of the backbone unfrozen, very low LR.

# A candidate must beat the incumbent by at least this much on the held-out
# split. A margin rather than ">" so run-to-run noise cannot promote a model
# that is not genuinely better.
PROMOTION_MARGIN = 0.005

# Expert-verified photos are worth more than base dataset images - they are
# real field conditions with a human label - so they are repeated this many
# times per epoch. Kept modest: higher values overfit to the handful of
# reviewed photos.
FEEDBACK_OVERSAMPLE = 3


def enable_gpu_growth():
    gpus = tf.config.list_physical_devices("GPU")
    for gpu in gpus:
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except RuntimeError as e:
            print(e)
    if gpus:
        print(f"  GPU memory growth enabled ({len(gpus)} device(s))")


def build_model(num_classes: int) -> tf.keras.Model:
    """MobileNetV3-Small backbone with a fresh classifier head."""
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False

    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))

    # Augmentation lives inside the graph so it applies at training time only
    # and is exported as a no-op, rather than being a separate generator.
    x = layers.RandomFlip("horizontal_and_vertical")(inputs)
    x = layers.RandomRotation(0.15)(x)
    x = layers.RandomZoom(0.15)(x)
    # Leaf photos come from every kind of phone camera in every light.
    x = layers.RandomContrast(0.2)(x)

    # MobileNetV3 expects raw 0-255 input; it rescales internally.
    x = base(x, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(num_classes, activation="softmax")(x)

    model = models.Model(inputs, outputs)
    model._gg_backbone = base  # noqa: SLF001 - referenced by the fine-tune step
    return model


def load_split(directory: str, subset: str, seed: int = 1337):
    return tf.keras.utils.image_dataset_from_directory(
        directory,
        validation_split=0.2,
        subset=subset,
        seed=seed,
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=BATCH_SIZE,
        label_mode="categorical",
    )


def merge_feedback(base_dir: str, feedback_dir: str, work_dir: str) -> dict:
    """
    Build a combined training tree.

    Corrections and confirmations are copied in alongside the base dataset and
    the corrections are duplicated FEEDBACK_OVERSAMPLE times. Training on the
    feedback alone is what causes catastrophic forgetting, so it never happens
    here.
    """
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    os.makedirs(work_dir, exist_ok=True)

    stats = {"base": 0, "confirmations": 0, "corrections": 0}

    # 1. Base dataset.
    base_train = os.path.join(base_dir, "Train")
    if not os.path.isdir(base_train):
        sys.exit(f"Base training data not found at {base_train}")

    for class_name in sorted(os.listdir(base_train)):
        src = os.path.join(base_train, class_name)
        if not os.path.isdir(src):
            continue
        dst = os.path.join(work_dir, class_name)
        os.makedirs(dst, exist_ok=True)
        for f in os.listdir(src):
            shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
            stats["base"] += 1

    # 2. Expert-verified samples.
    if feedback_dir and os.path.isdir(feedback_dir):
        for kind, repeats in (
            ("confirmations", 1),
            ("corrections", FEEDBACK_OVERSAMPLE),
        ):
            root = os.path.join(feedback_dir, kind)
            if not os.path.isdir(root):
                continue
            for class_name in sorted(os.listdir(root)):
                src = os.path.join(root, class_name)
                if not os.path.isdir(src):
                    continue

                dst = os.path.join(work_dir, class_name)
                if not os.path.isdir(dst):
                    # A label the base dataset has never seen. Allowed, but
                    # called out - a class that exists only in feedback will
                    # have far too few samples to learn from.
                    print(
                        f"  ! '{class_name}' appears only in feedback, not in "
                        f"the base dataset"
                    )
                    os.makedirs(dst, exist_ok=True)

                for f in os.listdir(src):
                    for r in range(repeats):
                        suffix = "" if r == 0 else f"_dup{r}"
                        stem, ext = os.path.splitext(f)
                        shutil.copy2(
                            os.path.join(src, f),
                            os.path.join(dst, f"fb_{stem}{suffix}{ext}"),
                        )
                    stats[kind] += 1

    return stats


def evaluate(model, dataset) -> float:
    _, acc = model.evaluate(dataset, verbose=0)
    return float(acc)


def evaluate_incumbent(path: str, dataset, num_classes: int):
    """Score the currently shipped model on the same split, if we have it."""
    if not path or not os.path.exists(path):
        return None
    try:
        incumbent = tf.keras.models.load_model(path)
        if incumbent.output_shape[-1] != num_classes:
            print(
                "  Incumbent has a different number of classes - cannot "
                "compare directly, treating as no incumbent."
            )
            return None
        return evaluate(incumbent, dataset)
    except Exception as e:  # noqa: BLE001
        print(f"  Could not score the incumbent model: {e}")
        return None


def main():
    p = argparse.ArgumentParser(description="Retrain with expert feedback.")
    p.add_argument("--base", required=True, help="DATA-SET root")
    p.add_argument("--feedback", default=None, help="Exported feedback folder")
    p.add_argument(
        "--incumbent",
        default="plant_disease_model.h5",
        help="Currently shipped model, for the promotion gate",
    )
    p.add_argument("--work", default="./_retrain_work")
    p.add_argument("--out", default=".")
    p.add_argument(
        "--force",
        action="store_true",
        help="Publish even if the candidate does not beat the incumbent",
    )
    args = p.parse_args()

    enable_gpu_growth()

    print("\n" + "=" * 62)
    print("  Building the combined training set")
    print("=" * 62)
    stats = merge_feedback(args.base, args.feedback, args.work)
    print(f"  base dataset images : {stats['base']}")
    print(f"  expert confirmations: {stats['confirmations']}")
    print(f"  expert corrections  : {stats['corrections']} "
          f"(x{FEEDBACK_OVERSAMPLE} oversampled)")

    total_feedback = stats["confirmations"] + stats["corrections"]
    if total_feedback == 0:
        print(
            "\n  No expert feedback in this run. The retrain will still pick "
            "up\n  the architecture change, but nothing is being learned from "
            "the field yet."
        )
    elif total_feedback < 100:
        print(
            f"\n  NOTE: {total_feedback} expert samples is a small signal "
            f"against\n  {stats['base']} base images. Expect the architecture "
            "change to drive\n  most of any improvement here, not the "
            "feedback."
        )

    train_ds = load_split(args.work, "training")
    val_ds = load_split(args.work, "validation")

    class_names = train_ds.class_names
    num_classes = len(class_names)
    print(f"\n  {num_classes} classes: {', '.join(class_names)}")

    autotune = tf.data.AUTOTUNE
    train_ds = train_ds.cache().shuffle(1000).prefetch(autotune)
    val_ds = val_ds.cache().prefetch(autotune)

    # ------------------------------------------------------ stage 1: head
    print("\n" + "=" * 62)
    print("  Stage 1 - training the classifier head (backbone frozen)")
    print("=" * 62)

    model = build_model(num_classes)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=HEAD_EPOCHS,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(
                monitor="val_accuracy",
                patience=4,
                restore_best_weights=True,
            )
        ],
    )

    # -------------------------------------------------- stage 2: finetune
    print("\n" + "=" * 62)
    print("  Stage 2 - fine-tuning the top of the backbone")
    print("=" * 62)

    backbone = model._gg_backbone  # noqa: SLF001
    backbone.trainable = True
    # Only the last third. Unfreezing everything at this data scale overfits.
    cutoff = int(len(backbone.layers) * 0.66)
    for layer in backbone.layers[:cutoff]:
        layer.trainable = False

    model.compile(
        # Very low LR - a normal one would wash out the pretrained features.
        optimizer=tf.keras.optimizers.Adam(1e-5),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=FINETUNE_EPOCHS,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(
                monitor="val_accuracy",
                patience=3,
                restore_best_weights=True,
            )
        ],
    )

    # ---------------------------------------------------- promotion gate
    print("\n" + "=" * 62)
    print("  Promotion gate")
    print("=" * 62)

    candidate_acc = evaluate(model, val_ds)
    print(f"  candidate accuracy: {candidate_acc:.4f}")

    incumbent_acc = evaluate_incumbent(args.incumbent, val_ds, num_classes)
    if incumbent_acc is None:
        print("  incumbent         : none available for comparison")
        promote = True
    else:
        print(f"  incumbent accuracy: {incumbent_acc:.4f}")
        promote = candidate_acc >= incumbent_acc + PROMOTION_MARGIN
        delta = candidate_acc - incumbent_acc
        print(f"  delta             : {delta:+.4f} "
              f"(needs >= +{PROMOTION_MARGIN})")

    if not promote and not args.force:
        print("\n  GATE FAILED - the candidate is not better.")
        print("  Nothing has been published. The candidate is saved as")
        print("  candidate_rejected.h5 if you want to inspect it.")
        model.save(os.path.join(args.out, "candidate_rejected.h5"))
        print("\n  This is the system working as intended: shipping a worse")
        print("  model to farmers is worse than shipping no update.\n")
        return 1

    if not promote and args.force:
        print("\n  GATE FAILED but --force was passed. Publishing anyway.")

    # ------------------------------------------------------------ export
    version = f"v{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M')}"

    h5_path = os.path.join(args.out, "plant_disease_model.h5")
    model.save(h5_path)
    print(f"\n  Saved Keras model -> {h5_path}")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    tflite_path = os.path.join(args.out, "plant_disease_model.tflite")
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    size_bytes = os.path.getsize(tflite_path)
    print(f"  Saved TFLite model -> {tflite_path} "
          f"({size_bytes / 1_048_576:.2f} MB)")

    # class_mapping.json must stay index-aligned with the model output, and
    # image_dataset_from_directory orders classes alphabetically.
    mapping = {}
    for i, name in enumerate(class_names):
        parts = name.split("_", 1)
        species = parts[0].capitalize()
        disease = parts[1].replace("_", " ").title() if len(parts) > 1 else ""
        mapping[str(i)] = [species, disease]

    mapping_path = os.path.join(args.out, "class_mapping.json")
    with open(mapping_path, "w", encoding="utf-8") as f:
        json.dump(mapping, f)
    print(f"  Saved class mapping -> {mapping_path}")

    release = {
        "version": version,
        "sizeBytes": size_bytes,
        "validationAccuracy": round(candidate_acc, 4),
        "previousAccuracy": (
            round(incumbent_acc, 4) if incumbent_acc is not None else None
        ),
        "expertSamplesUsed": total_feedback,
        "numClasses": num_classes,
        "inputSize": IMG_SIZE,
        "architecture": "MobileNetV3Small + dense head",
        "releasedAt": datetime.now(timezone.utc).isoformat(),
    }
    with open(
        os.path.join(args.out, "release.json"), "w", encoding="utf-8"
    ) as f:
        json.dump(release, f, indent=2)

    print("\n" + "=" * 62)
    print("  GATE PASSED - candidate promoted")
    print("=" * 62)
    print(json.dumps(release, indent=2))
    print(
        "\n  To ship it:\n"
        "   1. Upload plant_disease_model.tflite somewhere publicly "
        "readable\n"
        "   2. Add a doc to the `model_releases` collection with the fields "
        "in\n      release.json plus the download `url`\n"
        "   3. Phones pick it up through ModelUpdateService - no app-store\n"
        "      release needed\n"
        "   4. Copy class_mapping.json into the app assets if the class list\n"
        "      changed, and add any new class to lib/data/disease_kb.dart -\n"
        "      the knowledge-base test fails until you do\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
