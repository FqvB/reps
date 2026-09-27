import SwiftData
import Testing

@testable import Reps

@MainActor
struct RepsStoreTests {
    @Test func inMemoryContainerOpens() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        #expect(container.configurations.first?.isStoredInMemoryOnly == true)
    }

    @Test func schemaHasEveryModel() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        let names = Set(container.schema.entities.map(\.name))
        #expect(names == ["BagClub", "PracticePlan", "PlanBlock", "PracticeSession", "BlockResult", "ShotRecord"])
    }

    @Test func schemaIsVersionOne() {
        #expect(RepsSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(RepsMigrationPlan.schemas.count == 1)
    }

    @Test func schemaShapeIsPinned() throws {
        let expectedAttributes: [String: Set<String>] = [
            "BagClub": ["id", "name", "sortOrder", "isInBag"],
            "PracticePlan": ["id", "name", "mode", "isOrderMandatory", "isStrictCount", "createdAt"],
            "PlanBlock": ["id", "clubName", "targetReps", "note", "order"],
            "PracticeSession": [
                "id", "planName", "mode", "status", "startedAt", "endedAt", "cameraAngle", "isStrictCount",
                "isOrderMandatory", "activeBlockOrder",
            ],
            "BlockResult": [
                "id", "order", "clubName", "targetReps", "tags", "repsCounted", "repsManualAdjust",
            ],
            "ShotRecord": [
                "id", "timestamp", "detectedBy", "clubName", "tags", "isFavourite", "tempoRatio", "clipFileName",
            ],
        ]
        let expectedRelationships: [String: Set<String>] = [
            "BagClub": [],
            "PracticePlan": ["blocks", "sessions"],
            "PlanBlock": ["plan", "results"],
            "PracticeSession": ["plan", "blockResults"],
            "BlockResult": ["session", "block", "shots"],
            "ShotRecord": ["blockResult"],
        ]

        let schema = Schema(versionedSchema: RepsSchemaV1.self)
        for entity in schema.entities {
            let expectedAttrs = try #require(
                expectedAttributes[entity.name], "V1 schema changed — add RepsSchemaV2 + migration stage (ADR 0012)")
            let expectedRels = try #require(
                expectedRelationships[entity.name],
                "V1 schema changed — add RepsSchemaV2 + migration stage (ADR 0012)")
            #expect(
                Set(entity.attributes.map(\.name)) == expectedAttrs,
                "V1 schema changed — add RepsSchemaV2 + migration stage (ADR 0012)")
            #expect(
                Set(entity.relationships.map(\.name)) == expectedRels,
                "V1 schema changed — add RepsSchemaV2 + migration stage (ADR 0012)")
        }
    }
}
