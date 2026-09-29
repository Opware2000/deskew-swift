import XCTest
@testable import DeskewCore

/// Port de `Tests/TestImageUtils.pas` (partie binarisation).
final class BinarizationTests: XCTestCase {

    func testBinarizeWholeImageSimpleSplit() {
        var image = GrayImage(width: 128, height: 128, fill: 255)
        let half = image.width / 2
        image.fill(rect: IntRect(left: 0, top: 0, right: half, bottom: 128), 50)
        image.fill(rect: IntRect(left: half, top: 0, right: 128, bottom: 128), 200)

        Binarization.binarize(&image, threshold: 100)

        for y in 0..<image.height {
            for x in 0..<image.width {
                if x < image.width / 2 {
                    XCTAssertEqual(image[x, y], 0, "pixel (\(x),\(y)) initialement 50")
                } else {
                    XCTAssertEqual(image[x, y], 255, "pixel (\(x),\(y)) initialement 200")
                }
            }
        }
    }

    func testBinarizeContentRectLeavesOutsideUnchanged() {
        var image = GrayImage(width: 128, height: 128, fill: 150)
        let content = IntRect(left: 20, top: 20, right: 80, bottom: 80)
        let half = content.left + content.width / 2
        image.fill(rect: IntRect(left: content.left, top: content.top, right: half, bottom: content.bottom), 40)
        image.fill(rect: IntRect(left: half, top: content.top, right: content.right, bottom: content.bottom), 210)

        Binarization.binarize(&image, threshold: 128, rect: content)

        for y in 0..<image.height {
            for x in 0..<image.width {
                if content.contains(IntPoint(x: x, y: y)) {
                    XCTAssertTrue(image[x, y] == 0 || image[x, y] == 255)
                } else {
                    XCTAssertEqual(image[x, y], 150, "pixel (\(x),\(y)) hors rectangle")
                }
            }
        }
    }
}
