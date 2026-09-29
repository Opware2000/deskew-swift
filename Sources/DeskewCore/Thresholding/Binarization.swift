//
//  Binarization.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Binarisation d'une image Gray8 selon un seuil.
///
/// Équivalent de `ImageUtils.BinarizeImage` : les pixels **hors** du rectangle
/// effectif restent inchangés.
public enum Binarization {

    public static func binarize(_ image: inout GrayImage, threshold: Int, rect: IntRect? = nil) {
        let imageBounds = image.bounds
        var effective = imageBounds

        if let rect = rect, rect.width > 0, rect.height > 0 {
            effective = rect.intersect(imageBounds)
        }

        guard !effective.isEmpty else { return }

        for y in effective.top..<effective.bottom {
            let rowBase = y * image.width
            for x in effective.left..<effective.right {
                let index = rowBase + x
                image.pixels[index] = (Int(image.pixels[index]) >= threshold) ? 255 : 0
            }
        }
    }
}
