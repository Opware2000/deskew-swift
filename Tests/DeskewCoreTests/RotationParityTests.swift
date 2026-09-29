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

    /// Buffer RGBA **prémultiplié** (les zones transparentes sont normalisées).
    private func rgbaBuffer(_ image: PixelImage) -> (Int, Int, [UInt8]) {
        switch image {
        case .gray(let gray):
            var out = [UInt8](repeating: 0, count: gray.width * gray.height * 4)
            for i in 0..<(gray.width * gray.height) {
                let v = gray.pixels[i]
                out[i * 4] = v; out[i * 4 + 1] = v; out[i * 4 + 2] = v; out[i * 4 + 3] = 255
            }
            return (gray.width, gray.height, out)
        case .rgb(let rgb):
            var out = [UInt8](repeating: 0, count: rgb.width * rgb.height * 4)
            for i in 0..<(rgb.width * rgb.height) {
                out[i * 4] = rgb.pixels[i * 3]
                out[i * 4 + 1] = rgb.pixels[i * 3 + 1]
                out[i * 4 + 2] = rgb.pixels[i * 3 + 2]
                out[i * 4 + 3] = 255
            }
            return (rgb.width, rgb.height, out)
        case .rgba(let rgba):
            var out = [UInt8](repeating: 0, count: rgba.width * rgba.height * 4)
            for i in 0..<(rgba.width * rgba.height) {
                let r = Int(rgba.pixels[i * 4 + 2])
                let g = Int(rgba.pixels[i * 4 + 1])
                let b = Int(rgba.pixels[i * 4])
                let a = Int(rgba.pixels[i * 4 + 3])
                out[i * 4] = UInt8(r * a / 255)
                out[i * 4 + 1] = UInt8(g * a / 255)
                out[i * 4 + 2] = UInt8(b * a / 255)
                out[i * 4 + 3] = UInt8(a)
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
            let result = try Pipeline.run(input: loaded.image, resolution: loaded.resolution,
                                          options: options,
                                          inputTiffCompression: loaded.tiffCompression)

            guard let output = result.outputImage else {
                XCTFail("\(testCase.name): pas d'image de sortie")
                continue
            }

            let temp = NSTemporaryDirectory() + "deskew-parity-\(testCase.name).\(testCase.ext)"
            try ImageWriter.save(output, to: temp,
                                 options: ImageWriteOptions(jpegQuality: options.jpegCompressionQuality,
                                                            tiffCompression: result.resolvedTiffCompression,
                                                            resolution: loaded.resolution))
            let produced = try ImageLoader.load(path: temp).image
            let golden = try ImageLoader.load(
                path: Self.reference.appendingPathComponent(testCase.name)
                    .appendingPathComponent("out.\(testCase.ext)").path).image

            let (pw, ph, pbuf) = rgbaBuffer(produced)
            let (gw, gh, gbuf) = rgbaBuffer(golden)

            XCTAssertEqual(pw, gw, "\(testCase.name): largeur")
            XCTAssertEqual(ph, gh, "\(testCase.name): hauteur")
            guard pw == gw, ph == gh else { continue }

            var maxDiff = 0
            var sumDiff = 0
            var count = 0
            var outliers = 0
            for i in 0..<pbuf.count {
                let diff = abs(Int(pbuf[i]) - Int(gbuf[i]))
                if diff > maxDiff { maxDiff = diff }
                if diff > 8 { outliers += 1 }
                sumDiff += diff
                count += 1
            }
            let meanDiff = count > 0 ? Double(sumDiff) / Double(count) : 0
            let outlierFraction = count > 0 ? Double(outliers) / Double(count) : 0

            // Perte due au ré-encodage JPEG (fichiers .jpg ou TIFF compressé JPEG).
            let lossy = testCase.ext == "jpg" || testCase.ext == "jpeg"
                || options.tiffCompression == .jpeg
                || inputName.contains("tiff-jpeg")
            let binaryOutput = options.forcedOutputFormat == .binary
                || result.resolvedTiffCompression == .g4

            if options.resamplingFilter == .nearest {
                // Le Pascal d'origine lit hors du buffer au bord droit/bas après
                // `Round()` (comportement indéfini) ; notre implémentation borne
                // l'indice. Seuls quelques pixels de bord divergent.
                XCTAssertLessThanOrEqual(outlierFraction, 0.005,
                                         "\(testCase.name): fraction aberrante \(outlierFraction) (max \(maxDiff))")
            } else if lossy {
                XCTAssertLessThanOrEqual(meanDiff, 4.0,
                                         "\(testCase.name): écart moyen \(meanDiff) (max \(maxDiff))")
            } else if binaryOutput {
                // Sortie binaire : quelques pixels pile au seuil (128) peuvent
                // basculer selon l'arrondi de l'interpolation.
                XCTAssertLessThanOrEqual(outlierFraction, 0.005,
                                         "\(testCase.name): fraction aberrante \(outlierFraction) (max \(maxDiff))")
            } else {
                XCTAssertLessThanOrEqual(maxDiff, 3,
                                         "\(testCase.name): écart max \(maxDiff) (moyenne \(meanDiff))")
                XCTAssertLessThanOrEqual(meanDiff, 0.5,
                                         "\(testCase.name): écart moyen \(meanDiff) (max \(maxDiff))")
            }
        }
    }
}
