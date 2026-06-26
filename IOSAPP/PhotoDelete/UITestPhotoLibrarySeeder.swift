//
//  UITestPhotoLibrarySeeder.swift
//  PhotoDelete
//
//  Creates a deterministic Photos library for UI-test screenshots.
//

#if DEBUG
import CoreLocation
import Photos
import UIKit

enum UITestPhotoLibrarySeeder {
    private static var hasStarted = false

    static func seedIfRequested(completion: @escaping () -> Void) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PHOTO_DELETE_UI_TEST"] == "1",
              environment["PHOTO_DELETE_UI_TEST_SEED_LIBRARY"] == "1" else {
            completion()
            return
        }

        guard !hasStarted else {
            completion()
            return
        }
        hasStarted = true

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            completion()
            return
        }

        let language = environment["PHOTO_DELETE_UI_TEST_APP_LANGUAGE"] ?? "zh-Hans"
        let albumPlan = makeAlbumPlan(language: language)
        let cleanupTitles = Set(makeAlbumPlan(language: "zh-Hans").map(\.title) +
            makeAlbumPlan(language: "en").map(\.title) +
            ["Test", "Test2", "胖泽爱躺萍", "西冲周末游 2023-7-22", "斑斑"])

        let collectionsToDelete = fetchUserAlbums(matching: cleanupTitles)
        let assetsToDelete = assets(in: collectionsToDelete)

        if assetsToDelete.isEmpty && collectionsToDelete.isEmpty {
            createSeedAlbums(albumPlan: albumPlan, completion: completion)
            return
        }

        PHPhotoLibrary.shared().performChanges {
            if !assetsToDelete.isEmpty {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }

            if !collectionsToDelete.isEmpty {
                PHAssetCollectionChangeRequest.deleteAssetCollections(collectionsToDelete as NSArray)
            }
        } completionHandler: { _, _ in
            createSeedAlbums(albumPlan: albumPlan, completion: completion)
        }
    }

    private struct AlbumSeed {
        let title: String
        let kind: AlbumKind
    }

    private enum AlbumKind {
        case travel
        case beach
        case city
        case pet
    }

    private struct PhotoSeed {
        let resourceName: String?
        let albumTitle: String
        let date: Date
        let location: CLLocation?
        let generatedPetIndex: Int?
    }

    private static func makeAlbumPlan(language: String) -> [AlbumSeed] {
        if language.hasPrefix("en") {
            return [
                AlbumSeed(title: "Travel Photos", kind: .travel),
                AlbumSeed(title: "Weekend Beach", kind: .beach),
                AlbumSeed(title: "City Walk", kind: .city),
                AlbumSeed(title: "Pet Photos", kind: .pet)
            ]
        }

        return [
            AlbumSeed(title: "旅行照片", kind: .travel),
            AlbumSeed(title: "周末海边", kind: .beach),
            AlbumSeed(title: "城市漫步", kind: .city),
            AlbumSeed(title: "宠物照片", kind: .pet)
        ]
    }

    private static func makePhotoSeeds(albumPlan: [AlbumSeed]) -> [PhotoSeed] {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        func day(_ value: Double) -> Date { date.addingTimeInterval(value * 86_400) }

        var seeds: [PhotoSeed] = []
        for album in albumPlan {
            switch album.kind {
            case .travel:
                seeds.append(PhotoSeed(
                    resourceName: "travel-seed-04",
                    albumTitle: album.title,
                    date: day(0),
                    location: CLLocation(latitude: 22.3193, longitude: 114.1694),
                    generatedPetIndex: nil
                ))
                seeds.append(PhotoSeed(
                    resourceName: "travel-seed-07",
                    albumTitle: album.title,
                    date: day(-1),
                    location: CLLocation(latitude: 40.7128, longitude: -74.0060),
                    generatedPetIndex: nil
                ))
            case .beach:
                seeds.append(PhotoSeed(
                    resourceName: "travel-seed-08",
                    albumTitle: album.title,
                    date: day(-2),
                    location: CLLocation(latitude: 1.3521, longitude: 103.8198),
                    generatedPetIndex: nil
                ))
                seeds.append(PhotoSeed(
                    resourceName: "travel-seed-06",
                    albumTitle: album.title,
                    date: day(-3),
                    location: CLLocation(latitude: 48.8566, longitude: 2.3522),
                    generatedPetIndex: nil
                ))
            case .city:
                seeds.append(PhotoSeed(
                    resourceName: "travel-seed-02",
                    albumTitle: album.title,
                    date: day(-4),
                    location: CLLocation(latitude: 30.2741, longitude: 120.1551),
                    generatedPetIndex: nil
                ))
                seeds.append(PhotoSeed(
                    resourceName: "travel-seed-03",
                    albumTitle: album.title,
                    date: day(-5),
                    location: CLLocation(latitude: 25.0330, longitude: 121.5654),
                    generatedPetIndex: nil
                ))
            case .pet:
                seeds.append(PhotoSeed(
                    resourceName: nil,
                    albumTitle: album.title,
                    date: day(-6),
                    location: nil,
                    generatedPetIndex: 0
                ))
                seeds.append(PhotoSeed(
                    resourceName: nil,
                    albumTitle: album.title,
                    date: day(-7),
                    location: nil,
                    generatedPetIndex: 1
                ))
            }
        }
        return seeds
    }

    private static func createSeedAlbums(albumPlan: [AlbumSeed], completion: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges {
            var placeholdersByAlbum: [String: [PHObjectPlaceholder]] = [:]
            for seed in makePhotoSeeds(albumPlan: albumPlan) {
                guard let request = makeAssetRequest(for: seed) else { continue }
                request.creationDate = seed.date
                request.location = seed.location
                if let placeholder = request.placeholderForCreatedAsset {
                    placeholdersByAlbum[seed.albumTitle, default: []].append(placeholder)
                }
            }

            for album in albumPlan {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: album.title)
                let placeholders = placeholdersByAlbum[album.title] ?? []
                if !placeholders.isEmpty {
                    request.addAssets(placeholders as NSArray)
                }
            }
        } completionHandler: { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                completion()
            }
        }
    }

    private static func makeAssetRequest(for seed: PhotoSeed) -> PHAssetChangeRequest? {
        if let resourceName = seed.resourceName,
           let url = resourceURL(named: resourceName) {
            return PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }

        return PHAssetChangeRequest.creationRequestForAsset(from: makeGeneratedImage(for: seed))
    }

    private static func resourceURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "UITestSeedAssets") ??
            Bundle.main.url(forResource: name, withExtension: "jpg")
    }

    private static func fetchUserAlbums(matching titles: Set<String>) -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var collections: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle,
                  titles.contains(title),
                  collection.canPerform(.delete) else { return }
            collections.append(collection)
        }
        return collections
    }

    private static func assets(in collections: [PHAssetCollection]) -> [PHAsset] {
        var assetsByID: [String: PHAsset] = [:]
        let options = PHFetchOptions()
        for collection in collections {
            PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
                assetsByID[asset.localIdentifier] = asset
            }
        }
        return Array(assetsByID.values)
    }

    private static func makeGeneratedImage(for seed: PhotoSeed) -> UIImage {
        if let index = seed.generatedPetIndex {
            return makePetImage(index: index)
        }

        let variant = seed.resourceName ?? seed.albumTitle
        let size = CGSize(width: 1600, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let palette = scenicPalette(for: variant)
            let colors = [palette.top.cgColor, palette.bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            palette.sun.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1180, y: 140, width: 210, height: 210)).fill()

            UIColor.white.withAlphaComponent(0.36).setFill()
            UIBezierPath(roundedRect: CGRect(x: 130, y: 170, width: 360, height: 82), cornerRadius: 41).fill()
            UIBezierPath(roundedRect: CGRect(x: 350, y: 235, width: 260, height: 62), cornerRadius: 31).fill()

            palette.mountainBack.setFill()
            let backMountain = UIBezierPath()
            backMountain.move(to: CGPoint(x: 0, y: 780))
            backMountain.addLine(to: CGPoint(x: 330, y: 460))
            backMountain.addLine(to: CGPoint(x: 680, y: 780))
            backMountain.addLine(to: CGPoint(x: 1020, y: 500))
            backMountain.addLine(to: CGPoint(x: size.width, y: 790))
            backMountain.addLine(to: CGPoint(x: size.width, y: size.height))
            backMountain.addLine(to: CGPoint(x: 0, y: size.height))
            backMountain.close()
            backMountain.fill()

            palette.mountainFront.setFill()
            let frontMountain = UIBezierPath()
            frontMountain.move(to: CGPoint(x: 0, y: 890))
            frontMountain.addLine(to: CGPoint(x: 520, y: 520))
            frontMountain.addLine(to: CGPoint(x: 970, y: 890))
            frontMountain.addLine(to: CGPoint(x: 1280, y: 650))
            frontMountain.addLine(to: CGPoint(x: size.width, y: 900))
            frontMountain.addLine(to: CGPoint(x: size.width, y: size.height))
            frontMountain.addLine(to: CGPoint(x: 0, y: size.height))
            frontMountain.close()
            frontMountain.fill()

            palette.water.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 880, width: size.width, height: 320)).fill()

            UIColor.white.withAlphaComponent(0.42).setStroke()
            for offset in stride(from: CGFloat(40), through: CGFloat(1500), by: CGFloat(260)) {
                let wave = UIBezierPath()
                wave.lineWidth = 10
                wave.move(to: CGPoint(x: offset, y: 990))
                wave.addCurve(
                    to: CGPoint(x: offset + 180, y: 990),
                    controlPoint1: CGPoint(x: offset + 55, y: 950),
                    controlPoint2: CGPoint(x: offset + 125, y: 1030)
                )
                wave.stroke()
            }
        }
    }

    private struct ScenicPalette {
        let top: UIColor
        let bottom: UIColor
        let sun: UIColor
        let mountainBack: UIColor
        let mountainFront: UIColor
        let water: UIColor
    }

    private static func scenicPalette(for variant: String) -> ScenicPalette {
        switch variant {
        case "travel-seed-02", "travel-seed-03":
            return ScenicPalette(
                top: UIColor(red: 0.78, green: 0.88, blue: 0.96, alpha: 1),
                bottom: UIColor(red: 0.96, green: 0.88, blue: 0.74, alpha: 1),
                sun: UIColor(red: 1.0, green: 0.76, blue: 0.34, alpha: 1),
                mountainBack: UIColor(red: 0.47, green: 0.64, blue: 0.58, alpha: 1),
                mountainFront: UIColor(red: 0.26, green: 0.44, blue: 0.40, alpha: 1),
                water: UIColor(red: 0.39, green: 0.64, blue: 0.78, alpha: 1)
            )
        case "travel-seed-06", "travel-seed-08":
            return ScenicPalette(
                top: UIColor(red: 0.48, green: 0.72, blue: 0.92, alpha: 1),
                bottom: UIColor(red: 0.92, green: 0.76, blue: 0.60, alpha: 1),
                sun: UIColor(red: 1.0, green: 0.88, blue: 0.46, alpha: 1),
                mountainBack: UIColor(red: 0.52, green: 0.60, blue: 0.72, alpha: 1),
                mountainFront: UIColor(red: 0.33, green: 0.46, blue: 0.64, alpha: 1),
                water: UIColor(red: 0.22, green: 0.58, blue: 0.74, alpha: 1)
            )
        default:
            return ScenicPalette(
                top: UIColor(red: 0.70, green: 0.82, blue: 0.76, alpha: 1),
                bottom: UIColor(red: 0.98, green: 0.83, blue: 0.65, alpha: 1),
                sun: UIColor(red: 1.0, green: 0.72, blue: 0.38, alpha: 1),
                mountainBack: UIColor(red: 0.56, green: 0.66, blue: 0.48, alpha: 1),
                mountainFront: UIColor(red: 0.32, green: 0.48, blue: 0.36, alpha: 1),
                water: UIColor(red: 0.42, green: 0.68, blue: 0.72, alpha: 1)
            )
        }
    }

    private static func makePetImage(index: Int) -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let backgroundColors: [UIColor] = index == 0
                ? [UIColor(red: 0.78, green: 0.91, blue: 1.0, alpha: 1), UIColor(red: 1.0, green: 0.91, blue: 0.82, alpha: 1)]
                : [UIColor(red: 0.96, green: 0.88, blue: 1.0, alpha: 1), UIColor(red: 0.82, green: 0.95, blue: 0.88, alpha: 1)]
            let colors = backgroundColors.map(\.cgColor) as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            UIColor.white.withAlphaComponent(0.68).setFill()
            UIBezierPath(roundedRect: CGRect(x: 180, y: 520, width: 840, height: 650), cornerRadius: 120).fill()

            let faceRect = CGRect(x: 310, y: 420, width: 580, height: 580)
            UIColor(red: 0.88, green: 0.67, blue: 0.42, alpha: 1).setFill()
            UIBezierPath(ovalIn: faceRect).fill()

            UIColor(red: 0.65, green: 0.42, blue: 0.24, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 250, y: 360, width: 210, height: 260)).fill()
            UIBezierPath(ovalIn: CGRect(x: 740, y: 360, width: 210, height: 260)).fill()

            UIColor.black.withAlphaComponent(0.78).setFill()
            UIBezierPath(ovalIn: CGRect(x: 450, y: 630, width: 68, height: 88)).fill()
            UIBezierPath(ovalIn: CGRect(x: 682, y: 630, width: 68, height: 88)).fill()

            UIColor(red: 0.18, green: 0.12, blue: 0.10, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 560, y: 760, width: 80, height: 58)).fill()

            UIColor.white.withAlphaComponent(0.85).setStroke()
            let smile = UIBezierPath()
            smile.lineWidth = 12
            smile.move(to: CGPoint(x: 515, y: 850))
            smile.addQuadCurve(to: CGPoint(x: 685, y: 850), controlPoint: CGPoint(x: 600, y: 930))
            smile.stroke()

            UIColor.white.withAlphaComponent(0.76).setFill()
            UIBezierPath(ovalIn: CGRect(x: 470, y: 650, width: 18, height: 24)).fill()
            UIBezierPath(ovalIn: CGRect(x: 702, y: 650, width: 18, height: 24)).fill()
        }
    }
}
#endif
