import XCTest
import DeskewImageIO
@testable import DeskewCore

/// Tests de sécurité : les entrées non fiables (arguments CLI, rectangles) ne
/// doivent **jamais** provoquer de plantage, seulement un rejet propre.
final class SecurityTests: XCTestCase {

    private func rejected(_ args: [String]) -> Bool {
        var options = DeskewOptions()
        let parsed = options.parse(args)
        return !parsed || !options.isValid
    }

    // MARK: - Angle maximal (`-a`)

    func testNonFiniteOrUnboundedMaxAngleRejected() {
        for bad in ["inf", "-inf", "nan", "1e19", "1e15", "1e300", "100", "91", "0", "-5"] {
            XCTAssertTrue(rejected(["-a", bad, "in.png"]), "-a \(bad) doit être rejeté")
        }
    }

    func testValidMaxAngleAccepted() {
        for good in ["0.1", "10", "45", "90"] {
            var options = DeskewOptions()
            XCTAssertTrue(options.parse(["-a", good, "in.png"]), "-a \(good)")
            XCTAssertTrue(options.isValid, "-a \(good) valide")
        }
    }

    // MARK: - Autres options numériques

    func testNonFiniteSkipAngleRejected() {
        XCTAssertTrue(rejected(["-l", "inf", "in.png"]))
        XCTAssertTrue(rejected(["-l", "nan", "in.png"]))
    }

    func testNonFiniteAngleStepRejected() {
        for bad in ["inf", "nan", "0", "10"] {
            XCTAssertTrue(rejected(["-d", bad, "in.png"]), "-d \(bad)")
        }
    }

    // MARK: - Rectangles (`-r`, `-m`)

    func testNonFiniteContentRectRejected() {
        for bad in ["nan,0,10,10", "inf,0,10,10", "1e300,0,10,10", "0,nan,10,10"] {
            XCTAssertTrue(rejected(["-r", bad, "in.png"]), "-r \(bad)")
        }
    }

    func testNonFiniteMarginsRejected() {
        for bad in ["inf", "nan", "1e300", "nan,10", "inf,inf,inf,inf"] {
            XCTAssertTrue(rejected(["-m", bad, "in.png"]), "-m \(bad)")
        }
    }

    // MARK: - Défense en profondeur : géométrie

    func testScaledRectNonFiniteIsZeroNotCrash() {
        let nan = FloatRect(left: .nan, top: 0, right: 10, bottom: 10)
        XCTAssertEqual(nan.scaled(widthFactor: 1, heightFactor: 1), .zero)

        let inf = FloatRect(left: .infinity, top: 0, right: 10, bottom: 10)
        XCTAssertEqual(inf.scaled(widthFactor: 1, heightFactor: 1), .zero)

        // Float(1e300) == inf
        let huge = FloatRect(left: Float(1e300), top: 0, right: 10, bottom: 10)
        XCTAssertEqual(huge.scaled(widthFactor: 1, heightFactor: 1), .zero)

        // Valeur normale : inchangée
        let normal = FloatRect(left: 1, top: 2, right: 3, bottom: 4)
        XCTAssertEqual(normal.scaled(widthFactor: 2, heightFactor: 2),
                       IntRect(left: 2, top: 4, right: 6, bottom: 8))
    }

    func testContentRectNonFiniteReturnsNil() {
        let bounds = IntRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(ContentRect.forImage(contentRect: FloatRect(left: .nan, top: 0, right: 10, bottom: 10),
                                          contentMargins: nil, unit: .pixels,
                                          imageBounds: bounds, resolution: .unknown))
        XCTAssertNil(ContentRect.forImage(contentRect: nil,
                                          contentMargins: FloatRect(left: .infinity, top: 0, right: 10, bottom: 10),
                                          unit: .pixels, imageBounds: bounds, resolution: .unknown))
    }

    // MARK: - Défense en profondeur : détection

    func testHoughRejectsInvalidOrHugeParameters() {
        let image = GrayImage(width: 16, height: 16, fill: 255)
        XCTAssertThrowsError(try HoughSkewDetector.detect(maxAngle: .infinity, angleStep: 0.1,
                                                          threshold: 128, image: image))
        XCTAssertThrowsError(try HoughSkewDetector.detect(maxAngle: 1e9, angleStep: 0.1,
                                                          threshold: 128, image: image))
        XCTAssertThrowsError(try HoughSkewDetector.detect(maxAngle: 10, angleStep: 0,
                                                          threshold: 128, image: image))
        XCTAssertNoThrow(try HoughSkewDetector.detect(maxAngle: 10, angleStep: 0.1,
                                                      threshold: 128, image: image))
    }

    // MARK: - Pipeline (entrée non fiable -> erreur, pas de crash)

    func testPipelineRejectsHugeMaxAngle() {
        let image = PixelImage.gray(GrayImage(width: 16, height: 16, fill: 255))
        var options = DeskewOptions()
        _ = options.parse(["in.png"])
        options.maxAngle = .infinity
        XCTAssertThrowsError(try Pipeline.run(input: image, resolution: .unknown, options: options))
    }

    // MARK: - Chargement d'image (bornes)

    func testImageLoaderLimitsAreSane() {
        XCTAssertGreaterThan(ImageLoader.maxPixels, 50_000_000)
        XCTAssertLessThanOrEqual(ImageLoader.maxPixels, 1_000_000_000)
        XCTAssertGreaterThan(ImageLoader.maxDimension, 10_000)
    }
}
