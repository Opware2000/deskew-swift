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

    /// Construit un `CGImage` à partir d'une image de travail.
    public static func makeCGImage(_ image: PixelImage) -> CGImage? {
        switch image {
        case .gray(let gray):
            return makeCGImage(pixels: gray.pixels, width: gray.width, height: gray.height,
                               bitsPerPixel: 8, bytesPerRow: gray.width,
                               space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGImageAlphaInfo.none.rawValue)
        case .rgb(let rgb):
            return makeCGImage(pixels: rgb.pixels, width: rgb.width, height: rgb.height,
                               bitsPerPixel: 24, bytesPerRow: rgb.width * 3,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.none.rawValue)
        case .rgba(let rgba):
            return makeCGImage(pixels: rgba.pixels, width: rgba.width, height: rgba.height,
                               bitsPerPixel: 32, bytesPerRow: rgba.width * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.last.rawValue)
        }
    }

    private static func makeCGImage(pixels: [UInt8], width: Int, height: Int,
                                    bitsPerPixel: Int, bytesPerRow: Int,
                                    space: CGColorSpace, bitmapInfo: UInt32) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: bitsPerPixel,
                       bytesPerRow: bytesPerRow, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// Enregistre une image dans un fichier.
    public static func save(_ image: PixelImage, to path: String, options: ImageWriteOptions) throws {
        guard let uti = uti(forExtension: FilePath.fileExt(path)) else {
            throw ImageIOError.cannotWrite(path)
        }
        guard let cgImage = makeCGImage(image) else {
            throw ImageIOError.conversionFailed(path)
        }
        guard let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, uti as CFString, 1, nil) else {
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

        if !properties.isEmpty {
            CGImageDestinationSetProperties(destination, properties as CFDictionary)
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageIOError.cannotWrite(path)
        }
    }
}
