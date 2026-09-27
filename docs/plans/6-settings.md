# #6 Settings

Goal: the Settings screen (Figma 10) behind the Plans toolbar button, a small typed preferences store that later features read, and a reusable bag editor (Figma 08 look) that onboarding (#5) will host too.

Spec: F19 (your bag, editable in Settings), F25 (my bag, default angle, clip quality, save-to-Photos, record audio on clips, voice toggles, storage, version). ADR 0006 (clip folder), ADR 0013 (no enum-captured `#Predicate`). Figma: [10 Settings](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=12-2), [08 Your bag](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1?node-id=8-46).

Branch: `feat/6-settings`. Label `ui`, no review. Copy this plan to `docs/plans/6-settings.md` in the last commit.

## Scope

In scope:
- `AppSettings`: typed UserDefaults view with defaults. Keys: default camera angle, clip quality, save clips to Photos, record audio on clips, announce count, announce tempo.
- `SettingsView`: pushed from the Plans toolbar ("‹ Plans" back button, inline title "Settings").
- Bag editing: `BagEditorView` (reusable chip grid: catalog groups + custom clubs + "Add a custom club"), `BagSettingsView` (Settings host with a Reorder sheet), and `BagLibrary` writes (toggle, add, rename, delete, reorder).
- Storage row: size and count of `.mov` files under `Documents/clips` (computed off the main actor). Version row from the bundle.
- `RootView` reads the default angle when starting sessions.

Out of scope, with the owning issue:
- Asking for Photos access and saving anything to Photos → #26 (fable path). The toggle only stores the preference.
- Recording audio, applying clip quality, and asking for mic/camera permission → #22 / #13 / #5.
- Speaking (and so reading the voice toggles) → #10. Tempo announcements → #27.
- Storage "Manage" screen, deleting clips → #23.
- Guidance voice (F26) → later, no issue. The row is shown disabled.
- Seeding the default 14-club bag and the onboarding screen → #5. This issue only adds the `BagCatalog.defaultBag` list for #5 to use.
- Free-session mode choice (Q28) stays as is.

## Design decisions

1. **Settings store** is a `nonisolated struct AppSettings` over `UserDefaults` (default `.standard`). It isn't observable. Views bind the same keys with `@AppStorage(AppSettings.Key.x)` and use `AppSettings.Default.x` as the default, so both sides agree. Non-view readers (speaker, clip writer, `RootView` at start time) call `AppSettings().x`. Tests use a throwaway `UserDefaults(suiteName:)`.
2. **Default angle** offers only `.faceOn` / `.downTheLine`. `.none` or a garbage stored value reads as the default (`.faceOn`). Putting sessions start with `.none` (ModelEnums says `.none` = putting). Until now `RootView` passed `.faceOn` for putting too; `SessionDisplay.subtitle` already ignores the angle for putting, so nothing visible changes.
3. **Bag editor = Figma 08 chip grid, live writes.** Every tap saves right away, with no draft or Save button, so Settings and onboarding behave the same. Catalog groups (Woods, Hybrids, Irons, Wedges, Putter) show every standard club, and a selected chip reads "✓ Name". Clubs whose names aren't in the catalog show in a "Custom" group (only when there are any). Tap toggles `isInBag`. Custom chips get a context menu: Rename, Delete. Standard chips only toggle.
   - Turning a club off sets `isInBag = false` and keeps the row (spec §5.1). Turning a missing standard club on inserts a row at its catalog position. A new custom club is appended at the end.
   - Names match case-insensitively after trimming ("7 IRON" = "7 iron").
   - **Rename** changes only `BagClub.name`. Plan blocks, block results and shots keep the old name (they are snapshots, #4), and `ClubChoices` already shows an off-bag current club in the block editor.
   - **Delete** removes the row. Plans still reference the name, so nothing else changes.
   - **Reorder**: the grid shows catalog order, but pickers use `sortOrder`. So `BagSettingsView` has a "Reorder" toolbar button that opens `BagOrderSheet`, a `List` in edit mode over the in-bag clubs. Onboarding doesn't need it.
4. **Storage** comes from `ClipStorage.usage(at:)`: a sync `FileManager` enumeration run in `Task.detached(priority: .utility)` from `.task`. `ClipStorage.clipsDirectory` is the ADR 0006 root, and #22 should reuse it.
5. **Styling**: Figma 10 rows use regular-weight 16 pt titles in one grouped card with inset hairline dividers. The existing `ToggleRow` (semibold, one card per row) doesn't match, so this adds small `Settings*` row components plus a `SettingsTheme.swift` extension (same pattern as `SessionTheme.swift`, which keeps `Theme.swift` out of the diff).

## Files

```
Reps/Settings/AppSettings.swift        new  ClipQuality, AppSettings (keys, defaults, typed accessors, cameraAngle(for:))
Reps/Settings/ClipStorage.swift        new  ClipUsage, ClipStorage.clipsDirectory, usage(at:fileManager:)
Reps/Settings/SettingsCopy.swift       new  clubCount, angleTitle, clipQualityTitle, clipUsage, version
Reps/Bag/BagCatalog.swift              new  groups, allClubs, defaultBag, trimmed, key, catalogIndex, isStandard, insertionIndex
Reps/Bag/BagLibrary.swift              new  BagError, all, club(named:in:), setInBag, addCustom, rename, delete, move
Reps/UI/Settings/SettingsTheme.swift   new  Theme.Typography.settingsValue, Theme.Spacing.settingsLabelGap/settingsRowVertical
Reps/UI/Settings/SettingsRows.swift    new  SettingsSection, SettingsRow, SettingsToggleRow, SettingsRowText, SettingsDivider
Reps/UI/Settings/SettingsView.swift    new  Figma 10
Reps/UI/Bag/BagEditorView.swift        new  reusable Figma 08 grid (Settings + #5)
Reps/UI/Bag/BagSettingsView.swift      new  BagSettingsView (Settings host + Reorder), BagOrderSheet
Reps/UI/Plans/PlansView.swift          edit Settings button pushes SettingsView
Reps/App/RootView.swift                edit default angle from AppSettings
RepsTests/AppSettingsTests.swift       new
RepsTests/ClipStorageTests.swift       new
RepsTests/SettingsCopyTests.swift      new
RepsTests/BagCatalogTests.swift        new
RepsTests/BagLibraryTests.swift        new
docs/code-reference.md, docs/roadmap.md, docs/open-questions.md, docs/design.md, docs/plans/6-settings.md
```

The folders are file-system synchronized (ADR 0009), so the Xcode project needs no edits. The app target defaults to MainActor, so pure types are marked `nonisolated` like the existing ones.

## Steps (one commit each, body ends with `Refs #6`)

### Step 1: settings store, clip storage, copy (`added settings store`)

`Reps/Settings/AppSettings.swift`:

```swift
import Foundation

// Stored in UserDefaults by raw value; never rename.
nonisolated enum ClipQuality: String, CaseIterable, Sendable {
    case p1080fps60 = "1080p60"
    case p1080fps30 = "1080p30"
    case p720fps30 = "720p30"  // PLACEHOLDER: clip quality options (Q31)
}

// Typed Settings preferences (F25). SettingsView binds the same keys with @AppStorage.
nonisolated struct AppSettings {
    nonisolated enum Key {
        static let defaultCameraAngle = "settings.defaultCameraAngle"
        static let clipQuality = "settings.clipQuality"
        static let saveClipsToPhotos = "settings.saveClipsToPhotos"
        static let recordClipAudio = "settings.recordClipAudio"
        static let announceCount = "settings.announceCount"
        static let announceTempo = "settings.announceTempo"
    }

    nonisolated enum Default {
        static let cameraAngle: CameraAngle = .faceOn
        static let clipQuality: ClipQuality = .p1080fps60
        static let saveClipsToPhotos = false
        static let recordClipAudio = true
        static let announceCount = true
        static let announceTempo = false
    }

    // .none means putting, so it isn't a choice.
    static let angleChoices: [CameraAngle] = [.faceOn, .downTheLine]

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var defaultCameraAngle: CameraAngle {
        get {
            let stored = defaults.string(forKey: Key.defaultCameraAngle).flatMap(CameraAngle.init(rawValue:))
            guard let stored, Self.angleChoices.contains(stored) else { return Default.cameraAngle }
            return stored
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.defaultCameraAngle) }
    }

    var clipQuality: ClipQuality {
        get { defaults.string(forKey: Key.clipQuality).flatMap(ClipQuality.init(rawValue:)) ?? Default.clipQuality }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.clipQuality) }
    }

    var saveClipsToPhotos: Bool {
        get { bool(Key.saveClipsToPhotos, Default.saveClipsToPhotos) }
        nonmutating set { defaults.set(newValue, forKey: Key.saveClipsToPhotos) }
    }

    var recordClipAudio: Bool {
        get { bool(Key.recordClipAudio, Default.recordClipAudio) }
        nonmutating set { defaults.set(newValue, forKey: Key.recordClipAudio) }
    }

    var announceCount: Bool {
        get { bool(Key.announceCount, Default.announceCount) }
        nonmutating set { defaults.set(newValue, forKey: Key.announceCount) }
    }

    var announceTempo: Bool {
        get { bool(Key.announceTempo, Default.announceTempo) }
        nonmutating set { defaults.set(newValue, forKey: Key.announceTempo) }
    }

    // Putting has no camera angle; range sessions start at the default.
    func cameraAngle(for mode: PracticeMode) -> CameraAngle {
        mode == .putting ? .none : defaultCameraAngle
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
```

`Reps/Settings/ClipStorage.swift`:

```swift
import Foundation

nonisolated struct ClipUsage: Equatable, Sendable {
    var bytes: Int64
    var count: Int

    static let zero = ClipUsage(bytes: 0, count: 0)
}

// Clips live in Documents/clips/<sessionId>/<shotId>.mov (ADR 0006); #22 writes them.
nonisolated enum ClipStorage {
    static var clipsDirectory: URL {
        URL.documentsDirectory.appending(path: "clips", directoryHint: .isDirectory)
    }

    // Blocking file I/O: call it off the main actor. A missing folder is zero.
    static func usage(at root: URL, fileManager: FileManager = .default) -> ClipUsage {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard
            let files = fileManager.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return .zero }
        var usage = ClipUsage.zero
        for case let url as URL in files where url.pathExtension.lowercased() == "mov" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            usage.bytes += Int64(values.fileSize ?? 0)
            usage.count += 1
        }
        return usage
    }
}
```

`Reps/Settings/SettingsCopy.swift`:

```swift
import Foundation

// Copy for the Settings screen; pure, unit-tested.
nonisolated enum SettingsCopy {
    static func clubCount(_ count: Int) -> String {
        switch count {
        case 0: "No clubs"  // PLACEHOLDER: empty bag copy
        case 1: "1 club"
        default: "\(count) clubs"
        }
    }

    static func angleTitle(_ angle: CameraAngle) -> String {
        switch angle {
        case .faceOn: "Face-on"
        case .downTheLine: "Down-the-line"
        case .none: "None"
        }
    }

    static func clipQualityTitle(_ quality: ClipQuality) -> String {
        switch quality {
        case .p1080fps60: "1080p · 60 fps"
        case .p1080fps30: "1080p · 30 fps"
        case .p720fps30: "720p · 30 fps"
        }
    }

    // nil while the size is still being computed.
    static func clipUsage(_ usage: ClipUsage?, locale: Locale = .current) -> String {
        guard let usage else { return "Calculating…" }  // PLACEHOLDER: storage loading copy
        guard usage.count > 0 else { return "No clips yet" }  // PLACEHOLDER: empty storage copy
        let size = usage.bytes.formatted(.byteCount(style: .file).locale(locale))
        let clips = usage.count == 1 ? "1 clip" : "\(usage.count.formatted(.number.locale(locale))) clips"
        return "\(size) · \(clips)"
    }

    // "0.1 (12)" from CFBundleShortVersionString and CFBundleVersion.
    static func version(info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        case let (nil, build?): return "(\(build))"
        case (nil, nil): return "–"
        }
    }
}
```

Tests for step 1 are below (AppSettingsTests, ClipStorageTests, SettingsCopyTests). Add the three files' entries to `docs/code-reference.md` in this commit.

### Step 2: bag catalog and writes (`added bag library`)

`Reps/Bag/BagCatalog.swift`:

```swift
import Foundation

// Standard clubs for the bag grid (Figma 08) and the default bag (F19).
nonisolated enum BagCatalog {
    nonisolated struct Group: Identifiable, Sendable {
        let title: String
        let clubs: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Woods", clubs: ["Driver", "3 wood", "5 wood", "7 wood"]),
        Group(title: "Hybrids", clubs: ["3 hybrid", "4 hybrid", "5 hybrid"]),
        Group(title: "Irons", clubs: ["2 iron", "3 iron", "4 iron", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron"]),
        Group(title: "Wedges", clubs: ["PW", "GW", "SW", "LW"]),
        Group(title: "Putter", clubs: ["Putter"]),
    ]

    static let allClubs: [String] = groups.flatMap(\.clubs)

    // The common 14 (Figma 08 selection); onboarding (#5) seeds it.
    static let defaultBag: [String] = [
        "Driver", "3 wood", "5 wood", "4 hybrid", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron", "PW", "GW", "SW",
        "LW", "Putter",
    ]

    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Bag names match case-insensitively after trimming.
    static func key(_ name: String) -> String {
        trimmed(name).lowercased()
    }

    static func catalogIndex(of name: String) -> Int? {
        let target = key(name)
        return allClubs.firstIndex { key($0) == target }
    }

    static func isStandard(_ name: String) -> Bool {
        catalogIndex(of: name) != nil
    }

    // Where a new club goes in bag order: a standard club before the first later standard club, custom ones last.
    static func insertionIndex(for name: String, in names: [String]) -> Int {
        guard let index = catalogIndex(of: name) else { return names.count }
        return names.firstIndex { (catalogIndex(of: $0) ?? -1) > index } ?? names.count
    }
}
```

`Reps/Bag/BagLibrary.swift`:

```swift
import Foundation
import SwiftData

// Bag writes for Settings and onboarding (F19); every write saves.
enum BagLibrary {
    enum BagError: Error, Equatable {
        case emptyName
        case duplicateName
    }

    // Bag order, as the pickers show it.
    static func all(in context: ModelContext) throws -> [BagClub] {
        try context.fetch(FetchDescriptor<BagClub>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))
    }

    static func club(named name: String, in clubs: [BagClub]) -> BagClub? {
        let key = BagCatalog.key(name)
        return clubs.first { BagCatalog.key($0.name) == key }
    }

    // A chip tap. Off keeps the row (spec §5.1); on for a missing name inserts one.
    static func setInBag(_ name: String, _ isInBag: Bool, in context: ModelContext) throws {
        let trimmed = BagCatalog.trimmed(name)
        guard !trimmed.isEmpty else { throw BagError.emptyName }
        var clubs = try all(in: context)
        if let existing = club(named: trimmed, in: clubs) {
            existing.isInBag = isInBag
        } else if isInBag {
            insert(trimmed, into: &clubs, in: context)
        } else {
            return
        }
        renumber(clubs)
        try context.save()
    }

    // "Add a custom club". A hidden row with that name comes back; one already in the bag is a duplicate.
    @discardableResult
    static func addCustom(_ name: String, in context: ModelContext) throws -> BagClub {
        let trimmed = BagCatalog.trimmed(name)
        guard !trimmed.isEmpty else { throw BagError.emptyName }
        var clubs = try all(in: context)
        if let existing = club(named: trimmed, in: clubs) {
            guard !existing.isInBag else { throw BagError.duplicateName }
            existing.isInBag = true
            try context.save()
            return existing
        }
        let made = insert(trimmed, into: &clubs, in: context)
        renumber(clubs)
        try context.save()
        return made
    }

    // Only the bag row changes; plan blocks and shots keep the old name (snapshots, #4).
    static func rename(_ club: BagClub, to name: String, in context: ModelContext) throws {
        let trimmed = BagCatalog.trimmed(name)
        guard !trimmed.isEmpty else { throw BagError.emptyName }
        if let other = self.club(named: trimmed, in: try all(in: context)), other.id != club.id {
            throw BagError.duplicateName
        }
        club.name = trimmed
        try context.save()
    }

    // Plans reference clubs by name, so nothing else changes.
    static func delete(_ club: BagClub, in context: ModelContext) throws {
        let id = club.id
        context.delete(club)
        renumber(try all(in: context).filter { $0.id != id })
        try context.save()
    }

    // Offsets index the in-bag clubs in bag order (BagOrderSheet); hidden rows go after them.
    static func move(fromOffsets source: IndexSet, toOffset destination: Int, in context: ModelContext) throws {
        let clubs = try all(in: context)
        var inBag = clubs.filter(\.isInBag)
        let valid = source.filter { inBag.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { inBag[$0] }
        let shift = valid.filter { $0 < destination }.count
        for index in valid.reversed() { inBag.remove(at: index) }
        inBag.insert(contentsOf: moving, at: min(max(destination - shift, 0), inBag.count))
        renumber(inBag + clubs.filter { !$0.isInBag })
        try context.save()
    }

    @discardableResult
    private static func insert(_ name: String, into clubs: inout [BagClub], in context: ModelContext) -> BagClub {
        let club = BagClub(name: name, sortOrder: clubs.count)
        context.insert(club)
        clubs.insert(club, at: BagCatalog.insertionIndex(for: name, in: clubs.map(\.name)))
        return club
    }

    private static func renumber(_ clubs: [BagClub]) {
        for (index, club) in clubs.enumerated() where club.sortOrder != index { club.sortOrder = index }
    }
}
```

Notes for the implementer:
- `delete` filters by id after fetching because a fetch may still return the pending-deleted object before the save. Keep that filter.
- The only predicate here is the `sortBy`; nothing captures an enum (ADR 0013).
- The move math is copied from `PlanDraft.moveBlocks`, so it follows SwiftUI `onMove` semantics.

Tests: BagCatalogTests, BagLibraryTests (below). Add the code-reference entries.

### Step 3: Settings UI and wiring (`added settings screen`)

`Reps/UI/Settings/SettingsTheme.swift`:

```swift
import SwiftUI

// Settings values from Figma 10.
extension Theme.Typography {
    static let settingsValue = Font.subheadline
}

extension Theme.Spacing {
    static let settingsLabelGap: CGFloat = 6
    static let settingsRowVertical: CGFloat = 13
}
```

`Reps/UI/Settings/SettingsRows.swift`:

```swift
import SwiftUI

// Figma 10: a small label over one grey card of rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.settingsLabelGap) {
            Text(title)
                .font(Theme.Typography.footnoteMedium)
                .foregroundStyle(Theme.secondaryText)
            VStack(spacing: 0) { content }
                .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
        }
    }
}

struct SettingsRowText: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// Title (and subtitle) left; grey value and chevron right.
struct SettingsRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowText(title: title, subtitle: subtitle)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let value {
                    Text(value)
                        .font(Theme.Typography.settingsValue)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")  // PLACEHOLDER: Figma draws "›" as text
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.hairline)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, Theme.Spacing.settingsRowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowText(title: title, subtitle: subtitle)
        }
        .tint(Theme.accent)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, Theme.Spacing.settingsRowVertical)
    }
}

// Hairline inset to the row text.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.leading, Theme.Spacing.cardPadding)
    }
}
```

`Reps/UI/Settings/SettingsView.swift`:

```swift
import SwiftData
import SwiftUI

// Figma 10 Settings (F25). Pushed from the Plans toolbar.
struct SettingsView: View {
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @AppStorage(AppSettings.Key.defaultCameraAngle) private var defaultAngle: CameraAngle =
        AppSettings.Default.cameraAngle
    @AppStorage(AppSettings.Key.clipQuality) private var clipQuality: ClipQuality = AppSettings.Default.clipQuality
    @AppStorage(AppSettings.Key.saveClipsToPhotos) private var saveClipsToPhotos =
        AppSettings.Default.saveClipsToPhotos
    @AppStorage(AppSettings.Key.recordClipAudio) private var recordClipAudio = AppSettings.Default.recordClipAudio
    @AppStorage(AppSettings.Key.announceCount) private var announceCount = AppSettings.Default.announceCount
    @AppStorage(AppSettings.Key.announceTempo) private var announceTempo = AppSettings.Default.announceTempo
    @State private var clipUsage: ClipUsage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sheetGap) {
                SettingsSection(title: "Bag") {
                    NavigationLink {
                        BagSettingsView()
                    } label: {
                        SettingsRow(
                            title: "My bag", subtitle: SettingsCopy.clubCount(clubs.filter(\.isInBag).count),
                            value: "Edit", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
                SettingsSection(title: "Camera") {
                    Menu {
                        Picker("Default angle", selection: $defaultAngle) {
                            ForEach(AppSettings.angleChoices, id: \.self) {
                                Text(SettingsCopy.angleTitle($0)).tag($0)
                            }
                        }
                    } label: {
                        SettingsRow(
                            title: "Default angle", value: SettingsCopy.angleTitle(defaultAngle), showsChevron: true)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    SettingsDivider()
                    Menu {
                        Picker("Clip quality", selection: $clipQuality) {
                            ForEach(ClipQuality.allCases, id: \.self) {
                                Text(SettingsCopy.clipQualityTitle($0)).tag($0)
                            }
                        }
                    } label: {
                        SettingsRow(
                            title: "Clip quality", value: SettingsCopy.clipQualityTitle(clipQuality),
                            showsChevron: true)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    SettingsDivider()
                    // TODO(#26): honour this and ask for Photos access when it's turned on (fable-security path).
                    SettingsToggleRow(
                        title: "Save clips to Photos", subtitle: "Off keeps clips inside Reps only",
                        isOn: $saveClipsToPhotos)
                    SettingsDivider()
                    // TODO(#22): the clip writer reads recordClipAudio; the mic prompt belongs to #5/#13.
                    SettingsToggleRow(
                        title: "Record audio on clips", subtitle: "Never used for counting", isOn: $recordClipAudio)
                }
                SettingsSection(title: "Voice") {
                    // TODO(#10): the speaker reads announceCount.
                    SettingsToggleRow(title: "Announce count", isOn: $announceCount)
                    SettingsDivider()
                    // TODO(#27): tempo callouts read announceTempo.
                    SettingsToggleRow(title: "Announce tempo", isOn: $announceTempo)
                    SettingsDivider()
                    // PLACEHOLDER: Guidance (F26) is later; the row is inert.
                    SettingsRow(
                        title: "Guidance", subtitle: "Keep going / stop — coming later", value: "Off",
                        showsChevron: true)
                }
                SettingsSection(title: "Storage") {
                    // TODO(#23): Manage opens clip storage management; inert until then.
                    SettingsRow(
                        title: "Clips", subtitle: SettingsCopy.clipUsage(clipUsage), value: "Manage",
                        showsChevron: true)
                }
                SettingsSection(title: "About") {
                    SettingsRow(title: "Version", value: SettingsCopy.version(info: Bundle.main.infoDictionary))
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            clipUsage = await Task.detached(priority: .utility) {
                ClipStorage.usage(at: ClipStorage.clipsDirectory)
            }.value
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .modelContainer(PreviewData.container())
}
```

`Reps/UI/Bag/BagEditorView.swift`. This is the reusable bag editor. It has no title, footer or scroll view of its own: the host embeds it in a `ScrollView` and adds its own chrome. Settings uses `BagSettingsView`; #5 wraps it with the "Your bag" title, the intro copy and "Continue with N clubs".

```swift
import SwiftData
import SwiftUI

// Figma 08 bag grid (F19). Every tap saves. Hosted by BagSettingsView and onboarding (#5).
struct BagEditorView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var askNewClub = false
    @State private var newClubName = ""
    @State private var renaming: BagClub?
    @State private var renameText = ""
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.rowGap), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sheetGap) {
            ForEach(BagCatalog.groups) { group in
                section(group.title) {
                    ForEach(group.clubs, id: \.self) { name in
                        let selected = isInBag(name)
                        Chip(title: chipTitle(name, selected), isSelected: selected) { setInBag(name, !selected) }
                    }
                }
            }
            let custom = clubs.filter { !BagCatalog.isStandard($0.name) }
            if !custom.isEmpty {
                section("Custom") {  // PLACEHOLDER: custom group title (not in Figma)
                    ForEach(custom) { club in
                        Chip(title: chipTitle(club.name, club.isInBag), isSelected: club.isInBag) {
                            setInBag(club.name, !club.isInBag)
                        }
                        .contextMenu {
                            Button("Rename") {
                                renameText = club.name
                                renaming = club
                            }
                            Button("Delete", role: .destructive) { delete(club) }
                        }
                    }
                }
            }
            DashedAddButton(
                title: "Add a custom club", font: Theme.Typography.pill, verticalPadding: 14, cornerRadius: 14
            ) {
                newClubName = ""
                askNewClub = true
            }
        }
        .alert("Add a club", isPresented: $askNewClub) {  // PLACEHOLDER: add club alert copy
            TextField("Club name", text: $newClubName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { add() }
        }
        .alert(
            "Rename club",  // PLACEHOLDER: rename alert copy
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { club in
            TextField("Club name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename(club) }
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
            Text(title)
                .font(Theme.Typography.footnoteMedium)
                .foregroundStyle(Theme.secondaryText)
            LazyVGrid(columns: columns, spacing: Theme.Spacing.rowGap) { content() }
        }
    }

    private func chipTitle(_ name: String, _ selected: Bool) -> String {
        selected ? "✓ \(name)" : name
    }

    private func isInBag(_ name: String) -> Bool {
        BagLibrary.club(named: name, in: clubs)?.isInBag ?? false
    }

    private func setInBag(_ name: String, _ isInBag: Bool) {
        perform { try BagLibrary.setInBag(name, isInBag, in: context) }
    }

    private func add() {
        perform { try BagLibrary.addCustom(newClubName, in: context) }
    }

    private func rename(_ club: BagClub) {
        perform { try BagLibrary.rename(club, to: renameText, in: context) }
    }

    private func delete(_ club: BagClub) {
        perform { try BagLibrary.delete(club, in: context) }
    }

    private func perform(_ write: () throws -> Void) {
        do {
            try write()
        } catch BagLibrary.BagError.emptyName {
            return
        } catch BagLibrary.BagError.duplicateName {
            errorMessage = "That club is already in your bag."  // PLACEHOLDER: duplicate club copy
        } catch {
            errorMessage = "Couldn't save your bag."  // PLACEHOLDER: error copy (#29)
        }
    }
}
```

(`add()` discards `addCustom`'s return value; it's `@discardableResult`.)

`Reps/UI/Bag/BagSettingsView.swift`:

```swift
import SwiftData
import SwiftUI

// Settings → My bag: the bag grid plus a Reorder sheet for picker order.
struct BagSettingsView: View {
    @State private var reordering = false

    var body: some View {
        ScrollView {
            BagEditorView()
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .background(Theme.background)
        .navigationTitle("My bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reorder") { reordering = true }  // PLACEHOLDER: reorder entry (not in Figma)
                    .tint(Theme.accent)
            }
        }
        .sheet(isPresented: $reordering) { BagOrderSheet() }
    }
}

// Drag the in-bag clubs into picker order.
struct BagOrderSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(clubs.filter(\.isInBag)) { club in
                    Text(club.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.ink)
                }
                .onMove { source, destination in
                    do {
                        try BagLibrary.move(fromOffsets: source, toOffset: destination, in: context)
                    } catch {
                        failed = true
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Bag order")  // PLACEHOLDER: reorder sheet title
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Theme.accent)
                }
            }
            .alert("Couldn't save the order.", isPresented: $failed) {  // PLACEHOLDER: error copy (#29)
                Button("OK", role: .cancel) {}
            }
        }
    }
}

#Preview {
    NavigationStack { BagSettingsView() }
        .modelContainer(PreviewData.container())
}
```

`Reps/UI/Plans/PlansView.swift` edits:
- Add `@State private var showsSettings = false`.
- Replace `Button("Settings") {}  // TODO(#6): open Settings` with `Button("Settings") { showsSettings = true }`.
- Add `.navigationDestination(isPresented: $showsSettings) { SettingsView() }` next to the other modifiers inside the `NavigationStack` (after `.toolbar`).

`Reps/App/RootView.swift` edits:
- In `start(plan:)`, delete the `// TODO(#6)` line and call `try controller().start(plan: plan, cameraAngle: AppSettings().cameraAngle(for: plan.mode))`.
- In `startFree()`, change the comment to `// PLACEHOLDER: free sessions start in Range mode until there's a mode choice (Q28).` and call `try controller().startFree(mode: .rangeCounter, cameraAngle: AppSettings().cameraAngle(for: .rangeCounter), clubName: club)`.

Update `docs/code-reference.md` for SettingsView, SettingsRows, SettingsTheme, BagEditorView, BagSettingsView, and the PlansView/RootView lines (drop "Settings is `TODO(#6)`" and "voice hook" stays).

### Step 4: docs (`documented settings`)

- `docs/plans/6-settings.md`: this plan.
- `docs/roadmap.md`: #6 → ☑ (in the PR commit that closes it).
- `docs/design.md`: add one line under the frame map: "Settings (#6): tokens in `Reps/UI/Settings/SettingsTheme.swift`; rows in `SettingsRows.swift`; the bag grid `BagEditorView` is shared with onboarding (#5)."
- `docs/open-questions.md`: add two rows, using the next free Q numbers (Q30/Q31 at the time of writing; the parallel #11 plan may take one, so check):
  - Q30 | Figma 10 has a global "Save clips to Photos" toggle, but spec §5.8 says Photos saving is per clip and never automatic (40 clips would flood the roll). Which is it? | #26 | #6 stores the preference only (default off). Leaning: the toggle means "auto-save every clip", off by default, and per-clip save stays in the clip detail.
  - Q31 | Clip quality options: #6 offers 1080p60 (default), 1080p30, 720p30. Does capture (1080p60 for detection, §5.6) constrain these to export presets only? | #22 | #22 maps them to writer settings or trims the list.

## Tests (Unit plan, Swift Testing)

`RepsTests/AppSettingsTests.swift` (not MainActor-bound; uses a throwaway suite):

```swift
import Foundation
import Testing

@testable import Reps

struct AppSettingsTests {
    private func withSettings(_ body: (AppSettings) throws -> Void) rethrows {
        let suite = "RepsTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults))
    }
    ...
}
```

Cases:
- `defaultsWhenEmpty`: faceOn, p1080fps60, photos false, audio true, count true, tempo false.
- `roundTripsEveryValue`: set each value to its non-default and read it back, both through the same `AppSettings` and through a second `AppSettings(defaults:)` over the same suite.
- `unknownOrNoneAngleFallsBack`: `defaults.set("none", …)` → `.faceOn`; `defaults.set("sideways", …)` → `.faceOn`; `defaults.set("downTheLine", …)` → `.downTheLine`.
- `unknownQualityFallsBack`: "4k" → `.p1080fps60`.
- `keysMatchAppStorageNames`: `AppSettings.Key.defaultCameraAngle == "settings.defaultCameraAngle"` (pins the persisted key names; one expect per key).
- `cameraAngleForMode`: default set to `.downTheLine` → rangeCounter and rangeCounterWithClips give `.downTheLine`, putting gives `.none`.

`RepsTests/ClipStorageTests.swift`: make a temp root `FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)` and remove it with `defer`.
- `missingFolderIsZero`: `usage(at: <nonexistent>) == .zero`.
- `sumsMovFilesInSessionFolders`: `s1/a.mov` (100 bytes), `s1/b.MOV` (50), `s2/c.mov` (25), `s2/thumb.jpg` (999), `.hidden.mov` (7) → `ClipUsage(bytes: 175, count: 3)`. Write files with `Data(count: n).write(to:)` after `createDirectory(withIntermediateDirectories: true)`.
- `clipsDirectoryIsDocumentsClips`: `ClipStorage.clipsDirectory.lastPathComponent == "clips"` and its parent is `URL.documentsDirectory` (compare `standardizedFileURL.path`).

`RepsTests/SettingsCopyTests.swift` (en_US locale):
- `clubCount`: 0 → "No clubs", 1 → "1 club", 14 → "14 clubs".
- `clipUsage`: nil → "Calculating…"; `.zero` → "No clips yet"; `(48_000_000, 1)` → "48 MB · 1 clip"; `(3_200_000_000, 412)` → "3.2 GB · 412 clips"; `(3_200_000_000, 1_412)` → "3.2 GB · 1,412 clips".
- `version`: `["CFBundleShortVersionString": "0.1", "CFBundleVersion": "12"]` → "0.1 (12)"; short only → "0.1"; build only → "(12)"; nil → "–".
- `angleAndQualityTitles`: faceOn "Face-on", downTheLine "Down-the-line", p1080fps60 "1080p · 60 fps".

`RepsTests/BagCatalogTests.swift`:
- `defaultBagIsFourteenCatalogClubs`: count 14, every name `isStandard`, no duplicate keys.
- `catalogHasUniqueKeys`: `Set(allClubs.map(BagCatalog.key)).count == allClubs.count`.
- `keyTrimsAndIgnoresCase`: `key(" 7 IRON ") == "7 iron"`, `isStandard("pw")`, `!isStandard("Chipper")`.
- `insertionIndex`: in `["Driver", "7 iron", "Putter"]`, "5 wood" → 1, "LW" → 2, "Putter"-less `["Driver", "Chipper"]` + "Putter" → 2, custom "Chipper" → 3 (count), empty list → 0; `["Chipper", "Driver"]` + "3 wood" → 2 (customs before it don't count as later).

`RepsTests/BagLibraryTests.swift` (`@MainActor`, in-memory container like `PlanLibraryTests`; helper `seed(_ names: [String])` inserts `BagClub(name:sortOrder:)` 0..<n and saves; helper `names() -> [String]` = `BagLibrary.all(in:).map(\.name)`; `order()` = `all.map(\.sortOrder)`):
- `setInBagInsertsStandardClubAtCatalogPosition`: seed Driver, 7 iron, Putter; `setInBag("5 wood", true)` → names [Driver, 5 wood, 7 iron, Putter], order [0,1,2,3].
- `setInBagOffKeepsRow`: seed Driver, 7 iron; off "7 iron" → 2 rows, 7 iron `isInBag == false`.
- `setInBagOnRestoresHiddenRowCaseInsensitively`: hide 7 iron, then `setInBag("7 IRON", true)` → 2 rows, in bag, name unchanged "7 iron".
- `setInBagOffForMissingNameDoesNothing`: row count unchanged.
- `setInBagRejectsBlankName`: `#expect(throws: BagLibrary.BagError.emptyName)`.
- `addCustomAppendsTrimmed`: seed Driver, Putter; `addCustom("  Chipper ")` → names [Driver, Putter, Chipper].
- `addCustomRejectsDuplicateInBag`: seed Driver; `addCustom("driver")` throws `.duplicateName`.
- `addCustomRestoresHiddenRow`: seed Chipper hidden; `addCustom("chipper")` → same row, in bag, count 1.
- `addCustomStandardNameGoesToCatalogPosition`: seed Driver, Putter; `addCustom("PW")` → [Driver, PW, Putter].
- `renameKeepsPlanSnapshots`: seed Chipper; insert a `PracticePlan` with a `PlanBlock(clubName: "Chipper", targetReps: 10, note: nil, order: 0)`; rename to "Bump and run" → bag name changed, block still "Chipper".
- `renameRejectsDuplicateButAllowsCaseChange`: seed Driver, Chipper; rename Chipper → "driver" throws `.duplicateName`; rename Chipper → "CHIPPER" succeeds.
- `deleteRenumbers`: seed Driver, 7 iron, Putter; delete 7 iron → [Driver, Putter], order [0,1].
- `moveReordersInBagAndPutsHiddenLast`: seed Driver, 3 wood, 7 iron, Putter; hide 3 wood; `move(fromOffsets: [2], toOffset: 0)` (Putter, in-bag index 2) → names [Putter, Driver, 7 iron, 3 wood], order [0,1,2,3].
- `moveIgnoresOutOfRangeOffsets`: `move(fromOffsets: [9], toOffset: 0)` → unchanged.

Views, alerts, menus and the reorder sheet are build-only (UI, per the CLAUDE.md test table).

## Verification

```sh
for DEST in 'platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A' 'platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'; do
  xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" \
    -only-testing:RepsTests/AppSettingsTests -only-testing:RepsTests/ClipStorageTests \
    -only-testing:RepsTests/SettingsCopyTests -only-testing:RepsTests/BagCatalogTests \
    -only-testing:RepsTests/BagLibraryTests -only-testing:RepsTests/ClubChoicesTests
done
xcrun swift-format format --in-place --recursive --parallel Reps RepsTests
xcrun swift-format lint --strict --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
```

The first sim is iOS 27, the second iOS 26.5; the latter matters for SwiftData (ADR 0013). A test run also builds the app, so no separate build is needed. Optional manual check: open Settings from Plans, toggle a club, and confirm the block editor's club grid updates.

## Placeholders (all marked `// PLACEHOLDER:`)

1. `ClipQuality.p720fps30`: clip quality option set (Q31)
2. `SettingsCopy.clubCount(0)`: "No clubs"
3. `SettingsCopy.clipUsage(nil)`: "Calculating…"
4. `SettingsCopy.clipUsage(.zero)`: "No clips yet"
5. `SettingsRow` chevron: SF Symbol instead of Figma's "›" text
6. Guidance row (F26): inert
7. Bag "Custom" group title
8. Add club alert copy
9. Rename alert copy
10. Duplicate club copy
11. Bag save error copy (#29)
12. "Reorder" toolbar entry (not in Figma)
13. "Bag order" sheet title
14. Reorder error copy (#29)
15. `RootView.startFree` Range mode (existing, Q28)

TODOs left for other issues: `TODO(#26)` (Photos toggle + permission), `TODO(#22)` (audio toggle; the mic prompt is #5/#13), `TODO(#10)` (announce count), `TODO(#27)` (announce tempo), `TODO(#23)` (Storage Manage).

Deviations from Figma 10: the Version row has no chevron because there's nothing to open. Storage "Manage" and Guidance keep their chevrons but are inert until #23 / F26.

## Risks

- **Menu label styling.** A `Menu` label inside the card may be tinted accent or get button padding. If `.menuStyle(.button).buttonStyle(.plain)` doesn't keep `SettingsRow`'s colours, add `.tint(Theme.ink)` on the `Menu`. Worst case, use a `Picker(...).pickerStyle(.menu)` whose label is `SettingsRowText`. Check in the preview.
- **`@AppStorage` with `CameraAngle` / `ClipQuality`** uses the `RawRepresentable where RawValue == String` initializer. A scratch typecheck passed with an equivalent enum. A stored `"none"` would show "None" in the row; `AppSettings` still sanitizes it for sessions.
- **Byte formatting**: `ByteCountFormatStyle(.file)` with en_US gives "48 MB" / "3.2 GB" (checked on macOS; iOS uses the same Foundation). If the sim differs, fix the test strings, not the code.
- **SwiftData fetch after delete**: `BagLibrary.delete` filters the deleted id out itself, so it doesn't rely on fetch excluding pending deletes.
- **Onboarding (#5) reuse**: `BagEditorView` needs only a model context and a host `ScrollView`. #5 seeds `BagCatalog.defaultBag` (e.g. a `BagLibrary.useDefaultBag(in:)` added there) and reads the in-bag count for "Continue with N clubs" from its own `@Query`.
- **Photos toggle semantics** conflict with spec §5.8 (Q30). The preference is stored but unused until #26 decides.
