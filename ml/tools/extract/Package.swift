// swift-tools-version:5.9
// Package.swift — builds the `extract` command-line tool.
//
// Put this file at reps-ml/tools/extract/Package.swift with main.swift in
// reps-ml/tools/extract/Sources/extract/main.swift, then:
//
//     cd tools/extract
//     swift build -c release
//     .build/release/extract ../../data/raw/<video>.mov ../../data/keypoints/<video>.json

import PackageDescription

let package = Package(
    name: "extract",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "extract",
            path: "Sources/extract"
        )
    ]
)