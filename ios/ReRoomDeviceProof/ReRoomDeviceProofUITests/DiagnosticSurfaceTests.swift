import XCTest

final class DiagnosticSurfaceTests: XCTestCase {
    @MainActor
    func testBuiltProductExposesOnlyItsConfigurationSurface() {
        let app = XCUIApplication()
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
}
