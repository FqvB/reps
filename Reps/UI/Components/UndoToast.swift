import SwiftUI

// Dark toast with an Undo action (F24, §5.3c).
struct UndoToast: View {
    static let duration: Duration = .seconds(5)

    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(Theme.Typography.chip)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button("Undo", action: onUndo)
                .font(Theme.Typography.chipSelected)
                .foregroundStyle(Theme.toastAction)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.ink, in: .rect(cornerRadius: Theme.Radius.toast))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    // Clears `item` after UndoToast.duration; a new item restarts the timer.
    func undoToastTimer<Item: Identifiable>(_ item: Binding<Item?>) -> some View {
        task(id: item.wrappedValue?.id) {
            guard item.wrappedValue != nil else { return }
            try? await Task.sleep(for: UndoToast.duration)
            guard !Task.isCancelled else { return }
            withAnimation { item.wrappedValue = nil }
        }
    }
}
