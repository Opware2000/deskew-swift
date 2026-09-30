//
//  TiffWriter.swift
//  DeskewImageIO
//
//  Écriture TIFF via **libtiff** (chargement dynamique), pour contrôler
//  exactement la compression (LZW, RLE, Deflate, JPEG, G4).
//
//  Si libtiff est absent, `isAvailable` est faux et l'appelant retombe sur
//  ImageIO. Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import CTiffShim
import DeskewCore

/// Écriture TIFF contrôlée (compression exacte) via libtiff.
public enum TiffWriter {

    enum WriteError: Error {
        case unavailable
        case unsupportedFormat
        case openFailed
        case writeFailed
    }

    /// libtiff est-il chargeable ?
    public static var isAvailable: Bool { dsk_tiff_available() != 0 }

    /// Version de libtiff (diagnostic).
    public static var version: String? {
        guard let cString = dsk_tiff_version() else { return nil }
        return String(cString: cString)
    }

    // Tags et valeurs TIFF (tiff.h)
    private enum Tag {
        static let imageWidth: Int32 = 256
        static let imageLength: Int32 = 257
        static let bitsPerSample: Int32 = 258
        static let compression: Int32 = 259
        static let photometric: Int32 = 262
        static let samplesPerPixel: Int32 = 277
        static let rowsPerStrip: Int32 = 278
        static let xResolution: Int32 = 282
        static let yResolution: Int32 = 283
        static let planarConfig: Int32 = 284
        static let resolutionUnit: Int32 = 296
        static let extraSamples: Int32 = 338
        static let jpegColorMode: Int32 = 65538
    }
    private enum Compression {
        static let none: Int32 = 1
        static let g4: Int32 = 4
        static let lzw: Int32 = 5
        static let jpeg: Int32 = 7
        static let deflate: Int32 = 8   // Adobe Deflate (plus largement supporté que 32946)
        static let packbits: Int32 = 32773
    }
    private enum Photometric {
        static let minIsWhite: Int32 = 0
        static let minIsBlack: Int32 = 1
        static let rgb: Int32 = 2
    }
    private static let planarConfigContig: Int32 = 1
    private static let resolutionUnitInch: Int32 = 2
    private static let jpegColorModeRGB: Int32 = 2
    private static let extraSampleUnassAlpha: Int32 = 2

    /// Ce writer sait-il écrire ce couple (image, compression) ?
    static func canWrite(_ image: PixelImage, compression: TiffCompression) -> Bool {
        guard isAvailable else { return false }
        return true
    }

    /// Écrit une image en TIFF avec la compression demandée.
    static func save(_ image: PixelImage, to path: String,
                     compression: TiffCompression,
                     dpi: (x: Double, y: Double)?) throws {
        guard isAvailable else { throw WriteError.unavailable }
        guard let tif = dsk_tiff_open(path, "w") else { throw WriteError.openFailed }
        defer { dsk_tiff_close(tif) }

        let width = image.width
        let height = image.height
        let comp = compressionValue(compression)

        switch image {
        case .gray(let gray):
            setup(tif, width: width, height: height, bits: 8, samples: 1,
                  photometric: Photometric.minIsBlack, compression: comp, dpi: dpi)
            try gray.pixels.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                for row in 0..<height {
                    let pointer = UnsafeMutableRawPointer(mutating: base + row * width)
                    if dsk_tiff_write_scanline(tif, pointer, UInt32(row), 0) == 0 {
                        throw WriteError.writeFailed
                    }
                }
            }

        case .rgb(let rgb):
            setup(tif, width: width, height: height, bits: 8, samples: 3,
                  photometric: Photometric.rgb, compression: comp, dpi: dpi)
            if comp == Compression.jpeg {
                _ = dsk_tiff_set_field_u32(tif, Tag.jpegColorMode, UInt32(jpegColorModeRGB))
            }
            let stride = width * 3
            try rgb.pixels.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                for row in 0..<height {
                    let pointer = UnsafeMutableRawPointer(mutating: base + row * stride)
                    if dsk_tiff_write_scanline(tif, pointer, UInt32(row), 0) == 0 {
                        throw WriteError.writeFailed
                    }
                }
            }

        case .binary(let binary):
            // CCITT G4 attend WhiteIsZero (0) ; nos bits valent 1 = blanc → inverser.
            let invert = (compression == .g4)
            setup(tif, width: width, height: height, bits: 1, samples: 1,
                  photometric: invert ? Photometric.minIsWhite : Photometric.minIsBlack,
                  compression: comp, dpi: dpi)
            if invert {
                var rowBuffer = [UInt8](repeating: 0, count: binary.bytesPerRow)
                try rowBuffer.withUnsafeMutableBufferPointer { buffer in
                    for row in 0..<height {
                        let offset = row * binary.bytesPerRow
                        for i in 0..<binary.bytesPerRow {
                            buffer[i] = ~binary.bits[offset + i]
                        }
                        if dsk_tiff_write_scanline(tif, buffer.baseAddress, UInt32(row), 0) == 0 {
                            throw WriteError.writeFailed
                        }
                    }
                }
            } else {
                try binary.bits.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    for row in 0..<height {
                        let pointer = UnsafeMutableRawPointer(mutating: base + row * binary.bytesPerRow)
                        if dsk_tiff_write_scanline(tif, pointer, UInt32(row), 0) == 0 {
                            throw WriteError.writeFailed
                        }
                    }
                }
            }

        case .rgba(let rgba):
            // RGB + alpha non associé (ExtraSamples = unassociated).
            setup(tif, width: width, height: height, bits: 8, samples: 4,
                  photometric: Photometric.rgb, compression: comp, dpi: dpi)
            _ = dsk_tiff_set_field_u32(tif, Tag.extraSamples, UInt32(extraSampleUnassAlpha))
            var rowBuffer = [UInt8](repeating: 0, count: width * 4)
            try rowBuffer.withUnsafeMutableBufferPointer { buffer in
                for row in 0..<height {
                    let offset = row * width * 4
                    for x in 0..<width {
                        let s = offset + x * 4
                        buffer[x * 4] = rgba.pixels[s + 2]     // R
                        buffer[x * 4 + 1] = rgba.pixels[s + 1] // G
                        buffer[x * 4 + 2] = rgba.pixels[s]     // B
                        buffer[x * 4 + 3] = rgba.pixels[s + 3] // A
                    }
                    if dsk_tiff_write_scanline(tif, buffer.baseAddress, UInt32(row), 0) == 0 {
                        throw WriteError.writeFailed
                    }
                }
            }
        }

        _ = dsk_tiff_write_directory(tif)
    }

    // MARK: - Helpers

    private static func setup(_ tif: UnsafeMutableRawPointer, width: Int, height: Int,
                              bits: Int, samples: Int, photometric: Int32,
                              compression: Int32, dpi: (x: Double, y: Double)?) {
        _ = dsk_tiff_set_field_u32(tif, Tag.imageWidth, UInt32(width))
        _ = dsk_tiff_set_field_u32(tif, Tag.imageLength, UInt32(height))
        _ = dsk_tiff_set_field_u32(tif, Tag.bitsPerSample, UInt32(bits))
        _ = dsk_tiff_set_field_u32(tif, Tag.samplesPerPixel, UInt32(samples))
        _ = dsk_tiff_set_field_u32(tif, Tag.photometric, UInt32(photometric))
        _ = dsk_tiff_set_field_u32(tif, Tag.compression, UInt32(compression))
        _ = dsk_tiff_set_field_u32(tif, Tag.planarConfig, UInt32(planarConfigContig))

        var rowsPerStrip = dsk_tiff_default_strip_size(tif)
        if rowsPerStrip == 0 || rowsPerStrip > UInt32(height) { rowsPerStrip = UInt32(height) }
        _ = dsk_tiff_set_field_u32(tif, Tag.rowsPerStrip, rowsPerStrip)

        if let dpi = dpi {
            _ = dsk_tiff_set_field_f64(tif, Tag.xResolution, dpi.x)
            _ = dsk_tiff_set_field_f64(tif, Tag.yResolution, dpi.y)
            _ = dsk_tiff_set_field_u32(tif, Tag.resolutionUnit, UInt32(resolutionUnitInch))
        }
    }

    private static func compressionValue(_ compression: TiffCompression) -> Int32 {
        switch compression {
        case .none: return Compression.none
        case .lzw: return Compression.lzw
        case .rle: return Compression.packbits
        case .deflate: return Compression.deflate
        case .jpeg: return Compression.jpeg
        case .g4: return Compression.g4
        case .input: return Compression.none
        }
    }
}
