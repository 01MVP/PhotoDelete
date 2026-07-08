# AGENTS.md
DO NOT send optional commentary

This file provides guidance to Codex when working in this repository.

## Repository Rules

- Do not put internal instructions, agent notes, TODO process text, or hidden implementation guidance into any user-facing UI, website copy, App Store copy, screenshots, or localized strings.
- When the work can be split cleanly, use independent subagents for non-overlapping read-only research or disjoint file scopes, then integrate and verify in the main thread.
- Treat the worktree as shared. Check `git status --short` before edits, do not revert user changes, and keep staging/commits narrowly scoped when asked to commit.
- Public UI text must be concise, user-facing, and localized through `L10n` / `Localizable.xcstrings`. Avoid leaking raw technical failures unless they are only for diagnostics.
- Core cleanup remains free. Supporter features are a one-time StoreKit unlock; do not describe the app as subscription-only or imply that basic cleanup requires payment.

## Project Overview

PhotoDelete is an iOS 16+ SwiftUI app for organizing and cleaning a real Photos library. The app uses swipe gestures, a safe candidate library, batch confirmation, album management, local cleanup history, and an optional StoreKit supporter unlock for advanced statistics and cleanup queues.

Privacy positioning is part of the product: no account is required, photos are processed on-device, and the app does not upload photos, videos, library contents, or cleanup decisions.

## Development Commands

### Open In Xcode

```bash
cd IOSAPP
open PhotoDelete.xcodeproj
```

Build and run through Xcode. Use a simulator for quick UI work and a real iPhone for Photos framework, iCloud Photos, limited library, deletion, favorite, and album write validation.

### Build From CLI

```bash
SIMULATOR_DESTINATION="$(scripts/resolve-ios-simulator-destination.sh)"
xcodebuild -project IOSAPP/PhotoDelete.xcodeproj -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData \
  clean build
```

### CI-Style Unit Test Flow

```bash
SIMULATOR_DESTINATION="$(scripts/resolve-ios-simulator-destination.sh)"
xcodebuild build-for-testing \
  -project IOSAPP/PhotoDelete.xcodeproj \
  -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building \
  -project IOSAPP/PhotoDelete.xcodeproj \
  -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData \
  -only-testing:PhotoDeleteTests \
  CODE_SIGNING_ALLOWED=NO
```

The GitHub Actions workflow in `.github/workflows/ios-ci.yml` follows this pattern on `macos-15` with Xcode 16.4.

### Full Simulator Test

```bash
SIMULATOR_DESTINATION="$(scripts/resolve-ios-simulator-destination.sh)"
xcodebuild test \
  -project IOSAPP/PhotoDelete.xcodeproj \
  -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData
```

UI tests are smoke tests. They do not replace real-device Photos validation.

### Cleanup

```bash
rm -rf IOSAPP/DerivedData
xcodebuild clean -project IOSAPP/PhotoDelete.xcodeproj -scheme PhotoDelete
```

### TestFlight Release

- TestFlight build numbers must use UTC+8 time in `yyyyMMddHHmm` format, matching Beijing/Shanghai local time. Do not generate release build numbers from UTC time.
- Before uploading, make sure the new `CFBundleVersion` is numerically greater than the highest build already visible in App Store Connect/TestFlight; otherwise testers may not receive it as an update even if the upload succeeds.
- Do not manually bump `MARKETING_VERSION` for every TestFlight upload. Reuse the current version while the pre-release train accepts new builds; if App Store Connect rejects the upload because the train is closed or `CFBundleShortVersionString` must be higher than the approved version, let `scripts/release-testflight.sh` auto-increment the last marketing-version component once, write it back to the Xcode project, and retry with a fresh UTC+8 build number.
- The release script accepts an explicit override:

```bash
BUILD_NUMBER=202606111630 scripts/release-testflight.sh
```

`scripts/release-testflight.sh` runs tests unless `SKIP_TESTS=1`, checks that App Icon PNGs do not contain alpha channels, archives, exports, uploads to App Store Connect/TestFlight, and handles one automatic marketing-version retry when Apple closes the current train.

## Architecture

### App Shell

- `PhotoDeleteApp.swift`: App entry point, UI-test defaults, gesture preference migration, selected app language, and selected appearance.
- `ContentView.swift`: First-run onboarding and root switch into the main app.
- `MainTabView.swift`: Four tabs: Organize, Albums, Advanced, Settings.

### Core Data And Services

- `Models.swift`: Photo categories, gesture actions/presets, review modes, time groups, album models, app appearance, and advanced cleanup models.
- `DataManager.swift`: Central observable state, candidate libraries, reviewed asset IDs, time groups, album lists, batch operations, advanced summaries, and cleanup statistics coordination.
- `PhotoLibraryManager.swift`: Photos authorization, paged photo loading, classification into videos/screenshots/live photos/favorites, image/video requests, caching, write operations, and `PHPhotoLibraryChangeObserver`.
- `LibrarySnapshotStore.swift`: Local JSON snapshots for photo-library and album-list IDs to speed up reloads.
- `CleanupStatsStore.swift`: Local cleanup-session history, monthly summaries, streaks, and persisted cleanup totals.
- `CleanupAchievements.swift`: Achievement definitions, progress, newly unlocked milestone evaluation.
- `PurchaseManager.swift`: StoreKit product loading, supporter purchase, restore, entitlement refresh, and transaction updates.
- `FeedbackDiagnostics.swift`: User-facing email diagnostic body. Keep this concise and do not duplicate system mail signatures.
- `AppLanguage.swift`, `Localization.swift`, `Localizable.xcstrings`: Runtime language selection for system, `zh-Hans`, `zh-Hant`, and `en`.
- `DesignSystem.swift`: Shared colors, layout constants, app constants, haptics, toasts, buttons, and permission cards.

### User Interface

- `HomeView.swift`: Main library entry points, categories, time groups, permission cards, and progress indicators.
- `SwipePhotoView.swift`: Core review UI. Contains card mode, two-row browser mode, gesture handling, local undo, album quick filing, `RealPhotoCard`, video/photo preview helpers, `BatchConfirmView`, and completion celebration.
- `AlbumsView.swift`: User album listing, album order, create, rename, delete, and album detail flows. Do not imply that deleting an album deletes the photos inside it.
- `AdvancedView.swift`: Supporter-gated advanced dashboard with period summaries, achievements entry, and cleanup queues for similar photos, large files, screenshots, and videos. Locked state shows demo data.
- `CleanupAchievementsView.swift`: Achievement list and progress display.
- `SettingsView.swift`: Usage stats, supporter entry, gesture/language/appearance preferences, data and permission controls, feedback, creator, and privacy sheets.
- `SettingsSupportDetailViews.swift`: Creator/01MVP support sections used by Settings.
- `SupporterView.swift`: Supporter paywall, unlocked long-term stats, monthly summaries, history, and badge. Theme switching is a supporter feature exposed from Settings.

### Website And Marketing

- `site/`: Static website and privacy policy. Deploys to Cloudflare Pages through `.github/workflows/deploy-site.yml`.
- `Marketing/PhotoDeleteCampaign/`: App Store screenshots, actual iOS screenshots, promo copy, and screenshot generation assets.
- `Marketing/PhotoDeleteCampaign/actual-ios-screenshots-v4/`: Preferred source for current real-app UI screenshots. Do not use older concept art as primary UI evidence when real screenshots are needed.

## Photo Management Workflow

- Default gestures: left = delete candidate, right = keep, up = favorite candidate, down = skip.
- Left/right/up are user-configurable through gesture presets; down remains a skip/keep gesture.
- Swipe actions mark assets as reviewed locally and move to the next unreviewed photo.
- Deletions and favorites are staged in `deleteCandidates` and `favoriteCandidates`.
- Nothing is deleted immediately. `BatchConfirmView` shows pending assets and calls `DataManager.executeBatchOperations()`.
- On success, `PhotoLibraryManager` commits Photos changes, `DataManager` applies local incremental updates, `CleanupStatsStore` records a session, and achievement progress is recalculated.
- Undo restores the previous asset position and reviewed/candidate state for the last local action.

## Photos Framework Notes

- Required permissions live in `IOSAPP/Config/PhotoDelete-Info.plist`:
  - `NSPhotoLibraryUsageDescription`
  - `NSPhotoLibraryAddUsageDescription`
  - `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`
- Authorization access states:
  - `.notDetermined`: request only when the user starts photo work
  - `.authorized`: full access
  - `.limited`: supported, with a manage-limited-library path
  - `.denied` / `.restricted`: send the user to Settings
- Simulator testing can import seed photos, but real device testing is required for iCloud Photos, limited library picker behavior, real deletion prompts, favorites, large libraries, and performance.
- Screenshot detection uses Photos smart albums plus device/screen-size heuristics. Avoid claiming ML duplicate detection unless the implementation actually does it.

## Testing Strategy

- Add or update unit tests in `IOSAPP/PhotoDeleteTests/` for model logic, stats, achievements, localization gates, snapshots, and pure data behavior.
- Add UI smoke coverage in `IOSAPP/PhotoDeleteUITests/` for onboarding/settings/navigation surfaces that do not depend on a seeded real library.
- Use a physical iPhone for end-to-end Photos write paths: permission prompt, limited access, delete confirmation, favorite write, album write, iCloud optimized storage, large libraries, and recovery after app backgrounding.
- For App Store screenshot work, prefer a seeded simulator plus the real iOS app, then store outputs under `Marketing/PhotoDeleteCampaign/actual-ios-screenshots-*` or `appstore-upload/`.

## Development Guidelines

- Prefer existing SwiftUI patterns and shared UI from `DesignSystem.swift`.
- For native SwiftUI UI, navigation, accessibility, and iOS 26 Liquid Glass rules, use `IOSAPP/UI_GUIDELINES.md` as the source of truth.
- Keep photo-library mutations behind `DataManager` and `PhotoLibraryManager`; do not write Photos changes directly from random views.
- Keep user-visible strings localized. If adding text, update `Localizable.xcstrings` for Simplified Chinese, Traditional Chinese, and English.
- Keep advanced/supporter-only behavior behind `PurchaseManager.isSupporter`. Locked advanced screens should remain demo/preview only.
- Keep local persistence small and transparent: UserDefaults for preferences/reviewed IDs, Application Support JSON for snapshots and cleanup history.
- Do not add analytics, tracking SDKs, or network photo upload paths without explicit product approval and privacy-policy updates.

## Debugging References

- `IOSAPP/DEBUGGING_GUIDE.md`: Photos setup, simulator vs real device notes, permission and performance debugging.
- `IOSAPP/Config/PhotoDelete-Info.plist`: Source of truth for photo-library permission usage descriptions.
- `RELEASE_CHECKLIST.md`: App Store/TestFlight readiness checklist.
