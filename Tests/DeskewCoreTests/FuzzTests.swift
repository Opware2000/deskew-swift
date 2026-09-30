import XCTest
import Foundation
import DeskewCore
import DeskewImageIO

/// Fuzzers déterministes (graine fixe → reproductible).
///
/// Objectif : **aucune entrée non fiable ne doit faire planter** le programme.
/// On ne vérifie pas la sémantique, seulement l'absence de trap / signal.
final class FuzzTests: XCTestCase {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Générateur déterministe (SplitMix64).
    struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ upperBound: Int) -> Int {
            upperBound <= 0 ? 0 : Int(next() % UInt64(upperBound))
        }
        mutating func pick<T>(_ array: [T]) -> T {
            array[int(array.count)]
        }
        mutating func bytes(_ count: Int) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: count)
            for i in 0..<count { out[i] = UInt8(truncatingIfNeeded: next()) }
            return out
        }
    }

    // MARK: - Corpus de jetons d'arguments

    private let tokens: [String] = [
        // options valides
        "-o", "-a", "-d", "-l", "-t", "-b", "-f", "-q", "-g", "-s", "-r", "-m", "-p", "-c",
        // valeurs normales
        "10", "0.1", "5", "1", "255", "128", "a", "b1", "g8", "rgb24", "rgba32",
        "nearest", "linear", "cubic", "lanczos", "px", "%", "mm", "cm", "in",
        "1,2,3,4", "10,10", "j50", "tnone", "tlzw", "TestImages/2.png", "out.png",
        // valeurs limites / malveillantes
        "inf", "-inf", "nan", "-nan", "1e300", "1e19", "-1e300", "0", "-0",
        "0.0", "90", "91", "100", "-5", "1e-300",
        "nan,nan,nan,nan", "inf,0,10,10", "1e300,0,10,10", "0,nan,10,10",
        "j0", "j101", "j-1", "txyz", "tinput", "j99999999999999999999",
        "", " ", "  ", "-", "--", "---", "-a=1", "--help", "abc", "é", "中文",
        "\u{0}", "\u{7F}", "\u{FFFF}", String(repeating: "9", count: 2000),
        String(repeating: "a", count: 2000), ",,,,", ",", "1,", ",1"
    ]

    // MARK: - 1. Parsing d'arguments (in-process)

    func testFuzzArgumentParsingDoesNotCrash() {
        var rng = SplitMix64(state: 0x5EED_0001)
        for _ in 0..<5000 {
            let count = rng.int(9)
            var args: [String] = []
            for _ in 0..<count { args.append(rng.pick(tokens)) }
            if rng.int(2) == 0 { args.append("TestImages/2.png") }

            var options = DeskewOptions()
            let parsed = options.parse(args)

            if parsed {
                // Invariants : si valide, les noms de fichiers sont définis.
                if options.isValid {
                    XCTAssertNotNil(options.inputFileName, "entrée manquante pour \(args)")
                    XCTAssertNotNil(options.outputFileName, "sortie manquante pour \(args)")
                }
            } else {
                XCTAssertFalse(options.errorMessage.isEmpty, "erreur vide pour \(args)")
            }
            // Accès aux propriétés (déclenche d'éventuels traps)
            _ = options.optionsDescription(commandLine: args)
        }
    }

    // MARK: - 2. Chargement d'images (données non fiables)

    func testFuzzImageLoaderDoesNotCrash() throws {
        var rng = SplitMix64(state: 0x5EED_0002)
        let temp = NSTemporaryDirectory() + "fuzz-img.bin"

        // 2a. Données aléatoires pures
        for _ in 0..<200 {
            let size = rng.int(4096)
            let data = Data(rng.bytes(size))
            try data.write(to: URL(fileURLWithPath: temp))
            _ = try? ImageLoader.load(path: temp)
        }

        // 2b. En-têtes de formats connus + charge aléatoire
        let magics: [[UInt8]] = [
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], // PNG
            [0xFF, 0xD8, 0xFF, 0xE0],                            // JPEG
            [0x49, 0x49, 0x2A, 0x00],                            // TIFF LE
            [0x4D, 0x4D, 0x00, 0x2A],                            // TIFF BE
            [0x47, 0x49, 0x46, 0x38],                            // GIF
            [0x42, 0x4D]                                         // BMP
        ]
        for _ in 0..<200 {
            var data = Data(rng.pick(magics))
            data.append(contentsOf: rng.bytes(rng.int(2048)))
            try data.write(to: URL(fileURLWithPath: temp))
            _ = try? ImageLoader.load(path: temp)
        }

        // 2c. Mutation d'une image réelle (bits inversés / troncature)
        let realPath = Self.root.appendingPathComponent("TestImages/2.png").path
        let real = try Data(contentsOf: URL(fileURLWithPath: realPath))
        for _ in 0..<300 {
            var mutated = [UInt8](real)
            let flips = 1 + rng.int(16)
            for _ in 0..<flips {
                mutated[rng.int(mutated.count)] ^= UInt8(truncatingIfNeeded: rng.next())
            }
            if rng.int(3) == 0 { mutated = Array(mutated.prefix(rng.int(mutated.count))) }
            try Data(mutated).write(to: URL(fileURLWithPath: temp))
            _ = try? ImageLoader.load(path: temp)
        }
    }

    // MARK: - 3. Bout-en-bout CLI (détecte les traps du programme entier)

    func testFuzzCLIDoesNotCrash() throws {
        let bundleDir = URL(fileURLWithPath: Bundle(for: Self.self).bundlePath)
            .deletingLastPathComponent()
        let executable = bundleDir.appendingPathComponent("deskew").path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw XCTSkip("exécutable deskew introuvable à \(executable)")
        }

        // Bac à sable : toutes les écritures restent dans un dossier temporaire.
        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deskew-fuzz-cli")
        try? FileManager.default.removeItem(at: sandbox)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let input = Self.root.appendingPathComponent("TestImages/2.png")
        try FileManager.default.copyItem(at: input, to: sandbox.appendingPathComponent("in.png"))

        // Jetons sans chemin (aucune écriture hors du bac à sable).
        let cliTokens = tokens.filter { !$0.contains("/") && !$0.contains("TestImages") }

        var rng = SplitMix64(state: 0x5EED_0003)
        for iteration in 0..<80 {
            let count = rng.int(7)
            var args = ["-o", "out.png"]
            for _ in 0..<count { args.append(rng.pick(cliTokens)) }
            args.append("in.png")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.currentDirectoryURL = sandbox
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()

            XCTAssertNotEqual(process.terminationReason, .uncaughtSignal,
                              "itér. \(iteration) : signal reçu pour \(args)")
            XCTAssertLessThan(process.terminationStatus, 128,
                              "itér. \(iteration) : code \(process.terminationStatus) pour \(args)")
        }
    }

    // MARK: - 5. Corpus de régression (vecteurs déjà trouvés)

    /// Vecteurs malveillants connus (FIND-001 à FIND-005) : le programme doit les
    /// **rejeter proprement**, jamais planter. Garantit qu'une régression serait
    /// détectée même si le fuzz aléatoire ne retombait pas dessus.
    func testKnownMaliciousInputsDoNotCrash() throws {
        let bundleDir = URL(fileURLWithPath: Bundle(for: Self.self).bundlePath)
            .deletingLastPathComponent()
        let executable = bundleDir.appendingPathComponent("deskew").path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw XCTSkip("exécutable deskew introuvable")
        }

        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deskew-fuzz-corpus")
        try? FileManager.default.removeItem(at: sandbox)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.root.appendingPathComponent("TestImages/2.png"),
                                         to: sandbox.appendingPathComponent("in.png"))

        let corpus: [[String]] = [
            ["-a", "inf"], ["-a", "-inf"], ["-a", "nan"], ["-a", "1e19"],
            ["-a", "1e15"], ["-a", "1e300"], ["-a", "100"], ["-a", "91"], ["-a", "0"],
            ["-r", "nan,0,10,10"], ["-r", "inf,0,10,10"], ["-r", "1e300,0,10,10"],
            ["-r", "0,nan,10,10"], ["-m", "inf"], ["-m", "nan"], ["-m", "1e300"],
            ["-m", "inf,inf,inf,inf"], ["-l", "inf"], ["-l", "nan"], ["-d", "inf"], ["-d", "0"],
            ["-b", "GGG"], ["-b", "-FF"], ["-f", "g64"], ["-q", "ujo"], ["-t", "x"],
            ["-c", "j0"], ["-c", "j101"], ["-c", "txyz"], ["-p", "0"], ["-p", "-1"]
        ]

        for vector in corpus {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["-o", "out.png"] + vector + ["in.png"]
            process.currentDirectoryURL = sandbox
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertNotEqual(process.terminationReason, .uncaughtSignal,
                              "signal reçu pour \(vector)")
        }
    }

    // MARK: - 6. Écriture d'images (formats de sortie)

    func testFuzzImageWriterDoesNotCrash() throws {
        var rng = SplitMix64(state: 0x5EED_0004)
        let formats: [(String, PixelImage)] = [
            ("png", .gray(GrayImage(width: 8, height: 8, fill: 120))),
            ("tif", .rgb(RGBImage(width: 5, height: 7, fill: RGB24(r: 10, g: 20, b: 30)))),
            ("jpg", .rgb(RGBImage(width: 6, height: 6, fill: RGB24(r: 200, g: 100, b: 50)))),
            ("gif", .gray(GrayImage(width: 4, height: 4, fill: 0))),
            ("bmp", .rgb(RGBImage(width: 4, height: 4, fill: RGB24(r: 1, g: 2, b: 3))))
        ]
        for (ext, image) in formats {
            for _ in 0..<5 {
                let path = NSTemporaryDirectory() + "fuzz-write.\(ext)"
                let quality = rng.int(3) == 0 ? rng.int(101) : nil
                let compression: TiffCompression? = rng.int(3) == 0
                    ? rng.pick([TiffCompression.none, .lzw, .deflate, .rle, .jpeg])
                    : nil
                try? ImageWriter.save(image, to: path,
                                      options: ImageWriteOptions(jpegQuality: quality,
                                                                 tiffCompression: compression))
                _ = try? ImageLoader.load(path: path)
            }
        }
    }
}
