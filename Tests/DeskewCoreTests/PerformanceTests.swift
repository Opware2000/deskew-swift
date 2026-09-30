import XCTest
import Dispatch
@testable import DeskewCore

/// Garde-fou de performance.
///
/// On n'utilise **pas** de seuil absolu (fragile : la vitesse de la machine CI
/// varie). On vérifie la **mise à l'échelle** : doubler le nombre de pixels doit
/// environ doubler le temps. Une régression algorithmique (O(n²), parallélisme
/// cassé) ferait exploser ce ratio.
final class PerformanceTests: XCTestCase {

    private func makeTextImage(width: Int, height: Int) -> GrayImage {
        var image = GrayImage(width: width, height: height, fill: 255)
        for row in stride(from: 10, to: height - 4, by: 12) {
            for x in 6..<(width - 6) where (x / 5) % 3 != 0 {
                image[x, row] = 0
                image[x, row + 1] = 0
            }
        }
        return image
    }

    private func minSeconds(_ repetitions: Int, _ body: () -> Void) -> Double {
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<repetitions {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            best = min(best, elapsed)
        }
        return best
    }

    func testDetectionScalesLinearly() throws {
        // 2× de pixels (1 M -> 2 M)
        let small = makeTextImage(width: 1000, height: 1000)
        let large = makeTextImage(width: 2000, height: 1000)

        let tSmall = minSeconds(5) {
            _ = try? HoughSkewDetector.detect(maxAngle: 10, angleStep: 0.1, threshold: 128, image: small)
        }
        let tLarge = minSeconds(5) {
            _ = try? HoughSkewDetector.detect(maxAngle: 10, angleStep: 0.1, threshold: 128, image: large)
        }
        let ratio = tLarge / max(tSmall, 1e-6)
        print("PERF détection : petit=\(tSmall)s grand=\(tLarge)s ratio=\(ratio)")
        XCTAssertLessThan(ratio, 3.5, "détection : mise à l'échelle non linéaire (\(ratio))")
        XCTAssertLessThan(tLarge, 10.0, "détection : trop lente (\(tLarge)s)")
    }

    func testRotationScalesLinearly() {
        // 2× de pixels (1 M -> 2 M)
        let small = makeTextImage(width: 1000, height: 1000)
        let large = makeTextImage(width: 2000, height: 1000)

        func rotate(_ image: GrayImage) {
            var copy = image
            ImageRotation.rotate(&copy, angleDegrees: 3.0, background: .opaqueBlack,
                                 filter: .cubic, fitRotated: true)
        }

        let tSmall = minSeconds(5) { rotate(small) }
        let tLarge = minSeconds(5) { rotate(large) }
        let ratio = tLarge / max(tSmall, 1e-6)
        print("PERF rotation cubic : petit=\(tSmall)s grand=\(tLarge)s ratio=\(ratio)")
        XCTAssertLessThan(ratio, 3.5, "rotation : mise à l'échelle non linéaire (\(ratio))")
        XCTAssertLessThan(tLarge, 20.0, "rotation : trop lente (\(tLarge)s)")
    }

    /// Le filtre `nearest` doit rester bien plus rapide que `cubic`
    /// (détecte un effondrement du chemin rapide).
    func testNearestIsFasterThanCubic() {
        let image = makeTextImage(width: 1000, height: 1000)
        func rotate(_ filter: ResamplingFilter) {
            var copy = image
            ImageRotation.rotate(&copy, angleDegrees: 4.0, background: .opaqueBlack,
                                 filter: filter, fitRotated: true)
        }
        let tNearest = minSeconds(3) { rotate(.nearest) }
        let tCubic = minSeconds(3) { rotate(.cubic) }
        print("PERF nearest=\(tNearest)s cubic=\(tCubic)s")
        XCTAssertLessThan(tNearest, tCubic, "nearest devrait être plus rapide que cubic")
    }
}
