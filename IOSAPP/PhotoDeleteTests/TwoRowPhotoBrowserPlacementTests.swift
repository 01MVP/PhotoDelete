import Testing
import UIKit
@testable import PhotoDelete

@MainActor
struct TwoRowPhotoBrowserPlacementTests {
    @Test func placementUsesTwoStaggeredRows() {
        let placement = TwoRowPhotoBrowserPlacement.makeFrames(
            aspectRatios: [0.78, 1.2, 0.65, 1.5, 0.9],
            containerWidth: 390,
            rowHeight: 140,
            rowSpacing: 12,
            itemSpacing: 12,
            horizontalInset: 18,
            verticalInset: 4,
            bottomRowInset: 48
        )

        #expect(placement.frames.count == 5)
        #expect(!placement.laneIndices[0].isEmpty)
        #expect(!placement.laneIndices[1].isEmpty)
        #expect(placement.frames[0].minY != placement.frames[1].minY)
        #expect(placement.frames[1].minX > placement.frames[0].minX)
        #expect(placement.contentSize.width > 390)
    }

    @Test func layoutReturnsOnlyVisibleAttributesForLargeLibraries() {
        let layout = TwoRowPhotoBrowserLayout()
        let metrics = Array(repeating: TwoRowPhotoBrowserLayout.ItemMetric(aspectRatio: 0.78), count: 40_000)
        layout.configure(
            metrics: metrics,
            rowHeight: 150,
            rowSpacing: 12,
            itemSpacing: 12,
            horizontalInset: 18,
            verticalInset: 4,
            bottomRowInset: 51
        )

        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 320),
            collectionViewLayout: layout
        )
        _ = collectionView
        layout.prepare()
        collectionView.layoutIfNeeded()

        let firstScreenAttributes = layout.layoutAttributesForElements(
            in: CGRect(x: 0, y: 0, width: 390, height: 320)
        ) ?? []
        let farScreenAttributes = layout.layoutAttributesForElements(
            in: CGRect(x: 120_000, y: 0, width: 390, height: 320)
        ) ?? []

        #expect(firstScreenAttributes.count < 20)
        #expect(farScreenAttributes.count < 20)
        #expect(layout.collectionViewContentSize.width > 120_000)
    }
}
