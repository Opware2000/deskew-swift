//
//  Otsu.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import Dispatch

/// Seuillage automatique par la méthode d'Otsu.
///
/// Reproduction fidèle de `ImageUtils.OtsuThresholding`, y compris les
/// particularités de l'original :
/// - histogramme en simple précision (`Float`) ;
/// - décalage volontaire `(I + 1)` dans la moyenne et `LevelMean` ;
/// - epsilon `1E-6` sur `Omega` ;
/// - cas rectangle vide → `128` ;
/// - cas couleur unie (`Min == Max`) → `Min`.
public enum Otsu {

    /// Calcule le seuil `[0..255]` pour une image Gray8.
    ///
    /// - Parameter rect: rectangle de calcul optionnel (clippé aux bornes de
    ///   l'image). `nil` = image entière.
    public static func threshold(image: GrayImage, rect: IntRect? = nil) -> Int {
        let imageBounds = image.bounds
        var effective = IntRect.zero

        if let rect = rect {
            if !rect.isEmpty {
                effective = rect.intersect(imageBounds)
            }
        } else {
            effective = imageBounds
        }

        let numPixelsInRect = effective.width * effective.height
        if numPixelsInRect <= 0 { return 128 }

        var histogram = [Float](repeating: 0, count: 256)
        var minValue = 255
        var maxValue = 0

        computeHistogram(image: image, rect: effective,
                         histogram: &histogram, minValue: &minValue, maxValue: &maxValue)

        for i in minValue...maxValue {
            histogram[i] /= Float(numPixelsInRect)
        }

        var mean: Float = 0
        for i in minValue...maxValue {
            mean += Float(i + 1) * histogram[i]
        }

        var largestMu: Float = 0
        var level = 0

        for i in minValue...maxValue {
            var omega: Float = 0
            var levelMean: Float = 0

            if i > minValue {
                for j in minValue..<i {
                    omega += histogram[j]
                    levelMean += Float(j + 1) * histogram[j]
                }
            }

            var mu = mean * omega - levelMean
            mu *= mu
            omega = omega * (1.0 - omega)

            if omega > 1e-6 && omega < (1.0 - 1e-6) {
                mu /= omega
            } else {
                mu = 0
            }

            if mu > largestMu {
                largestMu = mu
                level = i
            }
        }

        if minValue == maxValue { level = minValue }
        return level
    }

    /// Histogramme (et min/max) sur un rectangle, parallélisé par bandes de lignes.
    ///
    /// Chaque bande calcule un histogramme local ; la fusion se fait dans l'ordre
    /// des bandes. Les compteurs étant entiers (`Float` exact < 2^24), le résultat
    /// est identique au calcul séquentiel.
    private static func computeHistogram(image: GrayImage, rect: IntRect,
                                         histogram: inout [Float],
                                         minValue: inout Int, maxValue: inout Int) {
        let rowCount = rect.bottom - rect.top
        let pixelCount = rowCount * rect.width
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let bandCount = (pixelCount >= 200_000 && threads > 1)
            ? min(threads * 4, max(1, rowCount))
            : 1

        let pixels = image.pixels
        let width = image.width
        let left = rect.left
        let right = rect.right

        var localHistograms = [Float](repeating: 0, count: bandCount * 256)
        var localMins = [Int](repeating: 255, count: bandCount)
        var localMaxs = [Int](repeating: 0, count: bandCount)

        func bandRange(_ band: Int) -> Range<Int> {
            let y0 = rect.top + band * rowCount / bandCount
            let y1 = rect.top + (band + 1) * rowCount / bandCount
            return y0..<y1
        }

        localHistograms.withUnsafeMutableBufferPointer { hbuf in
            localMins.withUnsafeMutableBufferPointer { minbuf in
                localMaxs.withUnsafeMutableBufferPointer { maxbuf in
                    DispatchQueue.concurrentPerform(iterations: bandCount) { band in
                        let base = band * 256
                        var lo = 255
                        var hi = 0
                        for y in bandRange(band) {
                            let rowBase = y * width
                            for x in left..<right {
                                let value = Int(pixels[rowBase + x])
                                hbuf[base + value] += 1.0
                                if value < lo { lo = value }
                                if value > hi { hi = value }
                            }
                        }
                        minbuf[band] = lo
                        maxbuf[band] = hi
                    }
                }
            }
        }

        for i in 0..<256 { histogram[i] = 0 }
        for band in 0..<bandCount {
            let base = band * 256
            for i in 0..<256 { histogram[i] += localHistograms[base + i] }
            if localMins[band] < minValue { minValue = localMins[band] }
            if localMaxs[band] > maxValue { maxValue = localMaxs[band] }
        }
    }
}
