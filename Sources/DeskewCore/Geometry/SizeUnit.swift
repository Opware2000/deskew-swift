//
//  SizeUnit.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Unités de taille pour les rectangles de contenu et les marges
/// (équivalent de `TSizeUnit`).
public enum SizeUnit: String, CaseIterable, Sendable {
    case pixels = "px"
    case percent = "%"
    case mm = "mm"
    case cm = "cm"
    case inch = "in"

    /// Jetons CLI associés, dans l'ordre de `SizeUnitTokens`.
    public static let tokens: [String] = ["px", "%", "mm", "cm", "in"]

    /// Analyse insensible à la casse, comme `TryParseSizeUnit`.
    public init?(token: String) {
        self.init(rawValue: token.lowercased())
    }
}
