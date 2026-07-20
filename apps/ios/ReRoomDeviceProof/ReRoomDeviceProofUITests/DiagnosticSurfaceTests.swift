import XCTest

final class DiagnosticSurfaceTests: XCTestCase {
    @MainActor
    func testBuiltProductExposesOnlyItsConfigurationSurface() {
        let app = XCUIApplication()
        app.launchEnvironment["REROOM_IMPLEMENTATION_REVISION"] =
            "git:" + String(repeating: "1", count: 40)
        app.launchEnvironment["REROOM_FIXTURE_SHA256"] = String(repeating: "a", count: 64)
        app.launch()

#if DEBUG
        XCTAssertTrue(
            element(in: app, identifiedBy: "debug.root.diagnostics")
                .waitForExistence(timeout: 5),
            "Debug must launch the diagnostic checklist root."
        )
        XCTAssertTrue(element(in: app, identifiedBy: "debug.check.camera").exists)
        XCTAssertTrue(element(in: app, identifiedBy: "debug.check.gate").exists)
        XCTAssertTrue(element(in: app, identifiedBy: "debug.action.exportEvidence").exists)
        XCTAssertTrue(element(in: app, identifiedBy: "debug.action.worldReset").exists)
        let startCapture = element(in: app, identifiedBy: "diagnostic.capture.start")
        makeHittable(startCapture, in: app)
        startCapture.tap()
        XCTAssertTrue(app.staticTexts["Start local room capture?"].waitForExistence(timeout: 3))
        let keepCaptureOff = button(in: app, named: "Keep Capture Off")
        XCTAssertTrue(keepCaptureOff.waitForExistence(timeout: 3))
        keepCaptureOff.tap()
        XCTAssertTrue(
            element(in: app, identifiedBy: "diagnostic.capture.denied")
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(element(in: app, identifiedBy: "diagnostic.capture.local-state").exists)

        makeHittable(startCapture, in: app)
        startCapture.tap()
        let acceptCapture = button(in: app, named: "Accept and Start")
        XCTAssertTrue(acceptCapture.waitForExistence(timeout: 3))
        acceptCapture.tap()
        let localState = element(in: app, identifiedBy: "diagnostic.capture.local-state")
        let localStateAppeared = localState.waitForExistence(timeout: 5)
        let captureFailure = element(in: app, identifiedBy: "diagnostic.capture.failure")
        XCTAssertTrue(
            localStateAppeared,
            "Capture did not start: \(captureFailure.label)"
        )
        guard localStateAppeared else { return }
        XCTAssertTrue(localState.label.contains("Recording locally"))
        XCTAssertTrue(element(in: app, identifiedBy: "diagnostic.capture.upload-state").exists)
        XCTAssertTrue(element(in: app, identifiedBy: "diagnostic.capture.share-state").exists)
        XCTAssertTrue(element(in: app, identifiedBy: "diagnostic.capture.admission").exists)
        XCTAssertTrue(element(in: app, identifiedBy: "diagnostic.capture.explicit").exists)
        XCTAssertTrue(element(in: app, identifiedBy: "diagnostic.capture.stop").exists)
        let orientation = element(in: app, identifiedBy: "debug.check.orientation")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForValue(containing: "Landscape", in: orientation))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForValue(containing: "Portrait", in: orientation))

        let export = element(in: app, identifiedBy: "debug.action.exportEvidence")
        for _ in 0..<3 where !export.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(export.isHittable)
        export.tap()
        let exported = element(in: app, identifiedBy: "debug.status.exportEvidence")
        XCTAssertTrue(exported.waitForExistence(timeout: 5))
        XCTAssertTrue((exported.label + String(describing: exported.value)).contains("Exported"))
        XCTAssertFalse(element(in: app, identifiedBy: "release.root.candidate").exists)
#else
        XCTAssertTrue(
            element(in: app, identifiedBy: "release.root.candidate")
                .waitForExistence(timeout: 5),
            "Release must launch the narrow candidate device-proof root."
        )
        XCTAssertTrue(app.staticTexts["ReRoom device check"].exists)
        XCTAssertFalse(element(in: app, identifiedBy: "debug.root.diagnostics").exists)
        XCTAssertFalse(element(in: app, identifiedBy: "debug.action.exportEvidence").exists)
        XCTAssertFalse(element(in: app, identifiedBy: "debug.permission.microphone").exists)
        XCTAssertFalse(element(in: app, identifiedBy: "debug.action.worldReset").exists)
#endif
    }

    @MainActor
    private func element(in app: XCUIApplication, identifiedBy identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func waitForValue(containing expected: String, in element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func button(in app: XCUIApplication, named label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
