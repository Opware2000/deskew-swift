//
//  PascalFormat.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation

/// Reproduit les formats numériques du Pascal (`FloatToStr`, `%n`, `%.0n`).
public enum PascalFormat {

    /// Équivalent de `FloatToStr` (15 chiffres significatifs, sans zéros inutiles).
    public static func floatToStr(_ value: Double) -> String {
        String(format: "%.15g", value)
    }

    /// Équivalent du format `%n` avec 2 décimales, séparateur de milliers `,`.
    public static func number2(_ value: Float) -> String {
        let raw = String(format: "%.2f", value)
        return groupIntegerPart(raw)
    }

    /// Équivalent du format `%.0n` : entier, séparateur de milliers `,`,
    /// complété à gauche par des espaces jusqu'à `minWidth`.
    public static func groupedInteger(_ value: Int, minWidth: Int = 0) -> String {
        let grouped = groupIntegerPart(String(value))
        if grouped.count >= minWidth { return grouped }
        return String(repeating: " ", count: minWidth - grouped.count) + grouped
    }

    /// Hexadécimal majuscule `%08X`.
    public static func hex8(_ value: UInt32) -> String {
        String(format: "%08X", value)
    }

    /// Insère des virgules tous les 3 chiffres dans la partie entière.
    private static func groupIntegerPart(_ raw: String) -> String {
        var sign = ""
        var body = raw
        if body.hasPrefix("-") {
            sign = "-"
            body.removeFirst()
        }

        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var integerPart = String(parts[0])
        let rest = parts.count > 1 ? "." + parts[1] : ""

        var grouped = ""
        let chars = Array(integerPart)
        for (index, ch) in chars.enumerated() {
            if index > 0 && (chars.count - index) % 3 == 0 {
                grouped.append(",")
            }
            grouped.append(ch)
        }
        integerPart = grouped
        return sign + integerPart + rest
    }
}
