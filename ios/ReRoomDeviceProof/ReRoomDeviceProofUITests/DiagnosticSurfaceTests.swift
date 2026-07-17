import XCTest

final class DiagnosticSurfaceTests: XCTestCase {
    func testBuiltProductExposesOnlyItsConfigurationSurface() {
        let app = XCUIApplication()
#if DEBUG
        app.launchEnvironment["REROOM_IMPLEMENTATION_REVISION"] =
            "git:0123456789abcdef0123456789abcdef01234567"
        app.launchEnvironment["REROOM_FIXTURE_SHA256"] = String(repeating: "a", count: 64)
#endif
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
        let orientation = element(in: app, identifiedBy: "debug.check.orientation")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForValue(containing: "Landscape", in: orientation))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForValue(containing: "Portrait", in: orientation))

        let export = element(in: app, identifiedBy: "debug.action.exportEvidence")
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
#endif
    }

    private func element(in app: XCUIApplication, identifiedBy identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForValue(containing expected: String, in element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
