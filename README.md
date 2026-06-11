<p align="center">
  <img src="IOSAPP/PhotoDel/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" width="120" alt="PhotoDel App Icon" />
</p>

<h1 align="center">PhotoDel</h1>

<p align="center">
  <strong>Free iPhone photo cleanup tool — swipe to organize your library</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-16.0%2B-blue" alt="iOS 16.0+" />
  <img src="https://img.shields.io/badge/SwiftUI-✓-orange" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/License-Free-green" alt="Free" />
  <img src="https://img.shields.io/badge/Privacy-On--Device-brightgreen" alt="On-Device" />
</p>

<p align="center">
  <a href="README_zh.md">中文版</a>
</p>

---

## Screenshots

<p align="center">
  <img src="site/assets/photodel-home.jpg" width="320" alt="PhotoDel Home Screen" />
</p>

<p align="center">
  <em>Home — Smart categories and time-based grouping</em>
</p>

> More screenshots: swipe gestures, album management, batch confirmation.
> See the interactive prototypes in [`Prototype/`](Prototype/) for a full preview of every screen.

---

## Features

### Swipe to Organize

| Gesture | Action | Indicator |
|---------|--------|-----------|
| ← Left | Mark for deletion | 🔴 Red |
| → Right | Keep | 🟢 Green |
| ↑ Up | Add to favorites | 🟡 Yellow |
| ↓ Down | Skip | ⚪ Gray |

Every action is undoable. Nothing is deleted until you explicitly confirm.

### Smart Categories

- **By type** — All Photos, Videos, Screenshots, Favorites
- **By time** — Today, This Week, This Month, Last Month, Older
- Progress rings show how much you've organized in each group

### Batch Confirmation

Photos are never deleted immediately. Instead, they're staged in a candidate library. When you're done swiping, review and confirm all pending deletions at once.

### Album Management

Create, edit, and delete custom albums. Quick-sort buttons appear in the swipe view for fast filing.

### Privacy-First

- No account required
- No photo uploads — everything stays on your device
- No analytics or tracking

---

## Getting Started

### Requirements

- Xcode 16.4+
- iOS 16.0+ deployment target
- A physical device recommended for Photos framework testing

### Build & Run

```bash
cd IOSAPP
open PhotoDel.xcodeproj
```

Select a simulator or device target, then build and run (Cmd+R).

### Build from CLI

```bash
cd IOSAPP
xcodebuild -project PhotoDel.xcodeproj -scheme PhotoDel \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean build
```

---

## Architecture

```
IOSAPP/PhotoDel/
├── PhotoDelApp.swift           # App entry point, dark mode config
├── ContentView.swift           # Root view with onboarding flow
├── Models.swift                # Core data structures
├── DataManager.swift           # Central data management & batch ops
├── PhotoLibraryManager.swift   # Photos framework integration
├── DesignSystem.swift          # UI style constants
├── MainTabView.swift           # Tab navigation (Organize / Albums / Settings)
├── HomeView.swift              # Photo categories & time groups
├── SwipePhotoView.swift        # Core swipe gesture interface
├── AlbumsView.swift            # Album CRUD
├── SettingsView.swift          # Stats & configuration
├── SupporterView.swift         # Supporter features and long-term stats
├── PurchaseManager.swift       # StoreKit supporter entitlement handling
└── Localizable.xcstrings       # Localized user-facing strings
```

`SwipePhotoView.swift` also contains `RealPhotoCard` and `BatchConfirmView`, which are kept with the core swipe workflow.

### Key Patterns

- **Candidate Library** — Deletions and favorites are staged in memory, then batch-processed on user confirmation via `executeBatchOperations()`
- **Authorization on Demand** — Photos access is requested on first interaction, not at startup
- **ObservableObject** — `DataManager` uses Combine `@Published` properties for reactive UI updates

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (declarative) |
| State | Combine + ObservableObject |
| Photos | PHAsset, PHAssetCollection, PHImageManager |
| Concurrency | async/await |
| Theme | Dark mode (preferredColorScheme) |

---

## Privacy

PhotoDel processes all photos on-device. The app requests Photos library access to display and organize your images, but never uploads, transmits, or shares your photos with any server.

See the [Privacy Policy](https://photodel.01mvp.com) for details.

---

## Project Info

Part of the [01MVP](https://01mvp.com) project by MakerJackie.

Website: [photodel.01mvp.com](https://photodel.01mvp.com)

---

## License

Copyright (c) 2025 MakerJackie / 01MVP. All rights reserved.
