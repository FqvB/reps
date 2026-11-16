"""
label_putt.py — tag a putting video, rename it to the standard name, and mark the impact frame of every putt.
Fork of label.py for the Reps putting threshold (Q17). Putting footage lives apart from the range data
so check.py / make_clips.py and the swing classifier never see it.

Usage:
    uv run tools/label_putt.py data/putting/raw/IMG_5012.mov
    uv run tools/label_putt.py data/putting/raw/IMG_5012.mov --who emils --light indoor

You label first, then tag. When you press x to finish, if the video is not yet
named in the standard form
    YYYY-MM-DD_<who>_putt_<light>_<n>.mov
the script asks for the tags in the terminal (or takes them from the flags),
picks the next free <n> for that day, renames the video AND its labels CSV,
and appends a row to data/putting/manifest.csv. Closing the window instead of
pressing x keeps the labels under the current name; re-run to continue and tag.

Keys in the video window:
    space   play / pause at normal speed
    d / a   one frame forward / back
    w / s   one second forward / back
    e / q   ten seconds forward / back
    i       mark this frame as IMPACT of a real putt (putter meets ball)
    p       mark this frame as a PICKUP — ball moved by hand, foot or putter without a stroke
    m       mark this frame as MOTION near the ball that is not a putt (waggle, practice stroke,
            foot or shaft crossing the view) — a hard negative
    u       undo the last mark
    x       save and quit

Labels go to data/putting/labels/<video name>.csv after every mark, so closing
early loses nothing, and re-running on the same video resumes.
"""

import argparse
import csv
import datetime
import re
import sys
from pathlib import Path

import cv2

# ---------------------------------------------------------------------------
# Tags: what each one may be
# ---------------------------------------------------------------------------

ALLOWED_LIGHTS = ["sun", "cloud", "shade", "indoor"]
STANDARD_NAME_PATTERN = re.compile(r"^(\d{4}-\d{2}-\d{2})_([a-z0-9]+)_putt_(sun|cloud|shade|indoor)_(\d+)$")
MARK_KINDS = {ord("i"): "putt", ord("p"): "pickup", ord("m"): "motion"}


def ask_for_choice(question, allowed_values):
    """Ask in the terminal until the answer is one of the allowed values."""
    while True:
        answer = input(f"{question} [{'/'.join(allowed_values)}]: ").strip().lower()
        if answer in allowed_values:
            return answer
        print(f"  please type one of: {', '.join(allowed_values)}")


def ask_for_name(question):
    """Ask for a lowercase name with only letters and digits (used in filenames)."""
    while True:
        answer = input(f"{question}: ").strip().lower()
        if re.fullmatch(r"[a-z0-9]+", answer):
            return answer
        print("  letters and digits only, no spaces — e.g. emils, janis")


def next_free_number(raw_folder, date_text, who, light):
    """Find the smallest <n> not already used by a video with the same date and tags."""
    prefix = f"{date_text}_{who}_putt_{light}_"
    used_numbers = set()
    for existing_path in raw_folder.glob(prefix + "*"):
        suffix = existing_path.stem[len(prefix):]
        if suffix.isdigit():
            used_numbers.add(int(suffix))
    number = 1
    while number in used_numbers:
        number += 1
    return number


def write_manifest_row(manifest_path, row):
    """Append one video's tags to data/putting/manifest.csv, creating the file with a header if needed."""
    is_new_file = not manifest_path.exists()
    with open(manifest_path, "a", newline="") as manifest_file:
        writer = csv.DictWriter(manifest_file, fieldnames=["video", "date", "who", "light", "fps", "frames", "notes"])
        if is_new_file:
            writer.writeheader()
        writer.writerow(row)


# ---------------------------------------------------------------------------
# Command line and renaming
# ---------------------------------------------------------------------------

parser = argparse.ArgumentParser(description="Tag, rename and label a putting video.")
parser.add_argument("video", help="path to the .mov / .mp4 in data/putting/raw/")
parser.add_argument("--who", help="person putting, e.g. emils")
parser.add_argument("--light", choices=ALLOWED_LIGHTS, help="lighting condition")
parser.add_argument("--date", help="recording date YYYY-MM-DD (default: the file's modification date)")
parser.add_argument("--notes", default="", help="free text stored in the manifest, e.g. 'green mat, white ball'")
arguments = parser.parse_args()

video_path = Path(arguments.video).resolve()
if not video_path.exists():
    print(f"No such file: {video_path}")
    sys.exit(1)

raw_folder = video_path.parent
putting_folder = raw_folder.parent
# Refuse anything outside data/putting/raw so putts never land in the range manifest.
if raw_folder.name != "raw" or putting_folder.name != "putting":
    print(f"Put the video in data/putting/raw/ first (got {raw_folder}).")
    sys.exit(1)
labels_folder = putting_folder / "labels"
labels_folder.mkdir(parents=True, exist_ok=True)
manifest_path = putting_folder / "manifest.csv"

# Open the video early so the manifest can record fps and frame count.
video = cv2.VideoCapture(str(video_path))
if not video.isOpened():
    print(f"Could not open {video_path}")
    sys.exit(1)
frames_per_second = video.get(cv2.CAP_PROP_FPS)
total_frame_count = int(video.get(cv2.CAP_PROP_FRAME_COUNT))

def tag_and_rename(video_path, labels_path):
    """Ask for the tags, rename the video and its labels CSV to the standard name, record it in the manifest.
    Returns the new (video_path, labels_path)."""
    if STANDARD_NAME_PATTERN.match(video_path.stem):
        print(f"{video_path.name} is already in standard form — nothing to rename.")
        return video_path, labels_path

    print(f"\nTagging {video_path.name}  ({total_frame_count} frames at {frames_per_second:.1f} fps)")

    if arguments.date:
        date_text = arguments.date
    else:
        modified_time = datetime.datetime.fromtimestamp(video_path.stat().st_mtime)
        date_text = modified_time.strftime("%Y-%m-%d")
        typed = input(f"Recording date [{date_text}]: ").strip()
        if typed:
            date_text = typed

    who = arguments.who or ask_for_name("Who is putting")
    light = arguments.light or ask_for_choice("Lighting", ALLOWED_LIGHTS)
    notes = arguments.notes or input("Notes — mat, ball colour, distance (optional, enter to skip): ").strip()

    number = next_free_number(raw_folder, date_text, who, light)
    new_stem = f"{date_text}_{who}_putt_{light}_{number}"
    new_video_path = raw_folder / (new_stem + video_path.suffix.lower())
    new_labels_path = labels_folder / (new_stem + ".csv")

    video_path.rename(new_video_path)
    if labels_path.exists():
        labels_path.rename(new_labels_path)

    write_manifest_row(manifest_path, {
        "video": new_stem, "date": date_text, "who": who, "light": light,
        "fps": f"{frames_per_second:.2f}", "frames": total_frame_count, "notes": notes,
    })
    print(f"Renamed to {new_video_path.name} (+ labels CSV) and added to putting/manifest.csv")
    return new_video_path, new_labels_path


labels_path = labels_folder / (video_path.stem + ".csv")

# ---------------------------------------------------------------------------
# Marks
# ---------------------------------------------------------------------------

# Each mark is a dictionary: {"frame": int, "seconds": float, "kind": "putt" | "pickup" | "motion"}
marks = []

if labels_path.exists():
    with open(labels_path, newline="") as existing_file:
        for row in csv.DictReader(existing_file):
            marks.append({"frame": int(row["frame"]), "seconds": float(row["seconds"]), "kind": row["kind"]})
    print(f"Loaded {len(marks)} existing marks from {labels_path.name}")


def save_marks():
    """Write all marks to the CSV, sorted by frame, in the same format as label.py."""
    marks.sort(key=lambda mark: mark["frame"])
    with open(labels_path, "w", newline="") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(["frame", "seconds", "kind"])
        for mark in marks:
            writer.writerow([mark["frame"], f"{mark['seconds']:.3f}", mark["kind"]])


# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

preview_height = 900  # portrait 1080x1920 doesn't fit a laptop screen; scale the preview down


def read_frame_at(frame_index):
    """Seek to a frame and return it, or None if it can't be read."""
    frame_index = max(0, min(frame_index, total_frame_count - 1))
    video.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
    frame_read_ok, frame = video.read()
    return frame if frame_read_ok else None


def draw_overlay(frame, frame_index, is_playing):
    """Scale the frame for display and write the status text onto it."""
    scale = preview_height / frame.shape[0]
    preview = cv2.resize(frame, None, fx=scale, fy=scale)

    counts = {kind: sum(1 for mark in marks if mark["kind"] == kind) for kind in MARK_KINDS.values()}
    seconds = frame_index / frames_per_second

    status_lines = [
        video_path.stem,
        f"frame {frame_index} / {total_frame_count}   {seconds:8.3f} s   {'PLAYING' if is_playing else 'paused'}",
        f"putts {counts['putt']}   pickup {counts['pickup']}   motion {counts['motion']}",
    ]
    nearby_marks = [mark for mark in marks if abs(mark["frame"] - frame_index) <= 3]
    if nearby_marks:
        status_lines.append(f"MARKED here: {nearby_marks[0]['kind']} at frame {nearby_marks[0]['frame']}")

    for line_number, line in enumerate(status_lines):
        y = 30 + line_number * 28
        cv2.putText(preview, line, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4)
        cv2.putText(preview, line, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (80, 255, 80), 2)
    return preview


# ---------------------------------------------------------------------------
# Controls window — a second, static window listing the keys
# ---------------------------------------------------------------------------

CONTROL_LINES = [
    ("space", "play / pause"),
    ("d  /  a", "one frame forward / back"),
    ("w  /  s", "one second forward / back"),
    ("e  /  q", "ten seconds forward / back"),
    ("i", "mark IMPACT of a real putt"),
    ("p", "mark PICKUP, ball moved no stroke"),
    ("m", "mark MOTION, not a putt"),
    ("u", "undo last mark"),
    ("x", "save, quit, then tag the video"),
    ("", ""),
    ("", "keys work when either window is focused"),
]


def build_controls_image():
    """Draw the key list onto a dark image, once."""
    import numpy as np
    line_height = 34
    image = np.full((line_height * (len(CONTROL_LINES) + 1) + 20, 440, 3), 28, dtype=np.uint8)
    cv2.putText(image, "Controls", (16, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (80, 255, 80), 2)
    for line_number, (key_text, description) in enumerate(CONTROL_LINES):
        y = 34 + line_height * (line_number + 1)
        cv2.putText(image, key_text, (16, y), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (255, 255, 255), 2)
        cv2.putText(image, description, (130, y), cv2.FONT_HERSHEY_SIMPLEX, 0.58, (200, 200, 200), 1)
    return image


controls_window_name = "controls"
cv2.namedWindow(controls_window_name)
cv2.imshow(controls_window_name, build_controls_image())
cv2.moveWindow(controls_window_name, 20, 40)          # top-left; the video window goes to its right


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

current_frame_index = 0
is_playing = False
finished_with_x = False
window_name = "label"
cv2.namedWindow(window_name)
cv2.moveWindow(window_name, 490, 40)

while True:
    frame = read_frame_at(current_frame_index)
    if frame is None:
        current_frame_index = max(0, current_frame_index - 1)
        is_playing = False
        continue

    cv2.imshow(window_name, draw_overlay(frame, current_frame_index, is_playing))

    wait_milliseconds = max(1, int(1000 / frames_per_second)) if is_playing else 0
    key = cv2.waitKey(wait_milliseconds) & 0xFF

    if is_playing and key == 255:  # nothing pressed while playing: advance one frame
        current_frame_index += 1
        continue

    if key == ord(" "):
        is_playing = not is_playing
    elif key == ord("d"):
        is_playing = False
        current_frame_index += 1
    elif key == ord("a"):
        is_playing = False
        current_frame_index -= 1
    elif key == ord("w"):
        current_frame_index += int(frames_per_second)
    elif key == ord("s"):
        current_frame_index -= int(frames_per_second)
    elif key == ord("e"):
        current_frame_index += int(frames_per_second * 10)
    elif key == ord("q"):
        current_frame_index -= int(frames_per_second * 10)
    elif key in MARK_KINDS:
        is_playing = False
        kind = MARK_KINDS[key]
        marks.append({"frame": current_frame_index, "seconds": current_frame_index / frames_per_second, "kind": kind})
        save_marks()
        print(f"marked {kind} at frame {current_frame_index}")
    elif key == ord("u"):
        if marks:
            removed = marks.pop()
            save_marks()
            print(f"removed {removed['kind']} at frame {removed['frame']}")
    elif key == ord("x"):
        save_marks()
        finished_with_x = True
        break

    # If the window was closed with the mouse, stop the loop too.
    if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
        save_marks()
        break

    current_frame_index = max(0, min(current_frame_index, total_frame_count - 1))

video.release()
cv2.destroyAllWindows()
print(f"Saved {len(marks)} marks to {labels_path}")

if finished_with_x:
    video_path, labels_path = tag_and_rename(video_path, labels_path)
    print(f"Labels are now at {labels_path}")
else:
    print("Window closed without x — labels kept under the current name; re-run this video to continue and tag.")
