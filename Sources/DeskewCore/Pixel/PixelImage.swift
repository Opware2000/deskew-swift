//
//  PixelImage.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Image dans l'un des formats de travail supportés.
public enum PixelImage {
    case gray(GrayImage)
    case rgb(RGBImage)
    case rgba(RGBAImage)

    public var width: Int {
        switch self {
        case .gray(let image): return image.width
        case .rgb(let image): return image.width
        case .rgba(let image): return image.width
        }
    }

    public var height: Int {
        switch self {
        case .gray(let image): return image.height
        case .rgb(let image): return image.height
        case .rgba(let image): return image.height
        }
    }

    public var format: PixelFormat {
        switch self {
        case .gray: return .gray8
        case .rgb: return .rgb24
        case .rgba: return .rgba32
        }
    }

    public var bounds: IntRect { IntRect(left: 0, top: 0, right: width, bottom: height) }

    /// Luminance d'Imaging (`Color32ToGray`).
    @inline(__always)
    public static func luminance(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        let value = Float(0.299) * Float(r) + Float(0.587) * Float(g) + Float(0.114) * Float(b)
        return DeskewMath.clampToByte(DeskewMath.pascalRound(value))
    }

    /// Conversion en niveaux de gris (équivalent de `Format := ifGray8`).
    public func toGray() -> GrayImage {
        switch self {
        case .gray(let image):
            return image
        case .rgb(let image):
            var gray = GrayImage(width: image.width, height: image.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let pixel = image[x, y]
                    gray[x, y] = PixelImage.luminance(r: pixel.r, g: pixel.g, b: pixel.b)
                }
            }
            return gray
        case .rgba(let image):
            var gray = GrayImage(width: image.width, height: image.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let pixel = image[x, y]
                    gray[x, y] = PixelImage.luminance(r: pixel.r, g: pixel.g, b: pixel.b)
                }
            }
            return gray
        }
    }

    /// Conversion vers un format de sortie.
    ///
    /// `binary` applique le seuillage d'Imaging (`> 128 → 255`, sinon `0`) et
    /// est stocké en Gray8 (le rendu 1 bit réel n'est pas nécessaire pour la
    /// comparaison pixel). `index8` est approximé par Gray8/RGB24.
    public func converted(to target: PixelFormat) -> PixelImage {
        switch target {
        case .gray8:
            if case .gray = self { return self }
            return .gray(toGray())

        case .binary:
            var gray = toGray()
            for i in 0..<gray.pixels.count {
                gray.pixels[i] = gray.pixels[i] > 128 ? 255 : 0
            }
            return .gray(gray)

        case .index8:
            return converted(to: .rgb24)

        case .rgb24:
            switch self {
            case .rgb: return self
            case .gray(let image):
                var rgb = RGBImage(width: image.width, height: image.height)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let v = image[x, y]
                        rgb[x, y] = RGB24(r: v, g: v, b: v)
                    }
                }
                return .rgb(rgb)
            case .rgba(let image):
                var rgb = RGBImage(width: image.width, height: image.height)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let p = image[x, y]
                        rgb[x, y] = RGB24(r: p.r, g: p.g, b: p.b)
                    }
                }
                return .rgb(rgb)
            }

        case .rgba32:
            switch self {
            case .rgba: return self
            case .gray(let image):
                var rgba = RGBAImage(width: image.width, height: image.height)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let v = image[x, y]
                        rgba[x, y] = RGBA32(r: v, g: v, b: v, a: 255)
                    }
                }
                return .rgba(rgba)
            case .rgb(let image):
                var rgba = RGBAImage(width: image.width, height: image.height)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let p = image[x, y]
                        rgba[x, y] = RGBA32(r: p.r, g: p.g, b: p.b, a: 255)
                    }
                }
                return .rgba(rgba)
            }
        }
    }

    /// Équivalent de `EnsurePixelFormatForRotation`.
    public func ensureRotatable(background: RGBA32) -> PixelImage {
        var image = self
        if background.a != 255 {
            image = image.converted(to: .rgba32)
        } else if case .gray = image, !background.isGray {
            image = image.converted(to: .rgb24)
        }
        return image
    }

    /// Rotation en place selon le filtre.
    public func rotated(angleDegrees: Double, background: RGBA32,
                        filter: ResamplingFilter, fitRotated: Bool) -> PixelImage {
        switch self {
        case .gray(var image):
            ImageRotation.rotate(&image, angleDegrees: angleDegrees, background: background,
                                 filter: filter, fitRotated: fitRotated)
            return .gray(image)
        case .rgb(var image):
            ImageRotation.rotate(&image, angleDegrees: angleDegrees, background: background,
                                 filter: filter, fitRotated: fitRotated)
            return .rgb(image)
        case .rgba(var image):
            ImageRotation.rotate(&image, angleDegrees: angleDegrees, background: background,
                                 filter: filter, fitRotated: fitRotated)
            return .rgba(image)
        }
    }
}
