# 0001 — Native Swift + SwiftUI, not React Native

- Status: Accepted
- Date: 2026-09-27 (from spec §3.1)

## Context
The app is mostly camera pipeline and on-device vision. React Native would still need a Swift frame-processor plugin, plus a bridge, plus working around Expo's camera abstractions.

## Decision
Swift, SwiftUI, AVFoundation, Vision, Core ML. No cross-platform layer.

## Consequences
Learning Swift costs 2–3 weeks. The UI is small, so losing RN productivity is cheap. Android would need a full rewrite (out of scope).
