---
status: resolved
trigger: "The app build fails with PhaseScriptExecution and Xcode reports missing package products ReRoomContracts and ReRoomCaptureCore."
created: 2026-07-18
updated: 2026-07-18
---

# Debug Session: Missing Local Package Products

## Symptoms

- Expected behavior: `ReRoomDeviceProof` resolves its local Swift package and builds normally.
- Actual behavior: the build stops with `Command PhaseScriptExecution failed with a nonzero exit code`.
- Error messages: Xcode reports missing package products `ReRoomContracts` and `ReRoomCaptureCore`.
- Timeline: observed on the current Phase 2 tree after native package-product integration; earlier automated Xcode tests passed with cached resolution.
- Reproduction: resolve or build the `ReRoomDeviceProof` shared scheme from the `.xcodeproj`.

## Current Focus

- hypothesis: Confirmed and fixed. The package diagnostics came from product dependencies without explicit package ownership, while the actual nonzero exit came from the Debug provenance phase rejecting the local signing-team project change.
- test: Bind both products to the local package, compare the project semantically while excluding only `DEVELOPMENT_TEAM`, and build with isolated DerivedData.
- expecting: Both package products resolve and compile, and the provenance phase accepts a signing-only override while rejecting other semantic project changes.
- next_action: None; verified resolved.
- reasoning_checkpoint: Clean package resolution succeeded before the fix, proving the products existed; the isolated build then identified `Embed Debug Build Provenance` as the failing phase.
- tdd_checkpoint: GREEN — two regression tests pass.

## Evidence

- timestamp: 2026-07-18
  observation: `Package.swift` exports `ReRoomContracts` and static `ReRoomCaptureCore`; the project references `../Packages/ReRoomContracts`.
- timestamp: 2026-07-18
  observation: Both `XCSwiftPackageProductDependency` records contained only `productName` and no `package` reference.
- timestamp: 2026-07-18
  observation: Isolated `xcodebuild -resolvePackageDependencies` succeeded and resolved the local package plus its pinned dependencies.
- timestamp: 2026-07-18
  observation: The isolated pre-fix build compiled and linked both package products, then failed specifically in `Embed Debug Build Provenance`.
- timestamp: 2026-07-18
  observation: Normalizing HEAD and the working project as JSON and removing only `DEVELOPMENT_TEAM` produced identical content, proving the local project difference was signing metadata plus nonsemantic Xcode formatting.
- timestamp: 2026-07-18
  observation: Post-fix clean simulator build completed with exit code 0 and embedded `ReRoomBuildProvenance.plist`.

## Eliminated

- hypothesis: The Swift package no longer exports the named products.
  reason: Both products are present in `ios/Packages/ReRoomContracts/Package.swift` and compiled in the isolated build.
- hypothesis: The project points at a nonexistent local package directory.
  reason: `../Packages/ReRoomContracts` resolves from the project directory to the existing package.
- hypothesis: Package resolution itself caused the `PhaseScriptExecution` failure.
  reason: Package resolution and compilation completed before the build entered and failed the provenance script phase.

## Resolution

- root_cause: The Xcode package-product objects omitted explicit ownership by the local package, creating the missing-product diagnostics. Separately, the fail-closed provenance script compared the raw project file and rejected the necessary local `DEVELOPMENT_TEAM` override, which caused the reported nonzero script exit.
- fix: Added the local package reference to both product dependencies. Changed provenance validation to compare normalized project semantics while ignoring only `DEVELOPMENT_TEAM`; all other behavior-bearing changes still fail closed.
- verification: `python3 -m unittest tools.verify.tests.test_ios_build_provenance -v` passes both tests; `plutil -lint` passes; an isolated Debug iOS Simulator `xcodebuild build` exits 0 and embeds `ReRoomBuildProvenance.plist`.
- files_changed: `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj`, `scripts/embed-ios-build-provenance`, `tools/verify/tests/test_ios_build_provenance.py`
