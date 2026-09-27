import SwiftUI

// Figma 04 "Filters": one capsule per filter, filled when set; each opens a menu (★ toggles).
struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    let clubs: [String]
    let tags: [String]
    let months: [LibraryMonth]
    let sessions: [LibrarySessionOption]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                clubMenu
                angleMenu
                monthMenu
                Button {
                    filter.favouritesOnly.toggle()
                } label: {
                    FilterChipLabel(title: "★", isSelected: filter.favouritesOnly)
                }
                .accessibilityLabel("Favourites")
                .accessibilityAddTraits(filter.favouritesOnly ? .isSelected : [])
                tagMenu
                sessionMenu
                if filter.hasChipFilters {
                    Button("Clear") {  // PLACEHOLDER: clear-filters copy
                        let search = filter.searchText
                        filter = LibraryFilter(searchText: search)
                    }
                    .font(Theme.Typography.filterChip)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var clubMenu: some View {
        Menu {
            Picker("Club", selection: $filter.club) {
                Text("All clubs").tag(String?.none)
                ForEach(clubs, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } label: {
            // PLACEHOLDER: filter chip copy ("Club", "Angle", "Date", "Session")
            FilterChipLabel(title: filter.club ?? "Club", isSelected: filter.club != nil)
        }
    }

    private var angleMenu: some View {
        Menu {
            Picker("Angle", selection: $filter.angle) {
                Text("Any angle").tag(CameraAngle?.none)
                ForEach(AppSettings.angleChoices, id: \.self) {
                    Text(LibraryDisplay.angleOptionTitle($0)).tag(Optional($0))
                }
            }
        } label: {
            FilterChipLabel(
                title: filter.angle.map(LibraryDisplay.angleOptionTitle) ?? "Angle", isSelected: filter.angle != nil)
        }
    }

    private var monthMenu: some View {
        Menu {
            Picker("Date", selection: $filter.month) {
                Text("Any date").tag(LibraryMonth?.none)
                ForEach(months, id: \.self) { Text(LibraryDisplay.monthTitle($0)).tag(Optional($0)) }
            }
        } label: {
            FilterChipLabel(
                title: filter.month.map { LibraryDisplay.monthTitle($0) } ?? "Date", isSelected: filter.month != nil)
        }
    }

    // Several tags can be on; a clip must have all of them.
    private var tagMenu: some View {
        Menu {
            ForEach(tags, id: \.self) { tag in
                Toggle(
                    tag,
                    isOn: Binding(
                        get: { filter.tags.contains(tag) },
                        set: { isOn in
                            if isOn { filter.tags.insert(tag) } else { filter.tags.remove(tag) }
                        }))
            }
            if tags.isEmpty { Text("No tags yet") }  // PLACEHOLDER: empty tag menu copy
        } label: {
            FilterChipLabel(title: LibraryDisplay.tagChipTitle(filter.tags), isSelected: !filter.tags.isEmpty)
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var sessionMenu: some View {
        Menu {
            Picker("Session", selection: $filter.sessionID) {
                Text("Any session").tag(UUID?.none)
                ForEach(sessions) { Text(LibraryDisplay.sessionTitle($0)).tag(Optional($0.id)) }
            }
        } label: {
            FilterChipLabel(
                title: sessions.first { $0.id == filter.sessionID }?.title ?? "Session",
                isSelected: filter.sessionID != nil)
        }
    }
}

private struct FilterChipLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(isSelected ? Theme.Typography.filterChipSelected : Theme.Typography.filterChip)
            .foregroundStyle(isSelected ? Color.white : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.accent : Theme.card, in: .capsule)
            .contentShape(.capsule)
    }
}
