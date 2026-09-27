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
