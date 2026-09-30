import XCTest
import ImageIO
import DeskewCore
import DeskewImageIO

/// Tests d'entrées-sorties ImageIO : palettes, round-trip, compression TIFF.
final class ImageIOTests: XCTestCase {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let testImages = [
        "1big.png", "2.png", "3.png", "4.png", "5.png", "6.png",
        "F1550.jpg", "1-lzw.tif", "1-g4.tif", "tiff-jpeg.tif"
    ]

    private func inputPath(_ name: String) -> String {
        Self.root.appendingPathComponent("TestImages").appendingPathComponent(name).path
    }

    private func tempPath(_ name: String) -> String {
        NSTemporaryDirectory() + "deskew-io-\(name)"
    }

    /// Buffer RGBA prémultiplié, pour comparer des images de formats différents.
    private func rgba(_ image: PixelImage) -> (Int, Int, [UInt8]) {
        switch image {
        case .binary(let binary):
            let gray = binary.toGray()
            var out = [UInt8](repeating: 0, count: gray.width * gray.height * 4)
            for i in 0..<(gray.width * gray.height) {
                let v = gray.pixels[i]
                out[i * 4] = v; out[i * 4 + 1] = v; out[i * 4 + 2] = v; out[i * 4 + 3] = 255
            }
            return (gray.width, gray.height, out)
        case .gray(let g):
            var out = [UInt8](repeating: 0, count: g.width * g.height * 4)
            for i in 0..<(g.width * g.height) {
                out[i * 4] = g.pixels[i]; out[i * 4 + 1] = g.pixels[i]
                out[i * 4 + 2] = g.pixels[i]; out[i * 4 + 3] = 255
            }
            return (g.width, g.height, out)
        case .rgb(let r):
            var out = [UInt8](repeating: 0, count: r.width * r.height * 4)
            for i in 0..<(r.width * r.height) {
                out[i * 4] = r.pixels[i * 3]; out[i * 4 + 1] = r.pixels[i * 3 + 1]
                out[i * 4 + 2] = r.pixels[i * 3 + 2]; out[i * 4 + 3] = 255
            }
            return (r.width, r.height, out)
        case .rgba(let a):
            var out = [UInt8](repeating: 0, count: a.width * a.height * 4)
            for i in 0..<(a.width * a.height) {
                let r = Int(a.pixels[i * 4 + 2]), g = Int(a.pixels[i * 4 + 1])
                let b = Int(a.pixels[i * 4]), al = Int(a.pixels[i * 4 + 3])
                out[i * 4] = UInt8(r * al / 255); out[i * 4 + 1] = UInt8(g * al / 255)
                out[i * 4 + 2] = UInt8(b * al / 255); out[i * 4 + 3] = UInt8(al)
            }
            return (a.width, a.height, out)
        }
    }

    private func assertImagesClose(_ a: PixelImage, _ b: PixelImage, maxDiff: Int, meanDiff: Double,
                                   _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let (aw, ah, abuf) = rgba(a)
        let (bw, bh, bbuf) = rgba(b)
        XCTAssertEqual(aw, bw, "\(message): largeur", file: file, line: line)
        XCTAssertEqual(ah, bh, "\(message): hauteur", file: file, line: line)
        guard aw == bw, ah == bh else { return }
        var maxSeen = 0
        var sum = 0
        for i in 0..<abuf.count {
            let d = abs(Int(abuf[i]) - Int(bbuf[i]))
            if d > maxSeen { maxSeen = d }
            sum += d
        }
        let mean = Double(sum) / Double(abuf.count)
        XCTAssertLessThanOrEqual(maxSeen, maxDiff, "\(message): écart max \(maxSeen)", file: file, line: line)
        XCTAssertLessThanOrEqual(mean, meanDiff, "\(message): écart moyen \(mean)", file: file, line: line)
    }

    // MARK: - Palettes

    func testPaletteHasAlpha() {
        let opaque = Palette(entries: [RGBA32(r: 0, g: 0, b: 0), RGBA32(r: 255, g: 255, b: 255)])
        XCTAssertFalse(opaque.hasAlpha)
        let withAlpha = Palette(entries: [RGBA32(r: 0, g: 0, b: 0), RGBA32(r: 1, g: 2, b: 3, a: 128)])
        XCTAssertTrue(withAlpha.hasAlpha)
    }

    func testPaletteIsGrayScale() {
        let gray = Palette(entries: [RGBA32(r: 0, g: 0, b: 0), RGBA32(r: 128, g: 128, b: 128)])
        XCTAssertTrue(gray.isGrayScale)
        let color = Palette(entries: [RGBA32(r: 255, g: 0, b: 0)])
        XCTAssertFalse(color.isGrayScale)
    }

    func testRotationFormatFromPalette() {
        let black = RGBA32.opaqueBlack
        XCTAssertEqual(PixelFormat.rotationFormat(palette: Palette(entries: [RGBA32(r: 0, g: 0, b: 0)]),
                                                  background: black), .gray8)
        XCTAssertEqual(PixelFormat.rotationFormat(palette: Palette(entries: [RGBA32(r: 255, g: 0, b: 0)]),
                                                  background: black), .rgb24)
        XCTAssertEqual(PixelFormat.rotationFormat(palette: Palette(entries: [RGBA32(r: 0, g: 0, b: 0, a: 100)]),
                                                  background: black), .rgba32)
        // Fond non gris sur une palette grise -> RGB24
        XCTAssertEqual(PixelFormat.rotationFormat(palette: Palette(entries: [RGBA32(r: 0, g: 0, b: 0)]),
                                                  background: RGBA32(r: 0, g: 255, b: 255)), .rgb24)
        // Fond avec alpha -> ARGB32
        XCTAssertEqual(PixelFormat.rotationFormat(palette: Palette(entries: [RGBA32(r: 0, g: 0, b: 0)]),
                                                  background: RGBA32(r: 0, g: 0, b: 0, a: 64)), .rgba32)
    }

    // MARK: - Chargement

    func testLoadAllTestImages() throws {
        for name in Self.testImages {
            let loaded = try ImageLoader.load(path: inputPath(name))
            XCTAssertGreaterThan(loaded.width, 0, "\(name): largeur")
            XCTAssertGreaterThan(loaded.height, 0, "\(name): hauteur")
        }
    }

    // MARK: - Round-trip

    func testPNGRoundTripLossless() throws {
        for name in Self.testImages {
            let loaded = try ImageLoader.load(path: inputPath(name))
            let out = tempPath("rt-\(name).png")
            try ImageWriter.save(loaded.image, to: out,
                                 options: ImageWriteOptions(resolution: loaded.resolution))
            let reloaded = try ImageLoader.load(path: out)
            assertImagesClose(loaded.image, reloaded.image, maxDiff: 0, meanDiff: 0, "\(name) png")
        }
    }

    func testTIFFRoundTripLossless() throws {
        for name in Self.testImages where !name.hasSuffix(".jpg") {
            let loaded = try ImageLoader.load(path: inputPath(name))
            let out = tempPath("rt-\(name).tif")
            try ImageWriter.save(loaded.image, to: out,
                                 options: ImageWriteOptions(tiffCompression: .lzw,
                                                            resolution: loaded.resolution))
            let reloaded = try ImageLoader.load(path: out)
            assertImagesClose(loaded.image, reloaded.image, maxDiff: 0, meanDiff: 0, "\(name) tif")
        }
    }

    func testJPEGRoundTrip() throws {
        let loaded = try ImageLoader.load(path: inputPath("F1550.jpg"))
        let out = tempPath("rt.jpg")
        try ImageWriter.save(loaded.image, to: out,
                             options: ImageWriteOptions(jpegQuality: 95, resolution: loaded.resolution))
        let reloaded = try ImageLoader.load(path: out)
        assertImagesClose(loaded.image, reloaded.image, maxDiff: 64, meanDiff: 3.0, "F1550 jpeg")
    }

    func testDPIPreservation() throws {
        let image = PixelImage.gray(GrayImage(width: 16, height: 16, fill: 128))
        let resolution = ResolutionInfo.from(dpiX: 300, dpiY: 300)
        let out = tempPath("dpi.png")
        try ImageWriter.save(image, to: out, options: ImageWriteOptions(resolution: resolution))

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: out)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return XCTFail("impossible de relire les propriétés")
        }
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 300)
        XCTAssertEqual((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.intValue, 300)
    }

    // MARK: - Compression TIFF

    func testTIFFCompressionSchemes() throws {
        // Image en niveaux de gris pour les schémas lossless.
        let gray = PixelImage.gray(GrayImage(width: 32, height: 32, fill: 200))

        for scheme in [TiffCompression.none, .lzw, .deflate, .rle] {
            let out = tempPath("comp-\(scheme.rawValue).tif")
            try ImageWriter.save(gray, to: out,
                                 options: ImageWriteOptions(tiffCompression: scheme))
            let reloaded = try ImageLoader.load(path: out)
            assertImagesClose(gray, reloaded.image, maxDiff: 0, meanDiff: 0, "tiff \(scheme.rawValue)")
        }
    }

    func testTIFFCompressionTagWritten() throws {
        let gray = PixelImage.gray(GrayImage(width: 16, height: 16, fill: 100))
        let out = tempPath("tag-lzw.tif")
        try ImageWriter.save(gray, to: out, options: ImageWriteOptions(tiffCompression: .lzw))

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: out)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] else {
            return XCTFail("propriétés TIFF absentes")
        }
        let compression = (tiff[kCGImagePropertyTIFFCompression] as? NSNumber)?.intValue
        XCTAssertEqual(compression, 5, "compression LZW attendue")
    }

    /// Le DPI forcé (`-p`) doit être appliqué à la **sortie** (issue #1).
    func testDPIOverrideAppliedToOutput() throws {
        var options = DeskewOptions()
        _ = options.parse(["-p", "300", "in.png"])
        let image = PixelImage.gray(GrayImage(width: 16, height: 16, fill: 255))
        let result = try Pipeline.run(input: image, resolution: .unknown, options: options)

        XCTAssertEqual(result.resolvedResolution.physicalPixelSize(.dpi)?.x ?? 0, 300, accuracy: 1e-6)

        let out = tempPath("dpi-override.png")
        try ImageWriter.save(result.outputImage!, to: out,
                             options: ImageWriteOptions(resolution: result.resolvedResolution))
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: out)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return XCTFail("propriétés absentes")
        }
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 300)
    }

    /// TIFF RGBA avec compression contrôlée (issue #7).
    func testRGBACompressedTIFFRoundTrip() throws {
        guard TiffWriter.isAvailable else { throw XCTSkip("libtiff absent") }
        let rgba = PixelImage.rgba(RGBAImage(width: 16, height: 16,
                                             fill: RGBA32(r: 10, g: 20, b: 30, a: 128)))
        for scheme in [TiffCompression.lzw, .deflate] {
            let out = tempPath("rgba-\(scheme.rawValue).tif")
            try ImageWriter.save(rgba, to: out, options: ImageWriteOptions(tiffCompression: scheme))

            guard let data = try? Data(contentsOf: URL(fileURLWithPath: out)),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] else {
                return XCTFail("propriétés TIFF absentes")
            }
            let compression = (tiff[kCGImagePropertyTIFFCompression] as? NSNumber)?.intValue
            let expected = scheme == .lzw ? 5 : 8
            XCTAssertEqual(compression, expected, "rgba tif \(scheme.rawValue)")

            let reloaded = try ImageLoader.load(path: out).image
            // Le round-trip alpha passe par prémultiplié/déprémultiplié : tolérance.
            assertImagesClose(rgba, reloaded, maxDiff: 2, meanDiff: 1.0, "rgba tif \(scheme.rawValue)")
        }
    }
}
