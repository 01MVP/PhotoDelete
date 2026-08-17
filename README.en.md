<p align="center">
  <img src="https://oneapps.studio/one-apps/assets/onephoto-icon.png" width="96" alt="OnePhoto icon" />
</p>

<h1 align="center">OnePhoto / 删图</h1>

<p align="center">
  <strong>Swipe through the noise. Confirm every delete.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="AGPL-3.0" />
  <img src="https://img.shields.io/badge/iOS-16.0%2B-blue" alt="iOS 16.0+" />
  <img src="https://img.shields.io/badge/SwiftUI-✓-orange" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Privacy-On--Device-brightgreen" alt="On-device privacy" />
</p>

<p align="center">
  <a href="README.md">中文</a>
  ·
  <a href="https://oneapps.studio/apps/onephoto">Product page</a>
  ·
  <a href="https://apps.apple.com/app/id6779493280">App Store</a>
</p>

<p align="center">
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/en/hero-review-card.webp" width="280" alt="OnePhoto review card" />
</p>

## What it is

OnePhoto (project name PhotoDelete) is a local-first iPhone photo cleaner. Review photos, videos, screenshots, albums, or a time and place. Queue what you do not want to keep, inspect the full pending list, then confirm before anything is written back to Photos.

Core cleanup is free. There is no account and no ad tracking. Photos stay on the device. A one-time supporter unlock adds similar-photo review, large-file cleanup, on-device compression, long-term stats, and achievements.

This is one small app from [One Apps Studio](https://oneapps.studio). Screenshots and product copy live at [oneapps.studio/apps/onephoto](https://oneapps.studio/apps/onephoto).

## Screenshots

From the product page:

<p align="center">
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/en/review-card.jpg" width="220" alt="Swipe or tap to decide" />
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/en/two-row-browser.jpg" width="220" alt="Two-row browser" />
</p>
<p align="center">
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/en/albums.jpg" width="220" alt="Organize by album" />
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/en/privacy.jpg" width="220" alt="On-device privacy" />
</p>

1. Swipe or tap to decide
2. Two-row browser
3. Organize by album
4. On-device privacy

## Why it is open source

Since vibe coding took off, the same photo-cleaner has been rebuilt over and over. You do not need another empty project.

Fork this repo. Change the gestures, the review UI, or the cleanup queues. Open-source commercial use is free. Closed-source commercial use needs a license.

If you want a structured path for building AI products, see [01MVP](https://01mvp.com).

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

The default license is the [GNU Affero General Public License v3.0](LICENSE).

- **Open-source commercial use is free.** You may ship and sell a product based on this code if you also release your source under AGPL-3.0.
- **Closed-source commercial use is CNY 299.** If you want to sell a closed-source product, you need a license from the author. The fee is 299 yuan, paid once.

Contact [MakerJackie](https://x.com/makerjackie) for a closed-source license. You can also scan the codes below — they work as a tip, or as the 299-yuan closed-source license fee.

<p align="center">
  <img src="site/assets/sponsor/wxpay.jpg" width="240" alt="WeChat Pay" />
  <img src="site/assets/sponsor/alipay.jpg" width="240" alt="Alipay" />
</p>

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

## Author

[MakerJackie](https://makerjackie.com)

- X / Twitter: [@makerjackie](https://x.com/makerjackie)
- AI product tutorials: [01MVP](https://01mvp.com)
- Shape of the world: [shapeof.world](https://shapeof.world)
- App factory: [OneApps.Studio](https://oneapps.studio)
