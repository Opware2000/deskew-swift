import XCTest
@testable import DeskewCore

/// Port de `Tests/TestImageUtils.pas` (partie rotation).
final class RotationTests: XCTestCase {

    private let imgWidth = 50
    private let imgHeight = 100

    private let gray1: UInt8 = 60
    private let gray2: UInt8 = 120
    private let gray3: UInt8 = 180
    private let gray4: UInt8 = 240

    private func makeQuadrantGray() -> GrayImage {
        var image = GrayImage(width: imgWidth, height: imgHeight, fill: 255)
        let halfW = imgWidth / 2
        let halfH = imgHeight / 2
        image.fill(rect: IntRect(left: 0, top: 0, right: halfW, bottom: halfH), gray1)
        image.fill(rect: IntRect(left: halfW, top: 0, right: imgWidth, bottom: halfH), gray2)
        image.fill(rect: IntRect(left: 0, top: halfH, right: halfW, bottom: imgHeight), gray3)
        image.fill(rect: IntRect(left: halfW, top: halfH, right: imgWidth, bottom: imgHeight), gray4)
        return image
    }

    private func makeQuadrantRGB() -> RGBImage {
        var image = RGBImage(width: imgWidth, height: imgHeight, fill: RGB24(r: 255, g: 255, b: 255))
        let halfW = imgWidth / 2
        let halfH = imgHeight / 2
        image.fill(rect: IntRect(left: 0, top: 0, right: halfW, bottom: halfH), pc(0xFFFF0000))
        image.fill(rect: IntRect(left: halfW, top: 0, right: imgWidth, bottom: halfH), pc(0xFF00FF00))
        image.fill(rect: IntRect(left: 0, top: halfH, right: halfW, bottom: imgHeight), pc(0xFF0000FF))
        image.fill(rect: IntRect(left: halfW, top: halfH, right: imgWidth, bottom: imgHeight), pc(0xFFFFFF00))
        return image
    }

    private func pc(_ color32: UInt32) -> RGB24 {
        let c = RGBA32(color32: color32)
        return RGB24(r: c.r, g: c.g, b: c.b)
    }

    private func expectedSize(_ currentWidth: Int, _ currentHeight: Int, _ angleDeg: Int,
                              _ filter: ResamplingFilter) -> (Int, Int) {
        let rad = Double(angleDeg) * Double.pi / 180
        var expectedWidth = Int(ceil(abs(Double(currentWidth) * cos(rad)) + abs(Double(currentHeight) * sin(rad))))
        var expectedHeight = Int(ceil(abs(Double(currentWidth) * sin(rad)) + abs(Double(currentHeight) * cos(rad))))

        if angleDeg == 180 {
            expectedWidth = currentWidth
            expectedHeight = currentHeight
        } else if angleDeg % 90 == 0 {
            expectedWidth = currentHeight
            expectedHeight = currentWidth
        }

        if filter != .nearest && angleDeg % 90 != 0 {
            expectedWidth += 1
            expectedHeight += 1
        }
        return (expectedWidth, expectedHeight)
    }

    func testRotate0DegreesNoChange() {
        let original = makeQuadrantGray()
        var image = original
        ImageRotation.rotate(&image, angleDegrees: 0, background: RGBA32(color32: 0),
                             filter: .nearest, fitRotated: true)
        XCTAssertEqual(image.width, original.width)
        XCTAssertEqual(image.height, original.height)
        XCTAssertEqual(image, original)
    }

    func testRotate90DegreesGray8Nearest() {
        var image = makeQuadrantGray()
        ImageRotation.rotate(&image, angleDegrees: 90, background: RGBA32(color32: 0),
                             filter: .nearest, fitRotated: true)
        XCTAssertEqual(image.width, imgHeight)
        XCTAssertEqual(image.height, imgWidth)
        XCTAssertEqual(image[0, image.height - 1], gray1, "bas-gauche = origine haut-gauche")
        XCTAssertEqual(image[0, 0], gray2, "haut-gauche = origine haut-droite")
        XCTAssertEqual(image[image.width - 1, image.height - 1], gray3, "bas-droite = origine bas-gauche")
        XCTAssertEqual(image[image.width - 1, 0], gray4, "haut-droite = origine bas-droite")
    }

    func testRotate180DegreesGray8Nearest() {
        var image = makeQuadrantGray()
        ImageRotation.rotate(&image, angleDegrees: 180, background: RGBA32(color32: 0xFF00FF00),
                             filter: .nearest, fitRotated: true)
        XCTAssertEqual(image.width, imgWidth)
        XCTAssertEqual(image.height, imgHeight)
        XCTAssertEqual(image[imgWidth - 1, imgHeight - 1], gray1)
        XCTAssertEqual(image[0, 0], gray4)
    }

    func testRotate45DegreesFitFalseGray8Nearest() {
        var image = makeQuadrantGray()
        ImageRotation.rotate(&image, angleDegrees: 45, background: RGBA32(color32: 0xFFFFFFFF),
                             filter: .nearest, fitRotated: false)
        XCTAssertEqual(image.width, imgWidth)
        XCTAssertEqual(image.height, imgHeight)
        XCTAssertEqual(image[10, 50], gray1, "pixel (10,50)")
        XCTAssertEqual(image[0, 0], 255)
        XCTAssertEqual(image[imgWidth - 1, 0], 255)
        XCTAssertEqual(image[0, imgHeight - 1], 255)
        XCTAssertEqual(image[imgWidth - 1, imgHeight - 1], 255)
    }

    func testFitTrueDimensionsGray8() {
        let angles = [90, 180, 270, -1, 1, 20, 45, 75, 111, 193, 217, 333]
        let original = GrayImage(width: imgWidth, height: imgHeight, fill: 255)

        for angle in angles {
            var image = original
            ImageRotation.rotate(&image, angleDegrees: Double(angle), background: RGBA32(color32: 0),
                                 filter: .nearest, fitRotated: true)
            let nearest = expectedSize(imgWidth, imgHeight, angle, .nearest)
            XCTAssertEqual(image.width, nearest.0, "largeur nearest \(angle)")
            XCTAssertEqual(image.height, nearest.1, "hauteur nearest \(angle)")

            image = original
            ImageRotation.rotate(&image, angleDegrees: Double(angle), background: RGBA32(color32: 0),
                                 filter: .cubic, fitRotated: true)
            let cubic = expectedSize(imgWidth, imgHeight, angle, .cubic)
            XCTAssertEqual(image.width, cubic.0, "largeur cubic \(angle)")
            XCTAssertEqual(image.height, cubic.1, "hauteur cubic \(angle)")
        }
    }

    func testBackgroundColorGray8Linear() {
        let angles = [1, 45, 75, 233, 359]
        let original = GrayImage(width: imgWidth, height: imgHeight, fill: 255)

        for angle in angles {
            var image = original
            ImageRotation.rotate(&image, angleDegrees: Double(angle), background: .opaqueBlack,
                                 filter: .linear, fitRotated: true)
            let w = image.width
            let h = image.height
            XCTAssertEqual(image[0, 0], 0, "coin haut-gauche @\(angle)")
            XCTAssertEqual(image[w - 1, 0], 0, "coin haut-droit @\(angle)")
            XCTAssertEqual(image[0, h - 1], 0, "coin bas-gauche @\(angle)")
            XCTAssertEqual(image[w - 1, h - 1], 0, "coin bas-droit @\(angle)")
        }
    }

    func testRotate90DegreesFitTrueRGB24Nearest() {
        var image = makeQuadrantRGB()
        ImageRotation.rotate(&image, angleDegrees: 45, background: RGBA32(color32: 0xFF000000),
                             filter: .linear, fitRotated: true)

        let expected = expectedSize(imgWidth, imgHeight, 45, .linear)
        XCTAssertEqual(image.width, expected.0)
        XCTAssertEqual(image.height, expected.1)

        let w = expected.0
        let h = expected.1
        XCTAssertEqual(image[w / 4, h / 2], pc(0xFFFF0000), "rouge")
        XCTAssertEqual(image[w / 2, h / 4], pc(0xFF00FF00), "vert")
        XCTAssertEqual(image[w / 2, h / 4 * 3], pc(0xFF0000FF), "bleu")
        XCTAssertEqual(image[w / 4 * 3, h / 2], pc(0xFFFFFF00), "jaune")
    }
}
