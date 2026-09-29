//
//  DeskewMath.swift
//  DeskewCore
//
//  Équivalents numériques des fonctions Pascal utilisées par Deskew.
//  Ce fichier fait partie du travail dérivé de Deskew (MPL 2.0).
//

/// Fonctions numériques reproduisant fidèlement le comportement Pascal.
public enum DeskewMath {

    /// Équivalent de `Round` en Free Pascal / Delphi.
    ///
    /// Arrondi au plus proche ; les valeurs exactement à mi-chemin (`x,5`) vont
    /// au nombre **pair** (arrondi bancaire). Comportement vérifié sur FPC 3.2.2
    /// arm64 : `Round(250.5) == 250`, `Round(2.5) == 2`, `Round(3.5) == 4`.
    public static func pascalRound(_ x: Double) -> Int {
        Int(x.rounded(.toNearestOrEven))
    }

    /// Variante `Float`.
    public static func pascalRound(_ x: Float) -> Int {
        Int(x.rounded(.toNearestOrEven))
    }

    /// Équivalent de `ClampToByte` : borne une valeur dans `[0, 255]`.
    public static func clampToByte(_ value: Int) -> UInt8 {
        if value < 0 { return 0 }
        if value > 255 { return 255 }
        return UInt8(value)
    }
}
