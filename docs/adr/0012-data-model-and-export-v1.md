# 0012 — Data model snapshots, VersionedSchema V1, JSON export v1

- Status: Accepted (extends 0004, 0006)
- Date: 2026-09-27

## Context
Spec §5.1 sketches six SwiftData models; §10 wants plans and sessions exportable as JSON without changes. Plans get edited and deleted while their session history must stay readable, and real sessions get logged from Phase 1 on.

## Decision
- Every model has a `UUID` `id`. Blocks and block results carry an explicit `order`; relationship arrays are never read in stored order.
- Delete rules: plan → blocks cascade; plan → sessions nullify; plan block → results nullify; session → results → shots cascade. BagClub has no relationships; everything references clubs by name.
- History is snapshotted: `PracticeSession.planName` and `mode`, `BlockResult.clubName`, `targetReps` (nil in free sessions) and `tags`, `ShotRecord.clubName`.
- Completion is pure (`Completion`): block = max(0, counted + manualAdjust) / target, uncapped; session = total done / total target over targeted blocks; nil without a target.
- Schema is `RepsSchemaV1` (1.0.0) with `RepsMigrationPlan` from day one. Before V2, the V1 classes are copied unchanged into `RepsSchemaV1` as nested types.
- Export format v1: `ExportDocument` with `formatVersion`, `exportedAt`, `bag`, `plans`, finished `sessions` (nested blocks and shots). Keys are the Swift property names, ISO 8601 UTC, millisecond precision (rounded), sorted keys, nil fields omitted, enums as raw strings, clips as bare `<shotId>.mov`, no derived values. Encoding returns `Data` only.

## Consequences
Editing or deleting plans and clubs never changes history or old exports. Any change to an `Export*` property name or enum raw value is a format change and bumps `formatVersion`. Writing or sharing the export is a separate, security-reviewed feature.
