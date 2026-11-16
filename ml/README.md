# ML tools

The tooling behind the Reps swing classifier: recording footage, labelling it frame by frame, checking the labels against pose keypoints, and cutting training clips for Create ML. The trained model the app ships with is in [`models/`](models).

Videos, frames, keypoints and labels are **not** in git. They stay local in `ml/data/` (gitignored), or wherever `REPS_ML_DIR` points.

## Pipeline

1. **`tools/compress.py`** takes the raw phone footage from `data/full/`, compresses it to HEVC at up to 1920 px (60 fps for slo-mo), numbers it and moves it into `data/raw/`.
2. **`tools/label.py`** is a frame-by-frame labeller (OpenCV window). You mark the impact frame of every real swing, practice swing and non-swing motion (hard negatives). Then it renames the video to `YYYY-MM-DD_<who>_<angle>_<light>_<n>.mov` and adds it to `data/manifest.csv`.
   - **`tools/label_putt.py`** is the same thing for putting footage (impact, pickup, motion). It is kept apart from the swing data.
3. **`tools/extract/`** is a Swift command-line tool that runs Apple Vision's body-pose request on every frame and writes 13 joints per frame to `data/keypoints/<video>.json`. It uses the same joint order as the iOS app.
4. **`tools/check.py`** makes sure videos, labels and keypoints line up (frame counts, fps, person-found rate). It draws the skeleton over the labelled impact frames into `data/checks/` so misalignment is visible at a glance.
5. **`tools/make_clips.py`** cuts 2-second clips around each impact (`swing/`) and from quiet stretches and hard negatives (`other/`), split into train and val from `data/splits.json`, for Create ML's Action Classifier. The test split is never cut.

## Data layout (local only)

```
data/
  full/        raw phone footage waiting to be compressed
  raw/         compressed, renamed videos
  labels/      <video>.csv: frame, seconds, kind (swing / practice / motion)
  keypoints/   <video>.json: per-frame Vision body pose
  manifest.csv angle, light and fps per video
  splits.json  train / val / test video lists
  createml/    generated training clips
  putting/     putting footage, labels and manifest
```

## Setup

Needs Python 3.14 with [uv](https://docs.astral.sh/uv/), and `ffmpeg` on the PATH (`brew install ffmpeg`).

```sh
cd ml
uv sync
uv run tools/label.py data/raw/IMG_4031.mov

cd tools/extract && swift build -c release
.build/release/extract ../../data/raw/<video>.mov ../../data/keypoints/<video>.json
```
