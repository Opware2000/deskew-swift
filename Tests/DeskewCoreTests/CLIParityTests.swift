import XCTest
import Foundation
import DeskewCore

/// Parité stricte de la sortie console de l'exécutable avec les golden files.
///
/// La bannière, les messages, les statistiques et les noms de format doivent
/// être identiques à l'original. Seuls les chemins absolus sont normalisés en
/// `<OUT>`, et les statistiques dépendant des pixels sont tolérées pour les
/// entrées JPEG (décodeurs différents).
final class CLIParityTests: XCTestCase {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let reference = root.appendingPathComponent("Tests/DeskewParityTests/reference")

    private func executablePath() throws -> String {
        let bundleDir = URL(fileURLWithPath: Bundle(for: Self.self).bundlePath)
            .deletingLastPathComponent()
        let candidate = bundleDir.appendingPathComponent("deskew").path
        guard FileManager.default.isExecutableFile(atPath: candidate) else {
            throw XCTSkip("exécutable deskew introuvable à \(candidate)")
        }
        return candidate
    }

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
            guard columns.count >= 3 else { continue }
            let args = columns[2].split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            cases.append(Case(name: columns[0], ext: columns[1], args: args))
        }
        return cases
    }

    private func run(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = Self.root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func isJPEG(_ args: [String]) -> Bool {
        args.contains { $0.lowercased().hasSuffix(".jpg") || $0.lowercased().hasSuffix(".jpeg") }
    }

    func testConsoleParityAgainstGolden() throws {
        let executable = try executablePath()
        var cases = try loadCases()
        if let filter = ProcessInfo.processInfo.environment["PARITY_FILTER"], !filter.isEmpty {
            cases = cases.filter { $0.name.contains(filter) }
        }

        for testCase in cases {
            let goldenPath = Self.reference.appendingPathComponent(testCase.name)
                .appendingPathComponent("stdout.txt")
            let golden = try String(contentsOf: goldenPath, encoding: .utf8)

            // Redirige la sortie vers un fichier temporaire.
            var args = testCase.args
            var tempOut = ""
            if testCase.ext != "none", let index = args.firstIndex(of: "-o"), index + 1 < args.count {
                tempOut = NSTemporaryDirectory() + "deskew-cli-\(testCase.name)/out.\(testCase.ext)"
                try? FileManager.default.createDirectory(
                    atPath: (tempOut as NSString).deletingLastPathComponent,
                    withIntermediateDirectories: true)
                args[index + 1] = tempOut
            }

            let produced = try run(executable, args: args)

            // Normalise les chemins de sortie.
            let goldenRel = "Tests/DeskewParityTests/reference/\(testCase.name)/out.\(testCase.ext)"
            func normalize(_ text: String) -> String {
                var result = text
                result = result.replacingOccurrences(of: "<ROOT>/\(goldenRel)", with: "<OUT>")
                result = result.replacingOccurrences(of: goldenRel, with: "<OUT>")
                if !tempOut.isEmpty {
                    result = result.replacingOccurrences(of: tempOut, with: "<OUT>")
                }
                return result
            }

            var producedLines = normalize(produced).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var goldenLines = normalize(golden).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

            if isJPEG(testCase.args) {
                let skipLabels = ["tested pixels:", "accumulated counts:", "best count:"]
                producedLines = producedLines.filter { line in !skipLabels.contains { line.contains($0) } }
                goldenLines = goldenLines.filter { line in !skipLabels.contains { line.contains($0) } }
            }

            XCTAssertEqual(producedLines.count, goldenLines.count,
                           "\(testCase.name): nombre de lignes")
            for (p, g) in zip(producedLines, goldenLines) {
                XCTAssertEqual(p, g, "\(testCase.name): ligne divergente")
            }
        }
    }
}
