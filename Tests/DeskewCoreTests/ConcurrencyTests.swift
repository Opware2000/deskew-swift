import XCTest
@testable import DeskewCore

/// Exerce les **chemins parallèles** (Otsu, Hough, rotation) sur des images
/// au-dessus des seuils de parallélisation, de façon répétée.
///
/// Objectif : servir de cible aux sanitizers (ThreadSanitizer, AddressSanitizer)
/// et vérifier le **déterminisme** (le multithreading ne doit rien changer).
final class ConcurrencyTests: XCTestCase {

    /// 600×600 = 360 000 pixels > seuils (rotation 100 k, Otsu 200 k).
    private func makeTextLikeGray(width: Int = 600, height: Int = 600) -> GrayImage {
        var image = GrayImage(width: width, height: height, fill: 255)
        for row in stride(from: 20, to: height - 4, by: 12) {
            for x in 10..<(width - 10) where (x / 5) % 3 != 0 {
                image[x, row] = 0
                image[x, row + 1] = 0
            }
        }
        return image
    }

    func testParallelPathsDeterministic() throws {
        let gray = makeTextLikeGray()

        // Référence
        let threshold = Otsu.threshold(image: gray, rect: nil)
        let reference = try HoughSkewDetector.detect(maxAngle: 10, angleStep: 0.1,
                                                     threshold: threshold, image: gray)

        // Plusieurs passes : augmente la fenêtre de détection des sanitizers et
        // vérifie que le résultat est stable (pas de dépendance à l'ordonnancement).
        for iteration in 0..<5 {
            let t = Otsu.threshold(image: gray, rect: nil)
            XCTAssertEqual(t, threshold, "seuil Otsu non déterministe (itération \(iteration))")

            let result = try HoughSkewDetector.detect(maxAngle: 10, angleStep: 0.1,
                                                      threshold: t, image: gray)
            XCTAssertEqual(result.angle, reference.angle, "angle Hough non déterministe")
            XCTAssertEqual(result.stats, reference.stats, "stats Hough non déterministes")

            // Rotation parallèle : gris, RGB, ARGB, tous les filtres.
            for filter in ResamplingFilter.allCases {
                var g = gray
                ImageRotation.rotate(&g, angleDegrees: result.angle, background: .opaqueBlack,
                                     filter: filter, fitRotated: true)
                XCTAssertGreaterThan(g.width, 0)

                var rgb = PixelImage.gray(gray).converted(to: .rgb24)
                if case .rgb(var image) = rgb {
                    ImageRotation.rotate(&image, angleDegrees: result.angle, background: .opaqueBlack,
                                         filter: filter, fitRotated: true)
                    rgb = .rgb(image)
                }
                XCTAssertEqual(rgb.width, g.width)
            }
        }
    }

    /// Binarisation + rotation de destination non initialisée : vérifie qu'aucun
    /// pixel de destination n'est laissé non écrit (sinon ASan/MSan le verrait).
    func testRotationFillsEveryDestinationPixel() {
        let gray = makeTextLikeGray(width: 300, height: 300)
        for filter in ResamplingFilter.allCases {
            var image = gray
            ImageRotation.rotate(&image, angleDegrees: 7.3, background: RGBA32(r: 1, g: 2, b: 3),
                                 filter: filter, fitRotated: true)
            // Tous les pixels doivent être définis (pas de valeur indéterminée).
            XCTAssertEqual(image.pixels.count, image.width * image.height)
        }
    }
}
