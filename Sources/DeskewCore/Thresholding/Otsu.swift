//
//  Otsu.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

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

        for y in effective.top..<effective.bottom {
            let rowBase = y * image.width
            for x in effective.left..<effective.right {
                let value = Int(image.pixels[rowBase + x])
                histogram[value] += 1.0
                if value < minValue { minValue = value }
                if value > maxValue { maxValue = value }
            }
        }

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
}
