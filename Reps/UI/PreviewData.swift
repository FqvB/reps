#if DEBUG
    import SwiftData

    // Seeded in-memory store for #Previews only (sample content from the Figma frames).
    enum PreviewData {
        static func container() -> ModelContainer {
            let container = try! RepsStore.makeContainer(inMemory: true)
            let context = container.mainContext
            let bag = [
                "Driver", "3 wood", "5 wood", "4 hybrid", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron", "PW", "GW",
                "SW", "LW", "Putter",
            ]
            for (index, name) in bag.enumerated() { context.insert(BagClub(name: name, sortOrder: index)) }
            let plans: [(String, PracticeMode, Bool, [(String, Int, String?)])] = [
                (
                    "Wedge day", .rangeCounterWithClips, false,
                    [
                        ("PW", 40, "110 m"), ("GW", 30, "95 m, half swing"), ("SW", 40, "80 m"),
                        ("LW", 30, "60 m, flop"), ("PW", 30, nil),
                    ]
                ),
                ("Irons ladder", .rangeCounter, true, [("5 iron", 30, nil), ("6 iron", 30, nil), ("7 iron", 30, nil)]),
                (
                    "Putting 3-6-9", .putting, true,
                    [("Putter", 30, "3 ft"), ("Putter", 30, "6 ft"), ("Putter", 30, "9 ft")]
                ),
            ]
            for (name, mode, ordered, blocks) in plans {
                let plan = PracticePlan(name: name, mode: mode, isOrderMandatory: ordered)
                context.insert(plan)
                plan.blocks = blocks.enumerated().map {
                    PlanBlock(clubName: $1.0, targetReps: $1.1, note: $1.2, order: $0)
                }
            }
            return container
        }
    }
#endif
