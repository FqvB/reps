# 0006 — Session persistence, no uncertainty flag, UUID clip names

- Status: Accepted
- Date: 2026-09-27

## Context
Spec §6 persists after every shot, while F28 says nothing saves until Done. §5.4 wants uncertain shots flagged. §5.8 builds clip file names from the club name, which is user text.

## Decision
- `PracticeSession.status: active | finished`. Every shot is persisted immediately. Done sets `finished`, and "Keep going" leaves it `active`. An `active` session on launch triggers the "resume?" prompt. The log and library only show `finished` sessions.
- No uncertainty flag or confidence on `ShotRecord`. A shot near the threshold still counts.
- Clips are stored as `Documents/clips/<sessionId>/<shotUUID>.mov`. Club and angle live only in SwiftData.

## Consequences
Kill-safe sessions with no separate draft store. Detector accuracy is tracked through `repsManualAdjust` only. Retagging never touches files, and user text never reaches a file path.
