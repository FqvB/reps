# 0013 — Session engine rules, −1, snapshots; V1 amended before first install

- Status: Accepted (extends 0006, 0012)
- Date: 2026-09-27

## Context
F2 says blocks advance at target, F21 says targets are minimums, and F22 adds a strict mode. F18 adds mandatory or free order. §6 needs kill-safe resume, including after the plan is edited or deleted (Q24). Q21 settles −1.

## Decision
- `SessionController` (MainActor, @Observable) is the only writer during a session. It saves after every change and reports to the voice layer through `SessionEvent` values.
- Minimums (default): reaching the target announces it and stays on the block; the user moves on. Strict: the block ends exactly at target and auto-advances; extra shots are ignored.
- Next block: mandatory order takes the next block in sequence; free order takes the next incomplete block, wrapping. With none left, no block is active until the user picks one or ends the session. Only Done finishes a session.
- One BlockResult per plan block is created at start. Free sessions start a new block when the club or tag set changes, unless the current block is unused.
- +1 counts as a manual adjustment and camera shots as detections, and both create a ShotRecord. −1 deletes the latest ShotRecord and its clip when there is one and always lowers `repsManualAdjust`, never below zero. Right after a strict auto-advance, −1 reopens the block that just ended (not persisted).
- The session snapshots `isStrictCount`, `isOrderMandatory` and `activeBlockOrder`. `RepsSchemaV1` was amended in place to add them, before any real store existed; the next schema change must be RepsSchemaV2 with a migration stage. Export format v1 gains the two rule flags. Dev installs from before this change must be deleted (V1 was amended in place).
- Event handlers registered via `addEventHandler` run synchronously inside `emit`; they must not call back into the controller from the handler body.

## Consequences
Resume never depends on the plan. Detector accuracy stays readable from `repsCounted` vs `repsManualAdjust`. Clip deletion is behind `ClipFileRemoving` until #22.
