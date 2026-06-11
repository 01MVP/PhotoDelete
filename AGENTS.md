# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

PhotoDel is an iOS app for photo organization and deletion with intuitive swipe gestures. The app features a dark theme design and real Photos library integration.

## Development Commands

### Building and Running
```bash
cd IOSAPP
open PhotoDel.xcodeproj
# Build and run through Xcode interface
# Target: iOS 16.0+
```

### TestFlight Release
- TestFlight build numbers must use UTC+8 time in `yyyyMMddHHmm` format, matching Beijing/Shanghai local time. Do not generate release build numbers from UTC time.
- Before uploading, make sure the new `CFBundleVersion` is numerically greater than the highest build already visible in App Store Connect/TestFlight; otherwise testers may not receive it as an update even if the upload succeeds.
- The release script accepts an explicit override, for example `BUILD_NUMBER=202606111630 scripts/release-testflight.sh`.

### Project Cleanup
```bash
rm -rf IOSAPP/DerivedData
xcodebuild clean -project IOSAPP/PhotoDel.xcodeproj -scheme PhotoDel
```

### Testing Options
- **Simulator**: Quick UI development and testing
- **Real Device**: Required for full Photos framework testing and performance validation

## Architecture

### Core Components

**Data Layer:**
- `Models.swift`: Core data structures (PhotoCategory, TimeGroup, AlbumInfo, OrganizeStats)
- `DataManager.swift`: Central data management with batch operations and candidate libraries
- `PhotoLibraryManager.swift`: Photos framework integration with authorization and CRUD operations

**View Layer:**
- `PhotoDelApp.swift`: App entry point with dark mode configuration
- `ContentView.swift` + `MainTabView.swift`: Navigation structure
- `HomeView.swift`: Photo categories and time groups with progress indicators
- `SwipePhotoView.swift`: Core swipe gesture interface
- `SwipePhotoView.swift` also contains `RealPhotoCard` and `BatchConfirmView`
- `AlbumsView.swift`: Album management
- `SettingsView.swift`: Statistics and configuration
- `SupporterView.swift`: Supporter features and long-term statistics

### Key Architecture Patterns

**Candidate Library Pattern**: Instead of immediate deletions, photos are staged in `deleteCandidates` and `favoriteCandidates` sets, then batch-processed when user confirms.

**Real Photos Integration**: 
- Real Photos library integration (PhotoLibraryManager)

**Authorization Flow**: App requests Photos library access on first real photo interaction, not at startup.

## Photo Management Workflow

### Swipe Gestures
- Left swipe: Skip/keep photo
- Right swipe: Add to delete candidates
- Up swipe: Add to favorites
- Down swipe: Skip photo

### Batch Operations
All real deletions and favorites are queued and executed via `executeBatchOperations()` when user confirms in `BatchConfirmView`.

## Photos Framework Integration

### Key Classes
- `PHAsset`: Individual photo/video representation
- `PHAssetCollection`: Album containers
- `PHImageManager`: Image loading and caching
- `PHPhotoLibrary`: Change notifications and write operations

### Permissions Required
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>PhotoDel需要访问您的照片库来帮助您整理和管理照片。我们不会上传或分享您的照片。</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>PhotoDel需要权限来把照片加入您选择的相册。</string>
```

### Authorization States
- `.notDetermined`: Request needed
- `.authorized`: Full access (required for app functionality)
- `.limited`: Partial access (suboptimal)
- `.denied`: No access

## Time-based Categorization

Photos are automatically grouped by:
- Today's photos
- This week's photos  
- This month's photos
- Last month's photos
- Older photos

Progress indicators show organization completion for each time group.

## Development Guidelines

### Testing Strategy
1. **Simulator Development**: UI development and testing
2. **Real Device Testing**: Essential for Photos framework validation
3. **Permission Testing**: Verify authorization flow on fresh installs

### Performance Considerations
- Photos loading is asynchronous with progress indicators
- Image caching via PHImageManager
- Batch operations prevent UI blocking
- Screenshot detection uses metadata + device dimensions

### Code Style
- SwiftUI declarative UI
- Combine for reactive data binding  
- ObservableObject pattern for data management
- async/await for Photos operations

## Debugging

Refer to `IOSAPP/DEBUGGING_GUIDE.md` for detailed debugging instructions including:
- Simulator vs real device testing
- Photo library setup methods
- Common permission and performance issues
- Instruments profiling guidance
