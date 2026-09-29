//
//  ContentRect.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Calcul de la zone de détection (rectangle de contenu ou marges de page).
///
/// Équivalents de `Utils.CalcRectInPixels` et de
/// `TCmdLineOptions.CalcContentRectForImage`.
public enum ContentRect {

    /// Équivalent de `CalcRectInPixels`.
    ///
    /// Renvoie `.zero` en cas d'échec (résolution physique manquante), comme
    /// `NullRect` dans l'original.
    public static func calcRectInPixels(
        _ rectInUnits: FloatRect,
        unit: SizeUnit,
        imageBounds: IntRect,
        resolution: ResolutionInfo
    ) -> IntRect {
        switch unit {
        case .pixels:
            return rectInUnits.scaled(widthFactor: 1, heightFactor: 1)

        case .percent:
            return rectInUnits.scaled(
                widthFactor: Double(imageBounds.width) / 100,
                heightFactor: Double(imageBounds.height) / 100)

        case .mm:
            guard let size = resolution.physicalPixelSize(.dpcm) else { return .zero }
            return rectInUnits.scaled(widthFactor: size.x / 10, heightFactor: size.y / 10)

        case .cm:
            guard let size = resolution.physicalPixelSize(.dpcm) else { return .zero }
            return rectInUnits.scaled(widthFactor: size.x, heightFactor: size.y)

        case .inch:
            guard let size = resolution.physicalPixelSize(.dpi) else { return .zero }
            return rectInUnits.scaled(widthFactor: size.x, heightFactor: size.y)
        }
    }

    /// Équivalent de `TCmdLineOptions.CalcContentRectForImage`.
    ///
    /// `contentMargins` a priorité sur `contentRect`. `nil` en retour signifie
    /// un échec (résolution manquante ou rectangle vide/hors image).
    public static func forImage(
        contentRect: FloatRect?,
        contentMargins: FloatRect?,
        unit: SizeUnit,
        imageBounds: IntRect,
        resolution: ResolutionInfo
    ) -> IntRect? {
        if contentRect == nil && contentMargins == nil {
            return imageBounds
        }

        var final: IntRect
        if let margins = contentMargins {
            let marginsInPx = calcRectInPixels(margins, unit: unit,
                                               imageBounds: imageBounds,
                                               resolution: resolution)
            if marginsInPx.isNull { return nil }
            final = IntRect(
                left: marginsInPx.left,
                top: marginsInPx.top,
                right: imageBounds.right - marginsInPx.right,
                bottom: imageBounds.bottom - marginsInPx.bottom)
        } else if let rect = contentRect {
            final = calcRectInPixels(rect, unit: unit,
                                     imageBounds: imageBounds,
                                     resolution: resolution)
        } else {
            return imageBounds
        }

        if final.isEmpty { return nil }
        final = final.intersect(imageBounds)
        if final.isEmpty { return nil }
        return final
    }
}
