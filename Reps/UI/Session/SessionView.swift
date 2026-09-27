import SwiftData
import SwiftUI

// Figma 03 (range), 05 (putting), 14 (next block early). Manual counting only; the camera arrives with #13.
struct SessionView: View {
    let controller: SessionController

    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var nextPrompt: NextBlockPrompt?
    @State private var showSummary = false
    @State private var pickingClub = false
    @State private var askNewTag = false
    @State private var newTag = ""

    var body: some View {
        Group {
            // Nil for a moment while the cover animates away after finish().
            if let session = controller.session {
                content(session)
            } else {
                Theme.background.ignoresSafeArea()
            }
        }
        .sessionScreenGuard()
        .alert(
            nextPrompt?.title ?? "",
            isPresented: Binding(get: { nextPrompt != nil }, set: { if !$0 { nextPrompt = nil } }),
            presenting: nextPrompt
        ) { _ in
            Button("Stay", role: .cancel) {}
            Button("Next block") { controller.advance() }
                .keyboardShortcut(.defaultAction)
        } message: { prompt in
            Text(prompt.message)
        }
        .alert("New tag", isPresented: $askNewTag) {  // PLACEHOLDER: new-tag alert copy
            TextField("e.g. fade", text: $newTag)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                if let tags = SessionDisplay.adding(newTag, to: controller.activeTags) { controller.setTags(tags) }
            }
        }
        .sheet(isPresented: $pickingClub) {
            FreeClubSheet(current: controller.activeBlock?.clubName ?? "") { controller.setClub($0) }
        }
        .sheet(isPresented: $showSummary) {
            SummaryPlaceholderView(
                onKeepGoing: { showSummary = false },
                // finish() clears the session, which closes the session cover and this sheet with it.
                onDone: { controller.finish() }
            )
        }
    }

    private func content(_ session: PracticeSession) -> some View {
        VStack(spacing: 0) {
            header(session)
            if !controller.isFreeSession {
                BlockStrip(chips: stripChips(session), onSelect: select)
                    .padding(.top, 10)
                    .padding(.bottom, showsChipRow(session) ? 4 : 10)
            }
            if showsChipRow(session) {
                chipRow
                    .padding(.top, controller.isFreeSession ? 10 : 6)
                    .padding(.bottom, 10)
            }
            // PLACEHOLDER: camera preview (#13)
            RoundedRectangle(cornerRadius: Theme.Radius.preview)
                .fill(Theme.fill)
                .overlay {
                    Label("Camera", systemImage: "camera")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(height: session.mode == .putting ? 150 : 190)
                .padding(.horizontal, Theme.Spacing.gutter)
            count(session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            manualControls
            if !controller.isFreeSession && controller.activeBlock != nil {
                Button("Next block", action: requestNextBlock)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.background)
    }

    private func header(_ session: PracticeSession) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(SessionDisplay.title(planName: session.planName))
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text(SessionDisplay.subtitle(mode: session.mode, angle: session.cameraAngle))
                    .font(Theme.Typography.navSubtitle)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .padding(.horizontal, 72)
            HStack {
                Button("End") { showSummary = true }
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                Spacer()
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(SessionDisplay.elapsed(context.date.timeIntervalSince(session.startedAt)))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                .accessibilityLabel("Elapsed time")
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, 6)
    }

    // Figma 05 has no chip row: putting uses one club and records no clips.
    private func showsChipRow(_ session: PracticeSession) -> Bool {
        session.mode != .putting
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.rowGap) {
                if let block = controller.activeBlock {
                    CapsuleChip(
                        title: block.clubName,
                        isSelected: true,
                        action: controller.isFreeSession ? { pickingClub = true } : nil
                    )
                }
                ForEach(SessionDisplay.tagChoices(active: controller.activeTags, recent: recentTags), id: \.self) {
                    tag in
                    CapsuleChip(title: tag, isSelected: controller.activeTags.contains(tag)) {
                        controller.setTags(SessionDisplay.toggling(tag, in: controller.activeTags))
                    }
                }
                CapsuleChip(title: "+ tag", isSelected: false) {
                    newTag = ""
                    askNewTag = true
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
        }
    }

    @ViewBuilder
    private func count(_ session: PracticeSession) -> some View {
        if let block = controller.activeBlock {
            let done = block.tally.done
            VStack(spacing: 0) {
                Text("\(done)")
                    .font(Theme.Typography.count)
                    .tracking(Theme.Typography.countTracking)
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: done)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(
                    SessionDisplay.countDetail(
                        done: done, target: block.targetReps, note: block.block?.note, mode: session.mode)
                )
                .font(Theme.Typography.countDetail)
                .foregroundStyle(Theme.secondaryText)
                // TODO(#27): tempo row ("tempo 3.1 : 1", Figma 03) goes here, 14 pt below the detail line.
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Text("All blocks done")  // PLACEHOLDER: no block left to run
                    .font(Theme.Typography.value)
                    .foregroundStyle(Theme.ink)
                Text("Pick a block from the strip, or tap End.")  // PLACEHOLDER: no block left hint
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var manualControls: some View {
        HStack(spacing: 12) {
            Button("−1") { controller.minusOne() }
                .accessibilityLabel("Minus one")
            Button("+1") { controller.recordShot(source: .manual) }
                .accessibilityLabel("Plus one")
                .disabled(controller.activeBlock == nil)
        }
        .buttonStyle(ManualCountButtonStyle())
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, 12)
    }

    private var recentTags: [String] {
        sessions.prefix(20).flatMap { $0.sortedBlockResults.reversed().flatMap(\.tags) }
    }

    private func stripChips(_ session: PracticeSession) -> [StripChip] {
        SessionDisplay.stripChips(
            controller.blocks.map(BlockSnapshot.init),
            mode: session.mode,
            activeOrder: controller.activeBlock?.order,
            canSelect: controller.canSelectBlocks,
            isStrict: controller.isStrictCount
        )
    }

    private func select(order: Int) {
        guard let block = controller.blocks.first(where: { $0.order == order }) else { return }
        controller.select(block)
    }

    private func requestNextBlock() {
        guard let block = controller.activeBlock else { return }
        if let prompt = SessionDisplay.nextBlockPrompt(
            clubName: block.clubName, done: block.tally.done, target: block.targetReps,
            canComeBack: controller.canSelectBlocks)
        {
            nextPrompt = prompt
        } else {
            controller.advance()
        }
    }
}

// Big grey −1 / +1 (Figma 03: 64 pt tall, radius 18).
private struct ManualCountButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.manualButton)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Theme.fill, in: .rect(cornerRadius: Theme.Radius.cta))
            .contentShape(.rect(cornerRadius: Theme.Radius.cta))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension BlockSnapshot {
    init(_ result: BlockResult) {
        self.init(
            order: result.order, clubName: result.clubName, note: result.block?.note, done: result.tally.done,
            target: result.targetReps)
    }
}

#if DEBUG
    #Preview {
        let container = PreviewData.container()
        let controller = SessionController(context: container.mainContext)
        let plan = try! container.mainContext.fetch(FetchDescriptor<PracticePlan>()).first { $0.name == "Wedge day" }!
        try! controller.start(plan: plan, cameraAngle: .faceOn)
        return SessionView(controller: controller)
            .modelContainer(container)
    }
#endif
