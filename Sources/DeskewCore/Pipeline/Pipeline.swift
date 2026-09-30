//
//  Pipeline.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation

/// Erreurs du pipeline.
public enum PipelineError: Error, CustomStringConvertible {
    case missingResolutionInfo

    public var description: String {
        switch self {
        case .missingResolutionInfo:
            return "Could not determine content rectangle in pixels.\n" +
                   "Image does not contain DPI information or Deskew failed to read it."
        }
    }
}

/// Résultat du pipeline (équivalent de `DoDeskew`).
public struct PipelineResult {
    public var outputImage: PixelImage?
    public var workImage: GrayImage?
    public var changed: Bool
    public var skewAngle: Double
    public var stats: SkewStats
    public var log: [String]
    /// Compression TIFF effective (après résolution de `input`).
    public var resolvedTiffCompression: TiffCompression?
    /// Format de sortie effectif (pour l'affichage console).
    public var resolvedOutputFormat: PixelFormat?
}

/// Orchestration du traitement (équivalent de `DoDeskew`).
public enum Pipeline {

    public static func run(input: PixelImage, resolution: ResolutionInfo,
                           options: DeskewOptions,
                           inputTiffCompression: TiffCompression? = nil,
                           inputFormat: PixelFormat? = nil) throws -> PipelineResult {
        let workingGray = input.toGray()

        var effectiveResolution = resolution
        if options.dpiOverride > 0 {
            let dpi = Double(options.dpiOverride)
            effectiveResolution = .from(dpiX: dpi, dpiY: dpi)
        }

        guard let contentRect = ContentRect.forImage(
            contentRect: options.contentRect,
            contentMargins: options.contentMargins,
            unit: options.contentSizeUnit,
            imageBounds: workingGray.bounds,
            resolution: effectiveResolution) else {
            throw PipelineError.missingResolutionInfo
        }

        var log: [String] = []
        var stopwatch = Stopwatch()

        let threshold: Int
        if options.thresholdingMethod == .explicit {
            threshold = options.thresholdLevel
        } else {
            stopwatch.restart()
            threshold = Otsu.threshold(image: workingGray, rect: contentRect)
            if options.showTimings { log.append(stopwatch.line("Auto thresholding")) }
        }

        let inRect = contentRect != workingGray.bounds
        log.append("Calculating skew angle" + (inRect ? " (in \(contentRect))" : "") +
                   " using threshold \(threshold)...")

        stopwatch.restart()
        let detection = HoughSkewDetector.detect(
            maxAngle: options.maxAngle,
            angleStep: options.angleStep,
            threshold: threshold,
            image: workingGray,
            detectionArea: contentRect)
        if options.showTimings { log.append(stopwatch.line("Skew detection")) }

        log.append("Skew angle found [deg]: " + String(format: "%4.3f", detection.angle))
        if options.showDetectionStats {
            log.append(contentsOf: statsLines(detection.stats))
        }

        var result = PipelineResult(outputImage: nil, workImage: nil, changed: false,
                                    skewAngle: detection.angle, stats: detection.stats, log: log,
                                    resolvedTiffCompression: nil, resolvedOutputFormat: nil)

        // Compression TIFF effective (option `input` reprise des métadonnées).
        let effectiveTiffCompression: TiffCompression?
        if options.tiffCompression == .input {
            effectiveTiffCompression = inputTiffCompression
        } else {
            effectiveTiffCompression = options.tiffCompression
        }
        result.resolvedTiffCompression = effectiveTiffCompression

        if options.saveWorkImage {
            var work = workingGray
            Binarization.binarize(&work, threshold: threshold, rect: contentRect)
            result.workImage = work
        }

        if options.detectOnly {
            return result
        }

        var output: PixelImage? = input
        if abs(detection.angle) >= options.skipAngle {
            result.log.append("Rotating image...")
            stopwatch.restart()
            var rotated = input.ensureRotatable(background: options.backgroundColor)
            rotated = rotated.rotated(angleDegrees: detection.angle,
                                      background: options.backgroundColor,
                                      filter: options.resamplingFilter,
                                      fitRotated: !options.cropToInput)
            output = rotated
            result.changed = true
            if options.showTimings { result.log.append(stopwatch.line("Rotate image")) }
        } else {
            result.log.append("Skipping deskewing step, skew angle lower than threshold of " +
                              String(format: "%4.2f", options.skipAngle))
        }

        // Format de sortie forcé.
        if let forced = options.forcedOutputFormat, let current = output, current.format != forced {
            output = current.converted(to: forced)
            result.changed = true
        }

        // Compression TIFF G4 => image binaire.
        if effectiveTiffCompression == .g4, let current = output, current.format != .binary {
            output = current.converted(to: .binary)
            result.changed = true
        }

        result.outputImage = output
        let binaryOutput = options.forcedOutputFormat == .binary || effectiveTiffCompression == .g4
        if binaryOutput {
            result.resolvedOutputFormat = .binary
        } else if !result.changed, options.forcedOutputFormat == nil {
            // Image inchangée : l'original conserve le format d'entrée.
            result.resolvedOutputFormat = inputFormat ?? output?.format
        } else {
            result.resolvedOutputFormat = output?.format
        }
        return result
    }

    /// Lignes de statistiques de détection (équivalent de `WriteDetectionStats`).
    public static func statsLines(_ stats: SkewStats) -> [String] {
        [
            "Skew detection stats:",
            "  pixel count:        " + PascalFormat.groupedInteger(stats.pixelCount, minWidth: 16),
            "  tested pixels:      " + PascalFormat.groupedInteger(stats.testedPixels, minWidth: 16),
            "  accumulator size:   " + PascalFormat.groupedInteger(stats.accumulatorSize, minWidth: 16),
            "  accumulated counts: " + PascalFormat.groupedInteger(stats.accumulatedCounts, minWidth: 16),
            "  best count:         " + PascalFormat.groupedInteger(stats.bestCount, minWidth: 16)
        ]
    }
}
