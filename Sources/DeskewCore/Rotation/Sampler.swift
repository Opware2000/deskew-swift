//
//  Sampler.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Accès uniforme aux pixels d'une image, avec gestion du hors-bornes.
///
/// Équivalent des fonctions `GetPixelColor8/24/32` : hors image, renvoie la
/// couleur de fond.
struct Sampler {
    enum Kind {
        case gray8
        case rgb24
        case rgba32
    }

    let kind: Kind
    let width: Int
    let height: Int
    let background: RGBA32
    let bytes: [UInt8]

    init(kind: Kind, width: Int, height: Int, background: RGBA32, bytes: [UInt8]) {
        self.kind = kind
        self.width = width
        self.height = height
        self.background = background
        self.bytes = bytes
    }

    @inline(__always)
    func pixel(_ x: Int, _ y: Int) -> RGBA32 {
        guard x >= 0, y >= 0, x < width, y < height else {
            return background
        }
        switch kind {
        case .gray8:
            let v = bytes[y * width + x]
            return RGBA32(r: v, g: v, b: v, a: 255)
        case .rgb24:
            let i = (y * width + x) * 3
            return RGBA32(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: 255)
        case .rgba32:
            let i = (y * width + x) * 4
            return RGBA32(r: bytes[i + 2], g: bytes[i + 1], b: bytes[i], a: bytes[i + 3])
        }
    }

    /// Pixel sous forme vectorielle `(B, G, R, A)` pour l'accumulation SIMD.
    @inline(__always)
    func pixelVector(_ x: Int, _ y: Int) -> SIMD4<Float> {
        guard x >= 0, y >= 0, x < width, y < height else {
            return SIMD4<Float>(Float(background.b), Float(background.g),
                                Float(background.r), Float(background.a))
        }
        switch kind {
        case .gray8:
            let v = Float(bytes[y * width + x])
            return SIMD4<Float>(v, v, v, 255)
        case .rgb24:
            let i = (y * width + x) * 3
            return SIMD4<Float>(Float(bytes[i]), Float(bytes[i + 1]), Float(bytes[i + 2]), 255)
        case .rgba32:
            let i = (y * width + x) * 4
            return SIMD4<Float>(Float(bytes[i]), Float(bytes[i + 1]),
                                Float(bytes[i + 2]), Float(bytes[i + 3]))
        }
    }
}
