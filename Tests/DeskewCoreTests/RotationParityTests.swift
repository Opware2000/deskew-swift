import XCTest
import DeskewCore
import DeskewImageIO

/// Tests de parité des images de sortie (rotation) contre les golden files.
final class RotationParityTests: XCTestCase {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let reference = root.appendingPathComponent("Tests/DeskewParityTests/reference")

    struct Case {
        let name: String
        let ext: String
        let args: [String]
    }

    private func loadCases() throws -> [Case] {
        let index = Self.reference.appendingPathComponent("index.tsv")
        guard FileManager.default.fileExists(atPath: index.path) else {
            throw XCTSkip("Golden files absents : \(index.path)")
        }
        let content = try String(contentsOf: index, encoding: .utf8)
        var cases: [Case] = []
        for line in content.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 3 else { continue }
            let name = columns[0]
            guard !name.hasPrefix("detect-"), !name.hasPrefix("work-") else { continue }
            let ext = columns[1]
            guard ext != "none" else { continue }
            let args = columns[2].split(whereSeparator: { $0 == " " || $0 == "\n" })
                .map(String.init)
            cases.append(Case(name: name, ext: ext, args: args))
        }
        return cases
    }

    private func rgbBuffer(_ image: PixelImage) -> (Int, Int, [UInt8]) {
        switch image {
        case .rgb(let rgb):
            return (rgb.width, rgb.height, rgb.pixels)
        case .gray(let gray):
            var out = [UInt8](repeating: 0, count: gray.width * gray.height * 3)
            for i in 0..<(gray.width * gray.height) {
                let v = gray.pixels[i]
                out[i * 3] = v; out[i * 3 + 1] = v; out[i * 3 + 2] = v
            }
            return (gray.width, gray.height, out)
        case .rgba(let rgba):
            var out = [UInt8](repeating: 0, count: rgba.width * rgba.height * 3)
            for i in 0..<(rgba.width * rgba.height) {
                out[i * 3] = rgba.pixels[i * 4 + 2]
                out[i * 3 + 1] = rgba.pixels[i * 4 + 1]
                out[i * 3 + 2] = rgba.pixels[i * 4]
            }
            return (rgba.width, rgba.height, out)
        }
    }

    func testRotationParityAgainstGolden() throws {
        var cases = try loadCases()
        if let filter = ProcessInfo.processInfo.environment["PARITY_FILTER"], !filter.isEmpty {
            cases = cases.filter { $0.name.contains(filter) }
        }
        XCTAssertFalse(cases.isEmpty, "aucun cas de rotation golden")

        for testCase in cases {
            var options = DeskewOptions()
            XCTAssertTrue(options.parse(testCase.args), "\(testCase.name): parsing")

            guard let inputName = options.inputFileName,
                  let outputName = options.outputFileName else {
                XCTFail("\(testCase.name): noms manquants")
                continue
            }

            let loaded = try ImageLoader.load(path: Self.root.appendingPathComponent(inputName).path)
            let result = try Pipeline.run(input: loaded.image, resolution: loaded.resolution, options: options)

            guard let output = result.outputImage else {
                XCTFail("\(testCase.name): pas d'image de sortie")
                continue
            }

            let temp = NSTemporaryDirectory() + "deskew-parity-\(testCase.name).\(testCase.ext)"
            try ImageWriter.save(output, to: temp,
                                 options: ImageWriteOptions(jpegQuality: options.jpegCompressionQuality,
                                                            tiffCompression: options.tiffCompression,
                                                            resolution: loaded.resolution))
            let produced = try ImageLoader.load(path: temp).image
            let golden = try ImageLoader.load(
                path: Self.reference.appendingPathComponent(testCase.name)
                    .appendingPathComponent("out.\(testCase.ext)").path).image

            let (pw, ph, pbuf) = rgbBuffer(produced)
            let (gw, gh, gbuf) = rgbBuffer(golden)

            XCTAssertEqual(pw, gw, "\(testCase.name): largeur")
            XCTAssertEqual(ph, gh, "\(testCase.name): hauteur")
            guard pw == gw, ph == gh else { continue }

            var maxDiff = 0
            var sumDiff = 0
            var count = 0
            var outliers = 0
            for y in 0..<ph {
                for x in 0..<pw {
                    for c in 0..<3 {
                        let i = (y * pw + x) * 3 + c
                        let diff = abs(Int(pbuf[i]) - Int(gbuf[i]))
                        if diff > maxDiff { maxDiff = diff }
                        if diff > 8 { outliers += 1 }
                        sumDiff += diff
                        count += 1
                    }
                }
            }
            let meanDiff = count > 0 ? Double(sumDiff) / Double(count) : 0
            let outlierFraction = count > 0 ? Double(outliers) / Double(count) : 0

            if options.resamplingFilter == .nearest {
                // Le Pascal d'origine lit hors du buffer au bord droit/bas après
                // `Round()` (comportement indéfini) ; notre implémentation borne
                // l'indice. Seuls quelques pixels de bord divergent : on tolère
                // une fraction infime de valeurs aberrantes.
                XCTAssertLessThanOrEqual(outlierFraction, 0.005,
                                         "\(testCase.name): fraction aberrante \(outlierFraction) (max \(maxDiff))")
            } else {
                let lossy = testCase.ext == "jpg" || testCase.ext == "jpeg"
                XCTAssertLessThanOrEqual(maxDiff, lossy ? 48 : 3,
                                         "\(testCase.name): écart max \(maxDiff) (moyenne \(meanDiff))")
                XCTAssertLessThanOrEqual(meanDiff, lossy ? 4.0 : 0.5,
                                         "\(testCase.name): écart moyen \(meanDiff) (max \(maxDiff))")
            }
        }
    }
}
