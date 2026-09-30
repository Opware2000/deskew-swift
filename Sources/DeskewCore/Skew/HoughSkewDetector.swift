//
//  HoughSkewDetector.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import Dispatch

/// Statistiques de détection d'inclinaison (équivalent de `TCalcSkewAngleStats`).
public struct SkewStats: Equatable, Sendable {
    public var pixelCount = 0
    public var testedPixels = 0
    public var accumulatorSize = 0
    public var accumulatedCounts = 0
    public var bestCount = 0

    public init() {}
}

/// Résultat de la détection.
public struct SkewDetectionResult: Equatable, Sendable {
    public var angle: Double
    public var stats: SkewStats

    public init(angle: Double, stats: SkewStats) {
        self.angle = angle
        self.stats = stats
    }
}

/// Erreurs de détection (paramètres non fiables, ressources excessives).
public enum HoughError: Error, CustomStringConvertible {
    case invalidParameters
    case detectionTooLarge

    public var description: String {
        switch self {
        case .invalidParameters:
            return "Invalid skew detection parameters (max angle / angle step)."
        case .detectionTooLarge:
            return "Skew detection accumulator too large; reduce max angle or increase angle step."
        }
    }
}

/// Détection d'inclinaison par transformée de Hough.
///
/// Reproduction fidèle de `RotationDetector.CalcRotationAngle`.
public enum HoughSkewDetector {

    /// Nombre de « meilleures » lignes retenues.
    public static let bestLinesCount = 20

    /// Garde-fou mémoire : nombre maximal de cases d'accumulateur.
    public static let maxAccumulatorSize = 200_000_000

    private struct Line {
        var count = 0
        var index = 0
        var alpha: Double = 0
        var distance: Double = 0
    }

    /// Calcule l'angle de rotation (en degrés) d'une image Gray8.
    ///
    /// - Throws: `HoughError` si les paramètres sont non finis/hors bornes ou si
    ///   l'accumulateur dépasserait la limite mémoire.
    public static func detect(maxAngle: Double, angleStep: Double, threshold: Int,
                              image: GrayImage, detectionArea: IntRect? = nil) throws -> SkewDetectionResult {
        let width = image.width
        let height = image.height

        var contentRect = IntRect(left: 0, top: 0, right: width, bottom: height)
        if let area = detectionArea {
            contentRect = area
        }

        let pageWidth = contentRect.width
        var pageHeight = contentRect.height
        if contentRect.bottom == height {
            pageHeight -= 1
        }

        var stats = SkewStats()

        let alphaStart = -maxAngle
        let alphaStepsDouble = ceil(2 * maxAngle / angleStep)
        guard maxAngle.isFinite, angleStep.isFinite, angleStep > 0,
              alphaStepsDouble.isFinite, alphaStepsDouble >= 1,
              alphaStepsDouble <= 10_000_000 else {
            throw HoughError.invalidParameters
        }
        let alphaSteps = Int(alphaStepsDouble)

        guard pageWidth > 0 && pageHeight > 0 else {
            return SkewDetectionResult(angle: 0, stats: stats)
        }

        let minDist = Double(-max(pageWidth, pageHeight))
        let (distCount, distOverflow) = 2.multipliedReportingOverflow(by: pageWidth + pageHeight)
        let (accumulatorSize, accOverflow) = distCount.multipliedReportingOverflow(by: alphaSteps)
        guard !distOverflow, !accOverflow,
              accumulatorSize > 0, accumulatorSize <= maxAccumulatorSize else {
            throw HoughError.detectionTooLarge
        }

        var accumulator = [Int32](repeating: 0, count: accumulatorSize)

        // Pré-calcul des sinus/cosinus pour chaque pas angulaire.
        var sines = [Double](repeating: 0, count: alphaSteps)
        var cosines = [Double](repeating: 0, count: alphaSteps)
        for i in 0..<alphaSteps {
            let radians = (alphaStart + Double(i) * angleStep) * Double.pi / 180
            sines[i] = sin(radians)
            cosines[i] = cos(radians)
        }

        let pixels = image.pixels
        let areaLeft = contentRect.left
        let areaTop = contentRect.top

        @inline(__always)
        func isBlack(_ x: Int, _ y: Int) -> Bool {
            pixels[y * width + x] < threshold
        }

        // Pixels « ligne de base » (noir avec pixel du dessous non noir).
        var testedX = [Int32]()
        var testedY = [Int32]()
        for y in 0..<pageHeight {
            for x in 0..<pageWidth {
                let px = areaLeft + x
                let py = areaTop + y
                guard px >= 0, px < width, py >= 0, py + 1 < height else { continue }
                if isBlack(px, py) && !isBlack(px, py + 1) {
                    testedX.append(Int32(x))
                    testedY.append(Int32(y))
                }
            }
        }

        // Accumulation : partition par plages d'angles. Deux pas angulaires
        // distincts écrivent dans des colonnes distinctes de l'accumulateur,
        // donc aucun verrou n'est nécessaire.
        let threadCount = min(ProcessInfo.processInfo.activeProcessorCount, alphaSteps)
        if threadCount > 1 && !testedX.isEmpty {
            accumulator.withUnsafeMutableBufferPointer { acc in
                testedX.withUnsafeBufferPointer { xs in
                    testedY.withUnsafeBufferPointer { ys in
                        sines.withUnsafeBufferPointer { sinPtr in
                            cosines.withUnsafeBufferPointer { cosPtr in
                                DispatchQueue.concurrentPerform(iterations: threadCount) { thread in
                                    let i0 = thread * alphaSteps / threadCount
                                    let i1 = (thread + 1) * alphaSteps / threadCount
                                    for p in 0..<xs.count {
                                        let xd = Double(xs[p])
                                        let yd = Double(ys[p])
                                        for i in i0..<i1 {
                                            let d = yd * cosPtr[i] - xd * sinPtr[i]
                                            let dIndex = Int(d - minDist)
                                            let index = dIndex * alphaSteps + i
                                            if index >= 0 && index < accumulatorSize {
                                                acc[index] += 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            for p in 0..<testedX.count {
                let xd = Double(testedX[p])
                let yd = Double(testedY[p])
                for i in 0..<alphaSteps {
                    let d = yd * cosines[i] - xd * sines[i]
                    let dIndex = Int(d - minDist)
                    let index = dIndex * alphaSteps + i
                    if index >= 0 && index < accumulatorSize {
                        accumulator[index] += 1
                    }
                }
            }
        }

        // Sélection des meilleures lignes (tri par insertion, décroissant).
        var best = [Line](repeating: Line(), count: bestLinesCount)
        var accumulatedCounts = 0
        for i in 0..<accumulatorSize {
            let count = Int(accumulator[i])
            if count > best[bestLinesCount - 1].count {
                best[bestLinesCount - 1].count = count
                best[bestLinesCount - 1].index = i
                var j = bestLinesCount - 1
                while j > 0 && best[j].count > best[j - 1].count {
                    best.swapAt(j, j - 1)
                    j -= 1
                }
            }
            accumulatedCounts += count
        }

        for i in 0..<bestLinesCount {
            let distIndex = best[i].index / alphaSteps
            let alphaIndex = best[i].index - distIndex * alphaSteps
            best[i].alpha = alphaStart + Double(alphaIndex) * angleStep
            best[i].distance = Double(distIndex) + minDist
        }

        var sumAngles = 0.0
        for i in 0..<bestLinesCount {
            sumAngles += best[i].alpha
        }
        let result = sumAngles / Double(bestLinesCount)

        stats.bestCount = best[0].count
        stats.pixelCount = pageWidth * pageHeight
        stats.accumulatorSize = accumulatorSize
        stats.accumulatedCounts = accumulatedCounts
        stats.testedPixels = accumulatedCounts / alphaSteps

        return SkewDetectionResult(angle: result, stats: stats)
    }
}
