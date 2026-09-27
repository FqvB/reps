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
