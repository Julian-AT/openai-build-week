import XCTest

final class RoomEditJourneyTests: XCTestCase {
    @MainActor
    func testBundledReplacementLoadsAndFullJourneyIsExactlyOnce() {
        var app = launch(reset: true, scenario: "healthy")
        XCTAssertTrue(element("roomedit.asset.proxy.loaded", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("roomedit.asset.proxy.loaded", in: app).label, "Six-cube local demo proxy loaded")
        XCTAssertTrue(element("roomedit.replace.supported-view", in: app).exists)
        XCTAssertTrue(element("roomedit.replace.gate.pending", in: app).exists)

        tapTargetSurface(in: app)
        element("roomedit.operation.replace", in: app).tap()
        XCTAssertTrue(element("roomedit.preview.replacement", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("roomedit.render.target.coverage", in: app).exists)
        XCTAssertTrue(element("roomedit.render.replacement", in: app).exists)
        XCTAssertEqual(element("roomedit.revision.current", in: app).label, "Current revision r0")

        element("roomedit.action.confirm.replace", in: app).tap()
        XCTAssertTrue(waitForLabel("Current revision r1", on: element("roomedit.revision.current", in: app)))
        XCTAssertTrue(element("roomedit.asset.replacement.committed", in: app).exists)
        XCTAssertTrue(element("roomedit.action.retry.replace", in: app).exists)
        element("roomedit.action.retry.replace", in: app).tap()
        XCTAssertEqual(element("roomedit.revision.current", in: app).label, "Current revision r1")

        app.terminate()
        app = launch(reset: false, scenario: "healthy")
        XCTAssertTrue(waitForLabel("Current revision r1", on: element("roomedit.revision.current", in: app)))
        XCTAssertTrue(element("roomedit.asset.replacement.committed", in: app).exists)
        element("roomedit.operation.restore", in: app).tap()
        XCTAssertTrue(waitForLabel("Current revision r2", on: element("roomedit.revision.current", in: app)))
        XCTAssertTrue(element("roomedit.restore.committed", in: app).exists)
        XCTAssertFalse(element("roomedit.asset.replacement.committed", in: app).exists)
    }

    @MainActor
    func testFiveDeterministicReplacementFixtureIterations() {
        for iteration in 1...5 {
            let app = launch(reset: true, scenario: "healthy")
            XCTAssertTrue(
                element("roomedit.asset.proxy.loaded", in: app).waitForExistence(timeout: 5),
                "asset iteration \(iteration)"
            )
            tapTargetSurface(in: app)
            XCTAssertEqual(
                element("roomedit.target.id", in: app).label,
                "Target ID object_53000000-0000-4000-8000-000000000030"
            )
            element("roomedit.operation.replace", in: app).tap()
            XCTAssertTrue(element("roomedit.action.confirm.replace", in: app).waitForExistence(timeout: 2))
            element("roomedit.action.confirm.replace", in: app).tap()
            XCTAssertTrue(waitForLabel("Current revision r1", on: element("roomedit.revision.current", in: app)))
            element("roomedit.action.retry.replace", in: app).tap()
            XCTAssertEqual(element("roomedit.revision.current", in: app).label, "Current revision r1")
            XCTAssertTrue(element("roomedit.asset.replacement.committed", in: app).exists)
            element("roomedit.operation.restore", in: app).tap()
            XCTAssertTrue(waitForLabel("Current revision r2", on: element("roomedit.revision.current", in: app)))
            XCTAssertFalse(element("roomedit.asset.replacement.committed", in: app).exists)
            app.terminate()
        }
    }

    @MainActor
    func testReplacementLoaderFailureRetainsSafeTarget() {
        let app = launch(reset: true, scenario: "healthy", failReplacementLoad: true)
        tapTargetSurface(in: app)
        XCTAssertTrue(element("roomedit.asset.proxy.failed", in: app).waitForExistence(timeout: 5))
        element("roomedit.operation.replace", in: app).tap()
        XCTAssertTrue(element("roomedit.blocker.replace.asset", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("roomedit.render.target.coverage", in: app).exists)
        XCTAssertFalse(element("roomedit.render.replacement", in: app).exists)
        XCTAssertEqual(element("roomedit.revision.current", in: app).label, "Current revision r0")
    }

    @MainActor
    func testManualTargetSeedReseedReadinessAndTrackingRevocation() {
        var app = launch(reset: true, scenario: "healthy")
        tapTargetSurface(in: app)

        XCTAssertTrue(element("roomedit.target.id", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("roomedit.target.epoch", in: app).exists)
        XCTAssertTrue(element("roomedit.readiness.select", in: app).exists)
        XCTAssertTrue(element("roomedit.readiness.place", in: app).exists)
        XCTAssertTrue(element("roomedit.readiness.replace", in: app).exists)
        XCTAssertTrue(element("roomedit.readiness.remove", in: app).exists)
        XCTAssertTrue(element("roomedit.readiness.restore", in: app).exists)
        XCTAssertTrue(element("roomedit.fallback.manual", in: app).exists)
        XCTAssertTrue(element("roomedit.fallback.no-dense", in: app).exists)
        XCTAssertTrue(element("roomedit.fallback.local", in: app).exists)
        XCTAssertTrue(element("roomedit.compositor.reveal.unavailable", in: app).exists)
        XCTAssertTrue(element("roomedit.compositor.occluder.unavailable", in: app).exists)
        XCTAssertTrue(element("roomedit.gates.pending", in: app).exists)

        element("roomedit.target.reseed", in: app).tap()
        XCTAssertTrue(waitForLabel(
            "Frozen proxy v2",
            on: element("roomedit.target.proxy.version", in: app)
        ))

        app.terminate()
        app = launch(reset: true, scenario: "tracking-loss")
        tapTargetSurface(in: app)
        XCTAssertTrue(element("roomedit.target.tracking.unavailable", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(waitForLabel(
            "Select: unavailable — tracking_not_normal",
            on: element("roomedit.readiness.select", in: app)
        ))
    }

    @MainActor
    func testTargetMissAndAmbiguityAreExplicit() {
        var app = launch(reset: true, scenario: "miss")
        tapTargetSurface(in: app)
        XCTAssertTrue(element("roomedit.target.failure.miss", in: app).waitForExistence(timeout: 2))

        app.terminate()
        app = launch(reset: true, scenario: "ambiguous")
        tapTargetSurface(in: app)
        XCTAssertTrue(element("roomedit.target.failure.ambiguous", in: app).waitForExistence(timeout: 2))
    }

    @MainActor
    func testPlaceCancelConfirmRelaunchAndOfflineRestore() {
        var app = launch(reset: true)
        XCTAssertTrue(element("roomedit.root", in: app).waitForExistence(timeout: 5))

        for operation in ["place", "replace", "remove", "restore"] {
            XCTAssertTrue(element("roomedit.operation.\(operation)", in: app).exists)
        }
        XCTAssertFalse(element("roomedit.operation.undo", in: app).exists)

        element("roomedit.operation.replace", in: app).tap()
        XCTAssertTrue(element("roomedit.blocker.replace", in: app).waitForExistence(timeout: 2))
        element("roomedit.operation.remove", in: app).tap()
        XCTAssertTrue(element("roomedit.blocker.remove", in: app).waitForExistence(timeout: 2))

        element("roomedit.operation.place", in: app).tap()
        XCTAssertTrue(element("roomedit.preview.proxy", in: app).waitForExistence(timeout: 2))
        XCTAssertEqual(element("roomedit.revision.current", in: app).label, "Current revision r0")
        XCTAssertEqual(element("roomedit.preview.base", in: app).label, "Preview base r0")
        XCTAssertTrue(element("roomedit.action.confirm", in: app).exists)
        element("roomedit.action.cancel", in: app).tap()
        XCTAssertFalse(element("roomedit.preview.proxy", in: app).exists)
        XCTAssertEqual(element("roomedit.revision.current", in: app).label, "Current revision r0")

        element("roomedit.operation.place", in: app).tap()
        XCTAssertTrue(element("roomedit.action.confirm", in: app).waitForExistence(timeout: 2))
        element("roomedit.action.confirm", in: app).tap()
        XCTAssertTrue(waitForLabel("Current revision r1", on: element("roomedit.revision.current", in: app)))
        XCTAssertTrue(element("roomedit.local.durable", in: app).exists)
        XCTAssertTrue(element("roomedit.asset.committed", in: app).exists)
        XCTAssertFalse(element("roomedit.action.confirm", in: app).exists)

        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(element("roomedit.root", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel("Current revision r1", on: element("roomedit.revision.current", in: app)))
        XCTAssertTrue(element("roomedit.asset.committed", in: app).exists)

        element("roomedit.operation.restore", in: app).tap()
        XCTAssertTrue(waitForLabel("Current revision r2", on: element("roomedit.revision.current", in: app)))
        XCTAssertTrue(element("roomedit.restore.committed", in: app).exists)
        XCTAssertFalse(element("roomedit.asset.committed", in: app).exists)
    }

    @MainActor
    private func launch(reset: Bool) -> XCUIApplication {
        launch(reset: reset, scenario: nil)
    }

    @MainActor
    private func launch(reset: Bool, scenario: String?) -> XCUIApplication {
        launch(reset: reset, scenario: scenario, failReplacementLoad: false)
    }

    @MainActor
    private func launch(
        reset: Bool,
        scenario: String?,
        failReplacementLoad: Bool
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--room-edit-ui-test"] + (reset ? ["--room-edit-reset"] : [])
        if failReplacementLoad {
            app.launchArguments.append("--room-edit-proxy-load-fail")
        }
        if let scenario {
            app.launchArguments.append("--room-edit-target-\(scenario)")
        }
        app.launchEnvironment["REROOM_IMPLEMENTATION_REVISION"] =
            "git:" + String(repeating: "1", count: 40)
        app.launchEnvironment["REROOM_FIXTURE_SHA256"] = String(repeating: "a", count: 64)
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func tapTargetSurface(in app: XCUIApplication) {
        let surface = element("roomedit.target.surface", in: app)
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        for _ in 0..<3 where surface.isHittable == false {
            app.swipeUp()
        }
        XCTAssertTrue(surface.isHittable)
        surface.tap()
    }
}
