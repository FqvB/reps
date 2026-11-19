# 0017 — Ball locator: gradient circle vote; presence: ball-sized NCC patch

- Status: Accepted (refines spec §5.2, ADR 0011)
- Date: 2026-11-19

## Context
ADR 0011 asks for a classic-vision locator ("small, round, bright blobs") and the newest ball still ~1 s. Spec §5.2 takes a reference patch ~3× the ball's diameter and compares it with NCC.

The planner prototyped both on the putting clip (`docs/plans/14-ball-presence.md`). With the phone on the floor, the ball sits in front of a light floor strip. It is barely brighter than that strip, and its shaded side is darker, so brightness blobs merge the ball with the background. Patches larger than the ball are mostly background: with half-side 1.5r, NCC hardly drops when the ball leaves (≈ 0.77 → 0.61), and half-side 1.5r with the final locator scored 7/22. The spec's 3× diameter is larger still.

## Decision
- Locator: a gradient-direction circle vote on luma. Edge pixels vote for centres at r ∈ [min, max] along ±gradient. Each peak needs radial edges on one exact ring in ≥ 13 of 16 sectors, which rejects squares, straight edges and texture.
- Lock: the first track still ≥ 1 s locks. Same-frame ties go to the newest, then higher coverage, then larger radius. Other tracks still ≥ 0.5 s at lock become ignored spots for the session.
- The ADR 0008 re-arm (present ≥ 1 s) is the lock itself; there's no separate timer.
- Presence: NCC on a patch of half-side = radius (the ball, not 3× it), best over ±0.25r shifts, threshold 0.75. Absent ≥ 300 ms emits one event timed at the first absent frame, then the locator searches again.
- Everything is defaults in `BallPresenceDetector.Config`; #16 tunes putting.

## Consequences
- Prototype: 19/22 putting positives, 1 false positive.
- At the very first lock, round static clutter that was in view before the ball can win, because nothing is "older" yet. ADR 0011's "newest" holds only from the second lock on. Recovery is #15's tap override (Q46).
- A putter resting against the ball can stop a lock. Re-checking the circle at the lock instead of NCC is a measured alternative for #16 (Q46).
- The range needs other radius bounds and the feet region (#19).
