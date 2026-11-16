"""
make_clips.py — cut the labelled videos into 2-second clips for Create ML's Action Classifier.

Usage:
    uv run tools/make_clips.py

Reads data/splits.json and data/labels/*.csv and writes:

    data/createml/train/swing/<video>_swing_<frame>.mp4     impact at 1.3 s into the clip
    data/createml/train/other/<video>_other_<start>.mp4     2 s with no swing anywhere near
    data/createml/val/swing/...                              same, from the val split
    data/createml/val/other/...

Test-split videos are never cut — they stay untouched for evaluate.py later.
Practice swings go into swing/ on purpose: the app's ball-absence check is what
separates them from real shots, so the classifier only has to see "a swing".
Rows labelled `motion` (fidgeting, re-teeing, raking a ball over — anything that
is NOT a swing but might look like one) get a 2 s clip centred on the mark and
go into other/ as hard negatives.

Every clip is re-encoded at 30 fps, 720 px tall, no audio. Create ML wants a
consistent frame rate, and re-encoding makes the cuts frame-accurate (stream
copying cuts only at keyframes, which can be a second away).

Needs ffmpeg on the PATH.
"""

import csv
import json
import shutil
import subprocess
import sys
from pathlib import Path

project_folder = Path(__file__).resolve().parent.parent
raw_folder = project_folder / "data" / "raw"
labels_folder = project_folder / "data" / "labels"
createml_folder = project_folder / "data" / "createml"
splits_path = project_folder / "data" / "splits.json"

CLIP_SECONDS = 2.0
IMPACT_OFFSET_SECONDS = 1.3          # where the impact sits inside a swing clip
CLIP_FPS = 30
CLIP_HEIGHT = 720
NEGATIVE_KEEPOUT_SECONDS = 2.0       # a negative clip must stay this far from any impact
NEGATIVES_PER_VIDEO = 3


def probe(video_path):
    """Duration in seconds and the video's frame rate, via ffprobe."""
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=r_frame_rate:format=duration", "-of", "json", str(video_path)],
        capture_output=True, text=True, check=True,
    )
    info = json.loads(result.stdout)
    numerator, denominator = info["streams"][0]["r_frame_rate"].split("/")
    return float(info["format"]["duration"]), float(numerator) / float(denominator)


def cut_clip(video_path, start_seconds, output_path):
    """Re-encode one 2 s window starting at start_seconds."""
    if output_path.exists():
        return
    command = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-ss", f"{start_seconds:.3f}", "-i", str(video_path),
        "-t", f"{CLIP_SECONDS:.3f}",
        "-vf", f"scale=-2:{CLIP_HEIGHT},fps={CLIP_FPS}",
        "-c:v", "libx264", "-crf", "20", "-preset", "fast", "-pix_fmt", "yuv420p",
        "-an", "-movflags", "+faststart",
        str(output_path),
    ]
    subprocess.run(command, check=True)


def load_labels(video_stem):
    """Every labelled row in one video as (frame, seconds, kind)."""
    labels_path = labels_folder / (video_stem + ".csv")
    if not labels_path.exists():
        return []
    with open(labels_path, newline="") as labels_file:
        return [(int(row["frame"]), float(row["seconds"]), row["kind"]) for row in csv.DictReader(labels_file)]


def negative_start_times(duration, impact_times):
    """Start times of up to NEGATIVES_PER_VIDEO windows that don't come near any impact."""
    candidates = []
    step = 0.5
    start = 0.0
    while start + CLIP_SECONDS <= duration:
        window_end = start + CLIP_SECONDS
        too_close = any(
            (impact - NEGATIVE_KEEPOUT_SECONDS) < window_end and (impact + NEGATIVE_KEEPOUT_SECONDS) > start
            for impact in impact_times
        )
        if not too_close:
            candidates.append(round(start, 3))
        start += step

    # Spread the picks across the video instead of taking the first three.
    if len(candidates) <= NEGATIVES_PER_VIDEO:
        return candidates
    picks = []
    for i in range(NEGATIVES_PER_VIDEO):
        picks.append(candidates[i * (len(candidates) - 1) // (NEGATIVES_PER_VIDEO - 1)])
    return sorted(set(picks))


def main():
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        print("ffmpeg/ffprobe not found:  brew install ffmpeg")
        sys.exit(1)

    with open(splits_path) as splits_file:
        splits = json.load(splits_file)

    totals = {"train": {"swing": 0, "other": 0}, "val": {"swing": 0, "other": 0}}

    for split_name in ("train", "val"):
        for class_name in ("swing", "other"):
            (createml_folder / split_name / class_name).mkdir(parents=True, exist_ok=True)

        for video_stem in splits.get(split_name, []):
            video_path = next((p for p in raw_folder.glob(video_stem + ".*")), None)
            if video_path is None:
                print(f"  missing video for {video_stem}, skipping")
                continue
            duration, _ = probe(video_path)
            labels = load_labels(video_stem)
            swing_rows = [(frame, seconds) for frame, seconds, kind in labels if kind in ("swing", "practice")]
            motion_rows = [(frame, seconds) for frame, seconds, kind in labels if kind == "motion"]
            # Random negatives keep clear of every mark, swings and motion alike.
            all_mark_times = [seconds for _, seconds, _ in labels]

            for frame, impact_seconds in swing_rows:
                start = max(0.0, impact_seconds - IMPACT_OFFSET_SECONDS)
                if start + CLIP_SECONDS > duration:
                    start = max(0.0, duration - CLIP_SECONDS)
                output_path = createml_folder / split_name / "swing" / f"{video_stem}_swing_{frame}.mp4"
                cut_clip(video_path, start, output_path)
                totals[split_name]["swing"] += 1

            for frame, motion_seconds in motion_rows:
                start = max(0.0, min(motion_seconds - CLIP_SECONDS / 2, duration - CLIP_SECONDS))
                output_path = createml_folder / split_name / "other" / f"{video_stem}_motion_{frame}.mp4"
                cut_clip(video_path, start, output_path)
                totals[split_name]["other"] += 1

            for start in negative_start_times(duration, all_mark_times):
                output_path = createml_folder / split_name / "other" / f"{video_stem}_other_{int(start * 1000)}.mp4"
                cut_clip(video_path, start, output_path)
                totals[split_name]["other"] += 1

            print(f"{split_name}: {video_stem}  ({duration:.1f} s, {len(swing_rows)} swings, {len(motion_rows)} motion)")

    print("\nClips written:")
    for split_name, counts in totals.items():
        print(f"  {split_name}: swing {counts['swing']}, other {counts['other']}")
    print(f"\nFolder for Create ML: {createml_folder}")


if __name__ == "__main__":
    main()