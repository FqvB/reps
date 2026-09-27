# 0014 — Capture permissions: ask in context, never block

- Status: Accepted
- Date: 2026-09-27

## Context
Reps needs the camera to count and record, and the microphone only to add sound to clips (spec §3.2). Spec §6 says a denied permission must explain what stops working, deep-link to Settings, and leave manual counting working. F20 puts both prompts on the last onboarding screen.

## Decision
- All camera/microphone authorization goes through the `CapturePermissions` protocol; `DevicePermissions` is the only code that calls `AVCaptureDevice.authorizationStatus`/`requestAccess`. Tests use a fake.
- Prompts are never shown at launch. Onboarding asks for the camera on "Allow and finish" (or a row tap) after an on-screen explanation; the microphone is asked only when the camera was just granted and "Record audio on clips" is on. Later features (#13 capture, #22 audio) re-check in context before first use and ask then if still undetermined.
- Denied → explain, offer the Settings deep link (`UIApplication.openSettingsURLString`), re-read on return. Restricted → explain, no action. Unknown future statuses read as denied.
- Nothing in the app is gated on a permission: sessions, manual counting and plans work with both denied. Audio on with the mic not granted records video only.
- Statuses are never cached in UserDefaults; the system is the source of truth.
- Usage strings live in the app target's `INFOPLIST_KEY_NSCameraUsageDescription` / `INFOPLIST_KEY_NSMicrophoneUsageDescription` build settings (generated Info.plist, ADR 0009).

## Consequences
One place to audit for prompts. Onboarding completes on every path, so a user who declines can still count by hand. Photos access is a separate decision (#26).
