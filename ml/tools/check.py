"""
check.py — make sure keypoints, labels and videos line up before training on them.

Usage:
    uv run tools/check.py                 # every video that has a keypoints JSON
    uv run tools/check.py <video stem>    # just one

For each video it prints one line:
    frames match / mismatch, fps, person found in N %, swings, practice,
    mean joint confidence at the impact frames
and writes data/checks/<video>.png — a strip of up to six labelled impact frames
with the skeleton drawn over them. Open the PNG. If the skeleton sits on the
golfer at the moment the club meets the ball, everything is aligned. If it's
rotated, mirrored, shifted, or on the wrong person, tell me before training.
"""

import csv
import json
import random
import sys
from pathlib import Path

import cv2
import numpy as np

project_folder = Path(__file__).resolve().parent.parent
raw_folder = project_folder / "data" / "raw"
labels_folder = project_folder / "data" / "labels"
keypoints_folder = project_folder / "data" / "keypoints"
checks_folder = project_folder / "data" / "checks"
checks_folder.mkdir(parents=True, exist_ok=True)

# Pairs of joint indices to connect when drawing, using the fixed 13-joint order.
SKELETON_BONES = [
    (1, 2),            # shoulders
    (1, 3), (3, 5),    # left arm
    (2, 4), (4, 6),    # right arm
    (1, 7), (2, 8),    # torso sides
    (7, 8),            # hips
    (7, 9), (9, 11),   # left leg
    (8, 10), (10, 12), # right leg
]

PREVIEW_HEIGHT = 480
PREVIEWS_PER_VIDEO = 6


def load_labels(video_stem):
    labels_path = labels_folder / (video_stem + ".csv")
    if not labels_path.exists():
        return []
    with open(labels_path, newline="") as labels_file:
        return [{"frame": int(row["frame"]), "kind": row["kind"]} for row in csv.DictReader(labels_file)]


def draw_skeleton(image, joints):
    """Draw bones and joints for one frame of keypoints onto an image (fractions -> pixels)."""
    height, width = image.shape[:2]

    def pixel(joint):
        x, y, confidence = joint
        if x is None or confidence < 0.2:
            return None
        return (int(x * width), int(y * height))

    for start_index, end_index in SKELETON_BONES:
        start, end = pixel(joints[start_index]), pixel(joints[end_index])
        if start and end:
            cv2.line(image, start, end, (255, 255, 255), 3)
    for joint in joints:
        point = pixel(joint)
        if point:
            cv2.circle(image, point, 5, (60, 220, 60), -1)
    return image


def check_video(video_stem):
    keypoints_path = keypoints_folder / (video_stem + ".json")
    video_path = next((p for p in raw_folder.glob(video_stem + ".*")), None)
    if video_path is None:
        print(f"{video_stem}: video not found in data/raw — skipping")
        return

    with open(keypoints_path) as keypoints_file:
        keypoints = json.load(keypoints_file)
    frames = keypoints["frames"]
    labels = load_labels(video_stem)

    video = cv2.VideoCapture(str(video_path))
    video_frame_count = int(video.get(cv2.CAP_PROP_FRAME_COUNT))

    frames_with_person = sum(1 for frame in frames if frame[1][2] > 0 or frame[2][2] > 0)
    swing_labels = [label for label in labels if label["kind"] == "swing"]
    practice_labels = [label for label in labels if label["kind"] == "practice"]

    impact_confidences = []
    for label in labels:
        if label["frame"] < len(frames):
            impact_confidences.append(np.mean([joint[2] for joint in frames[label["frame"]]]))
    mean_impact_confidence = float(np.mean(impact_confidences)) if impact_confidences else float("nan")

    frame_status = "frames OK" if len(frames) == video_frame_count else f"FRAME MISMATCH json={len(frames)} video={video_frame_count}"
    labels_past_end = [label for label in labels if label["frame"] >= len(frames)]
    if labels_past_end:
        frame_status += f"  ({len(labels_past_end)} labels beyond the last frame!)"

    print(
        f"{video_stem}: {frame_status}, {keypoints['fps']:.0f} fps, "
        f"person in {100 * frames_with_person / max(1, len(frames)):.0f}% of frames, "
        f"{len(swing_labels)} swings, {len(practice_labels)} practice, "
        f"impact confidence {mean_impact_confidence:.2f}"
    )

    # Preview strip: skeleton drawn on a handful of impact frames.
    chosen_labels = random.sample(labels, min(PREVIEWS_PER_VIDEO, len(labels))) if labels else []
    previews = []
    for label in sorted(chosen_labels, key=lambda l: l["frame"]):
        video.set(cv2.CAP_PROP_POS_FRAMES, label["frame"])
        frame_read_ok, image = video.read()
        if not frame_read_ok:
            continue
        image = draw_skeleton(image, frames[label["frame"]])
        scale = PREVIEW_HEIGHT / image.shape[0]
        image = cv2.resize(image, None, fx=scale, fy=scale)
        cv2.putText(image, f"{label['kind']} f{label['frame']}", (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4)
        cv2.putText(image, f"{label['kind']} f{label['frame']}", (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (80, 255, 80), 2)
        previews.append(image)
    video.release()

    if previews:
        strip = np.concatenate(previews, axis=1)
        output_path = checks_folder / (video_stem + ".png")
        cv2.imwrite(str(output_path), strip)
        print(f"    preview: {output_path.relative_to(project_folder)}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        stems = [sys.argv[1]]
    else:
        stems = sorted(path.stem for path in keypoints_folder.glob("*.json"))
    if not stems:
        print("No keypoint files in data/keypoints yet.")
        sys.exit(1)
    for stem in stems:
        check_video(stem)