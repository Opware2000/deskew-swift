//
//  ResamplingFilter.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Filtre de rééchantillonnage utilisé pour les rotations
/// (équivalent de `TResamplingFilter`, noms CLI inclus).
public enum ResamplingFilter: String, CaseIterable, Equatable, Sendable {
    case nearest
    case linear
    case cubic
    case lanczos

    /// Filtre par défaut (`rfLinear`).
    public static let `default` = ResamplingFilter.linear
}
