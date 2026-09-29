//
//  PixelTypes.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Format logique de pixel (sous-ensemble des formats utilisés par Deskew).
public enum PixelFormat: Equatable, Sendable {
    case binary   // 1 bit
    case index8   // 1 octet + palette
    case gray8    // 1 octet
    case rgb24    // 3 octets
    case rgba32   // 4 octets

    /// Nom affiché (équivalent de `GetFormatName` pour les formats supportés).
    public var name: String {
        switch self {
        case .binary: return "Binary"
        case .index8: return "Index8"
        case .gray8: return "Gray8"
        case .rgb24: return "R8G8B8"
        case .rgba32: return "A8R8G8B8"
        }
    }
}

/// Couleur 24 bits, ordre mémoire R, G, B.
public struct RGB24: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Couleur 32 bits.
///
/// L'ordre des champs reproduit l'ordre mémoire de `TColor32Rec` en Pascal
/// (B, G, R, A) ; la valeur entière correspond au format `0xAARRGGBB`.
public struct RGBA32: Equatable, Sendable {
    public var b: UInt8
    public var g: UInt8
    public var r: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Depuis une valeur `0xAARRGGBB` (comme `TColor32`).
    public init(color32: UInt32) {
        self.b = UInt8(color32 & 0xFF)
        self.g = UInt8((color32 >> 8) & 0xFF)
        self.r = UInt8((color32 >> 16) & 0xFF)
        self.a = UInt8((color32 >> 24) & 0xFF)
    }

    /// Vers une valeur `0xAARRGGBB`.
    public var color32: UInt32 {
        UInt32(b) | (UInt32(g) << 8) | (UInt32(r) << 16) | (UInt32(a) << 24)
    }

    public static let opaqueBlack = RGBA32(r: 0, g: 0, b: 0, a: 255)
    public static let black = RGBA32(r: 0, g: 0, b: 0, a: 0)

    public var isOpaque: Bool { a == 255 }
    public var isGray: Bool { r == g && b == g }
}
