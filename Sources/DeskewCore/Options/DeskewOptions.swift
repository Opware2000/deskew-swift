//
//  DeskewOptions.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Méthode de seuillage noir/blanc.
public enum ThresholdingMethod: Equatable, Sendable {
    case otsu
    case explicit
}

/// Options du programme, avec analyse de la ligne de commande.
///
/// Reproduction fidèle de `TCmdLineOptions` (valeurs par défaut, validation,
/// messages d'erreur et sortie `OptionsToString`).
public struct DeskewOptions: Equatable, Sendable {

    // Valeurs par défaut (constantes d'origine)
    public static let defaultThreshold = 128
    public static let defaultMaxAngle = 10.0
    public static let defaultAngleStep = 0.1
    public static let defaultSkipAngle = 0.01
    public static let defaultOutputPrefix = "deskewed-"
    public static let defaultOutputExtension = "png"

    // Valeurs des options
    public var inputFileName: String?
    public var outputFileName: String?
    public var maxAngle: Double = DeskewOptions.defaultMaxAngle
    public var angleStep: Double = DeskewOptions.defaultAngleStep
    public var skipAngle: Double = DeskewOptions.defaultSkipAngle
    public var resamplingFilter: ResamplingFilter = .default
    public var backgroundColor: RGBA32 = .opaqueBlack
    public var thresholdingMethod: ThresholdingMethod = .otsu
    public var thresholdLevel: Int = DeskewOptions.defaultThreshold
    public var contentRect: FloatRect?
    public var contentMargins: FloatRect?
    public var contentSizeUnit: SizeUnit = .pixels
    public var forcedOutputFormat: PixelFormat?
    public var dpiOverride: Int = 0
    public var jpegCompressionQuality: Int?
    public var tiffCompression: TiffCompression?
    public var cropToInput = false
    public var detectOnly = false
    public var showDetectionStats = false
    public var showParams = false
    public var showTimings = false
    public var saveWorkImage = false
    public var errorMessage: String = ""

    public init() {}

    /// Équivalent de `Reset`.
    public mutating func reset() {
        self = DeskewOptions()
    }

    /// Équivalent de `IsValid`.
    public var isValid: Bool {
        guard let input = inputFileName, !input.isEmpty else { return false }
        guard maxAngle > 0, skipAngle >= 0 else { return false }
        if thresholdingMethod == .explicit && thresholdLevel <= 0 { return false }
        return errorMessage.isEmpty
    }

    // MARK: - Analyse

    /// Équivalent de `Parse(Args)`.
    @discardableResult
    public mutating func parse(_ args: [String]) -> Bool {
        reset()

        var index = 0
        while index < args.count {
            let param = args[index]
            if param.hasPrefix("-") {
                if index + 1 < args.count {
                    let value = args[index + 1]
                    index += 1
                    if !parseOption(param, value) { return false }
                } else {
                    errorMessage = "Missing value for parameter: \(param)"
                    return false
                }
            } else {
                if let existing = inputFileName, !existing.isEmpty {
                    errorMessage = "Multiple input files specified (\(param), \(existing))"
                    return false
                }
                inputFileName = param
            }
            index += 1
        }

        guard let input = inputFileName, !input.isEmpty else {
            errorMessage = "No input file given"
            return false
        }

        if (outputFileName ?? "").isEmpty {
            let dir = FilePath.ensureTrailingDelimiter(FilePath.fileDir(input))
            outputFileName = dir + DeskewOptions.defaultOutputPrefix +
                FilePath.changeFileExt(FilePath.fileName(input),
                                       to: "." + DeskewOptions.defaultOutputExtension)
        }

        return true
    }

    /// Équivalent de `CheckParam` : analyse une option et sa valeur.
    @discardableResult
    public mutating func parseOption(_ param: String, _ value: String) -> Bool {
        let lower = value.lowercased()

        switch param {
        case "-o":
            outputFileName = value

        case "-a":
            // Borné et fini : évite les débordements d'entiers en aval
            // (accumulateur Hough) et un angle de skew non réaliste.
            if let v = parseFiniteDouble(value), v > 0, v <= 90 {
                maxAngle = v
            } else {
                errorMessage = "Invalid value for max angle parameter: \(value)"
            }

        case "-d":
            if let v = parseDouble(value), v >= 0.01 && v <= 5 {
                angleStep = v
            } else {
                errorMessage = "Invalid value for angle step parameter: \(value)"
            }

        case "-l":
            if let v = parseFiniteDouble(value) {
                skipAngle = v
            } else {
                errorMessage = "Invalid value for skip angle parameter: \(value)"
            }

        case "-t":
            if lower == "a" {
                thresholdingMethod = .otsu
            } else {
                thresholdingMethod = .explicit
                if let v = parseInt(value) {
                    thresholdLevel = v
                } else {
                    errorMessage = "Invalid value for treshold parameter: \(value)"
                }
            }

        case "-b":
            if !parseBackgroundColor(lower) {
                errorMessage = "Invalid value for background color parameter: \(value)"
            }

        case "-f":
            switch lower {
            case "b1": forcedOutputFormat = .binary
            case "g8": forcedOutputFormat = .gray8
            case "rgb24": forcedOutputFormat = .rgb24
            case "rgba32": forcedOutputFormat = .rgba32
            default: errorMessage = "Invalid value for format parameter: \(value)"
            }

        case "-q":
            if let filter = ResamplingFilter(rawValue: lower) {
                resamplingFilter = filter
            } else {
                errorMessage = "Invalid value for resampling filter parameter: \(value)"
            }

        case "-g":
            if lower.contains("c") { cropToInput = true }
            if lower.contains("d") { detectOnly = true }

        case "-s":
            if lower.contains("s") { showDetectionStats = true }
            if lower.contains("p") { showParams = true }
            if lower.contains("t") { showTimings = true }
            if lower.contains("w") { saveWorkImage = true }

        case "-r":
            if contentMargins != nil {
                errorMessage = "Cannot accept content rectangle when content margins are already defined"
                return false
            }
            let tokens = splitList(lower)
            var ok = false
            if tokens.count == 4 || tokens.count == 5 {
                if let rect = parseFloatRect(Array(tokens.prefix(4))) {
                    contentRect = rect
                    ok = true
                    if tokens.count == 5 {
                        if let unit = SizeUnit(token: tokens[4]) {
                            contentSizeUnit = unit
                        } else {
                            ok = false
                        }
                    }
                }
            }
            if !ok { errorMessage = "Invalid definition of content rectangle: \(value)" }

        case "-m":
            if contentRect != nil {
                errorMessage = "Cannot accept content margins when content rectangle is already defined"
                return false
            }
            let tokens = splitList(lower)
            let count = tokens.count
            var ok = false
            switch count {
            case 1, 4:
                if let margins = parseFloatRect(tokens) {
                    contentMargins = margins
                    ok = true
                }
            case 3, 5:
                if let unit = SizeUnit(token: tokens[count - 1]),
                   let margins = parseFloatRect(Array(tokens.prefix(count - 1))) {
                    contentSizeUnit = unit
                    contentMargins = margins
                    ok = true
                }
            case 2:
                if let unit = SizeUnit(token: tokens[1]) {
                    if let margins = parseFloatRect([tokens[0]]) {
                        contentSizeUnit = unit
                        contentMargins = margins
                        ok = true
                    }
                } else if let margins = parseFloatRect(tokens) {
                    contentMargins = margins
                    ok = true
                }
            default:
                ok = false
            }
            if !ok { errorMessage = "Invalid definition of content margins: \(value)" }

        case "-p":
            if let v = parseInt(value), v >= 1 {
                dpiOverride = v
            } else {
                errorMessage = "Invalid value for DPI override parameter: \(value)"
            }

        case "-c":
            if !parseCompression(lower) { return false }

        default:
            errorMessage = "Unknown parameter: \(param)"
        }

        return errorMessage.isEmpty
    }

    // MARK: - Analyse : helpers

    private func parseDouble(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespaces))
    }

    /// Comme `parseDouble` mais **rejette les valeurs non finies**
    /// (`nan`, `inf`) — frontière de confiance (arguments non fiables).
    private func parseFiniteDouble(_ value: String) -> Double? {
        guard let v = parseDouble(value), v.isFinite else { return nil }
        return v
    }

    private func parseInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return Int(trimmed)
    }

    private func splitList(_ value: String) -> [String] {
        value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    /// Équivalent de `TryParseSizeRect` (1, 2 ou 4 valeurs).
    private func parseFloatRect(_ tokens: [String]) -> FloatRect? {
        guard tokens.count == 1 || tokens.count == 2 || tokens.count == 4 else { return nil }
        var values = [Float]()
        for token in tokens {
            guard let v = parseFiniteDouble(token) else { return nil }
            let f = Float(v)
            guard f.isFinite else { return nil }   // 1e300 -> Float inf
            values.append(f)
        }
        switch values.count {
        case 1:
            return FloatRect(left: values[0], top: values[0], right: values[0], bottom: values[0])
        case 2:
            return FloatRect(left: values[0], top: values[1], right: values[0], bottom: values[1])
        default:
            return FloatRect(left: values[0], top: values[1], right: values[2], bottom: values[3])
        }
    }

    /// Équivalent de l'analyse de `-b`.
    private mutating func parseBackgroundColor(_ lower: String) -> Bool {
        guard lower.count <= 8, let hex = UInt64(lower, radix: 16) else { return false }
        let temp = UInt32(truncatingIfNeeded: hex)
        if temp <= 0xFF && lower.count <= 2 {
            let c = UInt8(temp)
            backgroundColor = RGBA32(r: c, g: c, b: c, a: 255)
        } else if temp <= 0xFFFFFF && lower.count <= 6 {
            backgroundColor = RGBA32(color32: 0xFF00_0000 | temp)
        } else {
            backgroundColor = RGBA32(color32: temp)
        }
        return true
    }

    /// Équivalent de l'analyse de `-c`.
    private mutating func parseCompression(_ lower: String) -> Bool {
        for spec in splitList(lower) {
            if spec.hasPrefix("t") {
                let name = String(spec.dropFirst())
                if tiffCompression != nil {
                    errorMessage = "TIFF output compression already set but received: \(name)"
                    return false
                }
                if let compression = TiffCompression(rawValue: name) {
                    tiffCompression = compression
                } else {
                    errorMessage = "Invalid TIFF output compression spec: \(name)"
                    return false
                }
            } else if spec.hasPrefix("j") {
                let quality = String(spec.dropFirst())
                if jpegCompressionQuality != nil {
                    errorMessage = "JPEG output compression already set but received: \(quality)"
                    return false
                }
                if let v = parseInt(quality), v >= 1 && v <= 100 {
                    jpegCompressionQuality = v
                } else {
                    errorMessage = "Invalid JPEG output compression spec: \(quality)"
                    return false
                }
            } else {
                errorMessage = "Invalid output compression parameter: \(spec)"
                return false
            }
        }
        return true
    }

    // MARK: - Sortie console

    /// Équivalent de `OptionsToString`.
    public func optionsDescription(commandLine: [String]) -> String {
        var cmdParams = ""
        for arg in commandLine { cmdParams += arg + " " }

        let filterStr = resamplingFilter.rawValue
        let compJpeg = jpegCompressionQuality.map(String.init) ?? "default"
        let compTiff = tiffCompression?.rawValue ?? "default"

        func rectToStr(_ rect: FloatRect?) -> String {
            let r = rect ?? .zero
            return "\(PascalFormat.number2(r.left)),\(PascalFormat.number2(r.top))," +
                   "\(PascalFormat.number2(r.right)),\(PascalFormat.number2(r.bottom)) " +
                   contentSizeUnit.rawValue
        }

        return "Parameters: " + cmdParams + "\n" +
            "  input file          = " + (inputFileName ?? "") + "\n" +
            "  output file         = " + (outputFileName ?? "") + "\n" +
            "  background color    = " + PascalFormat.hex8(backgroundColor.color32) + "\n" +
            "  resampling filter   = " + filterStr + "\n" +
            "  max angle           = " + PascalFormat.floatToStr(maxAngle) + "\n" +
            "  angle step          = " + PascalFormat.floatToStr(angleStep) + "\n" +
            "  thresholding method = " + (thresholdingMethod == .explicit ? "explicit" : "auto otsu") + "\n" +
            "  threshold level     = " + String(thresholdLevel) + "\n" +
            "  content rect        = " + rectToStr(contentRect) + "\n" +
            "  content margins     = " + rectToStr(contentMargins) + "\n" +
            "  output format       = " + (forcedOutputFormat?.name ?? "default") + "\n" +
            "  skip angle          = " + PascalFormat.floatToStr(skipAngle) + "\n" +
            "  dpi override        = " + String(dpiOverride) + "\n" +
            "  oper flags          = " + (cropToInput ? "crop-to-input " : "") +
                                            (detectOnly ? "detect-only " : "") + "\n" +
            "  info flags          = " + (showParams ? "params " : "") +
                                            (showDetectionStats ? "detection-stats " : "") +
                                            (showTimings ? "timings " : "") +
                                            (saveWorkImage ? "save-work-image " : "") + "\n" +
            "  output compression  = jpeg:" + compJpeg + " tiff:" + compTiff + "\n"
    }
}
