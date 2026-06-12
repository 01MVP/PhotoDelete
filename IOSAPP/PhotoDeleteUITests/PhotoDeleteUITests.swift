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
        let app = makeApp(completedOnboarding: false)
        app.launch()

        XCTAssertTrue(app.staticTexts["快速整理相册"].waitForExistence(timeout: 10))
        app.buttons["继续"].tap()

        XCTAssertTrue(app.staticTexts["手势很简单"].waitForExistence(timeout: 3))
        app.buttons["继续"].tap()

        XCTAssertTrue(app.staticTexts["隐私优先"].waitForExistence(timeout: 3))
        app.buttons["跳过"].tap()

        XCTAssertTrue(
            app.staticTexts["删图"].waitForExistence(timeout: 10) ||
                app.staticTexts["需要访问照片库"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testHomeShowsActionableLibraryState() throws {
        let app = makeApp(completedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.staticTexts["删图"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["需要访问照片库"].exists ||
                app.staticTexts["开始整理照片"].exists ||
                app.staticTexts["没有可整理的照片"].exists ||
                app.staticTexts["正在读取照片"].exists
        )
    }

    @MainActor
    func testSettingsTabShowsCoreControls() throws {
        let app = makeApp(completedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        openSettingsTab(in: app)

        XCTAssertTrue(app.staticTexts["个人设置与偏好"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["偏好设置"].exists)
        XCTAssertTrue(app.staticTexts["数据与权限"].exists)
        XCTAssertTrue(app.staticTexts["关于与支持"].exists)
        XCTAssertTrue(app.staticTexts["照片访问权限"].exists)
        XCTAssertTrue(app.staticTexts["触感反馈"].exists)
        XCTAssertTrue(app.staticTexts["给删图评分"].exists)
        XCTAssertTrue(app.staticTexts["邮件反馈"].exists)
        XCTAssertTrue(app.staticTexts["关于创作者"].exists)
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
        XCTAssertTrue(app.staticTexts["Rate Photo Delete"].exists)
        XCTAssertTrue(app.staticTexts["Email Feedback"].exists)
        XCTAssertTrue(app.staticTexts["About the Creator"].exists)
        XCTAssertFalse(app.staticTexts["微信反馈"].exists)
    }

    private func makeApp(completedOnboarding: Bool, appLanguage: String = "zh-Hans") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            AppLaunchEnvironmentKey.isUITest: "1",
            AppLaunchEnvironmentKey.appLanguage: appLanguage,
            AppLaunchEnvironmentKey.hasCompletedOnboarding: completedOnboarding ? "1" : "0",
            AppLaunchEnvironmentKey.hasSeenIntro: completedOnboarding ? "1" : "0"
        ]
        return app
    }

    @MainActor
    private func openSettingsTab(in app: XCUIApplication) {
        if app.tabBars.buttons["设置"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["设置"].tap()
        } else {
            app.tabBars.buttons["Settings"].tap()
        }
    }
}

private enum AppLaunchEnvironmentKey {
    static let isUITest = "PHOTO_DELETE_UI_TEST"
    static let appLanguage = "PHOTO_DELETE_UI_TEST_APP_LANGUAGE"
    static let hasCompletedOnboarding = "PHOTO_DELETE_UI_TEST_HAS_COMPLETED_ONBOARDING"
    static let hasSeenIntro = "PHOTO_DELETE_UI_TEST_HAS_SEEN_INTRO"
}
