<p align="center">
  <img src="IOSAPP/PhotoDelete/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" width="120" alt="OnePhoto app icon" />
</p>

<h1 align="center">OnePhoto / 删图</h1>

<p align="center">
  <strong>Swipe through your camera roll, queue decisions safely, and confirm before anything is changed.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="AGPL-3.0" />
  <img src="https://img.shields.io/badge/iOS-16.0%2B-blue" alt="iOS 16.0+" />
  <img src="https://img.shields.io/badge/SwiftUI-✓-orange" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Privacy-On--Device-brightgreen" alt="On-device privacy" />
  <img src="https://img.shields.io/badge/Core-Free-green" alt="Core features free" />
</p>

<p align="center">
  <a href="README.zh-CN.md">中文说明</a>
  ·
  <a href="https://oneapps.studio/apps/onephoto">OneApps.Studio</a>
  ·
  <a href="https://apps.apple.com/app/id6779493280">App Store</a>
</p>

<p align="center">
  <img src="site/assets/photodelete-home.jpg" width="320" alt="OnePhoto home screen" />
</p>

## What it is

OnePhoto (project name: PhotoDelete) is a local-first iPhone photo cleaner. Review photos, videos, screenshots, albums, or a time and place. Queue what you do not want to keep, inspect the full pending list, then confirm before anything is written back to Photos.

Core cleanup is free. There is no account and no ad tracking. Photos stay on the device. A one-time StoreKit supporter unlock adds similar-photo review, large-file cleanup, on-device compression, long-term stats, and achievements.

This is one small app from [One Apps Studio](https://oneapps.studio), MakerJackie's app factory. Most apps there keep the basics free.

## Why it is open source

Since vibe coding took off, the same photo-cleaner has been rebuilt over and over. You do not need another empty project.

Fork this repo. Change the gestures, the review UI, or the cleanup queues. Ship your own app if you want. Keep the source open under AGPL-3.0 and commercial use is allowed.

## Features

| Feature | Details |
| --- | --- |
| Swipe review | Default: left to queue delete, right to keep, up to favorite, down to skip. Gestures are customizable. Undo is available. |
| Safe confirmation | Delete and favorite actions stay queued until you review and confirm. |
| Review modes | Single-card review or a two-row browser. |
| Smart entry points | All photos, videos, screenshots, Live Photos, favorites, albums, time, and place. |
| Similar photos | Find near-duplicates and burst shots. |
| Large files | Start with the items that take the most space. |
| On-device compression | Compress photos and videos on the phone. |
| Privacy | No account. No photo uploads. Cleanup decisions stay on device. |

## Getting started

Requirements:

- Xcode 16.4+
- iOS 16.0+
- Simulator is fine for UI work. Use a real iPhone for Photos, iCloud Photos, limited library access, and real delete / favorite writes.

```bash
cd IOSAPP
open PhotoDelete.xcodeproj
```

Select a simulator or device, then press Cmd+R.

Build from the command line:

```bash
SIMULATOR_DESTINATION="$(scripts/resolve-ios-simulator-destination.sh)"
xcodebuild -project IOSAPP/PhotoDelete.xcodeproj -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData \
  clean build
```

Run tests:

```bash
SIMULATOR_DESTINATION="$(scripts/resolve-ios-simulator-destination.sh)"
xcodebuild test \
  -project IOSAPP/PhotoDelete.xcodeproj \
  -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData
```

## Project layout

| Path | Purpose |
| --- | --- |
| `IOSAPP/PhotoDelete.xcodeproj` | Xcode project |
| `IOSAPP/PhotoDelete/` | SwiftUI app source |
| `IOSAPP/PhotoDeleteTests/` | Unit tests |
| `IOSAPP/PhotoDeleteUITests/` | UI smoke tests |
| `IOSAPP/Config/PhotoDelete-Info.plist` | Permissions and bundle metadata |
| `site/` | Website and privacy policy |
| `scripts/` | Simulator helper and TestFlight upload script |

## License

[GNU Affero General Public License v3.0](LICENSE).

- You may use, modify, and sell products based on this code.
- If you distribute an app or a service based on this code, you must also release your source under AGPL-3.0.
- Closed-source forks are not allowed.

Copyright (c) 2025-2026 MakerJackie / 01MVP.

## More apps

Download them from [OneApps.Studio](https://oneapps.studio):

- **OneZen** — a quiet meditation app
- **OneScan** — scan paper into PDF
- **OneVoice** — AI voice notes and transcription
- **OneStarter** — a SwiftUI app starter
- **OneFocus** — focus that links Mac and iPhone
- **OneTune** — instrument tuner
- **OneMusic** — free offline music player
