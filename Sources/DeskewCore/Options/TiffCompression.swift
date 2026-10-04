//
//  TiffCompression.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Schéma de compression TIFF (équivalent des `TiffCompressionOption*` + `input`).
public enum TiffCompression: String, CaseIterable, Equatable, Sendable {
    case none
    case lzw
    case rle
    case deflate
    case jpeg
    case g4
    /// Reprendre la compression du fichier d'entrée.
    case input
    /// Comme `input`, mais jamais avec perte : un JPEG d'entrée est écrit en LZW.
    case inputLossless = "input-lossless"

    /// Valeur du tag TIFF `Compression` correspondant, si définie indépendamment
    /// de l'entrée. `nil` pour `input`/`input-lossless` (résolus à partir des métadonnées).
    public var tiffTagValue: Int? {
        switch self {
        case .none: return 1
        case .lzw: return 5
        case .rle: return 32773
        case .deflate: return 8
        case .jpeg: return 7
        case .g4: return 4
        case .input, .inputLossless: return nil
        }
    }

    /// Noms utilisés par la bibliothèque Imaging (pour `TrySetTiffCompressionFromMetadata`).
    public static func fromMetadataName(_ name: String) -> TiffCompression? {
        switch name {
        case "None": return TiffCompression.none
        case "LZW": return .lzw
        case "JPEG": return .jpeg
        case "Deflate": return .deflate
        case "Packbits RLE": return .rle
        case "CCITT Group 4 Fax", "CCITT": return .g4
        default: return nil
        }
    }

    /// Depuis la valeur du tag TIFF `Compression`.
    public static func fromTagValue(_ value: Int) -> TiffCompression? {
        switch value {
        case 1: return TiffCompression.none
        case 5: return .lzw
        case 32773: return .rle
        case 8, 32946: return .deflate
        case 7: return .jpeg
        case 4: return .g4
        default: return nil
        }
    }
}
