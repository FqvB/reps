# #5 Onboarding

Goal: three first-launch screens (Figma 07 Welcome, 08 Your bag, 09 Camera) that seed the common 14-club bag, set the default camera angle, ask for the camera (and, when clips will carry audio, the microphone), and then never show again. A denied permission never blocks the app: manual counting works without either.

Spec: F19 (bag set during onboarding, defaults to a common 14), F20 (three screens: welcome, your bag, camera/microphone permissions with default angle), §3.2 ("The microphone is used for exactly one thing: recording audio on the clips"), §5.3c ("a first session is two taps away"), §6 ("Camera or mic permission denied at onboarding: explain what stops working and deep-link to Settings; manual counting still works"). ADR 0009 (hand-written pbxproj, generated Info.plist). Figma file `pMKE8PoWxIEotHas0rmQX1`: [07 Welcome 8:2](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=8-2), [08 Your bag 8:46](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=8-46), [09 Camera 8:134](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=8-134). No Figma variables; values are literals off the layers.

Branch: `feat/5-onboarding` from `main` **after #6 has merged** (merge order #11 → #6 → #12 → #5). Labels `ui`, `review:fable-security` → `fable-security-reviewer` reviews before the PR. Copy this plan to `docs/plans/5-onboarding.md` in the docs commit.

**Depends on #6** (`docs/plans/6-settings.md`): `AppSettings` (`Reps/Settings/AppSettings.swift`, keys `settings.*`, `Default`, `angleChoices`, `recordClipAudio`, `defaultCameraAngle`), `SettingsCopy.angleTitle(_:)`, `BagCatalog.defaultBag` (the common 14), `BagLibrary` (`Reps/Bag/BagLibrary.swift`, `all(in:)`), `BagEditorView` (`Reps/UI/Bag/BagEditorView.swift`, chip grid with no chrome of its own; host provides the `ScrollView`). If any of those names differ on `main`, stop and report; don't invent replacements.

How this was checked: every file in Appendix A and B was type-checked together with the real `Theme.swift`, `PrimaryButtonStyle.swift`, `BagClub.swift` and stubs for the #6 types (`swiftc -typecheck`, iOS 26.0 simulator target, iPhoneSimulator 27.0 SDK, Swift 6.4, `-default-isolation MainActor`, `-enable-upcoming-feature MemberImportVisibility`, `-DDEBUG`): clean. `swift-format lint --strict` with the repo's `.swift-format`: clean. Nothing was built by Xcode or run. **Copy every file exactly.** Apple APIs were checked with Context7: `AVCaptureDevice.authorizationStatus(for:)` / `requestAccess(for:) async -> Bool` (AVFoundation, "call requestAccess only at a time that's appropriate for your app"; the `.audio` variant equals `AVAudioSession.requestRecordPermission`), `AVAuthorizationStatus` (notDetermined / restricted / denied / authorized), `UIApplication.openSettingsURLString` (UIKit), SwiftUI `openURL`, `scenePhase`, `AnyTransition.push(from:)`, `@State` holding an `@Observable` class.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Where onboarding lives | `RootView` shows `OnboardingView` **instead of** the `TabView` while `AppSettings.hasCompletedOnboarding` is false (`@AppStorage`, key `settings.hasCompletedOnboarding`, default false). No cover, no sheet. | A second `fullScreenCover` on the view that already owns the session cover is fragile, and the branch can't be swiped away. The resume prompt (`.task { offerResume() }`) moves onto the tabs branch, so it fires after onboarding, not over it. |
| Completion flag | `AppSettings.hasCompletedOnboarding`, set by `OnboardingModel.finish()` only. Stored in `UserDefaults.standard` like every other preference; wiped with the app. | Shows once. Nothing else (a session, a bag) is used as a proxy. |
| Navigation between pages | `OnboardingModel.page` (welcome → bag → camera), forward only, `.push(from: .trailing)` transition. Page dots are indicators, not controls. No back button, no swipe. | Figma 07–09 have neither. Everything set here is editable in Settings (#6). |
| Bag seeding | `BagLibrary.seedDefaultBag(in:)`: inserts `BagCatalog.defaultBag` **only when the BagClub table is empty**; returns whether it seeded. Called from `OnboardingView.task`. | Idempotent by construction: a rerun (flag reset, kill mid-onboarding) finds rows and does nothing, and it never re-adds a club the user turned off (off keeps the row, spec §5.1). Figma 08 arrives pre-ticked with the 14, which is §5.3c's "two taps away" (Get started → Continue). No separate "Use the default bag" button (not in Figma). |
| Bag page | `BagEditorView` from #6 under the Figma 08 title and intro; every tap saves. Footer: "Continue with N clubs" from an `@Query` count of in-bag clubs. Enabled at 0 too ("Continue without clubs", placeholder). | Reuse; #6 already handles add/rename/delete/duplicates. |
| Default angle | Figma 09 segmented control bound to `@AppStorage(AppSettings.Key.defaultCameraAngle)`; choices `AppSettings.angleChoices`; labels `SettingsCopy.angleTitle` ("Face-on", "Down-the-line"). | Same key and copy as Settings (#6). Deviation: Figma 09 says "Down the line"; Settings' spelling wins so the two screens agree. |
| **Camera prompt** | "Allow and finish" requests the camera if `notDetermined`, then finishes **whatever the answer**. The Camera row is also tappable while "Not yet". | F20 + Figma 09 put the prompt here with the explanation on screen, which is the "ask in context" the docs want. Denied → row says "Denied", a note explains manual counting still works, tapping the row opens Settings (`UIApplication.openSettingsURLString`); "Finish" still completes. |
| **Microphone prompt** | Asked on "Allow and finish" only when **all** of: mic `notDetermined`, camera just came back `granted`, `AppSettings().recordClipAudio` is on (#6 default: on). Also on an explicit tap of the Microphone row. Never when the camera is denied/restricted (no clips → no audio to add). **#22 must re-check in context** before its first recording with audio on and ask then if still undetermined; audio-on with mic not granted records video only, never blocks and never silently records. | F20 lists the mic on this screen and Figma 09 has the row with "optional" copy; the Settings toggle gates it so a user who turned audio off is never asked. Restricted is never asked (the request can't succeed). Recorded as Q34 for the owner. |
| No Photos prompt | Nothing here touches Photos. | #26 (fable path) owns it. |
| Denied / restricted handling | `PermissionRowAction`: notDetermined → request, denied → openSettings, granted/restricted → nothing. Statuses re-read on `scenePhase == .active` (back from Settings). Unknown future `AVAuthorizationStatus` cases map to `.denied` (fail closed: offer Settings, never assume access). | Spec §6. |
| Testability | `CapturePermissions` protocol (`state(of:)`, `request(_:) async`) with `DevicePermissions` (AVFoundation) in the app and `FakePermissions` in tests. `OnboardingModel` is `@Observable`, MainActor, has no SwiftUI/UIKit imports, and owns every decision: page, what to ask, what a row tap does, the completion flag. Views only render and forward. | Logic tests never touch TCC; the view is build-only. `DevicePermissions` is the one place that calls `AVCaptureDevice.requestAccess`; #13 and #22 reuse it. |
| Info.plist strings | `INFOPLIST_KEY_NSCameraUsageDescription` and `INFOPLIST_KEY_NSMicrophoneUsageDescription` added to both app configurations in `project.pbxproj` (generated Info.plist, ADR 0009). | Without them the first `requestAccess` kills the app. Wording says what the data is for and that it stays on the phone. |
| Illustration | Figma 09's stick figure, ball box and caption are drawn in code (`Canvas`) at the frame's 353×200 coordinates; colours `Theme.illustration` (#8A9A84) and `Theme.ballBox` (#E6D35A) added to `Theme.swift`. | The frame is six SVG lines and an ellipse; an asset export would be a new pipeline for a placeholder-grade drawing. Marked `PLACEHOLDER`. |
| Feature icons (07) | The three 40 pt circles get SF Symbols (`list.bullet.rectangle`, `camera`, `film`) in accent. | The Figma circles are empty; marked `PLACEHOLDER`. |
| App mark (07) | "40" on an accent 84 pt tile, as drawn. | The real icon is still #1's placeholder; marked `PLACEHOLDER`. |

## Files

```
Reps.xcodeproj/project.pbxproj                    edit  two INFOPLIST_KEY_NS*UsageDescription lines in each app configuration (AA…92 Debug, AA…93 Release)
Reps/Settings/AppSettings.swift                   edit  (#6 file) Key.hasCompletedOnboarding, Default.hasCompletedOnboarding, var hasCompletedOnboarding
Reps/Bag/BagLibrary.swift                         edit  (#6 file) seedDefaultBag(in:)
Reps/Permissions/CapturePermissions.swift         new   CaptureMedium, PermissionState, CapturePermissions
Reps/Permissions/DevicePermissions.swift          new   PermissionState.init(AVAuthorizationStatus), CaptureMedium.mediaType, DevicePermissions
Reps/Onboarding/OnboardingModel.swift             new   OnboardingPage, PermissionRowAction, OnboardingModel
Reps/Onboarding/OnboardingCopy.swift              new   OnboardingFeature, OnboardingCopy
Reps/UI/Onboarding/OnboardingTheme.swift          new   Theme.Typography.appMark/onboardingIntro/illustrationCaption, Spacing, Radius
Reps/UI/Onboarding/PageDots.swift                 new   PageDots
Reps/UI/Onboarding/OnboardingView.swift           new   OnboardingView + private WelcomePage, BagPage, CameraPage, PageTitle, AngleSegments, PermissionRow, CameraSetupIllustration, PreviewPermissions
Reps/UI/Theme/Theme.swift                         edit  + illustration, ballBox
Reps/App/RootView.swift                           edit  onboarding branch; resume task moves to the tabs
RepsTests/CapturePermissionsTests.swift           new
RepsTests/OnboardingModelTests.swift              new   (+ FakePermissions)
RepsTests/OnboardingCopyTests.swift               new
RepsTests/BagSeedingTests.swift                   new
RepsTests/AppSettingsTests.swift                  edit  (#6 file) onboarding flag cases
docs/code-reference.md, docs/roadmap.md, docs/design.md, docs/open-questions.md, docs/adr/0014-capture-permissions.md, docs/plans/5-onboarding.md
```

New folders (`Reps/Permissions`, `Reps/Onboarding`, `Reps/UI/Onboarding`) need no project edits (synced folders, ADR 0009). The **only** `project.pbxproj` edit is the two Info.plist keys in step 1; touch nothing else in that file.

## Steps

From the repo root:

```sh
DEST27='platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A'   # iPhone 17 Pro, iOS 27
DEST265='platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'  # iPhone 17 Pro, iOS 26.5
```

Before each commit: `xcrun swift-format format --in-place --recursive --parallel Reps RepsTests`, then `xcrun swift-format lint --strict --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests` must print nothing.

### Step 1: usage strings and permissions (`added capture permissions`)

1. `Reps.xcodeproj/project.pbxproj`: in **both** app configurations (`AA0000000000000000000092 /* Debug */` and `AA0000000000000000000093 /* Release */`, the ones with `PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps;`), insert these two lines directly after `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";`, keeping the file's tab indentation and alphabetical key order:

   ```
   INFOPLIST_KEY_NSCameraUsageDescription = "Reps watches the ball and your swing to count shots and save clips. Video stays on your phone.";
   INFOPLIST_KEY_NSMicrophoneUsageDescription = "Adds sound to your saved clips. Never used to count shots.";
   ```

   ASCII only inside the quotes. Do not add them to the ShotDetector or test targets.
2. Create `Reps/Permissions/CapturePermissions.swift` and `Reps/Permissions/DevicePermissions.swift` (Appendix A).
3. Create `RepsTests/CapturePermissionsTests.swift` (Appendix C).
4. Build once with an explicit derived-data path and check the generated plist carries both strings:

   ```sh
   xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST27" -derivedDataPath build/DerivedData -quiet
   plutil -p build/DerivedData/Build/Products/Debug-iphonesimulator/Reps.app/Info.plist | grep -E 'NSCameraUsageDescription|NSMicrophoneUsageDescription'
   ```

   Both keys must print with the text above (`build/` is gitignored). If either is missing, the pbxproj edit is in the wrong configuration block; fix it before going on.
5. `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST27" -only-testing:RepsTests/CapturePermissionsTests` → passes.
6. Add the code-reference entries (Appendix D, permissions part). `git add -A && git commit -m "added capture permissions" -m "Refs #5"`

### Step 2: settings flag and bag seeding (TDD) (`added onboarding flag and bag seeding`)

1. `Reps/Settings/AppSettings.swift` (#6's file), three edits:
   - in `enum Key` add `static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"`
   - in `enum Default` add `static let hasCompletedOnboarding = false`
   - after `var announceTempo` add:

     ```swift
         // Set once by onboarding (#5); the app shows the onboarding screens while it's false.
         var hasCompletedOnboarding: Bool {
             get { bool(Key.hasCompletedOnboarding, Default.hasCompletedOnboarding) }
             nonmutating set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
         }
     ```
2. `RepsTests/AppSettingsTests.swift` (#6's file): in `defaultsWhenEmpty` add `#expect(settings.hasCompletedOnboarding == false)`; in `roundTripsEveryValue` set it to `true` and read it back through both `AppSettings` instances; in `keysMatchAppStorageNames` add `#expect(AppSettings.Key.hasCompletedOnboarding == "settings.hasCompletedOnboarding")`. Match the existing style of those tests (they use `withSettings`).
3. Create `RepsTests/BagSeedingTests.swift` (Appendix C). Run `-only-testing:RepsTests/BagSeedingTests` → fails to compile.
4. `Reps/Bag/BagLibrary.swift` (#6's file): add this method right after `all(in:)`:

   ```swift
       // Onboarding (#5): the common 14 when the bag table is empty. A second run, or a bag the user already has, changes nothing.
       @discardableResult
       static func seedDefaultBag(in context: ModelContext) throws -> Bool {
           guard try all(in: context).isEmpty else { return false }
           for (index, name) in BagCatalog.defaultBag.enumerated() {
               context.insert(BagClub(name: name, sortOrder: index))
           }
           try context.save()
           return true
       }
   ```
5. `xcodebuild test … -destination "$DEST27" -only-testing:RepsTests/BagSeedingTests -only-testing:RepsTests/AppSettingsTests -only-testing:RepsTests/BagLibraryTests` → passes.
6. Code-reference updates for `AppSettings` and `BagLibrary` (Appendix D). `git add -A && git commit -m "added onboarding flag and bag seeding" -m "Refs #5"`

### Step 3: onboarding model and copy (TDD) (`added onboarding model`)

1. Create `RepsTests/OnboardingModelTests.swift` and `RepsTests/OnboardingCopyTests.swift` (Appendix C). Run `-only-testing:RepsTests/OnboardingModelTests -only-testing:RepsTests/OnboardingCopyTests` → fails to compile.
2. Create `Reps/Onboarding/OnboardingModel.swift` and `Reps/Onboarding/OnboardingCopy.swift` (Appendix A). Same command → **all tests pass** (11 + 5).
3. Code-reference entries (Appendix D). `git add -A && git commit -m "added onboarding model" -m "Refs #5"`

### Step 4: onboarding screens (`added onboarding screens`)

1. `Reps/UI/Theme/Theme.swift`: after the `toastAction` line (and after `accentDeep` if #11 added it) insert

   ```swift
       static let illustration = Color(hex: 0x8A9A84)
       static let ballBox = Color(hex: 0xE6D35A)
   ```
2. Create `Reps/UI/Onboarding/OnboardingTheme.swift`, `PageDots.swift`, `OnboardingView.swift` (Appendix B).
3. `Reps/App/RootView.swift`, three edits (Appendix B has the resulting top of the file):
   - add `@AppStorage(AppSettings.Key.hasCompletedOnboarding) private var hasCompletedOnboarding = AppSettings.Default.hasCompletedOnboarding` after `@State private var startFailed = false`
   - replace the whole `var body: some View { … }` with the `body` + `private var tabs: some View` from Appendix B (the tabs are the old body verbatim, now with `return`, and still carry `.task { offerResume() }`)
   - nothing else in the file changes.
4. `xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST27" -quiet` → succeeds, no new warnings. Open the `OnboardingView` preview if Xcode is available.
5. Full Unit plan on **both** simulators: `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST27"` and the same with `"$DEST265"` → both `** TEST SUCCEEDED **`.
6. Manual smoke test on the iOS 27 simulator (`UDID=A26BAE3A-CDDE-45A8-892D-2359740C877A`):
   - Fresh state: `xcrun simctl uninstall $UDID com.fqvb.reps` (clears the flag, the bag and TCC for the app). Run from Xcode or `xcodebuild … build` + `xcrun simctl install/launch`.
   - Welcome shows the tile, two-line title, three features, dots (first active), "Get started". Tap → Your bag slides in with all 14 ticked, footer "Continue with 14 clubs". Untick Driver → "Continue with 13 clubs". Tap → camera page: illustration, "Face-on" selected, both rows "Not yet", "Allow and finish".
   - Tap "Down-the-line". Tap "Allow and finish" → system camera prompt → Allow → system microphone prompt → Allow → Plans tab appears, no resume prompt. Plans › Settings shows Default angle "Down-the-line" and My bag with 13 clubs, Driver unticked.
   - Kill and relaunch → straight to Plans (flag persisted).
   - Denied path: `xcrun simctl uninstall $UDID com.fqvb.reps`, launch again, reach the camera page, tap "Allow and finish", **Don't Allow** on the camera prompt → **no** microphone prompt, Plans appears anyway. Uninstall again, reach the camera page, tap the Camera row → prompt → Don't Allow → row reads "Denied", the note under the rows appears, footer reads "Allow and finish" only if the mic is still askable (here the camera is denied, so it reads "Finish"). Tap the Camera row → the Settings app opens on Reps. Enable Camera there, return → row reads "Allowed" (scenePhase refresh), note gone. Tap Finish → Plans.
   - Audio off path: not reachable before onboarding in the UI (Settings comes after); covered by `allowAndFinishSkipsMicWhenClipAudioOff`.
   - Rerun safety: with the app installed, `xcrun simctl spawn $UDID defaults delete com.fqvb.reps settings.hasCompletedOnboarding` (if it errors, skip this check), relaunch → onboarding shows again, the bag page shows the existing bag unchanged (13 clubs, nothing duplicated), rows reflect the real statuses.
7. Code-reference and design.md entries (Appendix D). `git add -A && git commit -m "added onboarding screens" -m "Refs #5"`

### Step 5: docs (`documented onboarding`)

1. `docs/plans/5-onboarding.md`: this plan.
2. `docs/adr/0014-capture-permissions.md` (next free number; check `ls docs/adr` first) — Appendix E.
3. `docs/open-questions.md`, Open table, next free number after the ones #6/#11/#12 added (Q34 at the time of writing; Q33 was already taken by #12 by the time this landed):
   `| Q34 | Mic prompt timing: #5 asks at onboarding when Record audio is on and the camera was just granted (F20, Figma 09); #22 will ask in context if still undetermined. Keep the onboarding prompt, or defer entirely to the first clip with audio? | #22 | Apple's guidance is "only when the user invokes the feature". Leaning: keep; the screen explains it and the toggle gates it. If the owner prefers deferral, delete \`asksMicrophoneOnFinish\` from \`allowAndFinish\` and the row tap keeps working. |`
4. `docs/roadmap.md`: #5 ☐ → ☑.
5. `git add -A && git commit -m "documented onboarding" -m "Refs #5"`

Then the review: run `fable-security-reviewer` on the branch (label `review:fable-security`), fix findings, re-run the suites in step 4.5, push, open a PR titled `added onboarding` with body `welcome, bag seeding, default angle, camera and mic prompts with denied paths` plus `Closes #5`.

## Tests

- `RepsTests/CapturePermissionsTests` (Unit, 2): `AVAuthorizationStatus` → `PermissionState` for the four known cases (`@unknown default` can't be constructed in a test), `CaptureMedium.mediaType`.
- `RepsTests/OnboardingModelTests` (Unit, 11, `FakePermissions` scripted): page order and clamping; initial states read from the fake; allow-and-finish asks camera then mic in that order and sets the flag; mic skipped when Record audio is off; mic skipped when the camera comes back denied; nothing asked when both are already decided; restricted mic never asked; row actions per state; `request` ignored unless notDetermined; `refresh` picks up a change made outside; `willPrompt`.
- `RepsTests/OnboardingCopyTests` (Unit, 5): continue title (0 / 1 / 14), finish title, status pills, camera note per state, feature count.
- `RepsTests/BagSeedingTests` (Unit, 3): seeds 14 in catalog order into an empty store; second call is a no-op and returns false; an existing (hidden) club blocks seeding.
- `RepsTests/AppSettingsTests` (#6): flag default, round trip, key name.
- Views (`OnboardingView`, `PageDots`, `RootView` branch): build only + the smoke test (CLAUDE.md test table; no UI test target).

## Verification

```sh
for DEST in "$DEST27" "$DEST265"; do
  xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" \
    -only-testing:RepsTests/CapturePermissionsTests -only-testing:RepsTests/OnboardingModelTests \
    -only-testing:RepsTests/OnboardingCopyTests -only-testing:RepsTests/BagSeedingTests \
    -only-testing:RepsTests/AppSettingsTests -only-testing:RepsTests/BagLibraryTests
done
xcrun swift-format lint --strict --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
grep -rn "PLACEHOLDER:" Reps/Onboarding Reps/UI/Onboarding | wc -l      # 9 (list below)
grep -rn "requestAccess\|AVCaptureDevice" Reps | grep -v Reps/Permissions   # nothing: DevicePermissions is the only caller
plutil -p build/DerivedData/Build/Products/Debug-iphonesimulator/Reps.app/Info.plist | grep -c UsageDescription   # 2
```

Plus the full Unit plan on both simulators (step 4.5) and the smoke test (step 4.6). The iOS 26.5 run matters for SwiftData (ADR 0013) and for `@Observable` under the older runtime.

## Placeholders (`// PLACEHOLDER:` in code)

| Where | What ships now |
|---|---|
| `OnboardingCopy.features` | SF Symbols in the feature circles (Figma circles are empty) |
| `OnboardingCopy.continueTitle(0)` | "Continue without clubs" |
| `OnboardingCopy.finishTitle` | "Finish" when nothing is left to ask (not in Figma) |
| `OnboardingCopy.status` | "Allowed" / "Denied" / "Restricted" pills (Figma only shows "Not yet") |
| `OnboardingCopy.cameraNote` | denied / restricted explanation under the rows |
| `WelcomePage` app mark | "40" tile; real icon still pending (#1) |
| `PageDots` | inactive dot colour = `Theme.hairline` |
| `CameraSetupIllustration` | drawn in code instead of an exported asset |
| `OnboardingView` seed alert | "Couldn't set up your bag." (#29) |

Figma copy used verbatim: welcome title/intro/features, "Get started", "Your bag" + intro, "Continue with 14 clubs" pattern, "Set up the camera" + intro, illustration caption, "Default angle", "Face-on", "Camera / Counting and clips", "Microphone / Only for sound on your clips, optional", "Not yet", "Allow and finish". Deviation: "Down-the-line" (Settings spelling) instead of Figma's "Down the line".

TODOs left for other issues, written in code as `TODO(#22)` in `OnboardingModel.asksMicrophoneOnFinish`'s comment: #22 re-checks the mic in context; #13 reuses `DevicePermissions` before starting capture.

## Threat notes (for `fable-security-reviewer`)

- **Prompts and strings.** Camera and microphone are the only permissions touched. Both usage strings are set as `INFOPLIST_KEY_*` build settings on the app target (generated Info.plist, ADR 0009) and verified with `plutil` in step 1; they state purpose and that video stays on the phone. No Photos, location, contacts or notifications. Nothing is requested at launch: the first prompt is on the third screen after an on-screen explanation, on a tap ("Allow and finish" or a row). The mic is never requested when the camera is denied/restricted, when Record audio is off, or when it's restricted.
- **Denial paths.** Denied → row "Denied", explanatory note, tap opens `UIApplication.openSettingsURLString` through SwiftUI's `openURL` (no `UIApplication.shared.open` from a view), statuses refresh on `scenePhase == .active`. Restricted → row "Restricted", note, no action (the OS won't allow it). Onboarding always completes; the app never gates on a permission (spec §6, manual counting). `@unknown default` maps to `.denied` (fail closed). `DevicePermissions.request` re-reads the status instead of trusting the returned `Bool`, so restricted never shows as "Denied by user".
- **Single choke point.** `DevicePermissions` is the only code that calls `AVCaptureDevice.authorizationStatus`/`requestAccess` (grep in Verification). Later issues (#13 capture, #22 audio) go through the same protocol, so the prompt policy stays in one file and one ADR.
- **What leaves the device.** Nothing. No network, no share, no export. `openURL` is only ever given `UIApplication.openSettingsURLString`, never user text.
- **File paths from user input.** None. Onboarding writes only `BagClub` rows (SwiftData) and `UserDefaults` keys; no files are created. Club names typed in `BagEditorView` are #6's responsibility (they stay in SwiftData, ADR 0006).
- **Persisted state.** `settings.hasCompletedOnboarding` (Bool) and `settings.defaultCameraAngle` (existing #6 key). Permission statuses are **not** cached in UserDefaults: they're re-read from TCC every time, so the UI can't disagree with the system. No capture session is created here, so no frames or audio are ever captured during onboarding.
- **Seeding.** `seedDefaultBag` inserts fixed catalog names only when the table is empty; it can't duplicate, can't undo a user's edits, and runs inside the main context with one save.
- **Simulator note.** TCC prompts work on the simulator; `xcrun simctl privacy` and `simctl uninstall` reset them for the smoke test. No test ever calls `DevicePermissions.request`.

## Risks and unresolved

- **`@AppStorage` flip vs `AppSettings` write.** `OnboardingModel.finish()` writes `UserDefaults.standard`; `RootView`'s `@AppStorage` observes the same key and swaps to the tabs. If the swap doesn't happen on device, have `OnboardingView` take an `onFinish` closure that `RootView` uses to set its own `hasCompletedOnboarding = true`, and report.
- **Transition polish.** `.push(from: .trailing)` inside a `ZStack` with `withAnimation` is the documented conditional-view pattern; if pages overlap during the animation, wrap the `ZStack` content in `.clipped()`. Visual only.
- **Denied-camera note copy** and the extra pill states are placeholders; the owner may want different wording (they're all in `OnboardingCopy`).
- **Q34 (mic prompt timing)** is the owner's call; the code change either way is one line.
- **Rerun path.** If the owner wants a "Show onboarding again" or "Reset" entry, it belongs in Settings (#6 follow-up), not here.
- **`Canvas` illustration** doesn't follow Dynamic Type or high contrast; it's decorative and has an accessibility label.
- **#6 drift.** If `BagEditorView` grows chrome (title, scroll view) before this lands, `BagPage` must drop its own `ScrollView`/title to avoid doubling.

## Appendix A: logic (type-checked, copy exactly)

### `Reps/Permissions/CapturePermissions.swift`

```swift
import Foundation

nonisolated enum CaptureMedium: CaseIterable, Sendable {
    case camera
    case microphone
}

// App-side view of AVAuthorizationStatus.
nonisolated enum PermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

// The only way the app asks for the camera or mic. DevicePermissions is the real one; tests use a fake.
protocol CapturePermissions {
    func state(of medium: CaptureMedium) -> PermissionState
    // Prompts only while notDetermined; otherwise returns the current state.
    func request(_ medium: CaptureMedium) async -> PermissionState
}
```

### `Reps/Permissions/DevicePermissions.swift`

```swift
import AVFoundation

extension PermissionState {
    // Unknown future cases read as denied, so the UI offers Settings instead of assuming access.
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

extension CaptureMedium {
    var mediaType: AVMediaType {
        switch self {
        case .camera: .video
        case .microphone: .audio
        }
    }
}

// AVCaptureDevice-backed. The INFOPLIST_KEY_NS*UsageDescription strings must exist or the request crashes.
struct DevicePermissions: CapturePermissions {
    func state(of medium: CaptureMedium) -> PermissionState {
        PermissionState(AVCaptureDevice.authorizationStatus(for: medium.mediaType))
    }

    func request(_ medium: CaptureMedium) async -> PermissionState {
        guard state(of: medium) == .notDetermined else { return state(of: medium) }
        _ = await AVCaptureDevice.requestAccess(for: medium.mediaType)
        // Re-read rather than trust the Bool: restricted also answers false.
        return state(of: medium)
    }
}
```

### `Reps/Onboarding/OnboardingModel.swift`

```swift
import Foundation

nonisolated enum OnboardingPage: Int, CaseIterable, Sendable {
    case welcome
    case bag
    case camera
}

// What a tap on a permission row does.
nonisolated enum PermissionRowAction: Equatable, Sendable {
    case request
    case openSettings
    case none
}

// Onboarding state (F20). Prompts go through CapturePermissions, so tests never reach TCC.
@Observable
final class OnboardingModel {
    private(set) var page: OnboardingPage = .welcome
    private(set) var camera: PermissionState = .notDetermined
    private(set) var microphone: PermissionState = .notDetermined
    private(set) var isRequesting = false
    private(set) var isFinished = false

    private let permissions: any CapturePermissions
    private let settings: AppSettings

    init(permissions: any CapturePermissions, settings: AppSettings = AppSettings()) {
        self.permissions = permissions
        self.settings = settings
        refresh()
    }

    var isLastPage: Bool { page == .camera }

    // The mic is asked only when clips will carry audio and the camera is usable.
    // TODO(#22): re-check in context before the first recording with audio on; ask then if still undetermined.
    var asksMicrophoneOnFinish: Bool {
        microphone == .notDetermined && camera == .granted && settings.recordClipAudio
    }

    // Whether "Allow and finish" will show at least one system prompt.
    var willPrompt: Bool {
        camera == .notDetermined || asksMicrophoneOnFinish
    }

    func state(of medium: CaptureMedium) -> PermissionState {
        switch medium {
        case .camera: camera
        case .microphone: microphone
        }
    }

    func advance() {
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        page = next
    }

    // Re-read after the Settings app may have changed things.
    func refresh() {
        camera = permissions.state(of: .camera)
        microphone = permissions.state(of: .microphone)
    }

    func rowAction(for medium: CaptureMedium) -> PermissionRowAction {
        switch state(of: medium) {
        case .notDetermined: .request
        case .denied: .openSettings
        case .granted, .restricted: .none
        }
    }

    func request(_ medium: CaptureMedium) async {
        guard state(of: medium) == .notDetermined, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        let result = await permissions.request(medium)
        switch medium {
        case .camera: camera = result
        case .microphone: microphone = result
        }
    }

    // Camera first, then the mic. A denial never blocks: manual counting works without either (spec §6).
    func allowAndFinish() async {
        guard !isRequesting else { return }
        await request(.camera)
        if asksMicrophoneOnFinish { await request(.microphone) }
        finish()
    }

    func finish() {
        settings.hasCompletedOnboarding = true
        isFinished = true
    }
}
```

### `Reps/Onboarding/OnboardingCopy.swift`

```swift
import Foundation

nonisolated struct OnboardingFeature: Identifiable, Sendable {
    let title: String
    let detail: String
    let symbol: String
    var id: String { title }
}

// Copy for onboarding (Figma 07–09); pure, unit-tested.
nonisolated enum OnboardingCopy {
    static let welcomeTitle = "Count every shot.\nKeep every swing."
    static let welcomeIntro =
        "Put your phone on a tripod. Reps counts your range balls and putts, calls the number out loud, and saves a clip of every swing."
    // PLACEHOLDER: feature icons (the Figma circles are empty)
    static let features = [
        OnboardingFeature(
            title: "Practice plans", detail: "40 pitching wedges, then 30 nine irons — in order or any order.",
            symbol: "list.bullet.rectangle"),
        OnboardingFeature(
            title: "Counts by camera", detail: "Sees the ball leave, not your practice swings.", symbol: "camera"),
        OnboardingFeature(
            title: "Clips and tempo", detail: "Every swing trimmed and tagged, with your tempo ratio.", symbol: "film"),
    ]
    static let getStarted = "Get started"
    static let bagTitle = "Your bag"
    static let bagIntro =
        "Tap to add or remove clubs. This is the list you pick from when building a plan. Change it any time in Settings."
    static let cameraTitle = "Set up the camera"
    static let cameraIntro =
        "Reps needs the camera to count and record. The microphone only adds sound to your clips. Nothing leaves your phone."
    static let illustrationCaption = "Whole body and ball in frame · tripod at hip height"
    static let angleLabel = "Default angle"
    static let cameraRow = (title: "Camera", subtitle: "Counting and clips")
    static let microphoneRow = (title: "Microphone", subtitle: "Only for sound on your clips, optional")

    static func continueTitle(clubCount: Int) -> String {
        switch clubCount {
        case 0: "Continue without clubs"  // PLACEHOLDER: empty-bag continue copy
        case 1: "Continue with 1 club"
        default: "Continue with \(clubCount) clubs"
        }
    }

    // "Finish" once nothing is left to ask. PLACEHOLDER: not in Figma
    static func finishTitle(willPrompt: Bool) -> String {
        willPrompt ? "Allow and finish" : "Finish"
    }

    // Status pill. PLACEHOLDER: only "Not yet" is in Figma
    static func status(_ state: PermissionState) -> String {
        switch state {
        case .notDetermined: "Not yet"
        case .granted: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }

    // Under the rows when the camera can't be used; nil otherwise. PLACEHOLDER: denied/restricted copy
    static func cameraNote(_ state: PermissionState) -> String? {
        switch state {
        case .denied: "Reps can't count by camera until you allow it in Settings. The +1 button always works."
        case .restricted: "Camera access is restricted on this phone. You can still count with the +1 button."
        case .notDetermined, .granted: nil
        }
    }
}
```

## Appendix B: views (type-checked, copy exactly)

### `Reps/UI/Theme/Theme.swift` (two added lines, see step 4.1)

```swift
    static let illustration = Color(hex: 0x8A9A84)
    static let ballBox = Color(hex: 0xE6D35A)
```

### `Reps/UI/Onboarding/OnboardingTheme.swift`

```swift
import SwiftUI

// Onboarding values from Figma 07–09.
extension Theme.Typography {
    static let appMark = Font.system(size: 34, weight: .bold)
    static let onboardingIntro = Font.body
    static let illustrationCaption = Font.caption.weight(.medium)
}

extension Theme.Spacing {
    static let welcomeTop: CGFloat = 80
    static let welcomeGutter: CGFloat = 28
    static let welcomeGap: CGFloat = 28
    static let onboardingGap: CGFloat = 18
}

extension Theme.Radius {
    static let appMark: CGFloat = 22
    static let illustration: CGFloat = 20
    static let segment: CGFloat = 14
    static let segmentInner: CGFloat = 11
}
```

### `Reps/UI/Onboarding/PageDots.swift`

```swift
import SwiftUI

// Figma page dots: the current page is an 18×6 accent capsule, the others 6 pt dots.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.accent : Theme.hairline)  // PLACEHOLDER: inactive dot colour
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }
}
```

### `Reps/UI/Onboarding/OnboardingView.swift`

```swift
import SwiftData
import SwiftUI
import UIKit

// Figma 07–09 (F19, F20). RootView shows it until AppSettings.hasCompletedOnboarding is set.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query private var clubs: [BagClub]
    @State private var model: OnboardingModel
    @State private var seedFailed = false

    init(permissions: any CapturePermissions) {
        _model = State(initialValue: OnboardingModel(permissions: permissions))
    }

    var body: some View {
        ZStack {
            switch model.page {
            case .welcome:
                WelcomePage().transition(.push(from: .trailing))
            case .bag:
                BagPage().transition(.push(from: .trailing))
            case .camera:
                CameraPage(model: model, onOpenSettings: openSettings).transition(.push(from: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { footer }
        .task { seed() }
        // Back from the Settings app: the rows re-read what the user changed there.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
        .alert("Couldn't set up your bag.", isPresented: $seedFailed) {  // PLACEHOLDER: error copy (#29)
            Button("OK", role: .cancel) {}
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            PageDots(count: OnboardingPage.allCases.count, current: model.page.rawValue)
            FooterCTA(title: footerTitle, isEnabled: !model.isRequesting, action: footerAction)
        }
        .background(Theme.background)
    }

    private var footerTitle: String {
        switch model.page {
        case .welcome: OnboardingCopy.getStarted
        case .bag: OnboardingCopy.continueTitle(clubCount: clubs.count { $0.isInBag })
        case .camera: OnboardingCopy.finishTitle(willPrompt: model.willPrompt)
        }
    }

    private func footerAction() {
        if model.isLastPage {
            Task { await model.allowAndFinish() }
        } else {
            withAnimation { model.advance() }
        }
    }

    // Idempotent: only an empty bag table gets the common 14 (F19).
    private func seed() {
        do {
            try BagLibrary.seedDefaultBag(in: context)
        } catch {
            seedFailed = true
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// Figma 07.
private struct WelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.welcomeGap) {
                Text("40")  // PLACEHOLDER: app mark (Figma's "40" tile; the real icon is still the #1 placeholder)
                    .font(Theme.Typography.appMark)
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.appMark))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(OnboardingCopy.welcomeTitle)
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.ink)
                    Text(OnboardingCopy.welcomeIntro)
                        .font(Theme.Typography.onboardingIntro)
                        .foregroundStyle(Theme.secondaryText)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(OnboardingCopy.features) { feature in
                        HStack(spacing: 14) {
                            Image(systemName: feature.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 40)
                                .background(Theme.card, in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(Theme.Typography.rowTitle)
                                    .foregroundStyle(Theme.ink)
                                Text(feature.detail)
                                    .font(Theme.Typography.detail)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.welcomeGutter)
            .padding(.top, Theme.Spacing.welcomeTop)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// Figma 08: the shared bag grid under its onboarding title.
private struct BagPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.onboardingGap) {
                PageTitle(title: OnboardingCopy.bagTitle, intro: OnboardingCopy.bagIntro)
                BagEditorView()
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
    }
}

// Figma 09.
private struct CameraPage: View {
    let model: OnboardingModel
    let onOpenSettings: () -> Void
    @AppStorage(AppSettings.Key.defaultCameraAngle) private var defaultAngle: CameraAngle =
        AppSettings.Default.cameraAngle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.onboardingGap) {
                PageTitle(title: OnboardingCopy.cameraTitle, intro: OnboardingCopy.cameraIntro)
                CameraSetupIllustration()
                VStack(alignment: .leading, spacing: 8) {
                    Text(OnboardingCopy.angleLabel)
                        .font(Theme.Typography.footnoteMedium)
                        .foregroundStyle(Theme.secondaryText)
                    AngleSegments(selection: $defaultAngle)
                }
                VStack(alignment: .leading, spacing: 8) {
                    PermissionRow(
                        title: OnboardingCopy.cameraRow.title, subtitle: OnboardingCopy.cameraRow.subtitle,
                        state: model.camera, action: model.rowAction(for: .camera)
                    ) { tapped(.camera) }
                    PermissionRow(
                        title: OnboardingCopy.microphoneRow.title, subtitle: OnboardingCopy.microphoneRow.subtitle,
                        state: model.microphone, action: model.rowAction(for: .microphone)
                    ) { tapped(.microphone) }
                    if let note = OnboardingCopy.cameraNote(model.camera) {
                        Text(note)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func tapped(_ medium: CaptureMedium) {
        switch model.rowAction(for: medium) {
        case .request: Task { await model.request(medium) }
        case .openSettings: onOpenSettings()
        case .none: break
        }
    }
}

private struct PageTitle: View {
    let title: String
    let intro: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.ink)
            Text(intro)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Figma 09 "Angle selector": white segment on a grey track.
private struct AngleSegments: View {
    @Binding var selection: CameraAngle

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppSettings.angleChoices, id: \.self) { angle in
                let selected = angle == selection
                Button {
                    selection = angle
                } label: {
                    Text(SettingsCopy.angleTitle(angle))
                        .font(selected ? Theme.Typography.chipSelected : Theme.Typography.chip)
                        .foregroundStyle(selected ? Theme.ink : Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selected ? Theme.background : Color.clear,
                            in: .rect(cornerRadius: Theme.Radius.segmentInner)
                        )
                        .contentShape(.rect(cornerRadius: Theme.Radius.segmentInner))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.segment))
    }
}

// Figma 09 permission card: title, subtitle, status pill. Tap asks (Not yet) or opens Settings (Denied).
private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let state: PermissionState
    let action: PermissionRowAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Text(OnboardingCopy.status(state))
                    .font(Theme.Typography.footnoteMedium)
                    .foregroundStyle(state == .granted ? Theme.accent : Theme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.background, in: .capsule)
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 14)
            .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
            .contentShape(.rect(cornerRadius: Theme.Radius.row))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != .none)
        .accessibilityElement(children: .combine)
        .accessibilityHint(action == .openSettings ? "Opens Settings" : "")
    }
}

// Figma 09 "Setup illustration", drawn at the frame's 353×200 coordinates. PLACEHOLDER: replace with an asset if one lands.
private struct CameraSetupIllustration: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 353
            var figure = Path()
            figure.addEllipse(in: CGRect(x: 166, y: 48, width: 20, height: 20))
            figure.move(to: CGPoint(x: 176, y: 70))
            figure.addLine(to: CGPoint(x: 176, y: 128))
            figure.move(to: CGPoint(x: 176, y: 88))
            figure.addLine(to: CGPoint(x: 142, y: 116))
            figure.move(to: CGPoint(x: 176, y: 88))
            figure.addLine(to: CGPoint(x: 212, y: 110))
            figure.move(to: CGPoint(x: 176, y: 128))
            figure.addLine(to: CGPoint(x: 160, y: 186))
            figure.move(to: CGPoint(x: 176, y: 128))
            figure.addLine(to: CGPoint(x: 194, y: 186))
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            context.stroke(
                figure.applying(transform), with: .color(.white),
                style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
            let box = Path(roundedRect: CGRect(x: 262, y: 166, width: 22, height: 22), cornerRadius: 5)
            context.stroke(box.applying(transform), with: .color(Theme.ballBox), lineWidth: 2.5 * scale)
        }
        .aspectRatio(353.0 / 200.0, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            Text(OnboardingCopy.illustrationCaption)
                .font(Theme.Typography.illustrationCaption)
                .foregroundStyle(.white)
                .padding(14)
        }
        .background(Theme.illustration, in: .rect(cornerRadius: Theme.Radius.illustration))
        .accessibilityLabel(OnboardingCopy.illustrationCaption)
    }
}

#if DEBUG
    private struct PreviewPermissions: CapturePermissions {
        func state(of medium: CaptureMedium) -> PermissionState { .notDetermined }
        func request(_ medium: CaptureMedium) async -> PermissionState { .granted }
    }

    #Preview {
        OnboardingView(permissions: PreviewPermissions())
    }
#endif
```

### `Reps/App/RootView.swift` (top of the file after the edit; everything from `// One controller…` down is unchanged)

```swift
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var sessions: SessionController?
    @State private var pendingResume: PracticeSession?
    @State private var startFailed = false
    @AppStorage(AppSettings.Key.hasCompletedOnboarding) private var hasCompletedOnboarding =
        AppSettings.Default.hasCompletedOnboarding

    var body: some View {
        if hasCompletedOnboarding {
            tabs
        } else {
            // F20: shown once. The resume prompt lives on the tabs, so it waits until onboarding is done.
            OnboardingView(permissions: DevicePermissions())
        }
    }

    private var tabs: some View {
        let isInSession = sessions?.session != nil
        return TabView {
            Tab("Plans", systemImage: "list.bullet.rectangle") {  // PLACEHOLDER: Plans tab icon
                PlansView(onStartPlan: start(plan:), onStartFreeSession: startFree)
            }
            Tab("Library", systemImage: "film.stack") {  // PLACEHOLDER: Library tab icon
                LibraryPlaceholderView()
            }
        }
        .tint(Theme.accent)
        // Driven by the controller: finish() or discard() clears the session and closes the cover.
        .fullScreenCover(isPresented: Binding(get: { isInSession }, set: { _ in })) {
            if let sessions { SessionView(controller: sessions) }
        }
        .task { offerResume() }
        .alert(
            "Resume session?",  // PLACEHOLDER: resume prompt copy
            isPresented: Binding(get: { pendingResume != nil }, set: { if !$0 { pendingResume = nil } }),
            presenting: pendingResume
        ) { saved in
            Button("Resume") { resume(saved) }
            Button("End it") { endWithoutResuming(saved) }  // PLACEHOLDER: decline button copy
        } message: { saved in
            Text(
                SessionDisplay.resumeMessage(
                    title: SessionDisplay.title(planName: saved.planName),
                    done: saved.blockResults.reduce(0) { $0 + $1.tally.done },
                    mode: saved.mode))
        }
        .alert("Couldn't start the session.", isPresented: $startFailed) {  // PLACEHOLDER: start error copy (#29)
            Button("OK", role: .cancel) {}
        }
    }
```

If #6 or #11 changed the tab body on `main` (e.g. `start(plan:)` now reads `AppSettings().cameraAngle(for:)`), keep `main`'s version of the tab body: the only changes here are the `@AppStorage` property, the new `body`, and wrapping the old body in `private var tabs` with `return`.

## Appendix C: tests (copy exactly)

### `RepsTests/CapturePermissionsTests.swift`

```swift
import AVFoundation
import Testing

@testable import Reps

@MainActor
struct CapturePermissionsTests {
    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, PermissionState.notDetermined),
        (.authorized, .granted),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func mapsAuthorizationStatus(status: AVAuthorizationStatus, expected: PermissionState) {
        #expect(PermissionState(status) == expected)
    }

    @Test func mediaTypes() {
        #expect(CaptureMedium.camera.mediaType == .video)
        #expect(CaptureMedium.microphone.mediaType == .audio)
    }
}
```

### `RepsTests/OnboardingModelTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

// Scripted permissions: `answers` is what a prompt would return; `requests` records every prompt.
@MainActor
final class FakePermissions: CapturePermissions {
    var states: [CaptureMedium: PermissionState]
    var answers: [CaptureMedium: PermissionState] = [:]
    private(set) var requests: [CaptureMedium] = []

    init(camera: PermissionState = .notDetermined, microphone: PermissionState = .notDetermined) {
        states = [.camera: camera, .microphone: microphone]
    }

    func state(of medium: CaptureMedium) -> PermissionState {
        states[medium] ?? .notDetermined
    }

    func request(_ medium: CaptureMedium) async -> PermissionState {
        requests.append(medium)
        if let answer = answers[medium] { states[medium] = answer }
        return state(of: medium)
    }
}

@MainActor
final class OnboardingModelTests {
    private let suite = "RepsTests.Onboarding.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let settings: AppSettings

    init() {
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ permissions: FakePermissions) -> OnboardingModel {
        OnboardingModel(permissions: permissions, settings: settings)
    }

    @Test func pagesGoForwardAndStopAtCamera() {
        let model = model(FakePermissions())
        #expect(model.page == .welcome)
        #expect(!model.isLastPage)
        model.advance()
        #expect(model.page == .bag)
        model.advance()
        #expect(model.page == .camera)
        #expect(model.isLastPage)
        model.advance()
        #expect(model.page == .camera)
    }

    @Test func readsInitialStates() {
        let model = model(FakePermissions(camera: .denied, microphone: .granted))
        #expect(model.camera == .denied)
        #expect(model.microphone == .granted)
        #expect(model.state(of: .camera) == .denied)
        #expect(model.state(of: .microphone) == .granted)
        #expect(!model.isFinished)
        #expect(settings.hasCompletedOnboarding == false)
    }

    @Test func allowAndFinishAsksCameraThenMicrophone() async {
        let fake = FakePermissions()
        fake.answers = [.camera: .granted, .microphone: .granted]
        let model = model(fake)
        #expect(model.willPrompt)
        await model.allowAndFinish()
        #expect(fake.requests == [.camera, .microphone])
        #expect(model.camera == .granted)
        #expect(model.microphone == .granted)
        #expect(model.isFinished)
        #expect(settings.hasCompletedOnboarding)
        #expect(!model.isRequesting)
    }

    @Test func allowAndFinishSkipsMicWhenClipAudioOff() async {
        settings.recordClipAudio = false
        let fake = FakePermissions()
        fake.answers = [.camera: .granted]
        let model = model(fake)
        await model.allowAndFinish()
        #expect(fake.requests == [.camera])
        #expect(model.microphone == .notDetermined)
        #expect(model.isFinished)
    }

    @Test func deniedCameraSkipsMicAndStillFinishes() async {
        let fake = FakePermissions()
        fake.answers = [.camera: .denied]
        let model = model(fake)
        await model.allowAndFinish()
        #expect(fake.requests == [.camera])
        #expect(model.camera == .denied)
        #expect(model.microphone == .notDetermined)
        #expect(model.isFinished)
        #expect(settings.hasCompletedOnboarding)
    }

    @Test func decidedPermissionsAreNotAskedAgain() async {
        let fake = FakePermissions(camera: .granted, microphone: .denied)
        let model = model(fake)
        #expect(!model.willPrompt)
        await model.allowAndFinish()
        #expect(fake.requests.isEmpty)
        #expect(model.isFinished)
    }

    @Test func restrictedMicrophoneIsNeverAsked() async {
        let fake = FakePermissions(camera: .granted, microphone: .restricted)
        let model = model(fake)
        #expect(!model.asksMicrophoneOnFinish)
        await model.request(.microphone)
        await model.allowAndFinish()
        #expect(fake.requests.isEmpty)
    }

    @Test func rowActionsFollowTheState() {
        let model = model(FakePermissions(camera: .notDetermined, microphone: .denied))
        #expect(model.rowAction(for: .camera) == .request)
        #expect(model.rowAction(for: .microphone) == .openSettings)
        let decided = model(FakePermissions(camera: .granted, microphone: .restricted))
        #expect(decided.rowAction(for: .camera) == .none)
        #expect(decided.rowAction(for: .microphone) == .none)
    }

    @Test func requestOnlyPromptsWhileUndetermined() async {
        let fake = FakePermissions(camera: .denied)
        fake.answers = [.microphone: .granted]
        let model = model(fake)
        await model.request(.camera)
        #expect(fake.requests.isEmpty)
        await model.request(.microphone)
        #expect(fake.requests == [.microphone])
        #expect(model.microphone == .granted)
        #expect(!model.isFinished)
    }

    @Test func refreshPicksUpChangesMadeInSettings() {
        let fake = FakePermissions(camera: .denied)
        let model = model(fake)
        fake.states[.camera] = .granted
        #expect(model.camera == .denied)
        model.refresh()
        #expect(model.camera == .granted)
    }

    @Test func willPromptOnlyWhileSomethingIsAskable() {
        #expect(model(FakePermissions(camera: .notDetermined, microphone: .granted)).willPrompt)
        // Mic still undetermined but the camera isn't granted yet: the mic alone doesn't count.
        #expect(!model(FakePermissions(camera: .denied, microphone: .notDetermined)).willPrompt)
        #expect(model(FakePermissions(camera: .granted, microphone: .notDetermined)).willPrompt)
        settings.recordClipAudio = false
        #expect(!model(FakePermissions(camera: .granted, microphone: .notDetermined)).willPrompt)
    }
}
```

### `RepsTests/OnboardingCopyTests.swift`

```swift
import Testing

@testable import Reps

struct OnboardingCopyTests {
    @Test func continueTitle() {
        #expect(OnboardingCopy.continueTitle(clubCount: 0) == "Continue without clubs")
        #expect(OnboardingCopy.continueTitle(clubCount: 1) == "Continue with 1 club")
        #expect(OnboardingCopy.continueTitle(clubCount: 14) == "Continue with 14 clubs")
    }

    @Test func finishTitle() {
        #expect(OnboardingCopy.finishTitle(willPrompt: true) == "Allow and finish")
        #expect(OnboardingCopy.finishTitle(willPrompt: false) == "Finish")
    }

    @Test func statusPills() {
        #expect(OnboardingCopy.status(.notDetermined) == "Not yet")
        #expect(OnboardingCopy.status(.granted) == "Allowed")
        #expect(OnboardingCopy.status(.denied) == "Denied")
        #expect(OnboardingCopy.status(.restricted) == "Restricted")
    }

    @Test func cameraNoteOnlyWhenUnusable() {
        #expect(OnboardingCopy.cameraNote(.notDetermined) == nil)
        #expect(OnboardingCopy.cameraNote(.granted) == nil)
        #expect(OnboardingCopy.cameraNote(.denied)?.contains("Settings") == true)
        #expect(OnboardingCopy.cameraNote(.restricted)?.contains("+1") == true)
    }

    @Test func threeFeaturesWithUniqueTitles() {
        #expect(OnboardingCopy.features.count == 3)
        #expect(Set(OnboardingCopy.features.map(\.id)).count == 3)
    }
}
```

### `RepsTests/BagSeedingTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct BagSeedingTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    @Test func seedsTheDefaultBagIntoAnEmptyStore() throws {
        #expect(try BagLibrary.seedDefaultBag(in: context))
        let clubs = try BagLibrary.all(in: context)
        #expect(clubs.map(\.name) == BagCatalog.defaultBag)
        #expect(clubs.map(\.sortOrder) == Array(0..<BagCatalog.defaultBag.count))
        #expect(clubs.allSatisfy(\.isInBag))
    }

    @Test func secondSeedIsANoOp() throws {
        try BagLibrary.seedDefaultBag(in: context)
        #expect(try BagLibrary.seedDefaultBag(in: context) == false)
        #expect(try BagLibrary.all(in: context).count == BagCatalog.defaultBag.count)
    }

    @Test func existingBagIsLeftAlone() throws {
        context.insert(BagClub(name: "Chipper", sortOrder: 0, isInBag: false))
        try context.save()
        #expect(try BagLibrary.seedDefaultBag(in: context) == false)
        let clubs = try BagLibrary.all(in: context)
        #expect(clubs.map(\.name) == ["Chipper"])
        #expect(clubs[0].isInBag == false)
    }
}
```

## Appendix D: docs entries

`docs/code-reference.md`:

- `Reps/App/RootView.swift` entry: change the first words to "Root TabView (Plans, Library), the session host, and the onboarding gate." and append to the bullet: "; shows `OnboardingView(permissions: DevicePermissions())` instead of the tabs while `AppSettings.hasCompletedOnboarding` is false (the resume prompt waits for the tabs)".
- `Reps/Settings/AppSettings.swift` entry (#6): add `hasCompletedOnboarding` to the key/default/accessor lists ("set once by onboarding, #5").
- `Reps/Bag/BagLibrary.swift` entry (#6): add ``- `seedDefaultBag(in:) throws -> Bool`: inserts `BagCatalog.defaultBag` in catalog order only when there are no BagClub rows at all; false otherwise (idempotent, #5)``.
- `Reps/UI/Theme/Theme.swift`: add `illustration` (0x8A9A84) and `ballBox` (0xE6D35A) to the colour list.
- Add after the `Reps/Session/ClipFileRemoving.swift` entry:

```
## Reps/Permissions/CapturePermissions.swift
The app's view of camera and microphone authorization; the only way the app asks (ADR 0014).
- `CaptureMedium`: camera, microphone
- `PermissionState`: notDetermined, granted, denied, restricted
- `CapturePermissions`: `state(of:)`, `request(_:) async -> PermissionState` (prompts only while notDetermined)

## Reps/Permissions/DevicePermissions.swift
- `PermissionState.init(_ status: AVAuthorizationStatus)`: authorized → granted; `@unknown default` → denied (fail closed)
- `CaptureMedium.mediaType`: `.video` / `.audio`
- `DevicePermissions`: `AVCaptureDevice.authorizationStatus(for:)` / `requestAccess(for:)`; re-reads the status after the prompt instead of trusting the Bool. Needs the `INFOPLIST_KEY_NS{Camera,Microphone}UsageDescription` build settings.

## Reps/Onboarding/OnboardingModel.swift
Onboarding state (F20); MainActor, `@Observable`, no SwiftUI. Tests drive it with a fake `CapturePermissions`.
- `OnboardingPage`: welcome, bag, camera; `PermissionRowAction`: request, openSettings, none
- `OnboardingModel(permissions:settings:)`: `page`, `camera`, `microphone`, `isRequesting`, `isFinished`; `isLastPage`, `asksMicrophoneOnFinish` (mic undetermined, camera granted, Record audio on), `willPrompt`
- `advance()` (forward only, stops at camera), `refresh()` (re-reads both statuses; called on scenePhase active), `rowAction(for:)` (notDetermined → request, denied → openSettings, else none), `request(_:) async` (only while notDetermined and not already requesting), `allowAndFinish() async` (camera, then mic if `asksMicrophoneOnFinish`, then `finish()` regardless), `finish()` (sets `AppSettings.hasCompletedOnboarding`)

## Reps/Onboarding/OnboardingCopy.swift
Copy for Figma 07–09; pure, unit-tested.
- `OnboardingFeature(title:detail:symbol:)`; `OnboardingCopy.welcomeTitle/welcomeIntro/features/getStarted/bagTitle/bagIntro/cameraTitle/cameraIntro/illustrationCaption/angleLabel/cameraRow/microphoneRow`
- `continueTitle(clubCount:)`, `finishTitle(willPrompt:)`, `status(_:)` (pill text), `cameraNote(_:)` (denied/restricted explanation, else nil)
```

- Add after the `Reps/UI/Library/LibraryPlaceholderView.swift` entry:

```
## Reps/UI/Onboarding/OnboardingView.swift
Figma 07–09 (F19, F20). Shown by `RootView` until onboarding completes.
- `OnboardingView(permissions:)`: owns an `OnboardingModel`; pages switch with a push transition; footer = `PageDots` + `FooterCTA` (Get started / Continue with N clubs / Allow and finish|Finish); seeds the bag in `.task`; refreshes statuses on `scenePhase == .active`; Settings deep link via `openURL(UIApplication.openSettingsURLString)`
- private `WelcomePage`, `BagPage` (hosts `BagEditorView`), `CameraPage` (illustration, `AngleSegments` bound to the default-angle key, two `PermissionRow`s, denied/restricted note), `PageTitle`, `AngleSegments`, `PermissionRow`, `CameraSetupIllustration` (Canvas drawing of Figma 09)

## Reps/UI/Onboarding/PageDots.swift
- `PageDots(count:current:)`: 18×6 accent capsule for the current page, 6 pt dots otherwise

## Reps/UI/Onboarding/OnboardingTheme.swift
Onboarding values from Figma 07–09: `Theme.Typography.appMark` (34 bold), `onboardingIntro`, `illustrationCaption`; `Theme.Spacing.welcomeTop/welcomeGutter/welcomeGap/onboardingGap`; `Theme.Radius.appMark/illustration/segment/segmentInner`.
```

- Add after the last test entry:

```
## RepsTests/CapturePermissionsTests.swift
`AVAuthorizationStatus` → `PermissionState` mapping, media types.

## RepsTests/OnboardingModelTests.swift
- `FakePermissions`: scripted states and answers, records every request
- Page order, initial states, camera-then-mic on finish, mic skipped when Record audio is off or the camera is denied, decided/restricted never asked, row actions, request gating, refresh, `willPrompt`.

## RepsTests/OnboardingCopyTests.swift
Continue/finish titles, status pills, camera note, features.

## RepsTests/BagSeedingTests.swift
Default bag seeding: empty store, second run, existing bag untouched.
```

`docs/design.md`: below the table add `- Onboarding (#5): tokens in \`Reps/UI/Onboarding/OnboardingTheme.swift\`; the bag page hosts #6's \`BagEditorView\`; Figma 09's illustration is drawn in code; "Down-the-line" follows Settings, not Figma's "Down the line". Extra pill states and the denied note are placeholders.`

`docs/roadmap.md`: #5 ☐ → ☑.

## Appendix E: `docs/adr/0014-capture-permissions.md`

```markdown
# 0014 — Capture permissions: ask in context, never block

- Status: Accepted
- Date: <today>

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
```
