//
//  Palette.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Palette d'une image indexée.
///
/// Reproduction de `PaletteHasAlpha` et `PaletteIsGrayScale`
/// (`ImagingFormats.pas`).
public struct Palette: Equatable, Sendable {
    public var entries: [RGBA32]

    public init(entries: [RGBA32]) {
        self.entries = entries
    }

    /// `true` si une entrée au moins a un canal alpha différent de 255.
    public var hasAlpha: Bool {
        for entry in entries where entry.a != 255 {
            return true
        }
        return false
    }

    /// `true` si toutes les entrées sont en niveaux de gris (R == G == B).
    public var isGrayScale: Bool {
        for entry in entries where entry.r != entry.g || entry.r != entry.b {
            return false
        }
        return true
    }
}

extension PixelFormat {

    /// Format de travail à utiliser pour la rotation d'une image indexée,
    /// équivalent de la branche `ifIndex8` de `EnsurePixelFormatForRotation`
    /// suivie de l'ajustement selon la couleur de fond.
    public static func rotationFormat(palette: Palette, background: RGBA32) -> PixelFormat {
        var format: PixelFormat
        if palette.hasAlpha {
            format = .rgba32
        } else if palette.isGrayScale {
            format = .gray8
        } else {
            format = .rgb24
        }

        if background.a != 255 {
            format = .rgba32
        } else if format == .gray8 && !background.isGray {
            format = .rgb24
        }
        return format
    }
}
