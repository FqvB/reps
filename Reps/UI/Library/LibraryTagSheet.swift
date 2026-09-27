import SwiftUI

// Bulk add/remove tag (§5.3b). One tap applies and closes, so one Undo covers it. No Figma frame.
struct LibraryTagSheet: View {
    let selectedCount: Int
    let onSelection: [String]
    let suggestions: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Add a tag", text: $newTag)  // PLACEHOLDER: tag field copy
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { add(newTag) }
                    ForEach(matchingSuggestions, id: \.self) { tag in
                        Button(tag) { add(tag) }
                            .foregroundStyle(Theme.ink)
                    }
                } header: {
                    Text("Add to \(LibraryDisplay.countTitle(selectedCount))")
                }
                if !onSelection.isEmpty {
                    Section("Remove") {
                        ForEach(onSelection, id: \.self) { tag in
                            Button(tag, role: .destructive) {
                                onRemove(tag)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // Autocomplete from history (§5.3b): prefix matches first, at most 8.
    private var matchingSuggestions: [String] {
        let typed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return Array(suggestions.prefix(8)) }
        return Array(suggestions.filter { $0.localizedStandardContains(typed) && $0 != typed }.prefix(8))
    }

    private func add(_ tag: String) {
        guard !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAdd(tag)
        dismiss()
    }
}
