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

    public var description: String {
        switch self {
        case .cannotOpen(let path): return "Impossible d'ouvrir le fichier image : \(path)"
        case .unsupportedFormat(let path): return "Format d'image non supporté : \(path)"
        case .conversionFailed(let path): return "Échec de conversion d'image : \(path)"
        }
    }
}

/// Image chargée depuis le disque, dans un format de travail.
public struct LoadedImage {
    public enum Storage {
        case gray(GrayImage)
        case rgb(RGBImage)
        case rgba(RGBAImage)
    }

    public let storage: Storage
    public let format: PixelFormat
    public let resolution: ResolutionInfo

    public var width: Int {
        switch storage {
        case .gray(let image): return image.width
        case .rgb(let image): return image.width
        case .rgba(let image): return image.width
        }
    }

    public var height: Int {
        switch storage {
        case .gray(let image): return image.height
        case .rgb(let image): return image.height
        case .rgba(let image): return image.height
        }
    }

    /// Conversion en niveaux de gris 8 bits (équivalent de `Format := ifGray8`).
    ///
    /// Les sources déjà grises sont conservées telles quelles ; les sources
    /// couleur utilisent la luminance d'Imaging
    /// `Round(0.299·R + 0.587·G + 0.114·B)`.
    public func toGray() -> GrayImage {
        switch storage {
        case .gray(let image):
            return image
        case .rgb(let image):
            var gray = GrayImage(width: image.width, height: image.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let pixel = image[x, y]
                    gray[x, y] = ImageLoader.luminance(r: pixel.r, g: pixel.g, b: pixel.b)
                }
            }
            return gray
        case .rgba(let image):
            var gray = GrayImage(width: image.width, height: image.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let pixel = image[x, y]
                    gray[x, y] = ImageLoader.luminance(r: pixel.r, g: pixel.g, b: pixel.b)
                }
            }
            return gray
        }
    }
}

/// Chargement d'images via ImageIO / Core Graphics.
public enum ImageLoader {

    /// Luminance d'Imaging (`Color32ToGray`) : pondérations 0.299 / 0.587 / 0.114.
    @inline(__always)
    public static func luminance(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        let value = Float(0.299) * Float(r) + Float(0.587) * Float(g) + Float(0.114) * Float(b)
        return DeskewMath.clampToByte(DeskewMath.pascalRound(value))
    }

    /// Indique si le fichier est lisible comme image.
    public static func canRead(_ path: String) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

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

        let resolution = resolution(from: source)

        // Image monochrome sans alpha : lecture directe en Gray8.
        if cgImage.colorSpace?.model == .monochrome,
           cgImage.alphaInfo == .none || cgImage.alphaInfo == .noneSkipLast || cgImage.alphaInfo == .noneSkipFirst {
            let gray = try drawGray(cgImage, path: path)
            return LoadedImage(storage: .gray(gray), format: .gray8, resolution: resolution)
        }

        let hasAlpha = hasAlphaChannel(cgImage)
        if hasAlpha {
            let rgba = try drawRGBA(cgImage, path: path)
            return LoadedImage(storage: .rgba(rgba), format: .rgba32, resolution: resolution)
        } else {
            let rgb = try drawRGB(cgImage, path: path)
            return LoadedImage(storage: .rgb(rgb), format: .rgb24, resolution: resolution)
        }
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
        let dpiX = properties[kCGImagePropertyDPIWidth] as? Double
        let dpiY = properties[kCGImagePropertyDPIHeight] as? Double
        if let x = dpiX, let y = dpiY {
            return .from(dpiX: x, dpiY: y)
        }
        return .unknown
    }

    private static func drawGray(_ cgImage: CGImage, path: String) throws -> GrayImage {
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

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
        let colorSpace = CGColorSpaceCreateDeviceRGB()
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
        let colorSpace = CGColorSpaceCreateDeviceRGB()
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
