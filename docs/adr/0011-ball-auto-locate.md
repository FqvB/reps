# 0011 — The detector finds the ball, no tap

- Status: Accepted (refines spec §5.2, ADR 0008)
- Date: 2026-09-27

## Context
Spec §5.2 has the user tap the ball once and keeps a fixed reference patch. Every new ball lands somewhere slightly different (teed, raked in), so a fixed box goes stale after the first shot. On the range the frame also holds up to ~50 other balls (downrange, the pile).

## Decision
- A ball locator finds candidates on each frame with classic vision (small, round, bright blobs against the mat; contours or thresholds, no ML to start).
- Lock: the newest candidate that stays put ~1 s becomes the ball. Balls already static before it (pile, downrange) are ignored. The reference patch is taken at the lock, then presence works as in §5.2 / ADR 0008.
- After a shot (or when the ball is lost) the locator searches again, so each ball can sit anywhere.
- Putting: search the whole frame. Setup tells the user to keep spare balls out of view.
- Range: search only near the golfer's feet from body pose (#17), then apply the newest-settled rule there.
- A tap on the ball stays as a manual override.

## Consequences
- #14 builds the locator with a pluggable search region (whole frame by default); #19 supplies the pose-based feet region for the range.
- #15 becomes lock-box status (searching/locked/lost), the out-of-view instruction and the tap override, not a required tap.
- Footage needs no per-video ball positions (Q18). Warm-up: a detector can't count until its first lock (~1 s), which matters for swings < 2 s into a clip (Q19).
- If classic vision can't separate the ball from mat texture or glare, a small trained detector is the fallback (Phase 6).
