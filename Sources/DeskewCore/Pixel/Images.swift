//
//  Images.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Image en niveaux de gris 8 bits, lignes contiguës (`stride == width`).
///
/// Reproduit l'accès mémoire plat de `TImageData` (index `y * width + x`).
public struct GrayImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        precondition(width >= 0 && height >= 0, "dimensions négatives")
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: fill, count: width * height)
    }

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "taille de buffer invalide")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public var bounds: IntRect { IntRect(left: 0, top: 0, right: width, bottom: height) }
    public var isValid: Bool { width > 0 && height > 0 && pixels.count == width * height }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    public mutating func fill(_ value: UInt8) {
        for i in pixels.indices { pixels[i] = value }
    }

    /// Remplit un rectangle (clippé aux bornes de l'image).
    public mutating func fill(rect: IntRect, _ value: UInt8) {
        let r = rect.intersect(bounds)
        guard !r.isEmpty else { return }
        for y in r.top..<r.bottom {
            let base = y * width
            for x in r.left..<r.right {
                pixels[base + x] = value
            }
        }
    }
}

/// Image RGB 24 bits, 3 octets par pixel, ordre mémoire R, G, B.
public struct RGBImage: Equatable, Sendable {
    public static let bytesPerPixel = 3

    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, fill: RGB24 = RGB24(r: 0, g: 0, b: 0)) {
        precondition(width >= 0 && height >= 0, "dimensions négatives")
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
        if fill != RGB24(r: 0, g: 0, b: 0) {
            self.fill(fill)
        }
    }

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * Self.bytesPerPixel,
                     "taille de buffer invalide")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public var bounds: IntRect { IntRect(left: 0, top: 0, right: width, bottom: height) }
    public var isValid: Bool {
        width > 0 && height > 0 && pixels.count == width * height * Self.bytesPerPixel
    }

    public subscript(x: Int, y: Int) -> RGB24 {
        get {
            let i = (y * width + x) * Self.bytesPerPixel
            return RGB24(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2])
        }
        set {
            let i = (y * width + x) * Self.bytesPerPixel
            pixels[i] = newValue.r
            pixels[i + 1] = newValue.g
            pixels[i + 2] = newValue.b
        }
    }

    public mutating func fill(_ value: RGB24) {
        var i = 0
        while i < pixels.count {
            pixels[i] = value.r
            pixels[i + 1] = value.g
            pixels[i + 2] = value.b
            i += Self.bytesPerPixel
        }
    }
}

/// Image ARGB 32 bits, 4 octets par pixel, ordre mémoire B, G, R, A
/// (identique à `TColor32Rec`).
public struct RGBAImage: Equatable, Sendable {
    public static let bytesPerPixel = 4

    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, fill: RGBA32 = RGBA32(r: 0, g: 0, b: 0, a: 0)) {
        precondition(width >= 0 && height >= 0, "dimensions négatives")
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
        if fill != RGBA32(r: 0, g: 0, b: 0, a: 0) {
            self.fill(fill)
        }
    }

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * Self.bytesPerPixel,
                     "taille de buffer invalide")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public var bounds: IntRect { IntRect(left: 0, top: 0, right: width, bottom: height) }
    public var isValid: Bool {
        width > 0 && height > 0 && pixels.count == width * height * Self.bytesPerPixel
    }

    public subscript(x: Int, y: Int) -> RGBA32 {
        get {
            let i = (y * width + x) * Self.bytesPerPixel
            return RGBA32(r: pixels[i + 2], g: pixels[i + 1], b: pixels[i], a: pixels[i + 3])
        }
        set {
            let i = (y * width + x) * Self.bytesPerPixel
            pixels[i] = newValue.b
            pixels[i + 1] = newValue.g
            pixels[i + 2] = newValue.r
            pixels[i + 3] = newValue.a
        }
    }

    public mutating func fill(_ value: RGBA32) {
        var i = 0
        while i < pixels.count {
            pixels[i] = value.b
            pixels[i + 1] = value.g
            pixels[i + 2] = value.r
            pixels[i + 3] = value.a
            i += Self.bytesPerPixel
        }
    }
}
