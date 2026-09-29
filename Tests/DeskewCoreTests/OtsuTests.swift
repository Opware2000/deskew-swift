import XCTest
@testable import DeskewCore

/// Port de `Tests/TestImageUtils.pas` (partie Otsu).
final class OtsuTests: XCTestCase {

    /// Remplit un rectangle avec deux valeurs séparées horizontalement
    /// (deux bandes verticales) ou verticalement (deux bandes horizontales).
    private func makeTwoValueImage(
        width: Int, height: Int, background: UInt8,
        rect: IntRect, value1: UInt8, value2: UInt8, horizontalSplit: Bool
    ) -> GrayImage {
        var image = GrayImage(width: width, height: height, fill: background)
        let clipped = rect.intersect(image.bounds)
        XCTAssertFalse(clipped.isEmpty)
        if horizontalSplit {
            let half = clipped.left + clipped.width / 2
            image.fill(rect: IntRect(left: clipped.left, top: clipped.top, right: half, bottom: clipped.bottom), value1)
            image.fill(rect: IntRect(left: half, top: clipped.top, right: clipped.right, bottom: clipped.bottom), value2)
        } else {
            let half = clipped.top + clipped.height / 2
            image.fill(rect: IntRect(left: clipped.left, top: clipped.top, right: clipped.right, bottom: half), value1)
            image.fill(rect: IntRect(left: clipped.left, top: half, right: clipped.right, bottom: clipped.bottom), value2)
        }
        return image
    }

    func testWholeImageSimpleSplit() {
        let image = makeTwoValueImage(width: 128, height: 128, background: 255,
                                      rect: IntRect(left: 0, top: 0, right: 128, bottom: 128),
                                      value1: 50, value2: 200, horizontalSplit: true)
        let threshold = Otsu.threshold(image: image)
        XCTAssertTrue(threshold > 50 && threshold < 200,
                      "Seuil attendu entre 50 et 200, obtenu \(threshold)")
    }

    func testWholeImageSolidColor() {
        let image = GrayImage(width: 128, height: 128, fill: 150)
        XCTAssertEqual(Otsu.threshold(image: image), 150)
    }

    func testContentRectSimpleSplit() {
        var image = GrayImage(width: 128, height: 128, fill: 255)
        let content = IntRect(left: 10, top: 10, right: 90, bottom: 90)
        let half = content.top + content.height / 2
        image.fill(rect: IntRect(left: content.left, top: content.top, right: content.right, bottom: half), 30)
        image.fill(rect: IntRect(left: content.left, top: half, right: content.right, bottom: content.bottom), 180)
        let threshold = Otsu.threshold(image: image, rect: content)
        XCTAssertTrue(threshold > 30 && threshold < 180,
                      "Seuil attendu entre 30 et 180, obtenu \(threshold)")
    }

    func testContentRectSolidColor() {
        var image = GrayImage(width: 128, height: 128, fill: 255)
        let content = IntRect(left: 20, top: 20, right: 80, bottom: 80)
        image.fill(rect: content, 100)
        XCTAssertEqual(Otsu.threshold(image: image, rect: content), 100)
    }

    func testContentRectIgnoresOutside() {
        var image = makeTwoValueImage(width: 128, height: 128, background: 255,
                                      rect: IntRect(left: 0, top: 0, right: 128, bottom: 128),
                                      value1: 10, value2: 240, horizontalSplit: true)
        let content = IntRect(left: 25, top: 25, right: 75, bottom: 75)
        image.fill(rect: content, 120)
        XCTAssertEqual(Otsu.threshold(image: image, rect: content), 120)
    }

    func testContentRectInvalid() {
        let image = GrayImage(width: 128, height: 128, fill: 255)

        XCTAssertEqual(Otsu.threshold(image: image, rect: IntRect(left: 10, top: 10, right: 10, bottom: 20)), 128)
        XCTAssertEqual(Otsu.threshold(image: image, rect: IntRect(left: 10, top: 10, right: 20, bottom: 10)), 128)
        XCTAssertEqual(Otsu.threshold(image: image, rect: IntRect(left: 50, top: 50, right: 40, bottom: 60)), 128)
        XCTAssertEqual(Otsu.threshold(image: image, rect: IntRect(left: 50, top: 50, right: 60, bottom: 40)), 128)
    }

    func testContentRectClipped() {
        var image = GrayImage(width: 20, height: 20, fill: 100)
        // Seule la partie (10,10)-(20,20) est valide, unie à 50
        image.fill(rect: IntRect(left: 10, top: 10, right: 20, bottom: 20), 50)
        let outside = IntRect(left: 10, top: 10, right: 30, bottom: 30)
        XCTAssertEqual(Otsu.threshold(image: image, rect: outside), 50)
    }
}
