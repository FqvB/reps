"""
compress.py — compress every video in data/full/, number it, and move it into data/raw/.

Usage:
    uv run tools/compress.py                # process everything in data/full/
    uv run tools/compress.py --delete-originals
    uv run tools/compress.py --dry-run      # show what would happen, change nothing

What it does, per video in data/full/ (any depth, .mov / .mp4 / .m4v):
  1. picks the next number that has never been used (kept in data/next_number.txt,
     so it keeps counting even after label.py renames the files in data/raw/),
  2. runs ffmpeg: cap the long side at 1920 px, HEVC via the Mac's hardware encoder
     (falls back to libx265), audio down to 96 kbps AAC,
     - 120 / 240 fps sources (iPhone slo-mo straight off the phone) are already real
       time; they are thinned to 60 fps by dropping frames, no speed change,
     - a slo-mo that was EXPORTED from Photos is baked slow (30 fps, 4x or 8x long);
       the tool cannot detect that from the file, so pass --speed-up 4 (or 8) for
       those and it retimes them to real speed,
  3. checks the output plays the same duration as the input,
  4. writes data/raw/<n>.mov with the ORIGINAL file's date, so label.py can still
     default to the recording date,
  5. moves the original to data/full/_done/<n>_<original name> — or deletes it with
     --delete-originals. Nothing is left behind in data/full/ either way, and nothing is
     copied twice.

Needs ffmpeg and ffprobe on the PATH:   brew install ffmpeg
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

VIDEO_SUFFIXES = {".mov", ".mp4", ".m4v"}

# ---------------------------------------------------------------------------
# Folders
# ---------------------------------------------------------------------------

script_folder = Path(__file__).resolve().parent
project_folder = script_folder.parent                      # reps-ml/
full_folder = project_folder / "data" / "full"
raw_folder = project_folder / "data" / "raw"
done_folder = full_folder / "_done"
next_number_path = project_folder / "data" / "next_number.txt"

parser = argparse.ArgumentParser(description="Compress and number videos from data/full into data/raw.")
parser.add_argument("--delete-originals", action="store_true", help="delete originals instead of moving them to data/full/_done/")
parser.add_argument("--dry-run", action="store_true", help="print the plan and exit without touching any file")
parser.add_argument("--speed-up", type=float, default=1.0, help="retime baked slow-motion to real speed, e.g. 4 for 120 fps slo-mo, 8 for 240 fps")
parser.add_argument("--keep-fps", action="store_true", help="do not thin 120/240 fps sources down to 60 fps")
arguments = parser.parse_args()

for tool in ("ffmpeg", "ffprobe"):
    if shutil.which(tool) is None:
        print(f"{tool} not found. Install it with:  brew install ffmpeg")
        sys.exit(1)

raw_folder.mkdir(parents=True, exist_ok=True)
full_folder.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Numbering that never repeats
# ---------------------------------------------------------------------------

def read_next_number():
    """The next unused number. Also scans existing files so the counter can't go backwards
    if next_number.txt is ever lost."""
    highest_seen = 0
    if next_number_path.exists():
        highest_seen = int(next_number_path.read_text().strip()) - 1

    for existing in raw_folder.glob("*"):
        if existing.stem.isdigit():
            highest_seen = max(highest_seen, int(existing.stem))
    if done_folder.exists():
        for archived in done_folder.glob("*"):
            leading_number = archived.name.split("_", 1)[0]
            if leading_number.isdigit():
                highest_seen = max(highest_seen, int(leading_number))
    return highest_seen + 1


def save_next_number(number):
    next_number_path.write_text(f"{number}\n")


# ---------------------------------------------------------------------------
# ffmpeg helpers
# ---------------------------------------------------------------------------

def probe(video_path):
    """Ask ffprobe for duration and the video stream's frame rate."""
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=r_frame_rate:format=duration", "-of", "json", str(video_path)],
        capture_output=True, text=True, check=True,
    )
    info = json.loads(result.stdout)
    numerator, denominator = info["streams"][0]["r_frame_rate"].split("/")
    frames_per_second = float(numerator) / float(denominator)
    return float(info["format"]["duration"]), frames_per_second


TARGET_FPS = 60          # everything in data/raw/ ends up at this rate unless --keep-fps
HIGH_FPS_THRESHOLD = 100 # at or above this the source is iPhone slo-mo footage


# Cap the longer side at 1920 px, keep aspect ratio, keep it even (encoders need even sizes).
SCALE_FILTER = "scale='if(gt(iw,ih),min(1920,iw),-2)':'if(gt(iw,ih),-2,min(1920,ih))'"


def build_video_filter(source_fps):
    """Scale, then optionally retime baked slow-mo, then optionally thin high-fps sources to 60."""
    filters = [SCALE_FILTER]
    if arguments.speed_up != 1.0:
        # Play the frames faster: presentation timestamps divided by the factor.
        filters.append(f"setpts=PTS/{arguments.speed_up}")
    if source_fps >= HIGH_FPS_THRESHOLD and not arguments.keep_fps:
        # Drop frames to 60 fps. The motion speed does not change; 240 fps real-time
        # footage simply keeps every 4th frame.
        filters.append(f"fps={TARGET_FPS}")
    return ",".join(filters)


def build_ffmpeg_command(input_path, output_path, use_hardware_encoder, source_fps):
    """The encode command."""
    if arguments.speed_up != 1.0:
        # Speeding up video makes the audio meaningless (and atempo caps at 2x per pass); drop it.
        audio_arguments = ["-an"]
    else:
        audio_arguments = ["-c:a", "aac", "-b:a", "96k"]
    if use_hardware_encoder:
        video_codec_arguments = ["-c:v", "hevc_videotoolbox", "-q:v", "65", "-tag:v", "hvc1"]
    else:
        video_codec_arguments = ["-c:v", "libx265", "-crf", "22", "-preset", "medium", "-tag:v", "hvc1"]
    return [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-stats",
        "-i", str(input_path),
        "-map_metadata", "0",                      # keep creation date and rotation info
        "-vf", build_video_filter(source_fps),
        *video_codec_arguments,
        "-pix_fmt", "yuv420p",
        *audio_arguments,
        "-movflags", "+faststart",
        str(output_path),
    ]


def compress(input_path, output_path, source_fps):
    """Try the hardware encoder first; if it refuses, fall back to software."""
    for use_hardware_encoder in (True, False):
        completed = subprocess.run(build_ffmpeg_command(input_path, output_path, use_hardware_encoder, source_fps))
        if completed.returncode == 0:
            return use_hardware_encoder
        if output_path.exists():
            output_path.unlink()
        print("  hardware encoder failed, retrying with libx265 (slower)")
    raise RuntimeError(f"ffmpeg failed on {input_path.name}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

source_videos = sorted(
    path for path in full_folder.rglob("*")
    if path.is_file() and path.suffix.lower() in VIDEO_SUFFIXES and done_folder not in path.parents
)

if not source_videos:
    print(f"Nothing to do — no videos in {full_folder}")
    sys.exit(0)

next_number = read_next_number()
print(f"{len(source_videos)} video(s) to process, numbering starts at {next_number}\n")

for source_path in source_videos:
    output_path = raw_folder / f"{next_number}.mov"
    source_size_megabytes = source_path.stat().st_size / 1e6
    source_duration, source_fps = probe(source_path)
    plan_note = ""
    if source_fps >= HIGH_FPS_THRESHOLD and not arguments.keep_fps:
        plan_note += f"  [{source_fps:.0f} fps -> {TARGET_FPS} fps, frames dropped, speed unchanged]"
    if arguments.speed_up != 1.0:
        plan_note += f"  [retimed {arguments.speed_up:g}x faster, audio dropped]"
    print(f"{source_path.relative_to(full_folder)}  ({source_size_megabytes:.0f} MB, {source_fps:.0f} fps)  ->  raw/{output_path.name}{plan_note}")

    if arguments.dry_run:
        next_number += 1
        continue

    # 1. encode
    compress(source_path, output_path, source_fps)

    # 2. sanity check: the output should last the source duration divided by any speed-up
    expected_duration = source_duration / arguments.speed_up
    output_duration, _ = probe(output_path)
    if abs(expected_duration - output_duration) > 0.1 + 0.02 * expected_duration:
        output_path.unlink()
        print(f"  duration mismatch (expected {expected_duration:.2f}s, got {output_duration:.2f}s) — original left in place, skipping")
        continue

    # 3. give the compressed file the original's timestamps so the recording date survives
    source_stat = source_path.stat()
    os.utime(output_path, (source_stat.st_atime, source_stat.st_mtime))

    # 4. move (or delete) the original so nothing is processed twice
    if arguments.delete_originals:
        source_path.unlink()
        where_it_went = "deleted"
    else:
        done_folder.mkdir(parents=True, exist_ok=True)
        archived_path = done_folder / f"{next_number}_{source_path.name}"
        shutil.move(str(source_path), str(archived_path))
        where_it_went = f"moved to full/_done/{archived_path.name}"

    output_size_megabytes = output_path.stat().st_size / 1e6
    print(f"  done: {output_size_megabytes:.0f} MB, original {where_it_went}")

    next_number += 1
    save_next_number(next_number)

# Clean up empty sub-folders left behind in data/full/ (not _done)
for folder in sorted(full_folder.rglob("*"), reverse=True):
    if folder.is_dir() and folder != done_folder and done_folder not in folder.parents and not any(folder.iterdir()):
        folder.rmdir()

if arguments.dry_run:
    print("\nDry run — nothing changed.")
else:
    print(f"\nFinished. Next number will be {next_number}.")