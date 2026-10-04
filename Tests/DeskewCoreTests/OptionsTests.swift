import XCTest
@testable import DeskewCore

/// Port de `Tests/TestCmdLineArgs.pas`.
final class OptionsTests: XCTestCase {

    private func parse(_ args: [String]) -> DeskewOptions {
        var options = DeskewOptions()
        _ = options.parse(args)
        return options
    }

    private func assertParseSuccess(_ options: DeskewOptions, _ message: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        let prefix = message.isEmpty ? "" : "\(message): "
        XCTAssertTrue(options.isValid, "\(prefix)IsValid, erreur: \(options.errorMessage)", file: file, line: line)
        XCTAssertEqual(options.errorMessage, "", "\(prefix)message d'erreur vide", file: file, line: line)
    }

    private func assertParseFailure(_ options: DeskewOptions, contains part: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(options.isValid, file: file, line: line)
        XCTAssertTrue(options.errorMessage.lowercased().contains(part.lowercased()),
                      "« \(part) » absent de « \(options.errorMessage) »", file: file, line: line)
    }

    // MARK: - Défauts

    func testDefaults() {
        let o = DeskewOptions()
        XCTAssertEqual(o.maxAngle, DeskewOptions.defaultMaxAngle)
        XCTAssertEqual(o.skipAngle, DeskewOptions.defaultSkipAngle)
        XCTAssertEqual(o.thresholdLevel, DeskewOptions.defaultThreshold)
        XCTAssertEqual(o.thresholdingMethod, .otsu)
        XCTAssertEqual(o.resamplingFilter, .linear)
        XCTAssertEqual(o.backgroundColor.color32, 0xFF00_0000)
        XCTAssertNil(o.forcedOutputFormat)
        XCTAssertEqual(o.dpiOverride, 0)
        XCTAssertNil(o.jpegCompressionQuality)
        XCTAssertNil(o.tiffCompression)
        XCTAssertFalse(o.cropToInput)
        XCTAssertFalse(o.detectOnly)
        XCTAssertNil(o.inputFileName)
        XCTAssertNil(o.outputFileName)
        XCTAssertEqual(o.errorMessage, "")
        XCTAssertFalse(o.showDetectionStats)
        XCTAssertFalse(o.showParams)
        XCTAssertFalse(o.showTimings)
        XCTAssertFalse(o.saveImageWork())
        XCTAssertFalse(o.isValid)
    }

    // MARK: - Parsing de base

    func testUnknownParameter() {
        assertParseFailure(parse(["-z", "123", "in.jpg"]), contains: "Unknown parameter: -z")
        assertParseFailure(parse(["-A", "123", "in.jpg"]), contains: "Unknown parameter: -A")
    }

    func testMissingValue() {
        assertParseFailure(parse(["in.jpg", "-a"]), contains: "Missing value for parameter: -a")
    }

    func testParamAfterInput() {
        assertParseSuccess(parse(["in.jpg", "-a", "1"]), "Param après l'entrée")
    }

    func testInputOnly() {
        var o = parse(["input.jpg"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.inputFileName, "input.jpg")
        XCTAssertEqual(o.outputFileName, "deskewed-input.png")

        o = parse(["\"input with space.png\""])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.inputFileName, "\"input with space.png\"")

        assertParseFailure(parse(["-o", "out.png"]), contains: "No input file given")
        assertParseFailure(parse(["in1.png", "in2.png"]),
                           contains: "Multiple input files specified (in2.png, in1.png)")
    }

    func testInputOutput() {
        var o = parse(["-o", "output.tif", "input.jpg"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.inputFileName, "input.jpg")
        XCTAssertEqual(o.outputFileName, "output.tif")

        o = parse(["-o", "../dir/output.tif", "../other-dir/input.jpg"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.inputFileName, "../other-dir/input.jpg")
        XCTAssertEqual(o.outputFileName, "../dir/output.tif")
    }

    // MARK: - Options numériques

    func testMaxAngle() {
        let o = parse(["-a", "5.7", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.maxAngle, 5.7, accuracy: 1e-12)
        assertParseFailure(parse(["-a", "not_a_number", "in.jpg"]),
                           contains: "Invalid value for max angle parameter: not_a_number")
    }

    func testAngleStep() {
        let o = parse(["-d", "0.01", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.angleStep, 0.01, accuracy: 1e-12)
    }

    func testSkipAngle() {
        let o = parse(["-l", "0.5", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.skipAngle, 0.5, accuracy: 1e-12)
    }

    func testDpiOverride() {
        let o = parse(["-p", "300", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.dpiOverride, 300)
    }

    // MARK: - Seuil, filtre, format

    func testThreshold() {
        var o = parse(["-t", "99", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.thresholdingMethod, .explicit)
        XCTAssertEqual(o.thresholdLevel, 99)

        o = parse(["-t", "a", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.thresholdingMethod, .otsu)

        assertParseFailure(parse(["-t", "x", "in.jpg"]),
                           contains: "Invalid value for treshold parameter: x")
        assertParseFailure(parse(["-t", "55.55", "in.jpg"]),
                           contains: "Invalid value for treshold parameter: 55.55")
    }

    func testResamplingFilter() {
        for filter in ResamplingFilter.allCases {
            let o = parse(["-q", filter.rawValue, "in.png"])
            XCTAssertTrue(o.isValid)
            XCTAssertEqual(o.resamplingFilter, filter)
        }
        assertParseFailure(parse(["-q", "ujo", "in.jpg"]),
                           contains: "Invalid value for resampling filter parameter: ujo")
    }

    func testOutputFormat() {
        let names: [(String, PixelFormat)] = [("b1", .binary), ("g8", .gray8),
                                              ("rgb24", .rgb24), ("rgba32", .rgba32)]
        for (name, format) in names {
            let o = parse(["-f", name, "in.png"])
            XCTAssertTrue(o.isValid)
            XCTAssertEqual(o.forcedOutputFormat, format)
        }
        assertParseFailure(parse(["-f", "g64", "in.jpg"]),
                           contains: "Invalid value for format parameter: g64")
    }

    // MARK: - Couleur de fond

    func testBackgroundColor() {
        let valid: [(String, UInt32)] = [
            ("FF8000", 0xFFFF_8000),
            ("C0", 0xFFC0_C0C0),
            ("8000FF80", 0x8000_FF80),
            ("1", 0xFF01_0101),
            ("FF80", 0xFF00_FF80),
            ("AFF0080", 0x0AFF_0080),
            ("0", 0xFF00_0000),
            ("00000000", 0x0000_0000)
        ]
        for (string, expected) in valid {
            let o = parse(["-b", string, "in.png"])
            XCTAssertTrue(o.isValid, "couleur \(string)")
            XCTAssertEqual(o.backgroundColor.color32, expected, "couleur \(string)")
        }

        for invalid in ["GGG", "white", "123456789", "-FF", "35.2", "0xff", "$ff", "#ff"] {
            assertParseFailure(parse(["-b", invalid, "in.jpg"]),
                               contains: "Invalid value for background color parameter: \(invalid)")
        }
    }

    // MARK: - Compression

    func testCompression() {
        var o = parse(["-c", "j85", "in.jpg"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.jpegCompressionQuality, 85)
        XCTAssertNil(o.tiffCompression)

        let tiffs: [(String, TiffCompression)] = [
            ("g4", .g4), ("rle", .rle), ("input", .input),
            ("input-lossless", .inputLossless), ("none", .none)
        ]
        for (name, expected) in tiffs {
            o = parse(["-c", "t" + name, "in.png"])
            XCTAssertTrue(o.isValid, "tiff \(name)")
            XCTAssertEqual(o.tiffCompression, expected)
            XCTAssertNil(o.jpegCompressionQuality)
        }

        o = parse(["-c", "j90,tDEFLATE", "in.jpg"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.jpegCompressionQuality, 90)
        XCTAssertEqual(o.tiffCompression, .deflate)

        o = parse(["-c", "tjpeg,j75", "in.jpg"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.jpegCompressionQuality, 75)
        XCTAssertEqual(o.tiffCompression, .jpeg)

        assertParseFailure(parse(["-c", "jABC", "in.jpg"]),
                           contains: "Invalid JPEG output compression spec: abc")
        assertParseFailure(parse(["-c", "j101", "in.jpg"]),
                           contains: "Invalid JPEG output compression spec: 101")
        assertParseFailure(parse(["-c", "tXYZ", "in.tif"]),
                           contains: "Invalid TIFF output compression spec: XYZ")
        assertParseFailure(parse(["-c", "x99", "in.png"]),
                           contains: "Invalid output compression parameter: x99")
        assertParseFailure(parse(["-c", "j80,tBAD", "in.png"]),
                           contains: "Invalid TIFF output compression spec: bad")
        assertParseFailure(parse(["-c", "j80,trle,tlzw", "in.png"]),
                           contains: "TIFF output compression already set but received: lzw")
        assertParseFailure(parse(["-c", "j80,trle,j99", "in.png"]),
                           contains: "JPEG output compression already set but received: 99")
    }

    // MARK: - Drapeaux

    func testOperationalFlags() {
        var o = parse(["-g", "cd", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertTrue(o.cropToInput)
        XCTAssertTrue(o.detectOnly)

        o = parse(["-g", "d", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertFalse(o.cropToInput)
        XCTAssertTrue(o.detectOnly)
    }

    func testInfoFlags() {
        var o = parse(["-s", "sptw", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertTrue(o.showDetectionStats)
        XCTAssertTrue(o.showParams)
        XCTAssertTrue(o.showTimings)
        XCTAssertTrue(o.saveImageWork())

        o = parse(["-s", "t", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertFalse(o.showDetectionStats)
        XCTAssertFalse(o.showParams)
        XCTAssertTrue(o.showTimings)
        XCTAssertFalse(o.saveImageWork())
    }

    // MARK: - Rectangle de contenu

    func testContentRect() {
        var o = parse(["-r", "10,20,190,80", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentRect, FloatRect(left: 10, top: 20, right: 190, bottom: 80))
        XCTAssertEqual(o.contentSizeUnit, .pixels)

        assertParseFailure(parse(["-r", "10", "in.png"]),
                           contains: "Invalid definition of content rectangle")
        assertParseFailure(parse(["-r", "1,1,1,1,1", "in.png"]),
                           contains: "Invalid definition of content rectangle")
        assertParseFailure(parse(["-r", "1,1,1,1,nm", "in.png"]),
                           contains: "Invalid definition of content rectangle")
        assertParseFailure(parse(["-r", "1,1,%", "in.png"]),
                           contains: "Invalid definition of content rectangle")

        o = parse(["-r", "0.1,0.2,19.0,8.5,%", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentRect, FloatRect(left: 0.1, top: 0.2, right: 19.0, bottom: 8.5))
        XCTAssertEqual(o.contentSizeUnit, .percent)

        XCTAssertEqual(parse(["-r", "0.13,0,190,80,cm", "in.png"]).contentSizeUnit, .cm)
        XCTAssertEqual(parse(["-r", "0,0,190,80,mm", "in.png"]).contentSizeUnit, .mm)
        XCTAssertEqual(parse(["-r", "0,0,190,80.731,in", "in.png"]).contentSizeUnit, .inch)
        XCTAssertEqual(parse(["-r", "0,0,190,80,px", "in.png"]).contentSizeUnit, .pixels)

        assertParseFailure(parse(["-m", "10", "-r", "10,10,100,100", "in.png"]),
                           contains: "Cannot accept content rectangle when content margins are already defined")
    }

    // MARK: - Marges de contenu

    func testContentMargins() {
        var o = parse(["-m", "100,120,140,80", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentMargins, FloatRect(left: 100, top: 120, right: 140, bottom: 80))
        XCTAssertEqual(o.contentSizeUnit, .pixels)

        o = parse(["-m", "10,12,14,8,mm", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentMargins, FloatRect(left: 10, top: 12, right: 14, bottom: 8))
        XCTAssertEqual(o.contentSizeUnit, .mm)

        o = parse(["-m", "100", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentMargins, FloatRect(left: 100, top: 100, right: 100, bottom: 100))

        o = parse(["-m", "15.5,%", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentMargins, FloatRect(left: 15.5, top: 15.5, right: 15.5, bottom: 15.5))
        XCTAssertEqual(o.contentSizeUnit, .percent)

        o = parse(["-m", "100, 200", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentMargins, FloatRect(left: 100, top: 200, right: 100, bottom: 200))

        o = parse(["-m", "1,2,cm", "in.png"])
        XCTAssertTrue(o.isValid)
        XCTAssertEqual(o.contentMargins, FloatRect(left: 1, top: 2, right: 1, bottom: 2))
        XCTAssertEqual(o.contentSizeUnit, .cm)

        assertParseFailure(parse(["-m", "1,1,1,1,1", "in.png"]),
                           contains: "Invalid definition of content margins")
        assertParseFailure(parse(["-m", "1,1,1", "in.png"]),
                           contains: "Invalid definition of content margins")
        assertParseFailure(parse(["-m", "1,1,xibalba", "in.png"]),
                           contains: "Invalid definition of content margins")
        assertParseFailure(parse(["-m", "mm,1,1", "in.png"]),
                           contains: "Invalid definition of content margins")
        assertParseFailure(parse(["-m", "1,1,1,1,1,in", "in.png"]),
                           contains: "Invalid definition of content margins")

        assertParseFailure(parse(["-r", "10,10,100,100", "-m", "10", "in.png"]),
                           contains: "Cannot accept content margins when content rectangle is already defined")
    }
}

private extension DeskewOptions {
    /// Petit helper de lisibilité pour les tests (le champ s'appelle saveWorkImage).
    func saveImageWork() -> Bool { saveWorkImage }
}
