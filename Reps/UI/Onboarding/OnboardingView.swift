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
