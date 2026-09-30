//
//  BinaryImage.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Image binaire 1 bit par pixel, bits **empaquetés** (MSB en premier).
///
/// Équivalent de `ifBinary` d'Imaging : bit `1` = blanc, bit `0` = noir.
public struct BinaryImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Octets par ligne (`(width + 7) / 8`).
    public let bytesPerRow: Int
    /// Bits empaquetés, `1` = blanc.
    public var bits: [UInt8]

    public init(width: Int, height: Int) {
        precondition(width >= 0 && height >= 0, "dimensions négatives")
        self.width = width
        self.height = height
        self.bytesPerRow = (width + 7) / 8
        self.bits = [UInt8](repeating: 0, count: self.bytesPerRow * height)
    }

    public init(width: Int, height: Int, bits: [UInt8]) {
        let rowBytes = (width + 7) / 8
        precondition(bits.count == rowBytes * height, "taille de buffer invalide")
        self.width = width
        self.height = height
        self.bytesPerRow = rowBytes
        self.bits = bits
    }

    /// `true` si le pixel est blanc (bit `1`).
    @inline(__always)
    public func isWhite(_ x: Int, _ y: Int) -> Bool {
        (bits[y * bytesPerRow + x / 8] & (0x80 >> UInt8(x % 8))) != 0
    }

    @inline(__always)
    public mutating func setWhite(_ x: Int, _ y: Int, _ white: Bool) {
        let index = y * bytesPerRow + x / 8
        let mask: UInt8 = 0x80 >> UInt8(x % 8)
        if white { bits[index] |= mask } else { bits[index] &= ~mask }
    }

    /// Binarise une image grise : blanc si `valeur > seuil` (comme `EncodeBinary`
    /// d'Imaging, seuil 128 par défaut).
    public static func fromGray(_ gray: GrayImage, threshold: Int = 128) -> BinaryImage {
        var binary = BinaryImage(width: gray.width, height: gray.height)
        for y in 0..<gray.height {
            let rowBase = y * gray.width
            for x in 0..<gray.width where Int(gray.pixels[rowBase + x]) > threshold {
                binary.setWhite(x, y, true)
            }
        }
        return binary
    }

    /// Convertit en gris 8 bits (`0` ou `255`).
    public func toGray() -> GrayImage {
        var gray = GrayImage(uninitializedWidth: width, height: height)
        for y in 0..<height {
            let rowBase = y * width
            for x in 0..<width {
                gray.pixels[rowBase + x] = isWhite(x, y) ? 255 : 0
            }
        }
        return gray
    }
}
