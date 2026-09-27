import Testing

struct EventMatcherTests {
    private func score(
        _ labels: [(Double, LabelKind)], _ detections: [Double], profile: ScoringProfile = .rangeShot
    ) -> VideoScore {
        EventMatcher.score(
            labels: labels.map { TimedLabel(time: $0.0, kind: $0.1) },
            detections: detections.map { Detection(time: $0, emittedAt: $0 + 0.3) },
            profile: profile, window: 0.5)
    }

    @Test func detectionInsideWindowIsTruePositive() {
        let s = score([(10, .swing)], [10.2])
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 0)
        #expect(s.falseNegatives == 0)
        #expect(s.latencies.count == 1)
        #expect(abs(s.latencies[0] - 0.5) < 1e-9)  // emittedAt 10.5 − label 10
        #expect(abs(s.timingErrors[0] - 0.2) < 1e-9)
    }

    @Test func windowEdgeIsInclusive() {
        #expect(score([(10, .swing)], [9.5]).truePositives == 1)
        #expect(score([(10, .swing)], [10.5]).truePositives == 1)
    }

    @Test func detectionOutsideWindowIsMissPlusFalsePositive() {
        let s = score([(10, .swing)], [10.6])
        #expect(s.truePositives == 0)
        #expect(s.falseNegatives == 1)
        #expect(s.otherFalsePositives == 1)
        #expect(s.hardNegativeFalsePositives == 0)
    }

    @Test func doubleCountIsOneFalsePositive() {
        let s = score([(10, .swing)], [10.0, 10.1])
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 1)
        #expect(s.countError == 1)
    }

    @Test func oneDetectionServesOneLabel() {
        let s = score([(10, .swing), (10.4, .swing)], [10.2])
        #expect(s.truePositives == 1)
        #expect(s.falseNegatives == 1)
        #expect(s.countError == -1)
    }

    // Nearest-pair-first would pair 10.45 with 10.8 and lose a match.
    @Test func matchingMaximisesTruePositives() {
        let s = score([(10, .swing), (10.8, .swing)], [10.45, 11.2])
        #expect(s.truePositives == 2)
        #expect(s.falsePositives == 0)
    }

    @Test func unsortedInputGivesSameResult() {
        let s = score([(20, .swing), (10, .swing)], [20.1, 10.1])
        #expect(s.truePositives == 2)
    }

    @Test func practiceSwingIsHardNegativeForRangeShot() {
        let s = score([(5, .practice)], [5.1])
        #expect(s.positives == 0)
        #expect(s.hardNegativeFalsePositives == 1)
        #expect(s.firedByKind[.practice] == 1)
    }

    @Test func practiceSwingIsPositiveForRangeSwing() {
        let s = score([(5, .practice)], [5.1], profile: .rangeSwing)
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 0)
    }

    @Test func motionIsHardNegativeEverywhere() {
        for profile in [ScoringProfile.rangeShot, .rangeSwing, .putting] {
            #expect(score([(8, .motion)], [8.0], profile: profile).hardNegativeFalsePositives == 1)
        }
    }

    @Test func pickupCountsInPutting() {
        let s = score([(3, .pickup), (9, .putt)], [3.2, 9.1], profile: .putting)
        #expect(s.truePositives == 2)
        #expect(s.firedByKind[.pickup] == 1)
    }

    @Test func positiveWinsOverNearbyNegative() {
        let s = score([(10, .swing), (10.2, .motion)], [10.1])
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 0)
        #expect(s.firedByKind[.motion] == nil)
    }

    @Test func twoDetectionsOnOneNegativeAreTwoFalsePositives() {
        let s = score([(8, .motion)], [8.0, 8.2])
        #expect(s.hardNegativeFalsePositives == 2)
        #expect(s.firedByKind[.motion] == 1)
    }

    @Test func noDetections() {
        let s = score([(1, .swing), (2, .practice), (5, .swing)], [])
        #expect(s.detections == 0)
        #expect(s.falseNegatives == 2)
        #expect(s.labelsByKind == [.swing: 2, .practice: 1])
        #expect(s.firedByKind.isEmpty)
    }
}
