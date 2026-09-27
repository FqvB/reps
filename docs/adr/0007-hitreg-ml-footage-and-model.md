# 0007 — hitreg-ml is the footage, ground-truth and model source

- Status: Accepted
- Date: 2026-09-27

## Context
Footage, labels and a trained Create ML classifier already exist in the sibling repo `hitreg-ml` (Python 3.14 + uv, PyTorch, coremltools, OpenCV).

## Decision
- Footage and ground truth stay in hitreg-ml, not in this repo:
  - `data/raw/` holds the videos
  - `data/labels/*.csv` has `frame,seconds,kind` rows, with kind swing/practice/motion
  - `data/manifest.csv` records angle, light and fps
  - `data/splits.json` has 40 train / 13 val / 22 test
  - `data/keypoints/` has 2D Vision pose with 13 joints
- DetectorEval (#3) reads them through `REPS_ML_DIR`, defaulting to `~/Documents/Programming/GitHub/hitreg-ml`. It scores only the **test** split, which was never used for training.
- `motion` rows are re-tee, pickup and rake events: ball gone, no swing. They must never count, and they serve as the hard negatives.
- The app ships a copy of the model at `ml/models/SwingClassifier_hitreg_ml1.mlmodel`. A newer model gets a new suffix.
- The swing classifier is the Create ML action classifier from `export/hitreg_ml.mlproj` (swing vs other, 2 s @ 30 fps). Practice swings are labelled swing on purpose. The ball gate separates them (ADR 0002).
- The pose schema in the app matches hitreg-ml's extractor (same 13 joints, `[x, y, confidence]`), so the app's buffers and the training data stay compatible.
- The own model (#30) is trained in hitreg-ml with PyTorch via uv, and exported with coremltools.

## Consequences
One place for all ML data and training. The app repo stays small. The eval depends on a sibling checkout existing locally, which is fine since there's no CI (ADR 0005).
