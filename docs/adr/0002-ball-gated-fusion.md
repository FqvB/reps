# 0002 — Shot = ball-gated pose classification, no audio

- Status: Accepted
- Date: 2026-09-27 (from spec §3.2, §5.4)

## Context
Colour detection alone can't tell a practice swing or re-tee from a shot. Audio was rejected: wind, neighbouring bays, and quiet clean strikes all break it.

## Decision
A tapped reference patch watches the ball every frame. When the ball leaves, the last ~1.5 s of pose keypoints is classified. It counts as a shot if it's a swing whose impact falls within ±0.5 s of the ball leaving. Putting uses ball presence only. The microphone only records clip audio.

## Consequences
Practice swings never reach the model. The model runs a few dozen times per session, so battery and heat stay low. The ball watcher becomes load-bearing and needs its own test matrix (shadows, mat texture, tee markers, ball nudged at address).
