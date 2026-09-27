# Code reference

The documentation for files and functions. Code comments stay short, and the detail lives here. Update this file in the same commit as the code.

Format:

```
## path/to/File.swift
Purpose in one line.
- `TypeOrFunction(signature)`: what it does / returns, notable side effects
```

## Reps/App/RepsApp.swift
App entry point; opens the SwiftData store and shows the root view.
- `RepsApp`: `@main` app; builds the container with `RepsStore.makeContainer()` (fatal on failure until #29) and attaches it with `.modelContainer(_:)`

## Reps/App/RootView.swift
Root TabView (Plans, Library), the session host, and the onboarding gate.
- `RootView`: owns one `SessionController` (made on first use); Start hooks call `start(plan:cameraAngle:)` / `startFree(...)`, reading the default camera angle from `AppSettings().cameraAngle(for:)`; full-screen `SessionView` while `controller.session != nil`; launch "Resume session?" via `activeSession(in:)` (Resume, or "End it" = resume + finish, Q25 default); voice hook is `TODO(#10)`; shows `OnboardingView(permissions: DevicePermissions())` instead of the tabs while `AppSettings.hasCompletedOnboarding` is false (the resume prompt waits for the tabs); Library tab hosts `LibraryView` (#24)

## Reps/Model/ModelEnums.swift
Stored and exported enums; raw values are frozen (ADR 0012).
- `PracticeMode`: rangeCounter, rangeCounterWithClips, putting
- `CameraAngle`: faceOn, downTheLine, none (putting)
- `DetectionSource`: camera, manual
- `SessionStatus`: active, finished (ADR 0006)

## Reps/Model/Completion.swift
Pure completion math (spec §5.1, F21), nonisolated.
- `BlockTally(counted:manualAdjust:target:)`: `done` = max(0, counted + manualAdjust); `target` nil = free block
- `Completion.block(_:) -> Double?`: done / target, uncapped; nil without a positive target
- `Completion.isComplete(_:) -> Bool`: done ≥ target; false without a positive target
- `Completion.session(_:) -> Double?`: Σ min(done, target) / Σ target over targeted blocks (Q22: surplus never covers another block, max 1.0); nil if none

## Reps/Model/BagClub.swift
- `BagClub(name:sortOrder:isInBag:)`: one club in the user's bag; `isInBag` false hides it from pickers. No relationships.

## Reps/Model/PracticePlan.swift
- `PracticePlan(name:mode:isOrderMandatory:isStrictCount:createdAt:)`: reusable plan; `blocks` cascade, `sessions` nullify
- `sortedBlocks`: blocks by `(order, id)`, so ties are stable

## Reps/Model/PlanBlock.swift
- `PlanBlock(clubName:targetReps:note:order:)`: one block of a plan; `results` nullify on delete

## Reps/Model/PracticeSession.swift
- `PracticeSession(plan:mode:cameraAngle:startedAt:)`: one run (plan nil = free session); copies `planName`, `isStrictCount`, `isOrderMandatory`; `status` starts `.active`; `blockResults` cascade
- `activeBlockOrder`: `order` of the active block for resume; nil when no block is left (Q24, ADR 0013)
- `isFreeSession`: `planName == nil`
- `sortedBlockResults`: by `(order, id)`; `completion`: `Completion.session` over the results

## Reps/Model/BlockResult.swift
- `BlockResult(block:order:)`: result for a plan block; copies `clubName` and `targetReps`
- `BlockResult(clubName:tags:order:)`: free-session block, no target
- `tally`: `BlockTally` for completion; `sortedShots`: by `(timestamp, id)`; `shots` cascade

## Reps/Model/ShotRecord.swift
- `ShotRecord(timestamp:detectedBy:clubName:tags:)`: one counted shot; `clipFileName` is the bare `<id>.mov` in `Documents/clips/<sessionId>/` (ADR 0006)

## Reps/Model/RepsSchema.swift
- `RepsSchemaV1`: VersionedSchema 1.0.0 with the six models
- `RepsMigrationPlan`: schemas `[RepsSchemaV1]`, no stages yet
- `RepsSchemaCurrent`: alias for the schema the app actually runs (`RepsSchemaV1` today)

## Reps/Export/ExportDocument.swift
JSON export format v1 (ADR 0012); property names are the JSON keys.
- `ExportDocument`: `formatVersion`, `exportedAt`, `bag`, `plans`, `sessions`; `currentFormatVersion` = 1
- `ExportClub`, `ExportPlan`, `ExportPlanBlock`, `ExportSession` (with the `isStrictCount`/`isOrderMandatory` snapshot), `ExportBlockResult`, `ExportShot`: raw stored fields, ids for cross references

## Reps/Export/RepsExport.swift
- `RepsExport.document(clubs:plans:sessions:exportedAt:) -> ExportDocument`: sorted snapshot; finished sessions only; ties broken by `(sortOrder, name, id)` for clubs, `(createdAt, id)` for plans, `(startedAt, id)` for sessions, so export order is deterministic
- `RepsExport.document(from:exportedAt:) throws -> ExportDocument`: fetches everything from a context
- `RepsExport.bareFileName(_:) -> String`: last path component
- `ExportCoding.encode(_:) throws -> Data`: pretty, sorted keys, ISO 8601 UTC with ms; no file I/O
- `ExportCoding.decode(_:) throws -> ExportDocument`: inverse of `encode`
- `ExportCoding.encodeDate(_:) -> String`, `ExportCoding.decodeDate(_:) throws -> Date`: millisecond-rounded ISO 8601 UTC via whole-second formatting + a spliced-in `.mmm`, avoiding `ISO8601FormatStyle`'s fractional-seconds float truncation

## Reps/Settings/AppSettings.swift
Typed UserDefaults preferences (F25); nonisolated.
- `ClipQuality`: p1080fps60 (default), p1080fps30, p720fps30 (PLACEHOLDER, Q32); raw values persisted, never rename
- `AppSettings(defaults:)`: `Key` (persisted UserDefaults keys), `Default` (fallback values), `angleChoices` (faceOn/downTheLine; `.none` means putting, not a choice); typed accessors for each key, sanitizing unknown or `.none` stored angles back to `Default.cameraAngle`; `hasCompletedOnboarding` (set once by onboarding, #5)
- `cameraAngle(for:)`: `.none` for putting, `defaultCameraAngle` otherwise

## Reps/Settings/ClipStorage.swift
Clip folder size/count for the Settings Storage row.
- `ClipUsage(bytes:count:)`: `.zero`
- `ClipStorage.clipsDirectory`: `Documents/clips` (ADR 0006 root; #22 writes clips there)
- `ClipStorage.usage(at:fileManager:) -> ClipUsage`: sync `FileManager` enumeration of `.mov` files; call off the main actor; a missing folder is `.zero`
- `ClipStorage.clipURL(fileName:sessionID:root:) -> URL?`: `root/<sessionID>/<fileName>`; nil unless a bare `.mov` name (no separators, control chars, leading dot)

## Reps/Settings/SettingsCopy.swift
Copy for the Settings screen; pure, unit-tested.
- `clubCount(_:)`, `angleTitle(_:)`, `clipQualityTitle(_:)`: row copy
- `clipUsage(_:locale:)`: nil → "Calculating…" (PLACEHOLDER); zero → "No clips yet" (PLACEHOLDER); else byte count · clip count
- `version(info:)`: "<short> (<build>)" from the bundle's `CFBundleShortVersionString`/`CFBundleVersion`, falling back per missing part

## Reps/Persistence/RepsStore.swift
Builds the SwiftData container for the app and tests.
- `RepsStore.models`: the `@Model` types (`RepsSchemaCurrent.models`)
- `RepsStore.makeContainer(inMemory:) throws -> ModelContainer`: container over `RepsSchemaCurrent` with `RepsMigrationPlan`; `inMemory: true` for tests
- `RepsStore.makeContainer(url:) throws -> ModelContainer`: same, at a given store file (tests reopen it to simulate a kill)

## Reps/Session/SessionEvent.swift
What the session engine tells the voice layer (#10); plain values, nonisolated.
- `countChanged(done:target:)`: after every counted shot and every effective −1
- `targetReached(clubName:target:isStrict:)`: done just became equal to the target; strict blocks end here
- `blockChanged(clubName:target:done:)`: a block became active (start, resume, next, strip jump, strict auto-advance, club/tag change, −1 reopening a block)
- `planEnded`: no block left to run; shots are ignored until a block is selected or the session ends
- `sessionSaved`: Done saved the session; not sent when `finish()` discards or the save fails

## Reps/Session/ClipFileRemoving.swift
- `ClipFileRemoving`: `removeClip(fileName:sessionID:)`, `removeClips(sessionID:)` for `Documents/clips/<sessionId>/`; #22 supplies the real one
- `NoClipFiles`: no-op default

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

## Reps/Session/SessionController.swift
The session engine (spec §4, F2, F14, F16, F18, F21, F22, §6; ADR 0013). MainActor, `@Observable`, saves after every change, then emits events.
- `SessionController(context:clipFiles:now:saveHook:)`: clip remover, clock and the save call are injectable (`saveHook` defaults to `context.save()`; tests use it to make a save fail)
- State: `session`, `activeBlock`, `activeTags`, `lastSaveError`; computed `blocks`, `isFreeSession`, `isStrictCount`, `isOrderMandatory`, `canSelectBlocks`, `isPlanComplete`
- `addEventHandler(_:)`: synchronous handlers, called in order after the save; must not call back into the controller
- `start(plan:cameraAngle:) throws`: one BlockResult per plan block, first active; re-owns `plan` if it's from another context; `SessionError.emptyPlan`, `.sessionInProgress` (also when another session is already active in the store)
- `startFree(mode:cameraAngle:clubName:tags:) throws`: one untargeted block; `.sessionInProgress` when a session is already active (in this controller or the store)
- `activeSession(in:) throws -> PracticeSession?`: newest `.active` session, for the resume prompt; filters in Swift (a `#Predicate` capturing an enum constant isn't supported on this SDK)
- `resume(_:) throws`: re-owns a session fetched via another context; resolves the active block from `activeBlockOrder` (falling back to the first incomplete block if that order no longer exists), advances past it if strict and already complete, and takes `activeTags` from it or, with no active block, from the most recent block by order; `.sessionInProgress`, `.notActive`
- `recordShot(source:) -> ShotRecord?`: camera → `repsCounted`, manual (+1) → `repsManualAdjust`; nil when ignored; strict auto-advance and the shot share one save, in `countChanged` → `targetReached` → `blockChanged`/`planEnded` order
- `minusOne()`: deletes the latest shot, lowers `repsManualAdjust`, never below zero; removes the clip only if the save that deleted the shot succeeds; right after a strict auto-advance, reopens the block that ended
- `advance()`: next block (mandatory: next in order; free: next incomplete and targeted, wrapping), or `planEnded`
- `select(_:) -> Bool`: block strip jump; false in free sessions, with mandatory order, or onto a complete strict block
- `setClub(_:)`, `setTags(_:)`: free sessions start a new block unless the current one is unused; planned sessions carry tags across blocks
- `finish()`: `finished` + `endedAt`, drops unused free blocks, discards the session instead if that leaves none; emits `sessionSaved` only when the closing save succeeds; `discard()`: deletes the session and, only if that save succeeds, its clips

## Reps/Session/SessionDisplay.swift
Copy and chip states for the session screen; pure values, unit-tested.
- `BlockSnapshot(order:clubName:note:done:target:)`, `StripChip` (`id` = block order, `state` active/complete/pending, `isSelectable`), `NextBlockPrompt(title:message:)`
- `SessionDisplay`: `dimDelay` (30 s), `title(planName:)`, `subtitle(mode:angle:)`, `angleTitle(_:)`, `blockTitle(clubName:note:mode:)` (putting uses the note), `countDetail(done:target:note:mode:)`, `stripChips(_:mode:activeOrder:canSelect:isStrict:)` (mirrors `SessionController.select`), `nextBlockPrompt(clubName:done:target:canComeBack:)` (nil at/over target), `elapsed(_:)`, `tagChoices(active:recent:limit:)`, `toggling(_:in:)`, `adding(_:to:)`, `resumeMessage(title:done:mode:)`

## Reps/Session/SummaryDisplay.swift
Numbers and copy for the session summary (Figma 12, F23); pure values, unit-tested.
- `SummaryBlock(order:clubName:note:tags:counted:manualAdjust:target:clipCount:tempos:)`, `SummaryBar(fill:surplusFrom:)`, `SummaryRow`, `SummaryStat`, `SessionSummary(subtitle:headline:caption:rows:stats:)`
- `SummaryDisplay.summary(planName:mode:blocks:elapsed:)`: rows by order (free sessions hide unused blocks, add tags to titles); `overall(_:mode:)` (capped %, or total count without targets); `row(_:mode:isFree:)`; `percent(_:isComplete:)` (rounded, ≤ 99 % until complete); `stats(_:)` (clips, avg tempo, Σ |manualAdjust|); `tempo(_:)`; `duration(_:)`

## Reps/Voice/VoiceLines.swift
Session event → spoken text (F6, §5.7); pure, nonisolated, English only (Q12).
- `Phrase(text:kind:)`: `Kind` count (goes stale on a newer count) / callout (never dropped)
- `VoiceLines.phrases(for:announceCount:) -> [Phrase]`: `sessionSaved`/`targetReached`/`strictStop`/`planEnded` line constants (all but `sessionSaved` PLACEHOLDER, Q39); `announceCount` silences only `.countChanged`; `TODO(#27)` tempo on the count
- `count(_:)`: digits, so the synthesizer reads them as words
- `block(clubName:target:done:)`: "9 iron. 30 reps." / "…1 rep." / untargeted "9 iron." / returning "9 iron. 12 of 30." (PLACEHOLDER, Q39)
- `spokenClub(_:)`: `BagCatalog.key` wedge abbreviations (PW/GW/SW/LW) spelled out; everything else trimmed as stored

## Reps/Voice/Speaker.swift
- `Speaker`: the voice output seam (`SystemSpeaker` in the app, a fake in tests); `prepare()` warms the voice, `speak(_:finished:)` speaks one line and calls `finished` once unless stopped, `stop()` cuts it off without calling `finished`

## Reps/Voice/SpeechAnnouncer.swift
Turns session events into speech, one line at a time, never overlapping (F6, §5.7). MainActor (app target default).
- `SpeechAnnouncer(speaker:settings:)`: `prepare()` forwards to the speaker; `pending`, `isSpeaking` exposed for tests
- `handle(_:)`: reads `AppSettings.announceCount` on every call (mid-session toggle); a new count replaces any unspoken count, callouts are never dropped, the line being spoken always finishes; `sessionSaved` clears the queue and cuts in with `stop()`; never calls back into the controller (ADR 0013)
- A `generation` counter ignores a late `finished` from a line `stop()` already cancelled

## Reps/Voice/SystemSpeaker.swift
AVSpeechSynthesizer behind `Speaker` (§5.7, §6); build-only, checked by ear on a device.
- `SystemSpeaker`: `prepare()` sets the audio category and renders "Ready" with `write(_:toBufferCallback:)` to load the voice silently (idempotent); `speak(_:finished:)` prepares, activates audio if needed, tracks the utterance by `ObjectIdentifier`, and starts a 6 s timeout that force-stops a line that never reports back; `stop()` cancels the timeout and the synthesizer without calling `finished`
- `AVSpeechSynthesizerDelegate` `didFinish`/`didCancel` are `nonisolated`, hop to MainActor and call `ended(_:)`, which ignores the warm-up utterance and anything `stop()` already dropped
- Deactivates audio 0.6 s after the last line ends if nothing new started (`scheduleRelease`/`releaseAudio`)
- `englishVoice()`: device English variant or `en-US`; prefers an installed enhanced/premium voice, excluding novelty/personal voices (Q12)
- `VoiceAudioSession`: the only code touching the app's audio session; `configure()` sets `.playback`/`.voicePrompt`/`[.duckOthers]` once; `activate()`/`deactivate()` (the latter passes `.notifyOthersOnDeactivation`); all `try?` (voice failures never block counting); #22 revisits it (Q41)

## Reps/Plans/PlanDraft.swift
The plan editor's working copy (spec F1, F24, F28); nonisolated values, nothing persisted.
- `BlockDraft(id:clubName:targetReps:note:)`: `repsRange` 1...999, `defaultReps` 30; `trimmedClubName`, `storedNote` (trimmed, nil if blank), `isValid`, `adjustReps(by:)` clamps
- `RemovedBlock`: a removed block and its former index, for the undo toast; `id` is the block's
- `PlanDraft(name:mode:isOrderMandatory:isStrictCount:blocks:)`: `Equatable` (the editor compares it to the opening draft to detect changes); `trimmedName`, `totalReps`, `canSave` (name, ≥1 block, all blocks valid)
- `index(of:)`, `upsert(_:)` (replace by id or append), `removeBlock(id:) -> RemovedBlock?`, `restore(_:)` (old index, clamped; ignores duplicates), `moveBlocks(fromOffsets:toOffset:)` (SwiftUI move semantics without SwiftUI)

## Reps/Plans/PlanSummary.swift
Copy for plan cards and block rows; nonisolated.
- `reps(_:mode:)` ("1 shot", "90 putts"), `blocks(_:)`, `totals(blockCount:totalReps:mode:)`, `subtitle(blockCount:totalReps:mode:isOrderMandatory:)` (adds "in order"/"any order"), `blockDetail(targetReps:note:mode:)`
- `lastDone(_:now:calendar:locale:)`: today / weekday within 6 days / "Sep 9" / "Sep 9, 2025"; nil → placeholder "Not done yet"

## Reps/Plans/ClubChoices.swift
- `ClubChoices.names(bag:current:)`: picker names in bag order, trimmed, deduped; an off-bag current club goes last (F19)

## Reps/Plans/PlanLibrary.swift
Plan writes for the list and editor; MainActor; every write saves.
- `draft(from:) -> PlanDraft`: blocks in `sortedBlocks` order, ids kept, nil note → ""
- `save(_:to:in:now:) throws -> PracticePlan`: creates when `to` is nil; keeps block objects by id (results stay linked), inserts new ones with the draft id, deletes removed ones (results keep their snapshot), renumbers `order` 0..<n, trims name/club
- `duplicate(_:in:now:) throws -> PracticePlan`: "<name> copy", new block objects in order 0..<n, no sessions
- `delete(_:in:) throws`: sessions keep `planName` (nullify), blocks cascade
- `lastDone(_:) -> Date?`: newest `endedAt ?? startedAt` of finished sessions, filtered in Swift (ADR 0013)

## Reps/Log/SessionLogDisplay.swift
Grouping, sorting and copy for the session log (F8); values in, strings out.
- `LogBlock` / `LogEntry`: plain copies of a BlockResult / finished PracticeSession (built in `SessionLogView.swift`)
- `SessionLogDisplay.sections(_:calendar:locale:) -> [LogSection]`: month sections ("September 2026"), newest month and session first, ties by id
- `row(_:calendar:locale:) -> LogRow`: title, "Wed, Sep 16 · 9:14 AM · 48 min", "62 shots · 3 blocks · 60 clips" (free: clubs), session % (nil when free), `isComplete`
- `detail(_:calendar:locale:) -> LogDetail`: date line, mode line, headline % or count, caption, block rows, stats (duration, clips saved, manual fixes)
- `blockRow(_:mode:isFree:) -> LogBlockRow`: title (putting note, free tags), "45 / 30", block %, over-target flag
- `percent(_:isComplete:)`: rounded, capped at 99 until complete; `duration(from:to:)`: "48 min", "1 h 12 min", nil without an end
- `shownBlocks(_:)`: by order; free sessions drop unused blocks

## Reps/Log/SessionLog.swift
- `SessionLog.delete(_:in:clipFiles:) throws`: deletes a finished session (cascade to results and shots), saves, then `removeClips(sessionID:)`; throws `SessionLogError.notFinished` for an active one

## Reps/Library/LibraryFilter.swift
Library filter model (F15, §5.3b); tags and everything else are filtered in memory (Q23).
- `LibraryClip`: plain copy of a ShotRecord with a clip (id, timestamp, club, tags, favourite, tempo, file name, session id/title/start, angle)
- `LibraryMonth(year:month:)`, `init(_:calendar:)`: month filter value, Comparable
- `LibraryFilter`: club, angle, month, sessionID, tags (all required), favouritesOnly, searchText; `hasChipFilters`; `matches(_:calendar:locale:)` ANDs every set filter and every search word (club, angle, tags, session title, month/weekday name)

## Reps/Library/LibraryDisplay.swift
Grid order, filter choices and tile copy (Figma 04); pure, unit-tested.
- `LibrarySessionOption(id:title:startedAt:)`
- `LibraryDisplay.visible(_:filter:hidden:calendar:locale:)`: filtered, newest first (ties by id), minus pending deletes
- `countTitle`, `clubOptions(_:bag:)` (bag order, then others A–Z), `tagOptions` (most used first; also autocomplete), `monthOptions`, `sessionOptions`, `sessionTitle` ("Wedge day · Sep 16"), `monthTitle` (year only when not this year), `angleOptionTitle`, `tagChipTitle` ("fade +1"), `tileTitle` ("GW · face-on"), `tileDate` (Today/weekday/date), `tempo` ("3.1"), `tagLine`, `favouriteTarget` (false only when all are favourites), `undoMessage`

## Reps/Library/LibraryEdits.swift
Bulk library writes (F15, §5.3c).
- `LibraryClip.init?(_: ShotRecord)`: nil without `clipFileName`; session title via `SessionDisplay.title`, angle from the session (`.none` without one)
- `ShotSnapshot`, `LibraryUndo(message:kind:)` (`.restore([ShotSnapshot])` / `.delete(Set<UUID>)`)
- `LibraryEdits.setClub/addTag/removeTag/setFavourite(... on:in:) throws -> [ShotSnapshot]`: save, or roll back and rethrow; blank club/tag is a no-op (`[]`)
- `restore(_:in:)`: writes snapshots back, skipping deleted shots
- `delete(ids:in:clipFiles:) throws -> [UUID]`: deletes the rows, saves, then `removeClip` per clip file (ADR 0013 order); block counters untouched

## Reps/Library/ClipPlayback.swift
Clip player math and copy (F27, §5.3b); pure, tested.
- `PlaybackSpeed` (1×, ½×, ¼×): `next` cycles, `title`
- `ClipEventKind` (address, top, impact, finish), `ClipEvent(kind:seconds:)`
- `ClipPlayback.frameDuration(nominalFrameRate:)`: 1/rate, 60 fps fallback
- `ClipPlayback.stepped(from:by:frameDuration:duration:)`: middle of the frame `count` away, clamped to the clip
- `ClipPlayback.isAtEnd`, `fraction`, `seconds(atFraction:duration:)`, `timeTitle` ("2.098"), `filmstripTimes(count:duration:)`
- `ClipPlayback.events(duration:impactOffset:)`: impact at `assumedImpactOffset` (3 s, §5.8) when inside the clip; the rest #27
- `ClipPlayback.snapped(_:to:duration:trackWidth:tolerance:)`: jump to a mark released within `tolerance` points
- `ClipPlayback.label(_:)`: "Gap wedge · face-on · tempo 3.1 : 1"

## Reps/Bag/BagCatalog.swift
Standard clubs for the bag grid (Figma 08) and the default bag (F19); nonisolated.
- `Group(title:clubs:)`; `groups`: Woods, Hybrids, Irons, Wedges, Putter; `allClubs`: flattened; `defaultBag`: the common 14 for onboarding (#5) to seed
- `trimmed(_:)`, `key(_:)`: trimmed, lowercased match key
- `catalogIndex(of:)`, `isStandard(_:)`: catalog lookup by key
- `insertionIndex(for:in:)`: bag position for a new/restored club — before the first later standard club, custom ones last

## Reps/Bag/BagLibrary.swift
Bag writes for Settings and onboarding (F19); every write saves.
- `BagError`: `.emptyName`, `.duplicateName`
- `all(in:) throws -> [BagClub]`: bag order (`sortOrder`, then `name`)
- `club(named:in:)`: case-insensitive, trimmed lookup in an already-fetched list
- `setInBag(_:_:in:) throws`: a chip tap; off keeps the row (spec §5.1); on for a missing name inserts one at its catalog position
- `addCustom(_:in:) throws -> BagClub`: "Add a custom club"; restores a hidden row, throws `.duplicateName` if already in bag
- `rename(_:to:in:) throws`: only `BagClub.name`; plan blocks and shots keep the old name (snapshots, #4); throws `.duplicateName` against other rows (case-insensitive)
- `delete(_:in:) throws`: removes the row; plans keep referencing the old name
- `move(fromOffsets:toOffset:in:) throws`: reorders the in-bag clubs (offsets index bag order), hidden rows renumbered after them; SwiftUI `onMove` semantics, copied from `PlanDraft.moveBlocks`
- `seedDefaultBag(in:) throws -> Bool`: inserts `BagCatalog.defaultBag` in catalog order only when there are no BagClub rows at all; false otherwise (idempotent, #5)

## Reps/UI/Theme/Theme.swift
Literal Figma values (docs/design.md): colours (`ink`, `secondaryText`, `accent`, `accentDeep`, `card`, `fill`, `hairline`, `sheet`, `danger`, `thumbnail` (0x8A9A84), `favourite` (0xE6D35A), `illustration` (0x8A9A84), `ballBox` (0xE6D35A)…), `Typography` (text styles where Figma matches their default size), `Spacing`, `Radius`.

## Reps/UI/Components/*.swift
Shared by every screen.
- `PrimaryButtonStyle`: full-width green CTA, dimmed when disabled; `FooterCTA(title:isEnabled:action:accessory:)`: bottom inset with the CTA and an optional view above it (the undo toast)
- `PillButtonStyle(kind:)`: capsule "Start" (`.onAccent` white on green, `.neutral` on `fill`)
- `Chip(title:isSelected:action:)`: grid chip (clubs; tags later)
- `DashedAddButton(title:font:verticalPadding:cornerRadius:action:)`: "+  New plan" / "+  Add block"
- `ToggleRow(title:subtitle:isOn:)`, `FieldCard(label:content:)`: grey cards for switches and inputs
- `BlockRow(clubName:detail:targetReps:)`: handle, club, detail, green target, chevron
- `UndoToast(message:onUndo:)`, `UndoToast.duration` (5 s, §5.3c); `View.undoToastTimer(_:)` clears the bound item after the duration

## Reps/UI/Settings/SettingsTheme.swift
Settings values from Figma 10: `Theme.Typography.settingsValue`; `Theme.Spacing.settingsLabelGap`, `settingsRowVertical`.

## Reps/UI/Settings/SettingsRows.swift
Figma 10 row components: a section label over one grey card with inset hairline dividers.
- `SettingsSection(title:content:)`: label + card
- `SettingsRowText(title:subtitle:)`: title (and optional subtitle) block, reused by the row types below
- `SettingsRow(title:subtitle:value:showsChevron:)`: title left, grey value and optional chevron right
- `SettingsToggleRow(title:subtitle:isOn:)`: same layout with a trailing `Toggle`
- `SettingsDivider`: hairline inset to the row text

## Reps/UI/Settings/SettingsView.swift
Figma 10 Settings (F25). Pushed from the Plans toolbar.
- `SettingsView`: Bag (My bag → `BagSettingsView`, club count), Camera (default angle and clip quality menus, save-to-Photos and record-audio toggles), Voice (announce count/tempo toggles, inert Guidance row), Storage (clip usage from `ClipStorage.usage`, computed in a detached task), About (version); `@AppStorage` bindings share `AppSettings`'s keys and defaults

## Reps/UI/Plans/PracticeMode+Title.swift
- `PracticeMode.title`: "Range", "Range + clips", "Putting"

## Reps/UI/Plans/PlansView.swift
Figma 01 Plans.
- `PlansView(onStartPlan:onStartFreeSession:)`: `@Query` plans by `createdAt`; free-session card, plan cards (tap → editor, Start → closure), swipe Duplicate / Delete (delete asks first), "New plan"; editor in a full-screen cover; Log (top left) pushes `SessionLogView`; Settings pushes `SettingsView`
- `PlanEditorTarget`: `.new` / `.edit(plan)` for the cover

## Reps/UI/Plans/PlanCard.swift
- `PlanCard(plan:onOpen:onStart:)`: name, `PlanSummary.subtitle`, last done, Start (disabled without blocks)
- `FreeSessionCard(onStart:)`

## Reps/UI/Plans/PlanEditorView.swift
Figma 02 + 13. Edits a `PlanDraft`; only Save writes.
- `PlanEditorView(plan:)`: nil = new plan; name, mode segments, order/strict toggles, blocks (tap → sheet, long-press drag to reorder, swipe delete → 5 s undo toast), Add block, Save plan (disabled until `canSave`); Cancel with changes → "Discard changes?"

## Reps/UI/Plans/BlockEditorSheet.swift
Figma 06.
- `BlockEditorSheet(block:mode:title:isNew:onDone:onRemove:)`: edits a copy; club grid from the bag (`BagClub.isInBag`) plus "Other…" (custom name alert); reps stepper; note; Done hands back, Remove (existing blocks only) removes with undo
- `ClubPicker(names:selection:onCustom:)`: 4-column chip grid
- `RepsStepper(block:)`: ±10 big buttons, ±5/±1 pills, disabled at the 1...999 bounds

## Reps/UI/Bag/BagEditorView.swift
Figma 08 bag grid (F19). No title, footer or scroll view of its own; the host embeds it. Hosted by `BagSettingsView` and onboarding (#5).
- `BagEditorView`: catalog groups (Woods, Hybrids, Irons, Wedges, Putter) as chip grids, a "Custom" group for off-catalog clubs (context menu: Rename, Delete), "Add a custom club"; every tap writes through `BagLibrary` immediately

## Reps/UI/Bag/BagSettingsView.swift
Settings → My bag.
- `BagSettingsView`: hosts `BagEditorView` in a `ScrollView`; toolbar "Reorder" opens `BagOrderSheet`
- `BagOrderSheet`: `List` in edit mode over the in-bag clubs, `onMove` writes `BagLibrary.move`

## Reps/UI/Library/LibraryView.swift
Figma 04 Library tab.
- `LibraryView(clipFiles:)`: `@Query` shots with `clipFileName != nil` by timestamp desc (the only SQL predicate, Q23); search + `LibraryFilterBar`; 2-column `LazyVGrid` of `ClipTile`; tap opens `ClipDetailView` full screen (ends the undo window first); player favourite/tag edits save at once; player delete runs `LibraryEdits.delete` after the cover closes; long-press/"Select" starts bulk mode (`LibraryBulkBar`, `LibraryTagSheet`); Undo toast per bulk action; delete is hidden until the toast ends, then `LibraryEdits.delete` + thumbnail cleanup; `NoClipFiles` until #22
- `PreviewData.libraryContainer()` (DEBUG): 8 clips without files

## Reps/UI/Library/ClipTile.swift
- `ClipTile(clip:isSelecting:isSelected:)`: thumb (★, play mark, selection check), club · angle, date · tempo, tags; missing file shows `video.slash`

## Reps/UI/Library/ClipThumbnails.swift
- `ClipThumbnails` (actor, `.shared`): `image(shotID:clipURL:) async -> UIImage?` memory → `Caches/thumbnails/<id>.jpg` → middle frame via `AVAssetImageGenerator` (max 480 px), cached; nil when the file is missing; `remove(_:)` drops both caches

## Reps/UI/Library/LibraryFilterBar.swift
- `LibraryFilterBar(filter:clubs:tags:months:sessions:)`: Figma 04 chips as menus (Club, Angle, Date, ★ toggle, Tag multi-toggle, Session) + Clear

## Reps/UI/Library/LibraryTagSheet.swift
- `LibraryTagSheet(selectedCount:onSelection:suggestions:onAdd:onRemove:)`: add (field + history suggestions) or remove one tag; applies and closes

## Reps/UI/Library/LibraryBulkBar.swift
- `LibraryBulkBar(clubs:isEnabled:favouriteTarget:onClub:onTags:onFavourite:onDelete:)`: bottom bar in bulk mode (no Figma frame)

## Reps/UI/Library/ClipDetailTheme.swift
Figma 11 values: `Theme.playerPill`, `Theme.playerTrack`, `Theme.Typography.playerLabel/playerTime/playerSpeed/playerIcon/playerStep`, `ClipDetailMetrics`.

## Reps/UI/Library/PlayerLayerView.swift
- `PlayerLayerView(player:)`: `AVPlayerLayer` host, aspect fit on black, no system controls

## Reps/UI/Library/ClipPlayer.swift
- `ClipPlayer` (@Observable): `load(_:filmstripCount:)` (`.missing` for nil/missing/undecodable files), `togglePlay`, `pause`, `cycleSpeed`, `step(by:)`, `seek(to:)` (zero tolerance), `scrub(to:)`/`endScrub(at:)`, `stop`; publishes `state`, `duration`, `frameDuration`, `currentTime`, `isPlaying`, `speed`, `filmstrip` (10 frames via `AVAssetImageGenerator.images(for:)`)

## Reps/UI/Library/ClipScrubber.swift
- `ClipScrubber(player:events:)`: filmstrip with yellow playhead (drag to scrub), time, track with event marks and knob (release near a mark jumps to it), pose toggle (#27, disabled)

## Reps/UI/Library/ClipDetailView.swift
Figma 11, 15. Presented full screen by `LibraryView`.
- `ClipDetailView(clip:tagSuggestions:onFavourite:onAddTag:onRemoveTag:onDelete:)`: ✕, ★, share (#26), more (Tags sheet, Save to Photos (#26), Delete with confirm alert), label pill, scrubber, speed / frame step / play, overlay options (#27); missing-file placeholder

## Reps/UI/Library/LibraryTheme.swift
Figma 04 values: `Theme.Typography.filterChip/filterChipSelected/resultCount/tileTitle/tileDetail/tileTempo/tileStar/tilePlay`, `Theme.Spacing.gridGap`, `Theme.Radius.tile`, `LibraryMetrics.thumbnailHeight/playSize`

## Reps/UI/Onboarding/OnboardingView.swift
Figma 07–09 (F19, F20). Shown by `RootView` until onboarding completes.
- `OnboardingView(permissions:)`: owns an `OnboardingModel`; pages switch with a push transition; footer = `PageDots` + `FooterCTA` (Get started / Continue with N clubs / Allow and finish|Finish); seeds the bag in `.task`; refreshes statuses on `scenePhase == .active`; Settings deep link via `openURL(UIApplication.openSettingsURLString)`
- private `WelcomePage`, `BagPage` (hosts `BagEditorView`), `CameraPage` (illustration, `AngleSegments` bound to the default-angle key, two `PermissionRow`s, denied/restricted note), `PageTitle`, `AngleSegments`, `PermissionRow`, `CameraSetupIllustration` (Canvas drawing of Figma 09)

## Reps/UI/Onboarding/PageDots.swift
- `PageDots(count:current:)`: 18×6 accent capsule for the current page, 6 pt dots otherwise

## Reps/UI/Onboarding/OnboardingTheme.swift
Onboarding values from Figma 07–09: `Theme.Typography.appMark` (34 bold), `onboardingIntro`, `illustrationCaption`; `Theme.Spacing.welcomeTop/welcomeGutter/welcomeGap/onboardingGap`; `Theme.Radius.appMark/illustration/segment/segmentInner`.

## Reps/UI/Log/SessionLogView.swift
No Figma frame (Q33); cards follow 01 Plans.
- `SessionLogView`: `@Query` sessions by `startedAt` desc, finished only (filtered in memory, ADR 0013); month sections of cards → detail push; swipe Delete asks first → `SessionLog.delete` (`NoClipFiles` until #22); empty state
- `LogEntry.init(_:)`, `LogBlock.init(_:)`: model → value copies (clip count = shots with a `clipFileName`)
- `PreviewData.logContainer()` (DEBUG): preview store with one finished session per sample plan

## Reps/UI/Log/SessionLogDetailView.swift
Styled after Figma 12.
- `SessionLogDetailView(session:)`: title + date subtitle, headline card (% or count, caption, mode line), block rows, stat tiles; clips are `TODO(#24)`

## Reps/UI/Log/LogTheme.swift
- `Theme.Typography.log*`, `Theme.Radius.logStat`: log sizes from Figma 12

## Reps/UI/PreviewData.swift
- `PreviewData.container()` (DEBUG): in-memory store with the Figma sample bag and plans, for `#Preview`s only

## Reps/UI/Session/SessionView.swift
Figma 03, 05, 14. The live session; reads and drives a `SessionController`.
- `SessionView(controller:)`: nav (End → summary in place (Continue session / Done), title, mode · angle, elapsed), block strip (planned), club + tag chips (range modes), camera placeholder (#13), big count, −1/+1, Next block (asks first before target)
- `BlockSnapshot.init(_ result: BlockResult)`

## Reps/UI/Session/SessionSummaryView.swift
Figma 12. Shown by `SessionView` on End.
- `SessionSummaryView(summary:onContinue:onDone:)`: header, overall card, block rows with target/surplus bars, three stats, footnote, Continue session / Done
- `SummaryBlock.init(_ result: BlockResult)`

## Reps/UI/Session/SummaryTheme.swift
Summary values from Figma 12: `Theme.Typography.summaryHeadline` (88 rounded bold), `summaryHeadlineTracking`, `summarySubtitle`, `summaryCaption`, `summaryRowTitle`, `summaryRowPercent`, `summaryStatValue`, `summaryStatLabel`; `Theme.Radius.stat`.

## Reps/UI/Components/SecondaryButtonStyle.swift
- `SecondaryButtonStyle`: full-width grey CTA (Continue session)

## Reps/UI/Session/BlockStrip.swift
- `BlockStrip(chips:onSelect:)`: horizontal block chips, centres the active one; only selectable chips take taps

## Reps/UI/Session/SessionScreenGuard.swift
- `View.sessionScreenGuard()`: idle timer off while visible; black overlay after 30 s without a tap, first tap only wakes (§5.3c)

## Reps/UI/Session/FreeClubSheet.swift
- `FreeClubSheet(current:onPick:)`: bag club grid (`ClubPicker`) plus Other…; a pick closes the sheet (F14)

## Reps/UI/Session/SessionTheme.swift
Session values from Figma: `Theme.Typography.count` (132 rounded bold), `countTracking`, `countDetail`, `manualButton`, `stripTitle`, `stripDetail`, `navSubtitle`; `Theme.Radius.stripChip`, `preview`.

## Reps/UI/Components/CapsuleChip.swift
- `CapsuleChip(title:isSelected:action:)`: capsule chip, filled when selected, read-only without an action (session club and tags)

## ShotDetector/ShotEvent.swift
Output type of the ShotDetector framework (spec §4). The framework must never import AVFoundation, AVKit, UIKit, SwiftUI or CoreMedia (ADR 0010).
- `ShotEvent(time:)`: one detected shot; `time` is the detector's estimate of when it happened (impact or ball exit), in seconds on the frame stream's clock

## ShotDetector/ShotDetecting.swift
The detector boundary (spec §4, ADR 0010).
- `ShotDetecting`: `mutating process(_:) -> [ShotEvent]` takes frames in time order and returns shots confirmed on that frame; `mutating finish() -> [ShotEvent]` flushes at end of stream (default `[]`)

## ShotDetector/VideoFrame.swift
What detectors are fed.
- `VideoFrame(pixelBuffer:time:orientation:)`: one downscaled frame; `time` in seconds (presentation time), `orientation` for Vision
- `DetectorInput`: the frame contract for the camera pipeline and the eval harness: `frameRate` 15, `shortSide` 480, `pixelFormat` 420f

## RepsTests/RepsStoreTests.swift
- `inMemoryContainerOpens`, `schemaHasEveryModel`, `schemaIsVersionOne`
- `schemaShapeIsPinned`: exact attribute and relationship name sets per entity, so a silent schema change fails loudly (ADR 0012)

## RepsTests/CompletionTests.swift
Block and session completion: uncapped, manual adjust, clamping, missing targets, skipped blocks.

## RepsTests/ModelTests.swift
In-memory store: order indexes, snapshots, delete rules (BagClub has no relationships, so it isn't covered here), enum/tag persistence, status predicate.

## RepsTests/ExportTests.swift
Export key sets, ordering (including sort-key ties), finished-only, nil omission, ISO dates (ms rounding, sub-ms and pre-epoch dates), clip file names, round trip, determinism.

## RepsTests/LibraryDisplayTests.swift
Filter AND semantics, ordering, options and tile copy (fixed UTC calendar, en_US).

## RepsTests/LibraryEditsTests.swift
Bulk edits, undo snapshots and delete order against an in-memory store with `ClipSpy`.

## RepsTests/ClipPlaybackTests.swift
- Speed cycle, frame duration, frame step and clamping, end, fraction/seconds, time title, filmstrip times, impact mark, snapping, label pill

## RepsTests/ClipStorageTests.swift
Clip usage summing; `ClipURLTests`: valid clip path resolution, unsafe names rejected.

## RepsTests/SessionTestSupport.swift
- `TestClock` (1 s per read), `ClipSpy` (records clip removals), `EventLog` (collects `SessionEvent`s), `TestSaveError` (thrown by an injected `saveHook` to test save-gated cleanup)

## RepsTests/SessionControllerTests.swift
Planned sessions: start, counting, minimums vs strict, mandatory vs free order, skip, last block, zero-target blocks, plan edits, −1 (Q21), tags, finish, discard. Also: refusing a second active session (in-controller and store-wide), re-owning a plan fetched from another context, clip removal skipped when a save fails, and `sessionSaved` announced only on a successful finish.

## RepsTests/FreeSessionTests.swift
Free sessions: untargeted blocks, club/tag changes start blocks (in place when unused), navigation off, finish drops unused blocks, finish discards a session left with none, `sessionSaved` announced only when finish actually saves.

## RepsTests/SessionResumeTests.swift
On-disk kill and resume (autosave off), newest-active lookup, resume after a strict plan ended. Also: re-owning a session fetched from another context, tags from the most recent block with no active block, advancing off a completed strict block on resume, and falling back when `activeBlockOrder` is stale.

## RepsTests/PlanDraftTests.swift
Save validity, reps clamping, notes, upsert, move semantics, remove/restore, change detection (discard alert).

## RepsTests/PlanSummaryTests.swift
Reps nouns, subtitles, block detail, "last done" formatting (en_US, UTC).

## RepsTests/ClubChoicesTests.swift
Bag order, dedupe, off-bag current club.

## RepsTests/PlanLibraryTests.swift
In-memory store: create, round trip, edit in place with renumbering, removed blocks keep result snapshots, duplicate deep copy, delete keeps sessions, last done.

## RepsTests/SessionDisplayTests.swift
Session copy, strip chip states and selectability, Next block prompt, elapsed clock, tag choices, resume message.

## RepsTests/SessionLogDisplayTests.swift
Log sections and order, row and detail copy (planned, putting, free), percent cap, durations (en_US, UTC).

## RepsTests/SessionLogTests.swift
In-memory store: delete cascades and removes clips; active sessions are refused.

## RepsTests/SummaryDisplayTests.swift
Summary headline (Q22-capped), captions, rows and bars, percent rounding, putting and free sessions, stats, duration, tempo.

## RepsTests/CapturePermissionsTests.swift
`AVAuthorizationStatus` → `PermissionState` mapping, media types.

## RepsTests/OnboardingModelTests.swift
- `FakePermissions`: scripted states and answers, records every request
- Page order, initial states, camera-then-mic on finish, mic skipped when Record audio is off or the camera is denied, decided/restricted never asked, row actions, request gating, refresh, `willPrompt`.

## RepsTests/OnboardingCopyTests.swift
Continue/finish titles, status pills, camera note, features.

## RepsTests/BagSeedingTests.swift
Default bag seeding: empty store, second run, existing bag untouched.

## RepsTests/VoiceLinesTests.swift
Count text, announceCount gating, block callout wording (targeted/single/returning/untargeted), wedge names, target-reached strict vs minimums, plan end, session saved, callouts always speak with announceCount off.

## RepsTests/SpeechAnnouncerTests.swift
- `FakeSpeaker`: records spoken text, stop/prepare counts and each line's `finished` closure
- One line at a time, newest count replaces an unspoken one, a count queues behind pending callouts, callouts are never dropped and finish in order, `announceCount` re-read on every event, `sessionSaved` cuts in and clears the queue (idle case doesn't call `stop()`), a late `finished` from a stopped line is ignored

## DetectorEvalTests/MLData.swift
Locates the hitreg-ml checkout (ADR 0007).
- `MLData.root: URL?`: `REPS_ML_DIR` if set, else `<repo>/../hitreg-ml`; `nil` when `data/manifest.csv` isn't there (suites skip)

## DetectorEvalTests/MLDataTests.swift
- `MLDataTests.testSplitIsListed`: `data/splits.json` has a non-empty `test` split; skipped without footage

## DetectorEvalTests/Harness/CSV.swift
- `CSV.parse(_:) -> [[String]]`: RFC 4180 rows (quotes, `""`, CRLF)
- `CSV.records(_:) -> [[String: String]]`: rows keyed by the header; blank lines dropped, missing fields `""`

## DetectorEvalTests/Harness/EvalLabel.swift
Ground-truth kinds and how each detector type should treat them.
- `LabelKind`: swing, practice, motion (range); putt, pickup, motion (putting)
- `EvalLabel(frame:seconds:kind:)`: one CSV row
- `ScoringProfile`: kind → `LabelRole` (positive/negative); `.rangeShot` (practice negative), `.rangeSwing` (practice positive), `.putting` (pickup positive)

## DetectorEvalTests/Harness/EventMatcher.swift
- `Detection(time:emittedAt:)`: an event's estimated time and the frame time it was returned on
- `TimedLabel(time:kind:)`: a label on the decoder's clock
- `VideoScore`: per-video counts, latencies, timing errors, per-kind labels/fired
- `EventMatcher.score(labels:detections:profile:window:) -> VideoScore`: one-to-one matching within ±window; unmatched detections are hard (near a negative label) or other false positives

## DetectorEvalTests/Harness/EvalMetrics.swift
- `EvalMetrics(_ scores:)`: sums video scores; `precision`, `recall`, `falsePer50`, `meanLatency`, `maxLatency`, `meanAbsTimingError` are nil when undefined; `absCountError` sums per-video |detections − positives|

## DetectorEvalTests/Harness/EvalDataset.swift
- `EvalVideo`: name, file URL, scenario (`angle/light` or `putt/light`), labels
- `EvalDataset.rangeTest(root:profile:)`: hitreg-ml test split (skips `discard` rows); throws on missing files or bad rows
- `EvalDataset.putting(root:)`: every clip in `data/putting/manifest.csv`
- `EvalDataset.hasPutting(root:)`, `EvalDataset.labels(_:)`

## DetectorEvalTests/Harness/VideoFrameReader.swift
The only AVFoundation code on the detector path; test target only.
- `VideoFrameReader(url:frameRate:shortSide:)`: defaults from `DetectorInput`; `nil` = every frame / native size
- `read(_ body:) async throws -> [Double]`: calls `body` per sampled frame; returns the PTS of every decoded frame by index
- `orientation(from:)`: preferredTransform → `CGImagePropertyOrientation` (same as hitreg-ml `tools/extract`)
- `scaledSize(_:shortSide:)`: even output size with the short side at `shortSide`, nil if already smaller

## DetectorEvalTests/Harness/EvalRunner.swift
- `EvalRunner(window:frameRate:shortSide:)`: window defaults to 0.5 s
- `run(_ name:on:makeDetector:) async throws -> EvalReport`: decodes each video, feeds a fresh detector, moves labels onto the decoder clock by frame number, scores; throws `RunError.nonIncreasingFrameTimes` if a video's frame times aren't strictly increasing
- `labelTimes(_:frameTimes:) -> [Double]`: pure frame-number → timestamp mapping, CSV seconds past the end
- `isStrictlyIncreasing(_:) -> Bool`: guards the frame-time mapping is valid
- `VideoResult`: one video's score plus decoded/sampled frame counts

## DetectorEvalTests/Harness/EvalReport.swift
- `EvalReport.scenarios`: metrics per scenario (sorted) then `all`; `overall`
- `table`: fixed-width text report with per-kind fired/labels and miscounted videos
- `json`: pretty, sorted-keys JSON of the same

## DetectorEvalTests/Harness/EvalOutput.swift
- `EvalOutput.publish(_:)`: prints the table, attaches `.txt`/`.json` to the test, writes them to `build/eval/<name>.*`

## DetectorEvalTests/Detectors/LabelOracle.swift
- `LabelOracle(video:profile:)`: test-only `ShotDetecting` that fires on the first sampled frame at/after each positive label

## DetectorEvalTests/CSVTests.swift, EventMatcherTests.swift, EvalMetricsTests.swift, EvalRunnerTests.swift
Pure harness logic, no footage.

## DetectorEvalTests/EvalDatasetTests.swift
- Label parsing (pure); `rangeTestSplitLoads` (22 videos), `puttingLoads` (footage)

## DetectorEvalTests/VideoFrameReaderTests.swift
- Scaling and orientation math (pure); `decodesDownscaledSampledFrames` (footage: 480 short side, 420f, ~15 fps)

## DetectorEvalTests/OracleEvalTests.swift
- `rangeTestSplit`, `putting`: the oracle scores recall 1, precision 1 and publishes `oracle-range` / `oracle-putting` reports
