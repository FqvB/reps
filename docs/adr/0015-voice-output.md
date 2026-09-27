# 0015 — Voice output: own queue, newest count wins, duck while speaking

- Status: Accepted
- Date: 2026-09-27

## Context
F6/§5.7 want the count after every rep and a block callout, pre-warmed, queued and never overlapping; §6 wants music ducked, not stopped. AVSpeechSynthesizer can only clear its whole queue. Only Done saves a session (ADR 0013), but §5.7 says "Done. Session saved." at plan end.

## Decision
- SessionEvent → text lives in `VoiceLines` (pure). `SpeechAnnouncer` keeps its own queue and hands `Speaker` one line at a time. A new count replaces any unspoken count; callouts are never dropped; the line being spoken finishes.
- "Done. Session saved." is spoken on a new `SessionEvent.sessionSaved`, sent by `finish()` only after a successful save. It clears the queue and cuts in. Plan end says "End of plan." instead.
- `announceCount` silences counts only (Q40).
- Audio session: `.playback`, mode `.voicePrompt`, `[.duckOthers]`; active only while speaking, deactivated with `.notifyOthersOnDeactivation` 0.6 s after the last line. `VoiceAudioSession` is the only code that touches the app audio session.
- Warm-up renders a line with `write(_:toBufferCallback:)` when the controller is created.

## Consequences
Mapping and queue policy are unit-tested with a fake; the AVFoundation wrapper is checked by ear. #22 (clip audio) must revisit the audio session: recording needs `.playAndRecord`, an always-active session, and `AVCaptureSession.automaticallyConfiguresApplicationAudioSession = false` so capture doesn't reroute speech (Q41).
