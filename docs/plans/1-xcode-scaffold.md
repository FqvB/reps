# #1 Xcode project scaffold

Goal: a committed Xcode project that builds for iOS 26 iPhone, with a SwiftData-backed placeholder app, an AVFoundation-free `ShotDetector` framework, `Unit` and `DetectorEval` test plans, and swift-format. No features.

Spec: §4 (design rule: ShotDetector has no AVFoundation dependency), §7. ADRs: 0004, 0005, 0007. Issue owner: iOS 26, `com.fqvb.reps`, free provisioning, swift-format.

Every file below was built and tested by the planner in a scratch copy with Xcode 27.0 (27A5252f): simulator build, device build (`CODE_SIGNING_ALLOWED=NO`), both test plans, the skip path, `TEST_RUNNER_REPS_ML_DIR`, and `swift-format lint --strict` all passed. **Copy the file contents exactly.** Don't open the project in the Xcode GUI during implementation (it rewrites the pbxproj).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Project generation | Hand-authored `project.pbxproj`, `objectVersion = 77`, file-system synchronized root groups. No xcodegen/tuist. | Synced folders mean new files never touch the pbxproj, so no generator tool (brew is installed, but xcodegen adds a dependency and a regenerate step for no gain). |
| Module boundary | `ShotDetector` is a separate iOS **framework target** (folder `ShotDetector/`), embedded in the app. | Makes the spec §4 rule a real module boundary. DetectorEval links only the framework and runs without launching the app. |
| Targets | `Reps` (app), `ShotDetector` (framework), `RepsTests` (unit, hosted in the app), `DetectorEvalTests` (unit-test bundle, no host, links `ShotDetector`). | Matches CLAUDE.md test plans `Unit` / `DetectorEval`. |
| UI tests | **Not in this issue.** No `UI` plan or UI test target. | Nothing to UI-test yet. The first issue that needs one (#11, accident-proofing) adds a `RepsUITests` target and `TestPlans/UI.xctestplan`; that requires a pbxproj edit, noted in ADR 0009. |
| Test framework | Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`, `.enabled(if:)`) for both targets. | Current Apple default; `.enabled(if:)` gives a clean skip for missing footage. |
| SwiftData | `RepsStore.makeContainer(inMemory:)` over an **empty** schema; the app attaches it with `.modelContainer(_:)`. | #4 owns the `@Model` types; it only has to fill `RepsStore.models`. An empty schema was verified to open both on disk (app launch) and in memory. |
| Swift settings | Swift 6 language mode everywhere, `SWIFT_APPROACHABLE_CONCURRENCY = YES`. App target only: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. `ShotDetector` stays nonisolated by default (it will run off the main thread). | Xcode 26+ app defaults; detector code must not be main-actor bound. |
| Signing | `CODE_SIGN_STYLE = Automatic`, no `DEVELOPMENT_TEAM` in the pbxproj. The project-level configs use `Config/Signing.xcconfig`, which does `#include? "Signing.local.xcconfig"` (gitignored) where the owner puts `DEVELOPMENT_TEAM = <id>`. | Team ID never gets committed; simulator builds need no team. |
| Platform | `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `TARGETED_DEVICE_FAMILY = 1`, `SUPPORTS_MACCATALYST/…DESIGNED_FOR_IPHONE_IPAD/XR = NO`. | Owner comment, CLAUDE.md. |
| Bundle IDs | `com.fqvb.reps`, `com.fqvb.reps.ShotDetector`, `com.fqvb.reps.tests`, `com.fqvb.reps.detectoreval`. | |
| Footage location | `DetectorEvalTests/MLData.swift`: `REPS_ML_DIR` env var if set, else the sibling checkout derived from `#filePath` (`<repo>/../hitreg-ml`). If `data/manifest.csv` isn't there, `MLData.root` is `nil` and suites skip. | ADR 0007's default. `~` inside the simulator is the sim container, so `#filePath` is used instead of the home dir. Shell env vars reach the simulator test runner only with the `TEST_RUNNER_` prefix (xcodebuild man page). |
| Simulator | `platform=iOS Simulator,name=iPhone 17 Pro,OS=latest` (exists on iOS 26.5 and 27.0 here; `OS=latest` removes the ambiguity). | |
| Formatter | `xcrun swift-format` (bundled with Xcode). `.swift-format` = defaults from `dump-configuration` with 4-space indent and line length 120. | |

## Final layout

```
Reps.xcodeproj/
  project.pbxproj
  xcshareddata/xcschemes/Reps.xcscheme
Config/Signing.xcconfig
Reps/                      # app target (synced folder)
  App/RepsApp.swift
  App/RootView.swift
  Persistence/RepsStore.swift
  Assets.xcassets/{Contents.json, AppIcon.appiconset/Contents.json, AccentColor.colorset/Contents.json}
ShotDetector/              # framework target (synced folder), no AVFoundation/UIKit/SwiftUI
  ShotEvent.swift
RepsTests/                 # Unit plan
  RepsStoreTests.swift
DetectorEvalTests/         # DetectorEval plan
  MLData.swift
  MLDataTests.swift
TestPlans/
  Unit.xctestplan
  DetectorEval.xctestplan
.swift-format
```

`ml/models/` is untouched (the classifier is wired into the app by #18). Nothing else in the repo moves.

## Steps

Work on the existing branch `feat/1-xcode-scaffold`. Run all commands from the repo root `/Users/egsango/Documents/Programming/GitHub/reps`.

### Step 1 — project, app, framework, tests, test plans

1. Create every file in **Appendix A** with exactly the given content (create directories as needed).
2. Append to `.gitignore`:
   ```
   # Local signing (DEVELOPMENT_TEAM)
   Config/Signing.local.xcconfig
   ```
3. Verify (all must succeed):
   ```sh
   xcodebuild -project Reps.xcodeproj -scheme Reps -showTestPlans   # lists Unit, DetectorEval
   xcodebuild build -project Reps.xcodeproj -scheme Reps \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -quiet
   xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
   xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
   ```
   - `Unit`: `inMemoryContainerOpens()` passes.
   - `DetectorEval`: `testSplitIsListed()` **passes** here (hitreg-ml is a sibling checkout on this Mac). The first run may stall on a macOS privacy prompt for the Documents folder (the planner's first run took ~110 s); later runs are instant.
   - Skip path: `TEST_RUNNER_REPS_ML_DIR=/nonexistent xcodebuild test … -testPlan DetectorEval …` must end `** TEST SUCCEEDED **` with `Suite MLDataTests skipped: "hitreg-ml not found; set REPS_ML_DIR"`.
   - Boundary check prints nothing: `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI)' ShotDetector`
4. Make sure `git status` shows no `xcuserdata/`, `DerivedData/` or `build/` (already ignored). Commit:
   `git add -A && git commit -m "added xcode project scaffold" -m "Refs #1"`

### Step 2 — swift-format

1. Create `.swift-format`:
   ```sh
   xcrun swift-format dump-configuration > /tmp/sf.json
   python3 - <<'EOF'
   import json
   c = json.load(open('/tmp/sf.json'))
   c['indentation'] = {'spaces': 4}
   c['lineLength'] = 120
   json.dump(c, open('.swift-format', 'w'), indent=2, sort_keys=True)
   open('.swift-format', 'a').write('\n')
   EOF
   ```
   (Appendix B shows the expected result. If the dump differs from it because of a toolchain update, keep what the dump produced, with only those two edits.)
2. Format, then lint strictly; lint must exit 0 with no output:
   ```sh
   xcrun swift-format format --in-place --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
   xcrun swift-format lint --strict --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
   ```
   Appendix A files already pass, so `format` should change nothing (`git status` shows only `.swift-format`).
3. Commit: `git add .swift-format && git commit -m "added swift-format config" -m "Refs #1"`

### Step 3 — docs

1. **CLAUDE.md**, section "Testing": replace the line
   `- Filter with \`-only-testing:<Target>/<Suite>\` instead of running everything. Exact commands go here once #1 (scaffold) lands.`
   with the block in **Appendix C**.
2. **docs/code-reference.md**: replace the line `_No code yet. The first entries land with #1 (scaffold)._` with the entries in **Appendix D**.
3. **docs/adr/0009-project-structure.md**: create with the content in **Appendix E**, and add this row to the table in `docs/adr/README.md` after 0008:
   `| [0009](0009-project-structure.md) | Hand-written synced-folder Xcode project, ShotDetector as a framework | Accepted |`
4. **docs/roadmap.md**: in the Phase 0 table, change the #1 row status `☐` to `☑`.
5. Commit: `git add -A && git commit -m "documented project scaffold" -m "Refs #1"`

Then push and open the PR (per CLAUDE.md): title `added xcode project scaffold`, body one line (`xcode project, ShotDetector framework, Unit and DetectorEval plans, swift-format`) plus `Closes #1`. No attribution lines.

## Tests

- `Unit` → `RepsTests/RepsStoreTests.inMemoryContainerOpens`: the SwiftData container opens with the current schema in memory. Also exercises the app host launching with the on-disk store.
- `DetectorEval` → `DetectorEvalTests/MLDataTests.testSplitIsListed`: the footage locator finds hitreg-ml and `data/splits.json` has a non-empty `test` list; skips cleanly when the data isn't found.
- Nothing else. The root view and `ShotEvent` have no behaviour worth testing (CLAUDE.md).

## Risks / unresolved

- **Device install not verified.** Only simulator and `generic/platform=iOS` with signing disabled were built. First device run: owner creates `Config/Signing.local.xcconfig` with `DEVELOPMENT_TEAM = <personal team id>`. If Xcode's Signing & Capabilities UI is used instead, it writes the team into the pbxproj; don't commit that.
- **Embedded framework + free provisioning**: the embedded `ShotDetector.framework` is signed with the same automatic identity (`CodeSignOnCopy`); should be fine but untested on device.
- **TCC prompt** the first time the simulator reads `~/Documents/.../hitreg-ml` (see Step 1). One-off.
- **pbxproj hand edits later**: adding a target (UI tests in #11, maybe a widget) needs a manual pbxproj edit or a one-off Xcode GUI change. Adding files never does.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app means non-UI app types (SessionController, ClipWriter) must opt out with `nonisolated` where needed; #8/#22 planners should know this. Recorded in ADR 0009.
- No new open questions.

---

## Appendix A — files

### `Reps.xcodeproj/project.pbxproj`

```text
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		AA0000000000000000000050 /* ShotDetector.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000021 /* ShotDetector.framework */; };
		AA0000000000000000000051 /* ShotDetector.framework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000021 /* ShotDetector.framework */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };
		AA0000000000000000000052 /* ShotDetector.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000021 /* ShotDetector.framework */; };
		AA0000000000000000000053 /* ShotDetector.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000021 /* ShotDetector.framework */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		AA0000000000000000000060 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AA0000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = AA0000000000000000000031;
			remoteInfo = ShotDetector;
		};
		AA0000000000000000000061 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AA0000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = AA0000000000000000000030;
			remoteInfo = Reps;
		};
		AA0000000000000000000062 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AA0000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = AA0000000000000000000031;
			remoteInfo = ShotDetector;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		AA0000000000000000000043 /* Embed Frameworks */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
				AA0000000000000000000051 /* ShotDetector.framework in Embed Frameworks */,
			);
			name = "Embed Frameworks";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		AA0000000000000000000020 /* Reps.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Reps.app; sourceTree = BUILT_PRODUCTS_DIR; };
		AA0000000000000000000021 /* ShotDetector.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = ShotDetector.framework; sourceTree = BUILT_PRODUCTS_DIR; };
		AA0000000000000000000022 /* RepsTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = RepsTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		AA0000000000000000000023 /* DetectorEvalTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = DetectorEvalTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		AA0000000000000000000024 /* Signing.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Signing.xcconfig; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		AA0000000000000000000010 /* Reps */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Reps;
			sourceTree = "<group>";
		};
		AA0000000000000000000011 /* ShotDetector */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = ShotDetector;
			sourceTree = "<group>";
		};
		AA0000000000000000000012 /* RepsTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RepsTests;
			sourceTree = "<group>";
		};
		AA0000000000000000000013 /* DetectorEvalTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = DetectorEvalTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		AA0000000000000000000041 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000050 /* ShotDetector.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000045 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000048 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000052 /* ShotDetector.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA000000000000000000004B /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000053 /* ShotDetector.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		AA0000000000000000000002 = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000010 /* Reps */,
				AA0000000000000000000011 /* ShotDetector */,
				AA0000000000000000000012 /* RepsTests */,
				AA0000000000000000000013 /* DetectorEvalTests */,
				AA0000000000000000000004 /* Config */,
				AA0000000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		AA0000000000000000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000020 /* Reps.app */,
				AA0000000000000000000021 /* ShotDetector.framework */,
				AA0000000000000000000022 /* RepsTests.xctest */,
				AA0000000000000000000023 /* DetectorEvalTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		AA0000000000000000000004 /* Config */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000024 /* Signing.xcconfig */,
			);
			path = Config;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		AA0000000000000000000030 /* Reps */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000081 /* Build configuration list for PBXNativeTarget "Reps" */;
			buildPhases = (
				AA0000000000000000000040 /* Sources */,
				AA0000000000000000000041 /* Frameworks */,
				AA0000000000000000000042 /* Resources */,
				AA0000000000000000000043 /* Embed Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				AA0000000000000000000070 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000010 /* Reps */,
			);
			name = Reps;
			packageProductDependencies = (
			);
			productName = Reps;
			productReference = AA0000000000000000000020 /* Reps.app */;
			productType = "com.apple.product-type.application";
		};
		AA0000000000000000000031 /* ShotDetector */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000082 /* Build configuration list for PBXNativeTarget "ShotDetector" */;
			buildPhases = (
				AA0000000000000000000044 /* Sources */,
				AA0000000000000000000045 /* Frameworks */,
				AA0000000000000000000046 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000011 /* ShotDetector */,
			);
			name = ShotDetector;
			packageProductDependencies = (
			);
			productName = ShotDetector;
			productReference = AA0000000000000000000021 /* ShotDetector.framework */;
			productType = "com.apple.product-type.framework";
		};
		AA0000000000000000000032 /* RepsTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000083 /* Build configuration list for PBXNativeTarget "RepsTests" */;
			buildPhases = (
				AA0000000000000000000047 /* Sources */,
				AA0000000000000000000048 /* Frameworks */,
				AA0000000000000000000049 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				AA0000000000000000000071 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000012 /* RepsTests */,
			);
			name = RepsTests;
			packageProductDependencies = (
			);
			productName = RepsTests;
			productReference = AA0000000000000000000022 /* RepsTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		AA0000000000000000000033 /* DetectorEvalTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000084 /* Build configuration list for PBXNativeTarget "DetectorEvalTests" */;
			buildPhases = (
				AA000000000000000000004A /* Sources */,
				AA000000000000000000004B /* Frameworks */,
				AA000000000000000000004C /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				AA0000000000000000000072 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000013 /* DetectorEvalTests */,
			);
			name = DetectorEvalTests;
			packageProductDependencies = (
			);
			productName = DetectorEvalTests;
			productReference = AA0000000000000000000023 /* DetectorEvalTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		AA0000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
				TargetAttributes = {
					AA0000000000000000000030 = {
						CreatedOnToolsVersion = 27.0;
					};
					AA0000000000000000000031 = {
						CreatedOnToolsVersion = 27.0;
					};
					AA0000000000000000000032 = {
						CreatedOnToolsVersion = 27.0;
						TestTargetID = AA0000000000000000000030;
					};
					AA0000000000000000000033 = {
						CreatedOnToolsVersion = 27.0;
					};
				};
			};
			buildConfigurationList = AA0000000000000000000080 /* Build configuration list for PBXProject "Reps" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = AA0000000000000000000002;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = AA0000000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				AA0000000000000000000030 /* Reps */,
				AA0000000000000000000031 /* ShotDetector */,
				AA0000000000000000000032 /* RepsTests */,
				AA0000000000000000000033 /* DetectorEvalTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		AA0000000000000000000042 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000046 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000049 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA000000000000000000004C /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		AA0000000000000000000040 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000044 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000047 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA000000000000000000004A /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		AA0000000000000000000070 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AA0000000000000000000031 /* ShotDetector */;
			targetProxy = AA0000000000000000000060 /* PBXContainerItemProxy */;
		};
		AA0000000000000000000071 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AA0000000000000000000030 /* Reps */;
			targetProxy = AA0000000000000000000061 /* PBXContainerItemProxy */;
		};
		AA0000000000000000000072 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AA0000000000000000000031 /* ShotDetector */;
			targetProxy = AA0000000000000000000062 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		AA0000000000000000000090 /* Debug */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = AA0000000000000000000024 /* Signing.xcconfig */;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CODE_SIGN_STYLE = Automatic;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				IPHONEOS_DEPLOYMENT_TARGET = 26.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Debug;
		};
		AA0000000000000000000091 /* Release */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = AA0000000000000000000024 /* Signing.xcconfig */;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CODE_SIGN_STYLE = Automatic;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 26.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 1;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		AA0000000000000000000092 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = Reps;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps;
				PRODUCT_NAME = "$(TARGET_NAME)";
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
			};
			name = Debug;
		};
		AA0000000000000000000093 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = Reps;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps;
				PRODUCT_NAME = "$(TARGET_NAME)";
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
			};
			name = Release;
		};
		AA0000000000000000000094 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CURRENT_PROJECT_VERSION = 1;
				DEFINES_MODULE = YES;
				DYLIB_COMPATIBILITY_VERSION = 1;
				DYLIB_CURRENT_VERSION = 1;
				DYLIB_INSTALL_NAME_BASE = "@rpath";
				GENERATE_INFOPLIST_FILE = YES;
				INSTALL_PATH = "$(LOCAL_LIBRARY_DIR)/Frameworks";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps.ShotDetector;
				PRODUCT_NAME = "$(TARGET_NAME:c99extidentifier)";
				SKIP_INSTALL = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				VERSIONING_SYSTEM = "apple-generic";
				VERSION_INFO_PREFIX = "";
			};
			name = Debug;
		};
		AA0000000000000000000095 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CURRENT_PROJECT_VERSION = 1;
				DEFINES_MODULE = YES;
				DYLIB_COMPATIBILITY_VERSION = 1;
				DYLIB_CURRENT_VERSION = 1;
				DYLIB_INSTALL_NAME_BASE = "@rpath";
				GENERATE_INFOPLIST_FILE = YES;
				INSTALL_PATH = "$(LOCAL_LIBRARY_DIR)/Frameworks";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps.ShotDetector;
				PRODUCT_NAME = "$(TARGET_NAME:c99extidentifier)";
				SKIP_INSTALL = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				VERSIONING_SYSTEM = "apple-generic";
				VERSION_INFO_PREFIX = "";
			};
			name = Release;
		};
		AA0000000000000000000096 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Reps.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Reps";
			};
			name = Debug;
		};
		AA0000000000000000000097 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Reps.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Reps";
			};
			name = Release;
		};
		AA0000000000000000000098 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps.detectoreval;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
			};
			name = Debug;
		};
		AA0000000000000000000099 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 0.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.fqvb.reps.detectoreval;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		AA0000000000000000000080 /* Build configuration list for PBXProject "Reps" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000090 /* Debug */,
				AA0000000000000000000091 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000081 /* Build configuration list for PBXNativeTarget "Reps" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000092 /* Debug */,
				AA0000000000000000000093 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000082 /* Build configuration list for PBXNativeTarget "ShotDetector" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000094 /* Debug */,
				AA0000000000000000000095 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000083 /* Build configuration list for PBXNativeTarget "RepsTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000096 /* Debug */,
				AA0000000000000000000097 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000084 /* Build configuration list for PBXNativeTarget "DetectorEvalTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000098 /* Debug */,
				AA0000000000000000000099 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = AA0000000000000000000001 /* Project object */;
}
```

### `Reps.xcodeproj/xcshareddata/xcschemes/Reps.xcscheme`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "AA0000000000000000000030"
               BuildableName = "Reps.app"
               BlueprintName = "Reps"
               ReferencedContainer = "container:Reps.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <TestPlans>
         <TestPlanReference
            reference = "container:TestPlans/Unit.xctestplan"
            default = "YES">
         </TestPlanReference>
         <TestPlanReference
            reference = "container:TestPlans/DetectorEval.xctestplan">
         </TestPlanReference>
      </TestPlans>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "AA0000000000000000000030"
            BuildableName = "Reps.app"
            BlueprintName = "Reps"
            ReferencedContainer = "container:Reps.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "AA0000000000000000000030"
            BuildableName = "Reps.app"
            BlueprintName = "Reps"
            ReferencedContainer = "container:Reps.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

### `Config/Signing.xcconfig`

```text
// Put DEVELOPMENT_TEAM = <your team ID> in Signing.local.xcconfig (gitignored).
#include? "Signing.local.xcconfig"
```

### `Reps/App/RepsApp.swift`

```swift
import SwiftData
import SwiftUI

@main
struct RepsApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try RepsStore.makeContainer()
        } catch {
            // No recovery path yet; error handling lands with #29.
            fatalError("Failed to open the SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
```

### `Reps/App/RootView.swift`

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Reps")
            .font(.largeTitle.bold())
    }
}

#Preview {
    RootView()
}
```

### `Reps/Persistence/RepsStore.swift`

```swift
import SwiftData

enum RepsStore {
    // Empty until #4 adds the @Model types.
    static let models: [any PersistentModel.Type] = []

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

### `Reps/Assets.xcassets/Contents.json`

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

### `Reps/Assets.xcassets/AppIcon.appiconset/Contents.json`

```json
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

### `Reps/Assets.xcassets/AccentColor.colorset/Contents.json`

```json
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

### `ShotDetector/ShotEvent.swift`

```swift
// ShotDetector stays free of AVFoundation (spec §4): frames in, events out.
public struct ShotEvent: Sendable, Hashable {
    public var time: Double

    public init(time: Double) {
        self.time = time
    }
}
```

### `RepsTests/RepsStoreTests.swift`

```swift
import SwiftData
import Testing

@testable import Reps

@MainActor
struct RepsStoreTests {
    @Test func inMemoryContainerOpens() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        #expect(container.configurations.first?.isStoredInMemoryOnly == true)
    }
}
```

### `DetectorEvalTests/MLData.swift`

```swift
import Foundation

// Locates the hitreg-ml checkout (ADR 0007): REPS_ML_DIR, else the sibling repo.
enum MLData {
    static let root: URL? = {
        let candidate: URL
        if let path = ProcessInfo.processInfo.environment["REPS_ML_DIR"], !path.isEmpty {
            candidate = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            candidate = siblingCheckout
        }
        let manifest = candidate.appending(path: "data/manifest.csv")
        return FileManager.default.fileExists(atPath: manifest.path) ? candidate : nil
    }()

    // <repo>/DetectorEvalTests/MLData.swift -> <repo>/../hitreg-ml
    private static var siblingCheckout: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "hitreg-ml", directoryHint: .isDirectory)
    }
}
```

### `DetectorEvalTests/MLDataTests.swift`

```swift
import Foundation
import Testing

@Suite(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
struct MLDataTests {
    @Test func testSplitIsListed() throws {
        let root = try #require(MLData.root)
        let data = try Data(contentsOf: root.appending(path: "data/splits.json"))
        let splits = try JSONDecoder().decode([String: [String]].self, from: data)
        let test = try #require(splits["test"])
        #expect(!test.isEmpty)
    }
}
```

### `TestPlans/Unit.xctestplan`

```json
{
  "configurations" : [
    {
      "id" : "5F0C1A2B-0001-4000-8000-000000000001",
      "name" : "Default",
      "options" : {

      }
    }
  ],
  "defaultOptions" : {

  },
  "testTargets" : [
    {
      "target" : {
        "containerPath" : "container:Reps.xcodeproj",
        "identifier" : "AA0000000000000000000032",
        "name" : "RepsTests"
      }
    }
  ],
  "version" : 1
}
```

### `TestPlans/DetectorEval.xctestplan`

```json
{
  "configurations" : [
    {
      "id" : "5F0C1A2B-0002-4000-8000-000000000002",
      "name" : "Default",
      "options" : {

      }
    }
  ],
  "defaultOptions" : {
    "testTimeoutsEnabled" : false
  },
  "testTargets" : [
    {
      "target" : {
        "containerPath" : "container:Reps.xcodeproj",
        "identifier" : "AA0000000000000000000033",
        "name" : "DetectorEvalTests"
      }
    }
  ],
  "version" : 1
}
```

## Appendix B — expected `.swift-format`

```json
{
  "fileScopedDeclarationPrivacy": {
    "accessLevel": "private"
  },
  "indentBlankLines": false,
  "indentConditionalCompilationBlocks": true,
  "indentSwitchCaseLabels": false,
  "indentation": {
    "spaces": 4
  },
  "lineBreakAroundMultilineExpressionChainComponents": false,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": false,
  "lineBreakBeforeEachGenericRequirement": false,
  "lineBreakBetweenDeclarationAttributes": false,
  "lineLength": 120,
  "maximumBlankLines": 1,
  "multiElementCollectionTrailingCommas": true,
  "multilineTrailingCommaBehavior": "keptAsWritten",
  "noAssignmentInExpressions": {
    "allowedFunctions": [
      "XCTAssertNoThrow"
    ]
  },
  "orderedImports": {
    "includeConditionalImports": false,
    "shouldGroupImports": true
  },
  "prioritizeKeepingFunctionOutputTogether": false,
  "reflowMultilineStringLiterals": "never",
  "respectsExistingLineBreaks": true,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": false,
    "AlwaysUseLiteralForEmptyCollectionInit": false,
    "AlwaysUseLowerCamelCase": true,
    "AmbiguousTrailingClosureOverload": true,
    "AvoidRetroactiveConformances": true,
    "BeginDocumentationCommentWithOneLineSummary": false,
    "DoNotUseSemicolons": true,
    "DontRepeatTypeInStaticProperties": true,
    "FileScopedDeclarationPrivacy": true,
    "FullyIndirectEnum": true,
    "GroupNumericLiterals": true,
    "IdentifiersMustBeASCII": true,
    "NeverForceUnwrap": false,
    "NeverUseForceTry": false,
    "NeverUseImplicitlyUnwrappedOptionals": false,
    "NoAccessLevelOnExtensionDeclaration": true,
    "NoAssignmentInExpressions": true,
    "NoBlockComments": true,
    "NoCasesWithOnlyFallthrough": true,
    "NoEmptyLinesOpeningClosingBraces": false,
    "NoEmptyTrailingClosureParentheses": true,
    "NoLabelsInCasePatterns": true,
    "NoLeadingUnderscores": false,
    "NoParensAroundConditions": true,
    "NoPlaygroundLiterals": true,
    "NoVoidReturnOnFunctionSignature": true,
    "OmitExplicitReturns": false,
    "OneCasePerLine": true,
    "OneVariableDeclarationPerLine": true,
    "OnlyOneTrailingClosureArgument": true,
    "OrderedImports": true,
    "ReplaceForEachWithForLoop": true,
    "ReturnVoidInsteadOfEmptyTuple": true,
    "TypeNamesShouldBeCapitalized": true,
    "UseEarlyExits": false,
    "UseExplicitNilCheckInConditions": true,
    "UseLetInEveryBoundCaseVariable": true,
    "UseShorthandTypeNames": true,
    "UseSingleLinePropertyGetter": true,
    "UseSynthesizedInitializer": true,
    "UseTripleSlashForDocumentationComments": true,
    "UseWhereClausesInForLoops": false,
    "ValidateDocumentationComments": false
  },
  "spacesAroundRangeFormationOperators": false,
  "spacesBeforeEndOfLineComments": 2,
  "tabWidth": 8,
  "version": 1
}
```

## Appendix C — CLAUDE.md Testing commands

Replace the "Filter with…" line with:

````markdown
- Filter with `-only-testing:<Target>/<Suite>` instead of running everything. Commands (run from the repo root):

```sh
DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
# build
xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST" -quiet
# Unit, filtered to a suite
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/RepsStoreTests
# DetectorEval (footage from ../hitreg-ml; override with TEST_RUNNER_REPS_ML_DIR=/path, skips if not found)
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST"
# format + lint
xcrun swift-format format --in-place --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
xcrun swift-format lint --strict --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
```

- Env vars reach simulator tests only with the `TEST_RUNNER_` prefix (it's stripped), e.g. `TEST_RUNNER_REPS_ML_DIR`.
- Source files go in the synced folders (`Reps/`, `ShotDetector/`, `RepsTests/`, `DetectorEvalTests/`); never edit `project.pbxproj` to add files. Signing: put `DEVELOPMENT_TEAM = …` in `Config/Signing.local.xcconfig` (gitignored).
````

## Appendix D — docs/code-reference.md entries

```markdown
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
```

## Appendix E — docs/adr/0009-project-structure.md

```markdown
# 0009 — Hand-written synced-folder Xcode project, ShotDetector as a framework

- Status: Accepted
- Date: 2026-09-27

## Context
The project is created and changed by agents without the Xcode GUI. Spec §4 requires ShotDetector to have no AVFoundation dependency so it runs against video files in tests.

## Decision
- `Reps.xcodeproj` is hand-written (objectVersion 77) with file-system synchronized folders: `Reps/`, `ShotDetector/`, `RepsTests/`, `DetectorEvalTests/`. No xcodegen or tuist.
- `ShotDetector` is its own framework target, embedded in the app. It never imports AVFoundation, AVKit, UIKit or SwiftUI. It is nonisolated by default; the app target defaults to MainActor isolation.
- Tests use Swift Testing. `Unit` runs `RepsTests` (hosted in the app); `DetectorEval` runs `DetectorEvalTests` (no host, links only ShotDetector).
- Signing stays out of git: `Config/Signing.xcconfig` includes the gitignored `Signing.local.xcconfig`.

## Consequences
Adding files needs no project edits. Adding a target (UI tests with #11) needs a hand edit of `project.pbxproj`. The detector boundary is enforced by the module, and checked with `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI)' ShotDetector`.
```
