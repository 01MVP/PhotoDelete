//
//  PhotoDeleteUITests.swift
//  PhotoDeleteUITests
//
//  Created by jackie xiao on 11/7/25.
//

import XCTest

final class PhotoDeleteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingFlowCompletesToHome() throws {
        installPhotoLibraryInterruptionMonitor()

        let app = makeApp(completedOnboarding: false)
        app.launch()

        XCTAssertTrue(app.staticTexts["让照片整理变得简单"].waitForExistence(timeout: 10))
        app.buttons["继续"].tap()

        XCTAssertTrue(app.staticTexts["左滑删除，右滑保留"].waitForExistence(timeout: 3))
        app.buttons["继续"].tap()

        XCTAssertTrue(app.staticTexts["找回更多空间"].waitForExistence(timeout: 3))
        app.buttons["继续"].tap()

        XCTAssertTrue(app.staticTexts["照片不会上传"].waitForExistence(timeout: 3))
        app.buttons["开始整理照片"].tap()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)

        XCTAssertTrue(
            app.staticTexts["整理"].waitForExistence(timeout: 10) ||
                app.staticTexts["需要访问照片库"].waitForExistence(timeout: 2) ||
                app.staticTexts["随机浏览"].waitForExistence(timeout: 2) ||
                app.staticTexts["没有可整理的照片"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testHomeShowsActionableLibraryState() throws {
        let app = makeApp(completedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.staticTexts["整理"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["需要访问照片库"].exists ||
                app.staticTexts["随机浏览"].exists ||
                app.staticTexts["没有可整理的照片"].exists ||
                app.staticTexts["整理全部照片"].exists
        )
    }

    @MainActor
    func testSettingsTabShowsCoreControls() throws {
        let app = makeApp(completedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        openSettingsTab(in: app)

        XCTAssertTrue(app.staticTexts["使用统计"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["偏好设置"].exists)
        XCTAssertTrue(app.staticTexts["数据与权限"].exists)
        XCTAssertTrue(app.staticTexts["关于与支持"].exists)
        XCTAssertTrue(app.staticTexts["照片访问权限"].exists)
        XCTAssertTrue(app.staticTexts["触感反馈"].exists)
        XCTAssertTrue(app.staticTexts["给删图评分"].exists)
        XCTAssertTrue(app.staticTexts["邮件反馈"].exists)
        XCTAssertTrue(app.staticTexts["关于创作者"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["作者的更多 App"].waitForExistence(timeout: 2))
        let oneZenAppRow = app.descendants(matching: .any)["settings-onezen-app-row"]
        if !oneZenAppRow.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(oneZenAppRow.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["微信反馈"].exists)
        XCTAssertFalse(app.staticTexts["MVP 教程"].exists)
        XCTAssertFalse(app.staticTexts["创作理念"].exists)
    }

    @MainActor
    func testSettingsKeepsWeChatOutOfFeedbackSectionOutsideSimplifiedChinese() throws {
        let app = makeApp(completedOnboarding: true, appLanguage: "en")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        openSettingsTab(in: app)

        XCTAssertTrue(app.staticTexts["Preferences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rate OnePhoto"].exists)
        XCTAssertTrue(app.staticTexts["Email Feedback"].exists)
        XCTAssertTrue(app.staticTexts["About the Creator"].exists)
        XCTAssertFalse(app.staticTexts["微信反馈"].exists)
    }

    @MainActor
    func testMarketingCaptureLatestUI() throws {
        let environment = ProcessInfo.processInfo.environment
        let captureDirectoryValue = environment["PHOTO_DELETE_MARKETING_CAPTURE_DIR"] ??
            environment["TEST_RUNNER_PHOTO_DELETE_MARKETING_CAPTURE_DIR"]
        guard let captureDirectory = captureDirectoryValue,
              !captureDirectory.isEmpty else {
            throw XCTSkip("Set PHOTO_DELETE_MARKETING_CAPTURE_DIR to export marketing UI captures.")
        }
        let appLanguage = environment["PHOTO_DELETE_MARKETING_APP_LANGUAGE"] ??
            environment["TEST_RUNNER_PHOTO_DELETE_MARKETING_APP_LANGUAGE"] ??
            "zh-Hans"

        installPhotoLibraryInterruptionMonitor()

        let outputDirectory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let app = makeApp(completedOnboarding: true, appLanguage: appLanguage, seedLibrary: true)
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        if !waitForHomeReady(in: app, language: appLanguage, timeout: 30) {
            app.terminate()
            app.launch()
            _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        }

        XCTAssertTrue(waitForHomeReady(in: app, language: appLanguage, timeout: 30))
        try capture("01-home", in: outputDirectory, app: app)

        openAlbumsTab(in: app)
        let expectedAlbumTitle = appLanguage.hasPrefix("en") ? "Travel Photos" : "旅行照片"
        XCTAssertTrue(app.staticTexts[expectedAlbumTitle].waitForExistence(timeout: 60))
        try capture("02-albums-real", in: outputDirectory, app: app)

        openOrganizeTab(in: app)
        XCTAssertTrue(waitForHomeReady(in: app, language: appLanguage, timeout: 15))

        let startCleanupButton = firstExistingButton(
            in: app,
            labels: ["开始整理", "Start Cleanup", "整理全部照片", "Organize All Photos"]
        )
        XCTAssertTrue(startCleanupButton.waitForExistence(timeout: 10))
        startCleanupButton.tap()

        let doneButton = firstExistingButton(in: app, labels: ["完成", "Done"])
        XCTAssertTrue(doneButton.waitForExistence(timeout: 30))
        sleep(2)
        try capture("03-review-card", in: outputDirectory, app: app)

        dragCardLeft(in: app)
        sleep(1)
        try capture("04-left-swipe-delete", in: outputDirectory, app: app)

        dragCardRight(in: app)
        sleep(1)
        try capture("05-right-swipe-keep", in: outputDirectory, app: app)

        let reviewModeButton = firstExistingButton(in: app, labels: ["整理模式", "Review Mode"])
        XCTAssertTrue(reviewModeButton.waitForExistence(timeout: 5))
        reviewModeButton.tap()
        XCTAssertTrue(app.staticTexts["左右浏览"].waitForExistence(timeout: 5) ||
            app.staticTexts["Browse left or right"].waitForExistence(timeout: 5))
        sleep(2)
        try capture("06-two-row-browser", in: outputDirectory, app: app)

        ensurePendingDeleteCandidateForMarketing(in: app)

        let finishButton = firstExistingButton(in: app, labels: ["完成", "Done"])
        if finishButton.waitForExistence(timeout: 3) {
            finishButton.tap()
            _ = app.staticTexts["确认删除"].waitForExistence(timeout: 5) ||
                app.staticTexts["Confirm Deletion"].waitForExistence(timeout: 5)
            sleep(1)
            try capture("07-finish-or-confirm", in: outputDirectory, app: app)
        }
    }

    private func makeApp(
        completedOnboarding: Bool,
        appLanguage: String = "zh-Hans",
        seedLibrary: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            AppLaunchEnvironmentKey.isUITest: "1",
            AppLaunchEnvironmentKey.appLanguage: appLanguage,
            AppLaunchEnvironmentKey.appAppearance: "light",
            AppLaunchEnvironmentKey.seedLibrary: seedLibrary ? "1" : "0",
            AppLaunchEnvironmentKey.hasCompletedOnboarding: completedOnboarding ? "1" : "0",
            AppLaunchEnvironmentKey.hasSeenIntro: completedOnboarding ? "1" : "0"
        ]
        return app
    }

    @MainActor
    private func openSettingsTab(in app: XCUIApplication) {
        tapTabItem(in: app, labels: ["设置", "Settings"], fallbackOffset: CGVector(dx: 0.88, dy: 0.96))
    }

    @MainActor
    private func openOrganizeTab(in app: XCUIApplication) {
        tapTabItem(in: app, labels: ["整理", "Organize"], fallbackOffset: CGVector(dx: 0.13, dy: 0.96))
    }

    @MainActor
    private func openAlbumsTab(in app: XCUIApplication) {
        tapTabItem(in: app, labels: ["相册", "Albums"], fallbackOffset: CGVector(dx: 0.38, dy: 0.96))
    }

    @MainActor
    private func tapTabItem(in app: XCUIApplication, labels: [String], fallbackOffset: CGVector) {
        for label in labels {
            let tabBarButton = app.tabBars.buttons.matching(identifier: label).firstMatch
            if tabBarButton.waitForExistence(timeout: 1), tabBarButton.isHittable {
                tapHittableElement(tabBarButton)
                return
            }
        }

        for label in labels {
            let button = app.buttons.matching(identifier: label).firstMatch
            if button.waitForExistence(timeout: 1), button.isHittable {
                tapHittableElement(button)
                return
            }
        }

        for label in labels {
            let element = app.descendants(matching: .any).matching(identifier: label).firstMatch
            if element.waitForExistence(timeout: 1), element.isHittable {
                tapHittableElement(element)
                return
            }
        }

        app.coordinate(withNormalizedOffset: fallbackOffset).tap()
    }

    @MainActor
    private func tapHittableElement(_ element: XCUIElement) {
        element.tap()
    }

    @MainActor
    private func drag(in app: XCUIApplication, from start: CGVector, to end: CGVector) {
        let startCoordinate = app.coordinate(withNormalizedOffset: start)
        let endCoordinate = app.coordinate(withNormalizedOffset: end)
        startCoordinate.press(forDuration: 0.15, thenDragTo: endCoordinate)
    }

    @MainActor
    private func dragCardLeft(in app: XCUIApplication) {
        if usesWideMarketingLayout(app) {
            drag(in: app, from: CGVector(dx: 0.52, dy: 0.58), to: CGVector(dx: 0.16, dy: 0.58))
        } else {
            drag(in: app, from: CGVector(dx: 0.76, dy: 0.48), to: CGVector(dx: 0.18, dy: 0.48))
        }
    }

    @MainActor
    private func dragCardRight(in app: XCUIApplication) {
        if usesWideMarketingLayout(app) {
            drag(in: app, from: CGVector(dx: 0.22, dy: 0.58), to: CGVector(dx: 0.58, dy: 0.58))
        } else {
            drag(in: app, from: CGVector(dx: 0.24, dy: 0.48), to: CGVector(dx: 0.82, dy: 0.48))
        }
    }

    private func usesWideMarketingLayout(_ app: XCUIApplication) -> Bool {
        app.frame.width >= 800
    }

    @MainActor
    private func ensurePendingDeleteCandidateForMarketing(in app: XCUIApplication) {
        guard usesWideMarketingLayout(app) else { return }

        let deleteButton = firstExistingButton(in: app, labels: ["待删除", "To delete", "删除", "Delete"])
        if deleteButton.waitForExistence(timeout: 2), deleteButton.isHittable {
            deleteButton.tap()
            sleep(1)
        }
    }

    @MainActor
    private func skipLeadingNonMarketingMedia(in app: XCUIApplication) {
        let skipButton = firstExistingButton(in: app, labels: ["跳过", "Skip"])
        guard skipButton.waitForExistence(timeout: 5) else { return }

        for _ in 0..<15 where skipButton.exists && skipButton.isHittable {
            skipButton.tap()
            usleep(140_000)
        }

        sleep(1)
    }

    @MainActor
    private func capture(_ name: String, in directory: URL, app: XCUIApplication) throws {
        dismissMarketingSystemPrompts(app: app)
        let screenshot = XCUIScreen.main.screenshot()
        let outputURL = directory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: outputURL, options: .atomic)
        add(XCTAttachment(screenshot: screenshot))
    }

    private func firstExistingButton(in app: XCUIApplication, labels: [String]) -> XCUIElement {
        for label in labels {
            let button = app.buttons[label]
            if button.exists { return button }
        }
        return app.buttons[labels[0]]
    }

    @MainActor
    private func allowFullPhotoLibraryAccessIfNeeded(app: XCUIApplication) -> Bool {
        let didInteract = tapFirstExistingButton(in: app, labels: ["继续", "Continue"], timeout: 3)
        if didInteract {
            sleep(1)
        }

        let labels = ["允许完全访问", "允许访问所有照片", "Allow Full Access", "Allow Full Access to Photos"]
        if tapFirstExistingButton(in: app, labels: labels, timeout: 2) {
            sleep(1)
            return true
        }

        let writeLabels = ["允许删除", "Allow Delete Access", "Allow Deletion"]
        if tapFirstExistingButton(in: app, labels: writeLabels, timeout: 2) {
            sleep(1)
            return true
        }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if tapFirstExistingButton(in: springboard, labels: labels, timeout: 2) {
            sleep(1)
            return true
        }
        if tapFirstExistingButton(in: springboard, labels: writeLabels + ["删除", "Delete"], timeout: 2) {
            sleep(1)
            return true
        }

        return didInteract
    }

    @MainActor
    private func dismissMarketingSystemPrompts(app: XCUIApplication) {
        let labels = [
            "允许完全访问",
            "允许访问所有照片",
            "允许",
            "允许删除",
            "删除",
            "Allow Full Access",
            "Allow Full Access to Photos",
            "Allow",
            "Delete"
        ]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        for _ in 0..<5 {
            var didTap = tapFirstExistingButton(in: app, labels: labels, timeout: 1)
            didTap = tapFirstExistingButton(in: springboard, labels: labels, timeout: 1) || didTap
            if !didTap { return }
            sleep(1)
        }
    }

    private func installPhotoLibraryInterruptionMonitor() {
        addUIInterruptionMonitor(withDescription: "Photo library access") { alert in
            let labels = [
                "允许完全访问",
                "允许访问所有照片",
                "允许",
                "允许删除",
                "删除",
                "Allow Full Access",
                "Allow Full Access to Photos",
                "Allow",
                "Delete"
            ]
            for label in labels {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }

            let denyLabels = ["不允许", "Don’t Allow", "Don't Allow", "取消", "Cancel"]
            for button in alert.buttons.allElementsBoundByIndex {
                let label = button.label
                guard button.exists, !label.isEmpty, !denyLabels.contains(label) else { continue }
                button.tap()
                return true
            }

            return false
        }
    }

    @MainActor
    private func tapFirstExistingButton(in app: XCUIApplication, labels: [String], timeout: TimeInterval) -> Bool {
        for label in labels {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: timeout) {
                button.tap()
                return true
            }
        }
        return false
    }

    @MainActor
    private func waitForHomeReady(in app: XCUIApplication, language: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let labels = language.hasPrefix("en")
            ? ["Organize All Photos", "Start Cleanup", "Quick Entries", "All Photos"]
            : ["整理全部照片", "开始整理", "快速入口", "全部照片"]

        while Date() < deadline {
            for label in labels where app.staticTexts[label].exists || app.buttons[label].exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return false
    }
}

private enum AppLaunchEnvironmentKey {
    static let isUITest = "PHOTO_DELETE_UI_TEST"
    static let appLanguage = "PHOTO_DELETE_UI_TEST_APP_LANGUAGE"
    static let appAppearance = "PHOTO_DELETE_UI_TEST_APP_APPEARANCE"
    static let seedLibrary = "PHOTO_DELETE_UI_TEST_SEED_LIBRARY"
    static let hasCompletedOnboarding = "PHOTO_DELETE_UI_TEST_HAS_COMPLETED_ONBOARDING"
    static let hasSeenIntro = "PHOTO_DELETE_UI_TEST_HAS_SEEN_INTRO"
}
