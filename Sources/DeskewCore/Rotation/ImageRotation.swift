//
//  ImageRotation.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import Dispatch

/// Rotation d'image avec rééchantillonnage.
///
/// Reproduction fidèle de `ImageUtils.RotateImage` (et de
/// `Imaging.RotateImageMul90` pour les multiples de 90°).
public enum ImageRotation {

    /// `FloatEps` de l'original.
    static let floatEps = 1e-6

    // MARK: - API publique

    public static func rotate(_ image: inout GrayImage, angleDegrees: Double,
                              background: RGBA32, filter: ResamplingFilter,
                              fitRotated: Bool) {
        switch plan(srcWidth: image.width, srcHeight: image.height,
                    angleDegrees: angleDegrees, filter: filter, fitRotated: fitRotated) {
        case .noOp:
            return
        case .rotate90(let degrees):
            rotate90(&image, degrees: degrees)
        case .general(let plan):
            let sampler = Sampler(kind: .gray8, width: image.width, height: image.height,
                                  background: background, bytes: image.pixels)
            var destination = GrayImage(width: plan.dstWidth, height: plan.dstHeight)
            destination.pixels.withUnsafeMutableBufferPointer { buffer in
                renderParallel(sampler: sampler, filter: filter, plan: plan, background: background) { index, color in
                    buffer[index] = color.b
                }
            }
            image = destination
        }
    }

    public static func rotate(_ image: inout RGBImage, angleDegrees: Double,
                              background: RGBA32, filter: ResamplingFilter,
                              fitRotated: Bool) {
        switch plan(srcWidth: image.width, srcHeight: image.height,
                    angleDegrees: angleDegrees, filter: filter, fitRotated: fitRotated) {
        case .noOp:
            return
        case .rotate90(let degrees):
            rotate90(&image, degrees: degrees)
        case .general(let plan):
            let sampler = Sampler(kind: .rgb24, width: image.width, height: image.height,
                                  background: background, bytes: image.pixels)
            var destination = RGBImage(width: plan.dstWidth, height: plan.dstHeight)
            destination.pixels.withUnsafeMutableBufferPointer { buffer in
                renderParallel(sampler: sampler, filter: filter, plan: plan, background: background) { index, color in
                    let i = index * RGBImage.bytesPerPixel
                    buffer[i] = color.r
                    buffer[i + 1] = color.g
                    buffer[i + 2] = color.b
                }
            }
            image = destination
        }
    }

    public static func rotate(_ image: inout RGBAImage, angleDegrees: Double,
                              background: RGBA32, filter: ResamplingFilter,
                              fitRotated: Bool) {
        switch plan(srcWidth: image.width, srcHeight: image.height,
                    angleDegrees: angleDegrees, filter: filter, fitRotated: fitRotated) {
        case .noOp:
            return
        case .rotate90(let degrees):
            rotate90(&image, degrees: degrees)
        case .general(let plan):
            let sampler = Sampler(kind: .rgba32, width: image.width, height: image.height,
                                  background: background, bytes: image.pixels)
            var destination = RGBAImage(width: plan.dstWidth, height: plan.dstHeight)
            destination.pixels.withUnsafeMutableBufferPointer { buffer in
                renderParallel(sampler: sampler, filter: filter, plan: plan, background: background) { index, color in
                    let i = index * RGBAImage.bytesPerPixel
                    buffer[i] = color.b
                    buffer[i + 1] = color.g
                    buffer[i + 2] = color.r
                    buffer[i + 3] = color.a
                }
            }
            image = destination
        }
    }

    // MARK: - Plan de rotation

    struct RotationPlan {
        var forwardSin: Float
        var forwardCos: Float
        var backwardSin: Float
        var backwardCos: Float
        var srcWidthHalf: Float
        var srcHeightHalf: Float
        var dstWidth: Int
        var dstHeight: Int
        var dstWidthHalf: Float
        var dstHeightHalf: Float
    }

    enum Plan {
        case noOp
        case rotate90(Int)
        case general(RotationPlan)
    }

    static func plan(srcWidth: Int, srcHeight: Int, angleDegrees: Double,
                     filter: ResamplingFilter, fitRotated: Bool) -> Plan {
        var angle = angleDegrees
        while angle >= 360 { angle -= 360 }
        while angle < 0 { angle += 360 }

        if sameValue(angle, 0) || sameValue(angle, 360) { return .noOp }
        if sameValue(angle, 90) { return .rotate90(90) }
        if sameValue(angle, 180) { return .rotate90(180) }
        if sameValue(angle, 270) { return .rotate90(270) }

        let angleRad = Float(angle * Double.pi / 180.0)
        let forwardSin = sin(angleRad)
        let forwardCos = cos(angleRad)
        let backwardSin = sin(-angleRad)
        let backwardCos = cos(-angleRad)

        let w = Float(srcWidth)
        let h = Float(srcHeight)

        var dstWidth: Int
        var dstHeight: Int
        if fitRotated {
            dstWidth = Int(ceil(abs(w * forwardCos) + abs(h * forwardSin)))
            dstHeight = Int(ceil(abs(w * forwardSin) + abs(h * forwardCos)))
            if filter != .nearest {
                dstWidth += 1
                dstHeight += 1
            }
        } else {
            dstWidth = srcWidth
            dstHeight = srcHeight
        }
        if dstWidth <= 0 { dstWidth = 1 }
        if dstHeight <= 0 { dstHeight = 1 }

        return .general(RotationPlan(
            forwardSin: forwardSin,
            forwardCos: forwardCos,
            backwardSin: backwardSin,
            backwardCos: backwardCos,
            srcWidthHalf: Float(srcWidth - 1) / 2,
            srcHeightHalf: Float(srcHeight - 1) / 2,
            dstWidth: dstWidth,
            dstHeight: dstHeight,
            dstWidthHalf: Float(dstWidth - 1) / 2,
            dstHeightHalf: Float(dstHeight - 1) / 2))
    }

    @inline(__always)
    static func sameValue(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= Double(floatEps)
    }

    // MARK: - Rendu général

    /// Seuil en dessous duquel on reste séquentiel.
    static let parallelThreshold = 100_000

    /// Rend l'image destination par bandes de lignes en parallèle.
    static func renderParallel(sampler: Sampler, filter: ResamplingFilter, plan: RotationPlan,
                               background: RGBA32, write: (Int, RGBA32) -> Void) {
        let dstH = plan.dstHeight
        let total = plan.dstWidth * dstH
        if total < parallelThreshold {
            render(sampler: sampler, filter: filter, plan: plan, background: background,
                   rows: 0..<dstH, write: write)
            return
        }
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let bandHeight = max(1, (dstH + threads * 4 - 1) / (threads * 4))
        let bands = (dstH + bandHeight - 1) / bandHeight
        DispatchQueue.concurrentPerform(iterations: bands) { band in
            let y0 = band * bandHeight
            let y1 = min(y0 + bandHeight, dstH)
            if y0 < y1 {
                render(sampler: sampler, filter: filter, plan: plan, background: background,
                       rows: y0..<y1, write: write)
            }
        }
    }

    static func render(sampler: Sampler, filter: ResamplingFilter, plan: RotationPlan,
                       background: RGBA32, rows: Range<Int>,
                       write: (Int, RGBA32) -> Void) {
        let srcW = Float(sampler.width)
        let srcH = Float(sampler.height)
        let dstW = plan.dstWidth

        @inline(__always)
        func sourceCoordinates(_ dstX: Int, _ dstY: Int) -> (Float, Float) {
            let dstCoordX = Float(dstX) - plan.dstWidthHalf
            let dstCoordY = plan.dstHeightHalf - Float(dstY)
            let srcCoordX = plan.backwardCos * dstCoordX - plan.backwardSin * dstCoordY
            let srcCoordY = plan.backwardSin * dstCoordX + plan.backwardCos * dstCoordY
            return (srcCoordX + plan.srcWidthHalf, plan.srcHeightHalf - srcCoordY)
        }

        switch filter {
        case .nearest:
            for y in rows {
                for x in 0..<dstW {
                    let (sx, sy) = sourceCoordinates(x, y)
                    let color: RGBA32
                    if sx >= 0 && sy >= 0 && sx < srcW && sy < srcH {
                        let ix = min(max(DeskewMath.pascalRound(sx), 0), sampler.width - 1)
                        let iy = min(max(DeskewMath.pascalRound(sy), 0), sampler.height - 1)
                        color = sampler.pixel(ix, iy)
                    } else {
                        color = background
                    }
                    write(y * dstW + x, color)
                }
            }

        case .linear:
            for y in rows {
                for x in 0..<dstW {
                    let (sx, sy) = sourceCoordinates(x, y)
                    write(y * dstW + x, bilinear(sampler: sampler, sx, sy))
                }
            }

        case .cubic, .lanczos:
            guard let kernel = KernelTable(filter: filter) else { return }
            for y in rows {
                for x in 0..<dstW {
                    let (sx, sy) = sourceCoordinates(x, y)
                    write(y * dstW + x,
                          filterPixel(sampler: sampler, kernel: kernel, background: background, sx, sy))
                }
            }
        }
    }

    // MARK: - Filtres

    @inline(__always)
    static func bilinear(sampler: Sampler, _ sx: Float, _ sy: Float) -> RGBA32 {
        let fx = Int(floor(sx))
        let fy = Int(floor(sy))
        let horzWeight = sx - Float(fx)
        let vertWeight = sy - Float(fy)

        let topLeft = sampler.pixel(fx, fy)
        let bottomLeft = sampler.pixel(fx, fy + 1)
        let topRight = sampler.pixel(fx + 1, fy)
        let bottomRight = sampler.pixel(fx + 1, fy + 1)

        return RGBA32(
            r: interpolateByte(horzWeight, vertWeight, topLeft.r, bottomLeft.r, topRight.r, bottomRight.r),
            g: interpolateByte(horzWeight, vertWeight, topLeft.g, bottomLeft.g, topRight.g, bottomRight.g),
            b: interpolateByte(horzWeight, vertWeight, topLeft.b, bottomLeft.b, topRight.b, bottomRight.b),
            a: interpolateByte(horzWeight, vertWeight, topLeft.a, bottomLeft.a, topRight.a, bottomRight.a))
    }

    /// Équivalent de `InterpolateBytes` (C11=TL, C12=BL, C21=TR, C22=BR).
    @inline(__always)
    static func interpolateByte(_ horzWeight: Float, _ vertWeight: Float,
                                _ c11: UInt8, _ c12: UInt8, _ c21: UInt8, _ c22: UInt8) -> UInt8 {
        let value = (1 - horzWeight) * (1 - vertWeight) * Float(c11)
                  + (1 - horzWeight) * vertWeight * Float(c12)
                  + horzWeight * (1 - vertWeight) * Float(c21)
                  + horzWeight * vertWeight * Float(c22)
        return DeskewMath.clampToByte(Int(value))
    }

    /// Équivalent de `FilterPixel` (convolution séparable + bords).
    static func filterPixel(sampler: Sampler, kernel: KernelTable, background: RGBA32,
                            _ x: Float, _ y: Float) -> RGBA32 {
        let kw = kernel.kernelWidth
        let srcW = sampler.width
        let srcH = sampler.height
        let ceilX = Int(ceil(x))
        let ceilY = Int(ceil(y))

        var loX = 0, hiX = 0, loY = 0, hiY = 0
        var edge = false

        if !(ceilX < 0 || ceilX > srcW || ceilY < 0 || ceilY > srcH) {
            if ceilX - kw < 0 {
                loX = -ceilX
                edge = true
            } else {
                loX = -kw
            }
            if ceilX + kw >= srcW {
                hiX = srcW - ceilX - 1
                edge = true
            } else {
                hiX = kw
            }
            if ceilY - kw < 0 {
                loY = -ceilY
                edge = true
            } else {
                loY = -kw
            }
            if ceilY + kw >= srcH {
                hiY = srcH - ceilY - 1
                edge = true
            } else {
                hiY = kw
            }
        } else {
            return background
        }

        let xTablePos = DeskewMath.pascalRound((Float(ceilX) - x) * Float(kernel.maxTablePos))
        let yTablePos = DeskewMath.pascalRound((Float(ceilY) - y) * Float(kernel.maxTablePos))

        var vert = SIMD4<Float>.zero

        if loY <= hiY && loX <= hiX {
            for i in loY...hiY {
                let weightVert = kernel.weight(i, yTablePos)
                if weightVert != 0 {
                    var horz = SIMD4<Float>.zero
                    for j in loX...hiX {
                        horz += sampler.pixelVector(ceilX + j, ceilY + i) * kernel.weight(j, xTablePos)
                    }
                    vert += horz * weightVert
                }
            }
        }

        if edge {
            let backgroundVector = SIMD4<Float>(Float(background.b), Float(background.g),
                                                Float(background.r), Float(background.a))
            for i in -kw...kw {
                let weightVert = kernel.weight(i, yTablePos)
                if weightVert != 0 {
                    var horz = SIMD4<Float>.zero
                    for j in -kw...kw {
                        if j < loX || j > hiX || i < loY || i > hiY {
                            horz += backgroundVector * kernel.weight(j, xTablePos)
                        }
                    }
                    vert += horz * weightVert
                }
            }
        }

        func finish(_ value: Float) -> UInt8 {
            DeskewMath.clampToByte(Int(value + 0.5))
        }
        return RGBA32(r: finish(vert.z), g: finish(vert.y), b: finish(vert.x), a: finish(vert.w))
    }

    // MARK: - Multiples de 90

    static func rotate90(_ pixels: [UInt8], width: Int, height: Int,
                         bytesPerPixel: Int, degrees: Int) -> ([UInt8], Int, Int) {
        let outWidth: Int
        let outHeight: Int
        if degrees == 180 {
            outWidth = width
            outHeight = height
        } else {
            outWidth = height
            outHeight = width
        }

        var output = [UInt8](repeating: 0, count: outWidth * outHeight * bytesPerPixel)
        for oy in 0..<outHeight {
            for ox in 0..<outWidth {
                let sx: Int
                let sy: Int
                switch degrees {
                case 90:
                    sx = width - 1 - oy
                    sy = ox
                case 180:
                    sx = width - 1 - ox
                    sy = height - 1 - oy
                default: // 270
                    sx = height - 1 - ox
                    sy = oy
                }
                let src = (sy * width + sx) * bytesPerPixel
                let dst = (oy * outWidth + ox) * bytesPerPixel
                for b in 0..<bytesPerPixel {
                    output[dst + b] = pixels[src + b]
                }
            }
        }
        return (output, outWidth, outHeight)
    }

    static func rotate90(_ image: inout GrayImage, degrees: Int) {
        let (pixels, w, h) = rotate90(image.pixels, width: image.width, height: image.height,
                                      bytesPerPixel: 1, degrees: degrees)
        image = GrayImage(width: w, height: h, pixels: pixels)
    }

    static func rotate90(_ image: inout RGBImage, degrees: Int) {
        let (pixels, w, h) = rotate90(image.pixels, width: image.width, height: image.height,
                                      bytesPerPixel: RGBImage.bytesPerPixel, degrees: degrees)
        image = RGBImage(width: w, height: h, pixels: pixels)
    }

    static func rotate90(_ image: inout RGBAImage, degrees: Int) {
        let (pixels, w, h) = rotate90(image.pixels, width: image.width, height: image.height,
                                      bytesPerPixel: RGBAImage.bytesPerPixel, degrees: degrees)
        image = RGBAImage(width: w, height: h, pixels: pixels)
    }
}
