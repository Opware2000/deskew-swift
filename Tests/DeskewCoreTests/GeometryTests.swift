import XCTest
@testable import DeskewCore

final class GeometryTests: XCTestCase {

    // MARK: - Rectangles

    func testRectToStr() {
        XCTAssertEqual(IntRect(left: 1, top: 2, right: 3, bottom: 4).description, "[1,2,3,4]")
    }

    func testRectNullAndEmpty() {
        XCTAssertTrue(IntRect.zero.isNull)
        XCTAssertTrue(IntRect.zero.isEmpty)
        XCTAssertFalse(IntRect(x: 0, y: 0, width: 1, height: 1).isNull)
        XCTAssertFalse(IntRect(x: 0, y: 0, width: 1, height: 1).isEmpty)
        XCTAssertTrue(IntRect(x: 10, y: 10, width: 0, height: 5).isEmpty)
        XCTAssertTrue(IntRect(left: 50, top: 50, right: 40, bottom: 60).isEmpty)
    }

    func testRectIntersect() {
        let a = IntRect(left: 0, top: 0, right: 10, bottom: 10)
        let b = IntRect(left: 5, top: 5, right: 20, bottom: 20)
        XCTAssertEqual(a.intersect(b), IntRect(left: 5, top: 5, right: 10, bottom: 10))
        XCTAssertEqual(a.intersect(IntRect(left: 20, top: 20, right: 30, bottom: 30)), .zero)
    }

    func testRectContains() {
        let r = IntRect(left: 0, top: 0, right: 10, bottom: 10)
        XCTAssertTrue(r.contains(IntPoint(x: 0, y: 0)))
        XCTAssertTrue(r.contains(IntPoint(x: 9, y: 9)))
        XCTAssertFalse(r.contains(IntPoint(x: 10, y: 9)))
        XCTAssertFalse(r.contains(IntPoint(x: -1, y: 0)))
    }

    // MARK: - Units

    func testSizeUnitToken() {
        XCTAssertEqual(SizeUnit(token: "px"), .pixels)
        XCTAssertEqual(SizeUnit(token: "%"), .percent)
        XCTAssertEqual(SizeUnit(token: "MM"), .mm)
        XCTAssertEqual(SizeUnit(token: "Cm"), .cm)
        XCTAssertEqual(SizeUnit(token: "IN"), .inch)
        XCTAssertNil(SizeUnit(token: "nm"))
    }

    // MARK: - Résolution physique

    func testPhysicalPixelSize() {
        XCTAssertNil(ResolutionInfo.unknown.physicalPixelSize(.dpi))

        let fromDpi = ResolutionInfo.from(dpiX: 50, dpiY: 100)
        let dpi = fromDpi.physicalPixelSize(.dpi)
        XCTAssertNotNil(dpi)
        XCTAssertEqual(dpi!.x, 50, accuracy: 1e-6)
        XCTAssertEqual(dpi!.y, 100, accuracy: 1e-6)

        let fromDpcm = ResolutionInfo.from(dpcmX: 50, dpcmY: 100)
        let dpcm = fromDpcm.physicalPixelSize(.dpcm)
        XCTAssertEqual(dpcm!.x, 50, accuracy: 1e-6)
        XCTAssertEqual(dpcm!.y, 100, accuracy: 1e-6)

        // Taille de pixel en µm : 200 µm/px => 10000/200 = 50 px/cm
        let micro = ResolutionInfo(pixelSizeXMicrometers: 200, pixelSizeYMicrometers: 100)
        let cm = micro.physicalPixelSize(.dpcm)
        XCTAssertEqual(cm!.x, 50, accuracy: 1e-6)
        XCTAssertEqual(cm!.y, 100, accuracy: 1e-6)

        // Une seule dimension connue : l'autre est dupliquée
        let partial = ResolutionInfo(pixelSizeXMicrometers: 254)
        let p = partial.physicalPixelSize(.dpi)
        XCTAssertEqual(p!.x, 100, accuracy: 1e-6)
        XCTAssertEqual(p!.y, 100, accuracy: 1e-6)
    }

    // MARK: - CalcContentRectForImage (port de TestCalcDetectionRect)

    private let imageBounds = IntRect(left: 0, top: 0, right: 500, bottom: 1000)

    private func rect(_ l: Float, _ t: Float, _ r: Float, _ b: Float) -> FloatRect {
        FloatRect(left: l, top: t, right: r, bottom: b)
    }

    private func uniform(_ v: Float) -> FloatRect {
        FloatRect(left: v, top: v, right: v, bottom: v)
    }

    func testNoContentReduction() {
        let result = ContentRect.forImage(contentRect: nil, contentMargins: nil,
                                          unit: .pixels, imageBounds: imageBounds,
                                          resolution: .unknown)
        XCTAssertEqual(result, imageBounds)
    }

    func testContentMargins() {
        func margins(_ m: FloatRect, unit: SizeUnit = .pixels,
                     res: ResolutionInfo = .unknown) -> IntRect? {
            ContentRect.forImage(contentRect: nil, contentMargins: m,
                                 unit: unit, imageBounds: imageBounds, resolution: res)
        }

        XCTAssertEqual(margins(rect(100, 120, 140, 80)), IntRect(left: 100, top: 120, right: 360, bottom: 920))
        XCTAssertEqual(margins(uniform(100)), IntRect(left: 100, top: 100, right: 400, bottom: 900))
        XCTAssertEqual(margins(uniform(10), unit: .percent), IntRect(left: 50, top: 100, right: 450, bottom: 900))
        XCTAssertEqual(margins(rect(1, 20, 1, 20), unit: .percent), IntRect(left: 5, top: 200, right: 495, bottom: 800))
    }

    func testContentRect() {
        func content(_ r: FloatRect, unit: SizeUnit = .pixels) -> IntRect? {
            ContentRect.forImage(contentRect: r, contentMargins: nil,
                                 unit: unit, imageBounds: imageBounds, resolution: .unknown)
        }

        XCTAssertEqual(content(rect(100, 120, 440, 800)), IntRect(left: 100, top: 120, right: 440, bottom: 800))
        XCTAssertEqual(content(rect(10, 20, 90, 80), unit: .percent), IntRect(left: 50, top: 200, right: 450, bottom: 800))
    }

    func testContentFailures() {
        // Résolution manquante pour une unité physique
        XCTAssertNil(ContentRect.forImage(contentRect: nil, contentMargins: uniform(1),
                                          unit: .inch, imageBounds: imageBounds,
                                          resolution: .unknown))
        // Rectangle hors image
        XCTAssertNil(ContentRect.forImage(contentRect: rect(-10, -20, -90, -80), contentMargins: nil,
                                          unit: .pixels, imageBounds: imageBounds,
                                          resolution: .unknown))
        // Marges trop grandes
        XCTAssertNil(ContentRect.forImage(contentRect: nil, contentMargins: uniform(50.1),
                                          unit: .percent, imageBounds: imageBounds,
                                          resolution: .unknown))
    }

    func testContentPhysicalSizes() {
        // DPI 50x100 => image de 10x10 pouces
        let dpi = ResolutionInfo.from(dpiX: 50, dpiY: 100)
        XCTAssertEqual(ContentRect.forImage(contentRect: nil, contentMargins: uniform(1),
                                            unit: .inch, imageBounds: imageBounds,
                                            resolution: dpi),
                       IntRect(left: 50, top: 100, right: 450, bottom: 900))

        // 50x100 pixels par cm
        let dpcm = ResolutionInfo.from(dpcmX: 50, dpcmY: 100)
        XCTAssertEqual(ContentRect.forImage(contentRect: nil, contentMargins: uniform(1),
                                            unit: .cm, imageBounds: imageBounds,
                                            resolution: dpcm),
                       IntRect(left: 50, top: 100, right: 450, bottom: 900))
        XCTAssertEqual(ContentRect.forImage(contentRect: nil, contentMargins: uniform(1),
                                            unit: .mm, imageBounds: imageBounds,
                                            resolution: dpcm),
                       IntRect(left: 5, top: 10, right: 495, bottom: 990))

        // Taille pixel 200 x 100 µm => 5 x 10 px/mm
        let micro = ResolutionInfo(pixelSizeXMicrometers: 200, pixelSizeYMicrometers: 100)
        XCTAssertEqual(ContentRect.forImage(contentRect: nil, contentMargins: uniform(10),
                                            unit: .mm, imageBounds: imageBounds,
                                            resolution: micro),
                       IntRect(left: 50, top: 100, right: 450, bottom: 900))
    }
}
