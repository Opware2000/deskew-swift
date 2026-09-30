//
//  Stopwatch.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import Dispatch

/// Chronomètre à résolution microseconde (équivalent de `GetTimeMicroseconds`).
public struct Stopwatch {
    private var start: UInt64

    public init() {
        start = DispatchTime.now().uptimeNanoseconds
    }

    /// Réinitialise le chronomètre.
    public mutating func restart() {
        start = DispatchTime.now().uptimeNanoseconds
    }

    /// Temps écoulé depuis le départ, en microsecondes.
    public var microseconds: Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1000)
    }

    /// Ligne de timing au format de l'original :
    /// `<étape> - time taken: <µs> us`.
    public mutating func line(_ step: String) -> String {
        let elapsed = microseconds
        restart()
        return step + " - time taken: " + PascalFormat.groupedInteger(elapsed) + " us"
    }
}
