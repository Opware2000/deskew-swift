import XCTest
import ImageIO
import DeskewCore
import DeskewImageIO

/// Parité de **format de fichier** (profondeur de bits, compression TIFF) entre la
/// sortie Swift et les golden files. Complète `RotationParityTests`, qui ne compare
/// que les pixels et masquait donc une sortie 8 bits là où l'original produit 1 bit.
final class FormatParityTests: XCTestCase {

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
            throw XCTSkip("golden files absents")
        }
        let content = try String(contentsOf: index, encoding: .utf8)
        var cases: [Case] = []
        for line in content.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 3, columns[1] != "none" else { continue }
            guard !columns[0].hasPrefix("detect-"), !columns[0].hasPrefix("work-") else { continue }
            let args = columns[2].split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            cases.append(Case(name: columns[0], ext: columns[1], args: args))
        }
        return cases
    }

    /// `(profondeur de bits par échantillon, compression TIFF)` d'un fichier.
    private func formatInfo(_ path: String) -> (bits: Int?, compression: Int?) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (nil, nil)
        }
        let bits = properties[kCGImagePropertyDepth] as? Int
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let compression = tiff?[kCGImagePropertyTIFFCompression] as? Int
        return (bits, compression)
    }

    func testOutputFormatMatchesGolden() throws {
        var cases = try loadCases()
        if let filter = ProcessInfo.processInfo.environment["PARITY_FILTER"], !filter.isEmpty {
            cases = cases.filter { $0.name.contains(filter) }
        }
        XCTAssertFalse(cases.isEmpty)

        for testCase in cases {
            var options = DeskewOptions()
            XCTAssertTrue(options.parse(testCase.args), "\(testCase.name): parsing")

            guard let inputName = options.inputFileName,
                  let outputName = options.outputFileName else {
                XCTFail("\(testCase.name): noms manquants"); continue
            }

            let loaded = try ImageLoader.load(path: Self.root.appendingPathComponent(inputName).path)
            let result = try Pipeline.run(input: loaded.image, resolution: loaded.resolution,
                                          options: options,
                                          inputTiffCompression: loaded.tiffCompression)
            guard let output = result.outputImage else {
                XCTFail("\(testCase.name): pas de sortie"); continue
            }

            let temp = NSTemporaryDirectory() + "deskew-fmt-\(testCase.name).\(testCase.ext)"
            let sameExtension = FilePath.fileExt(inputName).lowercased() == testCase.ext.lowercased()
            if !result.changed && sameExtension {
                // La CLI copie le fichier d'entrée tel quel (aucun ré-encodage).
                let inputPath = Self.root.appendingPathComponent(inputName).path
                try? FileManager.default.removeItem(atPath: temp)
                try FileManager.default.copyItem(atPath: inputPath, toPath: temp)
            } else {
                try ImageWriter.save(output, to: temp,
                                     options: ImageWriteOptions(jpegQuality: options.jpegCompressionQuality,
                                                                tiffCompression: result.resolvedTiffCompression,
                                                                resolution: loaded.resolution))
            }

            let produced = formatInfo(temp)
            let golden = formatInfo(Self.reference.appendingPathComponent(testCase.name)
                .appendingPathComponent("out.\(testCase.ext)").path)

            // La profondeur de bits doit toujours correspondre (1 bit pour binaire/G4).
            XCTAssertEqual(produced.bits, golden.bits, "\(testCase.name): profondeur de bits")
            // Compression TIFF : stricte dès que libtiff est disponible (contrôle exact).
            if testCase.ext == "tif", TiffWriter.isAvailable {
                // Deflate : 8 (Adobe) et 32946 (legacy) désignent le même codec.
                let producedCompression = [8, 32946].contains(produced.compression ?? -1)
                    ? 8 : produced.compression
                let goldenCompression = [8, 32946].contains(golden.compression ?? -1)
                    ? 8 : golden.compression
                XCTAssertEqual(producedCompression, goldenCompression,
                               "\(testCase.name): compression TIFF")
            }
        }
    }

    /// Cas binaires/G4 explicites : 1 bit par échantillon, TIFF G4 (tag 4).
    func testBinaryAndG4AreTrulyOneBit() throws {
        let checks: [(name: String, ext: String, compression: Int?)] = [
            ("rot-2-b1", "png", nil),
            ("rot-1-b1-tiff", "tif", 4),
            ("rot-1-g4-input", "tif", 4)
        ]
        for check in checks {
            let goldenPath = Self.reference.appendingPathComponent(check.name)
                .appendingPathComponent("out.\(check.ext)").path
            guard FileManager.default.fileExists(atPath: goldenPath) else { continue }

            var options = DeskewOptions()
            let args = try String(contentsOf: Self.reference.appendingPathComponent(check.name)
                .appendingPathComponent("cmd.txt"), encoding: .utf8)
                .split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            _ = options.parse(args)
            let loaded = try ImageLoader.load(path: Self.root.appendingPathComponent(options.inputFileName!).path)
            let result = try Pipeline.run(input: loaded.image, resolution: loaded.resolution,
                                          options: options, inputTiffCompression: loaded.tiffCompression)
            let temp = NSTemporaryDirectory() + "deskew-fmt-explicit-\(check.name).\(check.ext)"
            try ImageWriter.save(result.outputImage!, to: temp,
                                 options: ImageWriteOptions(tiffCompression: result.resolvedTiffCompression,
                                                            resolution: loaded.resolution))
            let info = formatInfo(temp)
            XCTAssertEqual(info.bits, 1, "\(check.name): doit être 1 bit")
            if let expected = check.compression {
                XCTAssertEqual(info.compression, expected, "\(check.name): compression TIFF")
            }
        }
    }
}
