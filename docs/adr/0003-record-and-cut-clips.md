# 0003 — Clips via rolling segments + export

- Status: Accepted
- Date: 2026-09-27 (from spec §3.3, §5.8)

## Context
A 5 s in-memory frame ring buffer at 1080p60 is roughly 1 GB of raw frames.

## Decision
Record continuously to 60 s temp segments with AVAssetWriter. On each shot, export [impact − 3 s, impact + 2 s] with AVAssetExportSession. Delete segments older than 2 minutes.

## Consequences
More disk churn, but a much simpler implementation. Mode 1 (no clips) never writes video and runs cooler.
