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
