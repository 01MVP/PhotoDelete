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
        XCTAssertFalse(app.staticTexts["整理"].exists)
        app.buttons["选择照片访问权限"].tap()
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
    func testProPaywallOffersAnnualAndLifetimePlans() throws {
        let app = makeApp(completedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.staticTexts["整理"].waitForExistence(timeout: 10))
        openSettingsTab(in: app)

        guard let proEntry = waitForHittableButtonLabelContaining(
            in: app,
            substring: "解锁进阶功能",
            timeout: 10
        ) else {
            XCTFail("Expected the OnePhoto Pro settings entry")
            return
        }
        proEntry.tap()

        XCTAssertTrue(app.staticTexts["OnePhoto Pro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "年度 Pro")).firstMatch.waitForExistence(timeout: 10))
        let lifetimePlan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "永久 Pro")).firstMatch
        XCTAssertTrue(lifetimePlan.waitForExistence(timeout: 10))
        sleep(2)
        let paywallScreenshot = XCTAttachment(screenshot: app.screenshot())
        paywallScreenshot.name = "OnePhoto Pro Paywall"
        paywallScreenshot.lifetime = .keepAlways
        add(paywallScreenshot)
        lifetimePlan.tap()
        XCTAssertNotNil(waitForAnyElementLabelContaining(in: app, substring: "解锁永久 Pro", timeout: 5))
        XCTAssertTrue(app.buttons["恢复购买"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["supporter-privacy-policy-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["supporter-terms-of-use-link"].exists)
    }

    @MainActor
    func testSeededAlbumsTabAndReviewAlbumFilingShortcut() throws {
        installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: true)

        let app = makeApp(completedOnboarding: true, seedLibrary: true)
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        dismissMarketingSystemPrompts(app: app, allowDeletionConfirmation: true)

        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        if !waitForHomeReady(in: app, language: "zh-Hans", timeout: 30) {
            app.terminate()
            app.launch()
            _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
            dismissMarketingSystemPrompts(app: app, allowDeletionConfirmation: true)
        }
        XCTAssertTrue(waitForHomeReady(in: app, language: "zh-Hans", timeout: 30))

        openAlbumsTab(in: app)
        XCTAssertTrue(app.staticTexts["旅行照片"].waitForExistence(timeout: 60))

        openOrganizeTab(in: app)
        guard let startCleanupButton = waitForFirstExistingButton(
            in: app,
            labels: ["开始整理", "整理全部照片"],
            timeout: 30
        ) else {
            XCTFail("Expected a review entry button after seeded library load")
            return
        }
        startCleanupButton.tap()

        let doneButton = firstExistingButton(in: app, labels: ["完成"])
        XCTAssertTrue(doneButton.waitForExistence(timeout: 30))

        let dismissHintButton = app.buttons["知道了"]
        if dismissHintButton.exists, dismissHintButton.isHittable {
            dismissHintButton.tap()
        }

        guard let albumShortcutButton = waitForHittableButton(
            in: app,
            label: "归类到 宠物照片",
            timeout: 15
        ) else {
            XCTFail("Expected a hittable 宠物照片 album shortcut")
            return
        }
        albumShortcutButton.tap()

        XCTAssertNotNil(waitForAnyElementLabelContaining(in: app, substring: "已归类到 宠物照片", timeout: 10))

        openAlbumsTab(in: app)
        XCTAssertNotNil(waitForStaticTextLabel(in: app, label: "宠物照片", timeout: 10))
        guard let petAlbumButton = waitForHittableButton(in: app, label: "宠物照片、3 张照片", timeout: 10) else {
            XCTFail("Expected 宠物照片 album to include the filed photo")
            return
        }
        petAlbumButton.tap()

        let reviewCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "review-photo-card"))
            .firstMatch
        XCTAssertTrue(reviewCard.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["整理完成！"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testReviewAlbumShortcutsLoadWithoutOpeningAlbumsTab() throws {
        installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: true)

        let app = makeApp(completedOnboarding: true, seedLibrary: true)
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)

        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        if !waitForHomeReady(in: app, language: "zh-Hans", timeout: 30) {
            app.terminate()
            app.launch()
            _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        }
        XCTAssertTrue(waitForHomeReady(in: app, language: "zh-Hans", timeout: 30))

        openOrganizeTab(in: app)
        guard let startCleanupButton = waitForFirstExistingButton(
            in: app,
            labels: ["开始整理", "Start Cleanup", "整理全部照片", "Organize All Photos"],
            timeout: 30
        ) else {
            XCTFail("Expected a review entry button after seeded library load")
            return
        }
        startCleanupButton.tap()

        let doneButton = firstExistingButton(in: app, labels: ["完成"])
        XCTAssertTrue(doneButton.waitForExistence(timeout: 30))

        let dismissHintButton = app.buttons["知道了"]
        if dismissHintButton.exists, dismissHintButton.isHittable {
            dismissHintButton.tap()
        }

        guard let albumShortcutButton = waitForHittableButton(
            in: app,
            label: "归类到 旅行照片",
            timeout: 15
        ) else {
            XCTFail("Expected the album shortcut strip to appear")
            return
        }

        let visibilityButton = app.buttons["album-shortcut-visibility-button"].firstMatch
        let manageButton = app.buttons["album-shortcut-manage-button"].firstMatch
        XCTAssertTrue(visibilityButton.waitForExistence(timeout: 5))
        XCTAssertTrue(manageButton.waitForExistence(timeout: 5))
        XCTAssertEqual(manageButton.frame.midX, visibilityButton.frame.midX, accuracy: 2)
        XCTAssertLessThan(manageButton.frame.midY, visibilityButton.frame.midY)
        XCTAssertEqual(visibilityButton.label, "隐藏相册归类")
        visibilityButton.tap()

        XCTAssertTrue(albumShortcutButton.waitForNonExistence(timeout: 5))
        XCTAssertTrue(visibilityButton.waitForExistence(timeout: 5))
        XCTAssertEqual(visibilityButton.label, "显示相册归类")
        visibilityButton.tap()

        XCTAssertNotNil(waitForHittableButton(in: app, label: "归类到 旅行照片", timeout: 8))
        XCTAssertEqual(visibilityButton.label, "隐藏相册归类")
    }

    @MainActor
    func testFavoriteButtonTogglesFavoriteStatus() throws {
        installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: true)

        let app = makeApp(completedOnboarding: true, seedLibrary: true)
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)

        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(waitForHomeReady(in: app, language: "zh-Hans", timeout: 30))

        openOrganizeTab(in: app)
        guard let startCleanupButton = waitForFirstExistingButton(
            in: app,
            labels: ["开始整理", "整理全部照片"],
            timeout: 30
        ) else {
            XCTFail("Expected a review entry button after seeded library load")
            return
        }
        startCleanupButton.tap()

        if let existingUnfavoriteButton = waitForHittableButton(in: app, label: "取消收藏", timeout: 3) {
            existingUnfavoriteButton.tap()
            XCTAssertTrue(
                app.staticTexts["已取消收藏"].waitForExistence(timeout: 10),
                "Expected test setup favorite mutation to finish"
            )
            XCTAssertNotNil(
                waitForHittableButton(in: app, label: "收藏", timeout: 10),
                "Expected test setup to normalize the current photo to unfavorited"
            )
        }

        guard let favoriteButton = waitForHittableButton(in: app, label: "收藏", timeout: 30) else {
            XCTFail("Expected a favorite button in review")
            return
        }
        favoriteButton.tap()

        guard waitForHittableButton(in: app, label: "取消收藏", timeout: 10) != nil else {
            XCTFail("Expected the favorite button to become an unfavorite button")
            return
        }
        dragCardDown(in: app)

        guard let favoriteButtonAfterSwipe = waitForHittableButton(in: app, label: "收藏", timeout: 10) else {
            XCTFail("Expected swiping down to remove the favorite")
            return
        }
        favoriteButtonAfterSwipe.tap()

        guard let unfavoriteButtonAfterSwipe = waitForHittableButton(in: app, label: "取消收藏", timeout: 10) else {
            XCTFail("Expected the photo to be favorited again")
            return
        }
        unfavoriteButtonAfterSwipe.tap()

        XCTAssertNotNil(waitForHittableButton(in: app, label: "收藏", timeout: 10))

        guard let doneButton = waitForHittableButton(in: app, label: "完成", timeout: 10) else {
            XCTFail("Expected the review done button")
            return
        }
        doneButton.tap()
        XCTAssertTrue(waitForHomeReady(in: app, language: "zh-Hans", timeout: 15))

        openSettingsTab(in: app)
        guard let historyButton = waitForHittableButtonLabelContaining(
            in: app,
            substring: "成就与历史",
            timeout: 10
        ) else {
            XCTFail("Expected the achievements and history entry")
            return
        }
        historyButton.tap()
        XCTAssertTrue(app.staticTexts["最近整理"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["再次整理"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSimilarPhotoPreviewCanMarkCurrentAssetForDeletion() throws {
        installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: true)

        let app = makeApp(completedOnboarding: true, seedLibrary: true, supporterTrialActive: true)
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)

        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        if !waitForHomeReady(in: app, language: "zh-Hans", timeout: 30) {
            app.terminate()
            app.launch()
            _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        }
        XCTAssertTrue(waitForHomeReady(in: app, language: "zh-Hans", timeout: 30))

        openAlbumsTab(in: app)
        XCTAssertTrue(app.staticTexts["旅行照片"].waitForExistence(timeout: 60))

        openAdvancedTab(in: app)
        guard let similarPhotosButton = waitForButtonLabelPrefix(
            in: app,
            prefix: "相似照片",
            timeout: 60,
            excluding: "0 项"
        ) else {
            XCTFail("Expected a non-empty unlocked similar photos cleanup entry")
            return
        }
        similarPhotosButton.tap()

        XCTAssertTrue(app.staticTexts["相似照片"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["严格"].exists)
        XCTAssertFalse(app.buttons["标准"].exists)
        XCTAssertFalse(app.buttons["宽泛"].exists)
        XCTAssertFalse(app.progressIndicators["similar-photo-analysis-progress"].exists)
        XCTAssertTrue(app.buttons["保留首张"].waitForExistence(timeout: 30))

        guard let previewButton = waitForHittableButton(in: app, label: "预览", timeout: 30) else {
            XCTFail("Expected a similar-photo group preview button")
            return
        }
        previewButton.tap()

        let selectionToggleByID = app.descendants(matching: .any)["advanced-preview-delete-selection-toggle"]
        let selectionToggleByLabel = app.descendants(matching: .any)["加入待删除"]
        XCTAssertTrue(
            selectionToggleByID.waitForExistence(timeout: 10) ||
                selectionToggleByLabel.waitForExistence(timeout: 2)
        )
        XCTAssertNotNil(waitForAnyElementLabelContaining(in: app, substring: "1 /", timeout: 5))

        let selectionToggle = selectionToggleByID.exists ? selectionToggleByID : selectionToggleByLabel
        selectionToggle.tap()
        XCTAssertTrue(
            app.staticTexts["已加入待删除"].waitForExistence(timeout: 5) ||
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label BEGINSWITH %@", "已加入待删除"))
                    .firstMatch.exists
        )
    }

    private func waitForAnyElementToExist(
        _ elements: [XCUIElement],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if elements.contains(where: \.exists) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return elements.contains(where: \.exists)
    }

    @MainActor
    func testInlineVideoScrubberDoesNotBlockPlaybackControlsOrCardSwipe() throws {
        installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: true)

        let app = makeApp(completedOnboarding: true, seedLibrary: true)
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)

        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        if !waitForHomeReady(in: app, language: "zh-Hans", timeout: 30) {
            app.terminate()
            app.launch()
            _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        }
        XCTAssertTrue(waitForHomeReady(in: app, language: "zh-Hans", timeout: 30))

        openOrganizeTab(in: app)
        guard let videosButton = waitForButtonLabelPrefix(
            in: app,
            prefix: "视频",
            timeout: 30
        ) else {
            XCTFail("Expected a videos entry after seeded library load")
            return
        }
        videosButton.tap()

        let doneButton = firstExistingButton(in: app, labels: ["完成"])
        XCTAssertTrue(doneButton.waitForExistence(timeout: 30))

        let dismissHintButton = app.buttons["知道了"]
        if dismissHintButton.exists, dismissHintButton.isHittable {
            dismissHintButton.tap()
        }

        guard let videoPlayer = waitForInlineVideoPlayer(in: app, timeout: 20) else {
            XCTFail("Expected seeded video to appear in review")
            return
        }

        app.coordinate(withNormalizedOffset: normalizedOffset(for: videoPlayer, dx: 0.5, dy: 0.5, in: app)).tap()
        let playbackButton = app.buttons["video-playback-toggle-button"]
        XCTAssertTrue(playbackButton.waitForExistence(timeout: 5))
        let playButton = app.buttons["播放视频"]
        if playButton.exists, playButton.isHittable {
            playButton.tap()
        }

        let progressSlider = app.sliders["video-playback-slider"]
        XCTAssertTrue(progressSlider.waitForExistence(timeout: 5))
        let scrubStart = progressSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        let scrubEnd = progressSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.5))
        scrubStart.press(forDuration: 0.15, thenDragTo: scrubEnd)
        XCTAssertTrue(
            waitForElementToDisappear(playbackButton, timeout: 5),
            "Playback controls should auto-hide after scrubbing when the video resumes playback."
        )

        let leftStart = videoPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.48))
        let leftEnd = videoPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.48))
        leftStart.press(forDuration: 0.15, thenDragTo: leftEnd)

        XCTAssertTrue(
            app.staticTexts["已加入待删除"].waitForExistence(timeout: 5) ||
                app.staticTexts["待删除 1 张"].waitForExistence(timeout: 2),
            "Horizontal swipe from the video body should still reach the review card."
        )
    }

    @MainActor
    func testInlineVideoCanOpenFullPreviewWithPlaybackControls() throws {
        installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: true)

        let app = makeApp(completedOnboarding: true, seedLibrary: true)
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)

        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(waitForHomeReady(in: app, language: "zh-Hans", timeout: 30))

        openOrganizeTab(in: app)
        guard let videosButton = waitForButtonLabelPrefix(in: app, prefix: "视频", timeout: 30) else {
            XCTFail("Expected a videos entry after seeded library load")
            return
        }
        videosButton.tap()

        let doneButton = firstExistingButton(in: app, labels: ["完成"])
        XCTAssertTrue(doneButton.waitForExistence(timeout: 30))

        let dismissHintButton = app.buttons["知道了"]
        if dismissHintButton.exists, dismissHintButton.isHittable {
            dismissHintButton.tap()
        }

        guard waitForInlineVideoPlayer(in: app, timeout: 20) != nil else {
            XCTFail("Expected seeded video to appear in review")
            return
        }

        let expandButton = app.buttons["video-full-preview-button"]
        XCTAssertTrue(expandButton.waitForExistence(timeout: 8))
        expandButton.tap()

        XCTAssertTrue(app.navigationBars["视频预览"].waitForExistence(timeout: 8))
        let previewPlayer = app.buttons.matching(identifier: "photo-asset-video-player").firstMatch
        XCTAssertTrue(previewPlayer.waitForExistence(timeout: 12))
        previewPlayer.tap()

        let playbackButton = app.buttons.matching(identifier: "video-playback-toggle-button").firstMatch
        XCTAssertTrue(playbackButton.waitForExistence(timeout: 5))
        let progressSlider = app.sliders.matching(identifier: "video-playback-slider").firstMatch
        XCTAssertTrue(progressSlider.waitForExistence(timeout: 5))

        playbackButton.tap()
        let playButton = app.buttons.matching(NSPredicate(format: "label == %@", "播放视频")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()

        let scrubStart = progressSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let scrubEnd = progressSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.5))
        scrubStart.press(forDuration: 0.15, thenDragTo: scrubEnd)

        let closeButton = app.buttons["关闭"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 8))

        let reviewModeButton = firstExistingButton(in: app, labels: ["整理模式"])
        XCTAssertTrue(reviewModeButton.waitForExistence(timeout: 5))
        reviewModeButton.tap()
        XCTAssertTrue(app.staticTexts["左右浏览"].waitForExistence(timeout: 5))

        let currentVideoCell = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@ AND value CONTAINS %@ AND value CONTAINS %@",
                "浏览照片",
                "当前照片",
                "视频"
            )
        ).firstMatch
        XCTAssertTrue(currentVideoCell.waitForExistence(timeout: 8))
        currentVideoCell.tap()

        let browserExpandButton = app.buttons["browser-video-full-preview-button"]
        XCTAssertTrue(browserExpandButton.waitForExistence(timeout: 8))
        browserExpandButton.tap()
        XCTAssertTrue(app.navigationBars["视频预览"].waitForExistence(timeout: 8))
        app.buttons["关闭"].tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.staticTexts["更多 App"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["One Apps Studio"].waitForExistence(timeout: 2))
        let catalogEntry = app.descendants(matching: .any)["settings-oneapps-catalog-entry"]
        if !catalogEntry.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(catalogEntry.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["微信反馈"].exists)
        XCTAssertFalse(app.staticTexts["MVP 教程"].exists)
        XCTAssertFalse(app.staticTexts["创作理念"].exists)
    }

    @MainActor
    func testGestureSettingsShowsHapticFeedbackToggle() throws {
        let app = makeApp(completedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        openSettingsTab(in: app)

        var gestureSettingsButton = waitForHittableButtonLabelContaining(in: app, substring: "手势与播放", timeout: 2)
        for _ in 0..<3 where gestureSettingsButton == nil {
            app.swipeUp()
            gestureSettingsButton = waitForHittableButtonLabelContaining(in: app, substring: "手势与播放", timeout: 2)
        }
        guard let gestureSettingsButton else {
            XCTFail("Expected gesture settings row")
            return
        }
        gestureSettingsButton.tap()

        XCTAssertTrue(app.navigationBars["手势与播放"].waitForExistence(timeout: 3))
        var hapticFeedbackTitle = waitForStaticTextLabel(in: app, label: "触感反馈", timeout: 2)
        for _ in 0..<3 where hapticFeedbackTitle == nil {
            app.swipeUp()
            hapticFeedbackTitle = waitForStaticTextLabel(in: app, label: "触感反馈", timeout: 2)
        }
        XCTAssertNotNil(hapticFeedbackTitle)
        XCTAssertTrue(app.staticTexts["滑动、撤销和归类时提供轻微反馈"].exists)
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
    func testAdvancedTabUpdatesAfterLanguageChangeInSettings() throws {
        let app = makeApp(completedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        openSettingsTab(in: app)

        var languageButton = waitForHittableButtonLabelContaining(in: app, substring: "语言", timeout: 2) ??
            waitForHittableButtonLabelContaining(in: app, substring: "Language", timeout: 2)
        for _ in 0..<3 where languageButton == nil {
            app.swipeUp()
            languageButton = waitForHittableButtonLabelContaining(in: app, substring: "语言", timeout: 2) ??
                waitForHittableButtonLabelContaining(in: app, substring: "Language", timeout: 2)
        }
        guard let languageButton else {
            XCTFail("Expected language settings row")
            return
        }
        languageButton.tap()

        guard let englishButton = waitForHittableButton(in: app, label: "English", timeout: 5) else {
            XCTFail("Expected English language option")
            return
        }
        englishButton.tap()

        guard let doneButton = waitForFirstExistingButton(in: app, labels: ["Done", "完成"], timeout: 5) else {
            XCTFail("Expected language settings done button")
            return
        }
        doneButton.tap()

        openAdvancedTab(in: app)

        XCTAssertTrue(app.staticTexts["Focused Cleanup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["高效清理"].exists)
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
        let shouldSeedLibrary = (environment["PHOTO_DELETE_MARKETING_SEED_LIBRARY"] ??
            environment["TEST_RUNNER_PHOTO_DELETE_MARKETING_SEED_LIBRARY"] ??
            "1") != "0"

        installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: true)

        let outputDirectory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let app = makeApp(
            completedOnboarding: true,
            appLanguage: appLanguage,
            seedLibrary: shouldSeedLibrary,
            supporterTrialActive: true
        )
        app.launch()
        _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        if !waitForHomeReady(in: app, language: appLanguage, timeout: 30) {
            app.terminate()
            app.launch()
            _ = allowFullPhotoLibraryAccessIfNeeded(app: app)
        }

        XCTAssertTrue(waitForHomeReady(in: app, language: appLanguage, timeout: 30))
        sleep(2)
        dismissMarketingSystemPrompts(app: app, allowDeletionConfirmation: true)
        XCTAssertTrue(waitForHomeReady(in: app, language: appLanguage, timeout: 15))
        try capture("01-home", in: outputDirectory, app: app)

        openAlbumsTab(in: app)
        let expectedAlbumTitle = appLanguage.hasPrefix("en") ? "Travel Photos" : "旅行照片"
        let hasLocalizedSeedAlbum = app.staticTexts[expectedAlbumTitle].waitForExistence(
            timeout: shouldSeedLibrary ? 60 : 5
        )
        if hasLocalizedSeedAlbum {
            try capture("05-albums-real", in: outputDirectory, app: app)
        } else {
            XCTAssertTrue(
                appLanguage.hasPrefix("en") && !shouldSeedLibrary &&
                    app.staticTexts["4 albums"].exists,
                "Expected localized seeded albums or a reusable existing English album capture"
            )
        }

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
        try capture("02-review-card", in: outputDirectory, app: app)

        dragCardLeft(in: app)
        sleep(1)

        let reviewModeButton = firstExistingButton(in: app, labels: ["整理模式", "Review Mode"])
        XCTAssertTrue(reviewModeButton.waitForExistence(timeout: 5))
        reviewModeButton.tap()
        XCTAssertTrue(app.staticTexts["左右浏览"].waitForExistence(timeout: 5) ||
            app.staticTexts["Browse left or right"].waitForExistence(timeout: 5))
        sleep(2)
        try capture("03-two-row-browser", in: outputDirectory, app: app)

        ensurePendingDeleteCandidateForMarketing(in: app)

        let finishButton = firstExistingButton(in: app, labels: ["完成", "Done"])
        if finishButton.waitForExistence(timeout: 3) {
            finishButton.tap()
            _ = app.staticTexts["确认删除"].waitForExistence(timeout: 5) ||
                app.staticTexts["Confirm Deletion"].waitForExistence(timeout: 5)
            sleep(1)
            try capture("04-finish-or-confirm", in: outputDirectory, app: app)
        }

        let cancelAllActionsButton = firstExistingButton(
            in: app,
            labels: ["取消所有操作", "Cancel All Actions"]
        )
        if cancelAllActionsButton.waitForExistence(timeout: 5) {
            cancelAllActionsButton.tap()
            XCTAssertTrue(waitForElementToDisappear(cancelAllActionsButton, timeout: 5))
        }
        navigateBack(in: app)

        openAdvancedTab(in: app)
        let focusedCleanupTitle = appLanguage.hasPrefix("en") ? "Focused Cleanup" : "高效清理"
        XCTAssertTrue(app.staticTexts[focusedCleanupTitle].waitForExistence(timeout: 60))
        sleep(3)
        try capture("06-advanced-dashboard", in: outputDirectory, app: app)

        let similarPhotosPrefix = appLanguage.hasPrefix("en") ? "Similar Photos" : "相似照片"
        guard let similarPhotosButton = waitForButtonLabelPrefix(
            in: app,
            prefix: similarPhotosPrefix,
            timeout: 60,
            excluding: appLanguage.hasPrefix("en") ? "0 items" : "0 项"
        ) else {
            XCTFail("Expected a non-empty similar photos cleanup entry for marketing capture")
            return
        }
        similarPhotosButton.tap()
        XCTAssertTrue(app.staticTexts[similarPhotosPrefix].waitForExistence(timeout: 10))
        sleep(2)
        try capture("07-similar-photos", in: outputDirectory, app: app)

        navigateBack(in: app)
        XCTAssertTrue(app.staticTexts[focusedCleanupTitle].waitForExistence(timeout: 10))

        let largeFilesPrefix = appLanguage.hasPrefix("en") ? "Large Files" : "大文件"
        guard let largeFilesButton = waitForButtonLabelPrefix(
            in: app,
            prefix: largeFilesPrefix,
            timeout: 30,
            excluding: appLanguage.hasPrefix("en") ? "0 items" : "0 项"
        ) else {
            XCTFail("Expected a non-empty large files cleanup entry for marketing capture")
            return
        }
        largeFilesButton.tap()
        XCTAssertTrue(app.staticTexts[largeFilesPrefix].waitForExistence(timeout: 10))
        sleep(2)
        try capture("08-large-files", in: outputDirectory, app: app)
    }

    @MainActor
    func testMarketingCaptureSettingsAndPrivacy() throws {
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

        let outputDirectory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let app = makeApp(
            completedOnboarding: true,
            appLanguage: appLanguage,
            seedLibrary: false,
            supporterTrialActive: true
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        openSettingsTab(in: app)
        let achievementsTitle = appLanguage.hasPrefix("en") ? "Achievements & History" : "成就与历史"
        let settingsUsageTitle = appLanguage.hasPrefix("en") ? "Usage stats" : "使用统计"
        XCTAssertTrue(app.staticTexts[settingsUsageTitle].waitForExistence(timeout: 10))
        guard let achievementsButton = waitForHittableButtonLabelContaining(
            in: app,
            substring: achievementsTitle,
            timeout: 10
        ) else {
            XCTFail("Expected achievements entry for marketing capture")
            return
        }
        achievementsButton.tap()
        XCTAssertTrue(app.staticTexts[achievementsTitle].waitForExistence(timeout: 10))
        sleep(2)
        try capture("09-achievements", in: outputDirectory, app: app)

        let doneButton = firstExistingButton(in: app, labels: ["完成", "Done"])
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        let privacyTitle = appLanguage.hasPrefix("en") ? "Privacy Notes" : "隐私说明"
        var privacyButton = waitForHittableButton(in: app, label: privacyTitle, timeout: 2)
        for _ in 0..<5 where privacyButton == nil {
            app.swipeUp()
            privacyButton = waitForHittableButton(in: app, label: privacyTitle, timeout: 2)
        }
        guard let privacyButton else {
            XCTFail("Expected privacy entry for marketing capture")
            return
        }
        privacyButton.tap()
        XCTAssertTrue(app.staticTexts[privacyTitle].waitForExistence(timeout: 10))
        sleep(2)
        try capture("10-privacy", in: outputDirectory, app: app)
    }

    private func makeApp(
        completedOnboarding: Bool,
        appLanguage: String = "zh-Hans",
        seedLibrary: Bool = false,
        supporterTrialActive: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            AppLaunchEnvironmentKey.isUITest: "1",
            AppLaunchEnvironmentKey.appLanguage: appLanguage,
            AppLaunchEnvironmentKey.appAppearance: "light",
            AppLaunchEnvironmentKey.seedLibrary: seedLibrary ? "1" : "0",
            AppLaunchEnvironmentKey.hasCompletedOnboarding: completedOnboarding ? "1" : "0",
            AppLaunchEnvironmentKey.hasSeenIntro: completedOnboarding ? "1" : "0",
            AppLaunchEnvironmentKey.supporterTrialActive: supporterTrialActive ? "1" : "0"
        ]
        return app
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
    private func openAdvancedTab(in app: XCUIApplication) {
        tapTabItem(in: app, labels: ["进阶", "Advanced"], fallbackOffset: CGVector(dx: 0.63, dy: 0.96))
    }

    @MainActor
    private func openAlbumsTab(in app: XCUIApplication) {
        returnToTabRootIfNeeded(in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.96)).tap()
    }

    @MainActor
    private func tapTabItem(in app: XCUIApplication, labels: [String], fallbackOffset: CGVector) {
        for label in labels {
            let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
            let tabBarButton = app.tabBars.buttons.matching(predicate).firstMatch
            if tabBarButton.waitForExistence(timeout: 1), tabBarButton.isHittable {
                tapHittableElement(tabBarButton)
                return
            }
        }

        for label in labels {
            let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
            let button = app.buttons.matching(predicate).firstMatch
            if button.waitForExistence(timeout: 1), button.isHittable {
                tapHittableElement(button)
                return
            }
        }

        for label in labels {
            let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
            let element = app.descendants(matching: .any).matching(predicate).firstMatch
            if element.waitForExistence(timeout: 1), element.isHittable {
                tapHittableElement(element)
                return
            }
        }

        app.coordinate(withNormalizedOffset: fallbackOffset).tap()
    }

    @MainActor
    private func returnToTabRootIfNeeded(in app: XCUIApplication) {
        let backButton = app.buttons.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "向左", "arrow.left")
        ).firstMatch
        guard backButton.waitForExistence(timeout: 1), backButton.isHittable else { return }
        tapHittableElement(backButton)
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let navigationBarBackButton = app.navigationBars.buttons.element(boundBy: 0)
        if navigationBarBackButton.waitForExistence(timeout: 2), navigationBarBackButton.isHittable {
            navigationBarBackButton.tap()
            return
        }

        let fallbackBackButton = app.buttons.matching(
            NSPredicate(
                format: "label IN %@ OR identifier IN %@",
                ["返回", "Back", "向左", "arrow.left"],
                ["返回", "Back", "向左", "arrow.left"]
            )
        ).firstMatch
        if fallbackBackButton.waitForExistence(timeout: 2), fallbackBackButton.isHittable {
            fallbackBackButton.tap()
        }
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
    private func normalizedOffset(for element: XCUIElement, dx: CGFloat, dy: CGFloat, in app: XCUIApplication) -> CGVector {
        let frame = element.frame
        guard app.frame.width > 0, app.frame.height > 0 else {
            return CGVector(dx: dx, dy: dy)
        }
        return CGVector(
            dx: (frame.minX + frame.width * dx) / app.frame.width,
            dy: (frame.minY + frame.height * dy) / app.frame.height
        )
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

    @MainActor
    private func dragCardDown(in app: XCUIApplication) {
        drag(in: app, from: CGVector(dx: 0.5, dy: 0.34), to: CGVector(dx: 0.5, dy: 0.72))
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
    private func waitForHittableButton(in app: XCUIApplication, label: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label == %@", label)
        while Date() < deadline {
            let buttons = app.buttons.matching(predicate).allElementsBoundByIndex
            if let button = buttons.first(where: { $0.exists && $0.isHittable }) {
                return button
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    @MainActor
    private func waitForHittableButtonLabelContaining(in app: XCUIApplication, substring: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label CONTAINS %@", substring)
        while Date() < deadline {
            let buttons = app.buttons.matching(predicate).allElementsBoundByIndex
            if let button = buttons.first(where: { $0.exists && $0.isHittable }) {
                return button
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    @MainActor
    private func waitForStaticTextLabel(in app: XCUIApplication, label: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label == %@", label)
        while Date() < deadline {
            let texts = app.staticTexts.matching(predicate).allElementsBoundByIndex
            if let text = texts.first(where: { $0.exists }) {
                return text
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    @MainActor
    private func waitForStaticTextLabelPrefix(in app: XCUIApplication, prefix: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        while Date() < deadline {
            let texts = app.staticTexts.matching(predicate).allElementsBoundByIndex
            if let text = texts.first(where: { $0.exists }) {
                return text
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    @MainActor
    private func waitForAnyElementLabelContaining(in app: XCUIApplication, substring: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label CONTAINS %@", substring)
        while Date() < deadline {
            let elements = app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
            if let element = elements.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    @MainActor
    private func waitForButtonLabel(in app: XCUIApplication, label: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label == %@", label)
        while Date() < deadline {
            let buttons = app.buttons.matching(predicate).allElementsBoundByIndex
            if let button = buttons.first(where: { $0.exists }) {
                return button
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    @MainActor
    private func waitForButtonLabelPrefix(
        in app: XCUIApplication,
        prefix: String,
        timeout: TimeInterval,
        excluding excludedLabelFragment: String? = nil
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        var swipeAttempts = 0

        while Date() < deadline {
            let buttons = app.buttons.matching(predicate).allElementsBoundByIndex
            if let button = buttons.first(where: { button in
                guard button.exists && button.isHittable else { return false }
                if let excludedLabelFragment {
                    return !button.label.contains(excludedLabelFragment)
                }
                return true
            }) {
                return button
            }

            if swipeAttempts < 4 {
                app.swipeUp()
                swipeAttempts += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        return nil
    }

    @MainActor
    private func waitForInlineVideoPlayer(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let videoPlayer = app.descendants(matching: .any)["photo-asset-video-player"]
        let skipButton = firstExistingButton(in: app, labels: ["跳过", "Skip"])

        while Date() < deadline {
            if videoPlayer.exists {
                return videoPlayer
            }

            if skipButton.exists, skipButton.isHittable {
                skipButton.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }

        return videoPlayer.exists ? videoPlayer : nil
    }

    @MainActor
    private func waitForFirstExistingButton(in app: XCUIApplication, labels: [String], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let button = app.buttons[label]
                if button.exists {
                    return button
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
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
        if tapFirstExistingButton(in: springboard, labels: writeLabels, timeout: 2) {
            sleep(1)
            return true
        }

        return didInteract
    }

    @MainActor
    private func dismissMarketingSystemPrompts(app: XCUIApplication, allowDeletionConfirmation: Bool = false) {
        var labels = [
            "允许完全访问",
            "允许访问所有照片",
            "允许",
            "允许删除",
            "Allow Full Access",
            "Allow Full Access to Photos",
            "Allow"
        ]
        if allowDeletionConfirmation {
            labels += ["删除", "Delete"]
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        for _ in 0..<5 {
            var didTap = tapFirstExistingButton(in: app, labels: labels, timeout: 1)
            didTap = tapFirstExistingButton(in: springboard, labels: labels, timeout: 1) || didTap
            if !didTap { return }
            sleep(1)
        }
    }

    private func installPhotoLibraryInterruptionMonitor(allowDeletionConfirmation: Bool = false) {
        addUIInterruptionMonitor(withDescription: "Photo library access") { alert in
            var labels = [
                "允许完全访问",
                "允许访问所有照片",
                "允许",
                "允许删除",
                "Allow Full Access",
                "Allow Full Access to Photos",
                "Allow"
            ]
            if allowDeletionConfirmation {
                labels += ["删除", "Delete"]
            }
            for label in labels {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }

            var denyLabels = ["不允许", "Don’t Allow", "Don't Allow", "取消", "Cancel"]
            if !allowDeletionConfirmation {
                denyLabels += ["删除", "Delete"]
            }
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
        let predicate = NSPredicate(format: "label IN %@ OR identifier IN %@", labels, labels)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            return true
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
    static let supporterTrialActive = "PHOTO_DELETE_UI_TEST_SUPPORTER_TRIAL_ACTIVE"
}
