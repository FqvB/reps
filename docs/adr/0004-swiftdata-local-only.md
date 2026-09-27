# 0004 — SwiftData, local only, JSON-exportable

- Status: Accepted
- Date: 2026-09-27 (from spec §5.1, §10)

## Context
Offline, zero cost, no backend. A future coach feature would need export.

## Decision
SwiftData on device. Club and tags are stored on every ShotRecord so bulk retag and library filters stay simple. Manual adjustments are kept separate from detected reps. Models must serialise to JSON without changes.

## Consequences
No backup beyond iCloud device backup. CloudKit is the cheapest later path.
