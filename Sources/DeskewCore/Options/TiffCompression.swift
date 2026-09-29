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

    /// Valeur du tag TIFF `Compression` correspondant, si définie indépendamment
    /// de l'entrée. `nil` pour `input` (résolu à partir des métadonnées).
    public var tiffTagValue: Int? {
        switch self {
        case .none: return 1
        case .lzw: return 5
        case .rle: return 32773
        case .deflate: return 8
        case .jpeg: return 7
        case .g4: return 4
        case .input: return nil
        }
    }

    /// Noms utilisés par la bibliothèque Imaging (pour `TrySetTiffCompressionFromMetadata`).
    public static func fromMetadataName(_ name: String) -> TiffCompression? {
        switch name {
        case "None": return .none
        case "LZW": return .lzw
        case "JPEG": return .jpeg
        case "Deflate": return .deflate
        case "CCITT Group 4 Fax", "CCITT": return .g4
        default: return nil
        }
    }
}
