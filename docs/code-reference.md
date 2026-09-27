# Code reference

The documentation for files and functions. Code comments stay short, and the detail lives here. Update this file in the same commit as the code.

Format:

```
## path/to/File.swift
Purpose in one line.
- `TypeOrFunction(signature)`: what it does / returns, notable side effects
```

## Reps/App/RepsApp.swift
App entry point; opens the SwiftData store and shows the root view.
- `RepsApp`: `@main` app; builds the container with `RepsStore.makeContainer()` (fatal on failure until #29) and attaches it with `.modelContainer(_:)`

## Reps/App/RootView.swift
Placeholder root screen until the plans list (#7) replaces it.
- `RootView`: shows the app name

## Reps/Persistence/RepsStore.swift
Builds the SwiftData container for the app and tests.
- `RepsStore.models`: the `@Model` types in the schema (empty until #4)
- `RepsStore.makeContainer(inMemory:) throws -> ModelContainer`: container over `models`; `inMemory: true` for tests

## ShotDetector/ShotEvent.swift
Output type of the ShotDetector framework (spec §4). The framework must never import AVFoundation, UIKit or SwiftUI.
- `ShotEvent(time:)`: one detected shot; `time` is seconds from the start of the frame stream

## RepsTests/RepsStoreTests.swift
- `RepsStoreTests.inMemoryContainerOpens`: the schema opens in an in-memory container

## DetectorEvalTests/MLData.swift
Locates the hitreg-ml checkout (ADR 0007).
- `MLData.root: URL?`: `REPS_ML_DIR` if set, else `<repo>/../hitreg-ml`; `nil` when `data/manifest.csv` isn't there (suites skip)

## DetectorEvalTests/MLDataTests.swift
- `MLDataTests.testSplitIsListed`: `data/splits.json` has a non-empty `test` split; skipped without footage
