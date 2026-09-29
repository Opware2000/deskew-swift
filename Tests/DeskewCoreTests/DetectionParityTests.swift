import XCTest
import DeskewCore
import DeskewImageIO

/// Tests de parité de la détection d'inclinaison contre les golden files
/// (produits par le binaire Pascal d'origine).
final class DetectionParityTests: XCTestCase {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DeskewCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // racine du dépôt

    static let reference = root.appendingPathComponent("Tests/DeskewParityTests/reference")

    struct GoldenCase {
        let name: String
        let angle: Double
    }

    private func loadGoldenCases() throws -> [GoldenCase] {
        let summary = Self.reference.appendingPathComponent("summary.txt")
        guard FileManager.default.fileExists(atPath: summary.path) else {
            throw XCTSkip("Golden files absents : \(summary.path)")
        }
        let content = try String(contentsOf: summary, encoding: .utf8)
        var cases: [GoldenCase] = []
        for line in content.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ")
            guard columns.count >= 3 else { continue }
            let name = String(columns[0])
            guard name.hasPrefix("detect-") else { continue }
            let angle = Double(columns[2]) ?? .nan
            cases.append(GoldenCase(name: name, angle: angle))
        }
        return cases
    }

    private func args(forCase name: String) throws -> [String] {
        let cmd = Self.reference.appendingPathComponent(name).appendingPathComponent("cmd.txt")
        let text = try String(contentsOf: cmd, encoding: .utf8)
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" })
            .map(String.init)
    }

    /// Statistiques attendues, extraites de la sortie console golden.
    private func expectedStats(forCase name: String) throws -> [String: Int] {
        let stdout = Self.reference.appendingPathComponent(name).appendingPathComponent("stdout.txt")
        let text = try String(contentsOf: stdout, encoding: .utf8)
        let labels = ["pixel count:", "tested pixels:", "accumulator size:",
                      "accumulated counts:", "best count:"]
        var result: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            for label in labels where line.contains(label) {
                let digits = line.filter { $0.isNumber }
                if let value = Int(digits) { result[label] = value }
            }
        }
        return result
    }

    func testDetectionParityAgainstGolden() throws {
        let cases = try loadGoldenCases()
        XCTAssertFalse(cases.isEmpty, "aucun cas de détection golden")

        for golden in cases {
            let args = try args(forCase: golden.name)

            var options = DeskewOptions()
            XCTAssertTrue(options.parse(args), "\(golden.name): parsing échoué \(options.errorMessage)")

            guard let inputName = options.inputFileName else {
                XCTFail("\(golden.name): pas de fichier d'entrée")
                continue
            }
            let inputPath = Self.root.appendingPathComponent(inputName).path
            let loaded = try ImageLoader.load(path: inputPath)
            let gray = loaded.toGray()

            let contentRect = ContentRect.forImage(
                contentRect: options.contentRect,
                contentMargins: options.contentMargins,
                unit: options.contentSizeUnit,
                imageBounds: gray.bounds,
                resolution: loaded.resolution)

            let threshold: Int
            if options.thresholdingMethod == .explicit {
                threshold = options.thresholdLevel
            } else {
                threshold = Otsu.threshold(image: gray, rect: contentRect)
            }

            let result = HoughSkewDetector.detect(
                maxAngle: options.maxAngle,
                angleStep: options.angleStep,
                threshold: threshold,
                image: gray,
                detectionArea: contentRect)

            XCTAssertEqual(result.angle, golden.angle, accuracy: 0.05,
                           "\(golden.name): angle détecté \(result.angle), attendu \(golden.angle)")

            let expected = try expectedStats(forCase: golden.name)
            XCTAssertEqual(result.stats.pixelCount, expected["pixel count:"], "\(golden.name): pixel count")
            XCTAssertEqual(result.stats.accumulatorSize, expected["accumulator size:"], "\(golden.name): accumulator size")

            // Les statistiques dépendant des pixels peuvent varier d'une unité
            // pour les JPEG : les décodeurs (ImageIO vs libjpeg d'Imaging) ne
            // produisent pas exactement les mêmes valeurs (compression lossy).
            func assertClose(_ actual: Int, _ key: String, _ tolerance: Double = 0.001) {
                guard let expectedValue = expected[key] else {
                    XCTFail("\(golden.name): statistique absente \(key)")
                    return
                }
                let allowed = max(1, Int(Double(expectedValue) * tolerance))
                XCTAssertLessThanOrEqual(abs(actual - expectedValue), allowed,
                                         "\(golden.name): \(key) = \(actual), attendu \(expectedValue)")
            }
            assertClose(result.stats.testedPixels, "tested pixels:")
            assertClose(result.stats.accumulatedCounts, "accumulated counts:")
            assertClose(result.stats.bestCount, "best count:")
        }
    }
}
