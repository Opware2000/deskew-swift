//
//  ImageLoader.swift
//  DeskewImageIO
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import CoreGraphics
import ImageIO
import DeskewCore

/// Erreurs de chargement/écriture d'images.
public enum ImageIOError: Error, CustomStringConvertible {
    case cannotOpen(String)
    case unsupportedFormat(String)
    case conversionFailed(String)
    case cannotWrite(String)
    case imageTooLarge(String)

    public var description: String {
        switch self {
        case .cannotOpen(let path): return "Impossible d'ouvrir le fichier image : \(path)"
        case .unsupportedFormat(let path): return "Format d'image non supporté : \(path)"
        case .conversionFailed(let path): return "Échec de conversion d'image : \(path)"
        case .cannotWrite(let path): return "Impossible d'écrire le fichier image : \(path)"
        case .imageTooLarge(let path): return "Image trop grande (dimensions ou nombre de pixels au-delà de la limite) : \(path)"
        }
    }
}

/// Image chargée depuis le disque, dans un format de travail.
public struct LoadedImage {
    public let image: PixelImage
    public let format: PixelFormat
    public let resolution: ResolutionInfo
    public let tiffCompression: TiffCompression?

    public var width: Int { image.width }
    public var height: Int { image.height }

    public func toGray() -> GrayImage { image.toGray() }
}

/// Chargement d'images via ImageIO / Core Graphics.
public enum ImageLoader {

    /// Borne de sécurité sur une dimension (pixels).
    public static let maxDimension = 100_000
    /// Borne de sécurité sur le nombre total de pixels.
    public static let maxPixels = 250_000_000

    /// Indique si le fichier est probablement lisible (vérification **peu
    /// coûteuse**, par extension — ne lit pas le contenu ; le décodage réel est
    /// fait par `load`).
    public static func canRead(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return readableExtensions.contains(FilePath.fileExt(path).lowercased())
    }

    /// Extensions lisibles via ImageIO.
    private static let readableExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "psd", "heic", "heif"
    ]

    /// Charge une image et la convertit en niveaux de gris 8 bits.
    public static func loadGray8(path: String) throws -> GrayImage {
        try load(path: path).toGray()
    }

    /// Charge une image dans un format de travail.
    public static func load(path: String) throws -> LoadedImage {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw ImageIOError.cannotOpen(path)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageIOError.unsupportedFormat(path)
        }

        // Frontière de confiance : bornes sur les dimensions d'une image non fiable
        // (évite un débordement ou une allocation démesurée).
        let pixelCount = cgImage.width.multipliedReportingOverflow(by: cgImage.height)
        guard cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= ImageLoader.maxDimension, cgImage.height <= ImageLoader.maxDimension,
              !pixelCount.overflow, pixelCount.partialValue <= ImageLoader.maxPixels else {
            throw ImageIOError.imageTooLarge(path)
        }

        let resolution = resolution(from: source)
        let tiffCompression = tiffCompression(from: source)
        let sourceFormat = sourceFormat(from: source, cgImage: cgImage)

        // Image monochrome sans alpha : lecture directe en Gray8.
        if cgImage.colorSpace?.model == .monochrome,
           cgImage.alphaInfo == .none || cgImage.alphaInfo == .noneSkipLast || cgImage.alphaInfo == .noneSkipFirst {
            let gray = try drawGray(cgImage, path: path)
            return LoadedImage(image: .gray(gray), format: sourceFormat,
                               resolution: resolution, tiffCompression: tiffCompression)
        }

        if hasAlphaChannel(cgImage) {
            let rgba = try drawRGBA(cgImage, path: path)
            return LoadedImage(image: .rgba(rgba), format: sourceFormat,
                               resolution: resolution, tiffCompression: tiffCompression)
        } else {
            let rgb = try drawRGB(cgImage, path: path)
            let isIndexed = cgImage.colorSpace?.model == .indexed
            // Image indexée (palette) : ImageIO l'étend en RGB. On reproduit la
            // décision d'Imaging « palette en niveaux de gris -> Gray8 » en
            // analysant le contenu décodé.
            if isIndexed, rgb.isGrayscale {
                let gray = PixelImage.rgb(rgb).toGray()
                return LoadedImage(image: .gray(gray), format: sourceFormat,
                                   resolution: resolution, tiffCompression: tiffCompression)
            }
            return LoadedImage(image: .rgb(rgb), format: sourceFormat,
                               resolution: resolution, tiffCompression: tiffCompression)
        }
    }

    /// Format source affiché (équivalent des noms de format d'Imaging).
    ///
    /// Déduit des propriétés de la source (profondeur, modèle de couleur) et de
    /// l'espace colorimétrique décodé : 1 bit → Binary, indexé → Index8,
    /// gris → Gray8, alpha → A8R8G8B8, sinon → R8G8B8.
    private static func sourceFormat(from source: CGImageSource, cgImage: CGImage) -> PixelFormat {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let depth = properties?[kCGImagePropertyDepth] as? Int ?? 8
        let colorModel = properties?[kCGImagePropertyColorModel] as? String

        if depth == 1 { return .binary }
        if cgImage.colorSpace?.model == .indexed { return .index8 }
        if colorModel == "Gray" { return .gray8 }
        if hasAlphaChannel(cgImage) { return .rgba32 }
        return .rgb24
    }

    /// Compression TIFF de l'image source (pour l'option `tinput`).
    private static func tiffCompression(from source: CGImageSource) -> TiffCompression? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let value = tiff[kCGImagePropertyTIFFCompression] as? Int {
            return TiffCompression.fromTagValue(value)
        }
        if let value = properties[kCGImagePropertyTIFFCompression] as? Int {
            return TiffCompression.fromTagValue(value)
        }
        return nil
    }

    // MARK: - Helpers

    private static func hasAlphaChannel(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }

    private static func resolution(from source: CGImageSource) -> ResolutionInfo {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .unknown
        }
        if let x = properties[kCGImagePropertyDPIWidth] as? Double,
           let y = properties[kCGImagePropertyDPIHeight] as? Double {
            return .from(dpiX: x, dpiY: y)
        }
        return .unknown
    }

    /// Espace colorimétrique source si son modèle correspond, sinon un espace
    /// device. Utiliser l'espace source évite toute conversion colorimétrique.
    private static func rgbSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb { return space }
        return CGColorSpaceCreateDeviceRGB()
    }

    private static func graySpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .monochrome { return space }
        return CGColorSpaceCreateDeviceGray()
    }

    private static func drawGray(_ cgImage: CGImage, path: String) throws -> GrayImage {
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height)
        let colorSpace = graySpace(for: cgImage)

        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw ImageIOError.conversionFailed(path) }
        return GrayImage(width: width, height: height, pixels: buffer)
    }

    private static func drawRGB(_ cgImage: CGImage, path: String) throws -> RGBImage {
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = rgbSpace(for: cgImage)
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw ImageIOError.conversionFailed(path) }

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            let s = i * 4 // BGRA (noneSkipFirst + little endian)
            rgb[i * 3] = buffer[s + 2]
            rgb[i * 3 + 1] = buffer[s + 1]
            rgb[i * 3 + 2] = buffer[s]
        }
        return RGBImage(width: width, height: height, pixels: rgb)
    }

    private static func drawRGBA(_ cgImage: CGImage, path: String) throws -> RGBAImage {
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = rgbSpace(for: cgImage)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw ImageIOError.conversionFailed(path) }

        // Layout mémoire BGRA prémultiplié -> RGBA droit (comme TColor32Rec).
        for i in 0..<(width * height) {
            let s = i * 4
            let a = buffer[s + 3]
            if a > 0 && a < 255 {
                buffer[s] = UInt8(min(255, Int(buffer[s]) * 255 / Int(a)))
                buffer[s + 1] = UInt8(min(255, Int(buffer[s + 1]) * 255 / Int(a)))
                buffer[s + 2] = UInt8(min(255, Int(buffer[s + 2]) * 255 / Int(a)))
            }
        }
        return RGBAImage(width: width, height: height, pixels: buffer)
    }
}
