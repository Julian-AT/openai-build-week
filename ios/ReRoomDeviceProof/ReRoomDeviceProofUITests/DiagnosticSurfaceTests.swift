import XCTest

final class DiagnosticSurfaceTests: XCTestCase {
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
}
