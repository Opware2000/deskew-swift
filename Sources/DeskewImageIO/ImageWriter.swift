//
//  ImageWriter.swift
//  DeskewImageIO
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import CoreGraphics
import ImageIO
import DeskewCore

/// Options d'écriture d'image.
public struct ImageWriteOptions {
    public var jpegQuality: Int?
    public var tiffCompression: TiffCompression?
    public var resolution: ResolutionInfo

    public init(jpegQuality: Int? = nil, tiffCompression: TiffCompression? = nil,
                resolution: ResolutionInfo = .unknown) {
        self.jpegQuality = jpegQuality
        self.tiffCompression = tiffCompression
        self.resolution = resolution
    }
}

/// Écriture d'images via ImageIO / Core Graphics.
public enum ImageWriter {

    /// UTI correspondant à une extension de fichier.
    public static func uti(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "public.png"
        case "jpg", "jpeg": return "public.jpeg"
        case "tif", "tiff": return "public.tiff"
        case "gif": return "com.compuserve.gif"
        case "bmp": return "com.microsoft.bmp"
        default: return nil
        }
    }

    /// Indique si l'extension de sortie est supportée en écriture.
    public static func canWrite(_ path: String) -> Bool {
        uti(forExtension: FilePath.fileExt(path)) != nil
    }

    /// Compression TIFF par défaut (comme l'original) : 1 bit → G4, sinon LZW.
    private static func defaultTiffCompression(for image: PixelImage) -> TiffCompression {
        if case .binary = image { return .g4 }
        return .lzw
    }

    /// Enregistre une image dans un fichier.
    public static func save(_ image: PixelImage, to path: String, options: ImageWriteOptions) throws {
        let ext = FilePath.fileExt(path).lowercased()

        // TIFF : utiliser libtiff si disponible, pour un contrôle exact de la
        // compression (LZW, RLE, Deflate, JPEG, G4) qu'ImageIO n'offre pas.
        // Compression par défaut comme l'original : 1 bit -> G4, sinon LZW.
        if ext == "tif" || ext == "tiff" {
            let compression = options.tiffCompression ?? defaultTiffCompression(for: image)
            if TiffWriter.canWrite(image, compression: compression) {
                let dpi = options.resolution.physicalPixelSize(.dpi)
                try TiffWriter.save(image, to: path, compression: compression, dpi: dpi)
                return
            }
        }

        guard let uti = uti(forExtension: FilePath.fileExt(path)) else {
            throw ImageIOError.cannotWrite(path)
        }

        var properties: [CFString: Any] = [:]
        if let quality = options.jpegQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100.0
        }
        if let size = options.resolution.physicalPixelSize(.dpi) {
            properties[kCGImagePropertyDPIWidth] = Int(size.x.rounded())
            properties[kCGImagePropertyDPIHeight] = Int(size.y.rounded())
        }
        if let compression = options.tiffCompression, let value = compression.tiffTagValue {
            properties[kCGImagePropertyTIFFCompression] = value
        }

        // Le `CGImage` est créé sans copier le tampon : il n'est valide que pendant
        // la fermeture, qui réalise l'écriture complète (Finalize synchrone).
        try withCGImage(image) { cgImage in
            guard let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, uti as CFString, 1, nil) else {
                throw ImageIOError.cannotWrite(path)
            }
            if !properties.isEmpty {
                CGImageDestinationSetProperties(destination, properties as CFDictionary)
            }
            CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ImageIOError.cannotWrite(path)
            }
        }
    }

    // MARK: - CGImage sans copie

    /// Construit un `CGImage` partageant (sans copie) le tampon de l'image et le
    /// passe à `body`. Le `CGImage` ne doit pas survivre à `body`.
    private static func withCGImage<T>(_ image: PixelImage,
                                       _ body: (CGImage) throws -> T) throws -> T {
        switch image {
        case .binary(let binary):
            return try binary.bits.withUnsafeBytes { raw in
                guard let cgImage = makeCGImage(raw, width: binary.width, height: binary.height,
                                                bitsPerComponent: 1, bitsPerPixel: 1,
                                                bytesPerRow: binary.bytesPerRow,
                                                space: CGColorSpaceCreateDeviceGray(),
                                                bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                    throw ImageIOError.conversionFailed("binary")
                }
                return try body(cgImage)
            }
        case .gray(let gray):
            return try gray.pixels.withUnsafeBytes { raw in
                guard let cgImage = makeCGImage(raw, width: gray.width, height: gray.height,
                                                bitsPerComponent: 8, bitsPerPixel: 8,
                                                bytesPerRow: gray.width,
                                                space: CGColorSpaceCreateDeviceGray(),
                                                bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                    throw ImageIOError.conversionFailed("gray")
                }
                return try body(cgImage)
            }
        case .rgb(let rgb):
            return try rgb.pixels.withUnsafeBytes { raw in
                guard let cgImage = makeCGImage(raw, width: rgb.width, height: rgb.height,
                                                bitsPerComponent: 8, bitsPerPixel: 24,
                                                bytesPerRow: rgb.width * 3,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                    throw ImageIOError.conversionFailed("rgb")
                }
                return try body(cgImage)
            }
        case .rgba(let rgba):
            // Notre buffer est B,G,R,A (comme TColor32Rec) ; CGImage avec
            // alphaInfo `.last` + big-endian attend R,G,B,A. Ce réordonnancement
            // nécessite un tampon temporaire (valide pendant `body`).
            var ordered = [UInt8](repeating: 0, count: rgba.pixels.count)
            for i in 0..<(rgba.width * rgba.height) {
                let s = i * 4
                ordered[s] = rgba.pixels[s + 2]     // R
                ordered[s + 1] = rgba.pixels[s + 1] // G
                ordered[s + 2] = rgba.pixels[s]     // B
                ordered[s + 3] = rgba.pixels[s + 3] // A
            }
            return try ordered.withUnsafeBytes { raw in
                guard let cgImage = makeCGImage(raw, width: rgba.width, height: rgba.height,
                                                bitsPerComponent: 8, bitsPerPixel: 32,
                                                bytesPerRow: rgba.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.last.rawValue
                                                    | CGBitmapInfo.byteOrder32Big.rawValue) else {
                    throw ImageIOError.conversionFailed("rgba")
                }
                return try body(cgImage)
            }
        }
    }

    /// `CGImage` pointant sur `raw` **sans copie** (durée de vie gérée par l'appelant).
    private static func makeCGImage(_ raw: UnsafeRawBufferPointer, width: Int, height: Int,
                                    bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
                                    space: CGColorSpace, bitmapInfo: UInt32) -> CGImage? {
        guard let base = raw.baseAddress else { return nil }
        let provider = CGDataProvider(dataInfo: nil, data: base, size: raw.count,
                                      releaseData: { _, _, _ in })
        guard let provider = provider else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerPixel,
                       bytesPerRow: bytesPerRow, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
