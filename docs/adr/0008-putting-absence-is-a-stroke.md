# 0008 — Putting: ball gone = stroke

- Status: Accepted (refines spec §5.5)
- Date: 2026-09-27

## Context
In putting mode the phone lies on the ground, roughly face-on to the ball. From that angle a waggle or the putter at address sits beside the ball rather than hiding it, and small nudges don't matter.

## Decision
- Count a stroke when the ball leaves the region and stays gone for ≥ 300 ms (debounce against a foot or shaft briefly crossing the view).
- Drop the `occluded` requirement from §5.5. Movement inside the region doesn't count and doesn't block.
- Re-arm when a ball has been present ≥ 1 s.
- Picking the ball up also counts. Fix it with −1.

## Consequences
The putting detector is a thin configuration of BallPresenceDetector with no motion analysis. Only a short putting clip is needed to set the similarity threshold. The setup overlay (#15) should show the phone-on-ground, face-on placement.
