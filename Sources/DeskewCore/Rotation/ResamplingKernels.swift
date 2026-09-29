//
//  ResamplingKernels.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation

/// Noyaux de rééchantillonnage et table de poids précalculée.
///
/// Reproduction de `FilterCatmullRom`, `FilterLanczos` et
/// `PrecomputeFilterWeights` de `ImageUtils.pas`.
public struct ResamplingKernels {

    /// Noyau Catmull-Rom (filtre `rfCubic`), rayon 2.
    public static func catmullRom(_ value: Float) -> Float {
        let x = abs(value)
        if x < 1.0 {
            return 0.5 * (2.0 + x * x * (-5.0 + 3.0 * x))
        } else if x < 2.0 {
            return 0.5 * (4.0 + x * (-8.0 + x * (5.0 - x)))
        }
        return 0.0
    }

    /// Noyau Lanczos (filtre `rfLanczos`), rayon 3.
    public static func lanczos(_ value: Float) -> Float {
        let x = abs(value)
        if x < 3.0 {
            return sinc(x) * sinc(x / 3.0)
        }
        return 0.0
    }

    private static func sinc(_ value: Float) -> Float {
        if value != 0.0 {
            let v = value * Float.pi
            return sin(v) / v
        }
        return 1.0
    }
}

/// Table de poids précalculée pour une convolution séparable.
///
/// Reproduit `WeightTable` : les fractions sont quantifiées sur `TableSize - 1`
/// intervalles (32 pas dans l'original).
public struct KernelTable {
    public let kernelWidth: Int
    public let maxTablePos: Int
    private let tableSize: Int
    private let weights: [Float]

    /// `TableSize` de l'original.
    public static let defaultTableSize = 32

    public init?(filter: ResamplingFilter, tableSize: Int = KernelTable.defaultTableSize) {
        let kernelWidth: Int
        let function: (Float) -> Float
        switch filter {
        case .cubic:
            kernelWidth = 2
            function = ResamplingKernels.catmullRom
        case .lanczos:
            kernelWidth = 3
            function = ResamplingKernels.lanczos
        case .nearest, .linear:
            return nil
        }

        self.kernelWidth = kernelWidth
        self.tableSize = tableSize
        self.maxTablePos = tableSize - 1

        var weights = [Float](repeating: 0, count: (2 * kernelWidth + 1) * tableSize)
        for i in 0..<tableSize {
            let fraction = Float(i) / Float(tableSize - 1)
            for j in -kernelWidth...kernelWidth {
                weights[(j + kernelWidth) * tableSize + i] = function(Float(j) + fraction)
            }
        }
        self.weights = weights
    }

    /// Poids pour un décalage de noyau et une position de table.
    @inline(__always)
    public func weight(_ offset: Int, _ tablePos: Int) -> Float {
        weights[(offset + kernelWidth) * tableSize + tablePos]
    }
}
