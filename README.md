# Reps

**An iOS app that counts your golf practice reps.** Put your phone on a tripod and it counts your shots and putts, calls the count out loud, and saves a clip of every swing. You never have to touch the screen mid-session.

I built it for my own practice. I train with fixed plans (say, 40 × 8-iron, then 30 × 9-iron), and counting balls by hand while trying to focus on the swing doesn't work.

<!-- TODO: add a screenshot or short GIF of a session here -->

## Features

- **Practice plans.** Build plans from your own bag, with per-club targets. Toggle a fixed club order or a strict count per plan.
- **Session engine.** Live count, spoken count-outs and a summary at the end. Built to survive interruptions (calls, backgrounding, accidental exits).
- **Session log and JSON export.** All data stays on the device (SwiftData, no backend).
- **Video library.** Clips are tagged in bulk while you record, with a frame-by-frame clip player.
- **Camera counting (in progress).** Ball detection and ball-gated swing detection that fuses pose estimation with a Core ML swing classifier.

## How detection works

A shot only counts when two independent signals agree:

1. **Ball gate.** The app finds the ball in a "lock box" at address and watches for it to disappear.
2. **Swing signal.** Body pose from Apple Vision, plus a swing classifier trained in Create ML on my own footage and about 1,400 swings from GolfDB.

Requiring both keeps false counts down. Practice swings and someone walking past don't register. The target is ≥95% recall, at most 1 false count per 50 shots, and under 1.5 s latency. Putting uses a simpler rule: if the ball is gone, that's a stroke ([ADR 0008](docs/adr/0008-putting-absence-is-a-stroke.md)).

Detectors are scored against labelled footage by an evaluation harness (`DetectorEvalTests`) before any of them ship.

## Tech

Swift · SwiftUI · SwiftData · AVFoundation · Vision · Core ML / Create ML. iOS 26+, iPhone only, fully offline.

## Project status

| Phase | Status |
|---|---|
| 0: Project setup and detector eval harness | ✅ Done |
| 1: Manual counter (plans, sessions, voice, log, export) | ✅ Done |
| 2: Camera pipeline and putting mode | 🚧 In progress |
| 3: Hands-free range counter | Planned |
| 4: Clips and library | Partly done |

The full roadmap is in [docs/roadmap.md](docs/roadmap.md).

## Docs

The design decisions are written up as architecture decision records:

- [Architecture decision records](docs/adr/), e.g. [ball-gated fusion](docs/adr/0002-ball-gated-fusion.md) and [record-then-cut clips](docs/adr/0003-record-and-cut-clips.md)
- [Code reference](docs/code-reference.md)
- [Development guide](docs/development.md): building, testing and conventions
- [ML tools](ml/README.md): labelling, pose extraction and training-clip pipeline

## Running it

1. Open `Reps.xcodeproj` in Xcode (iOS 26 SDK).
2. Select your iPhone and run. The camera features need a real device.
