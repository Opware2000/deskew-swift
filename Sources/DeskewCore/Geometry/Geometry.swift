//
//  Geometry.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation

/// Point entier (équivalent de `TPoint`).
public struct IntPoint: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Rectangle entier `[left, top, right, bottom[` (équivalent de `TRect`).
public struct IntRect: Equatable, Sendable {
    public var left: Int
    public var top: Int
    public var right: Int
    public var bottom: Int

    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(left: x, top: y, right: x + width, bottom: y + height)
    }

    /// Équivalent de `NullRect`.
    public static let zero = IntRect(left: 0, top: 0, right: 0, bottom: 0)

    /// Équivalent de `RectWidth`.
    public var width: Int { right - left }
    /// Équivalent de `RectHeight`.
    public var height: Int { bottom - top }

    /// Équivalent de `IsRectNull` (tous les champs nuls, comparaison exacte).
    public var isNull: Bool { left == 0 && top == 0 && right == 0 && bottom == 0 }

    /// Équivalent de `IsRectEmpty` (largeur ou hauteur nulle/négative).
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func contains(_ p: IntPoint) -> Bool {
        p.x >= left && p.x < right && p.y >= top && p.y < bottom
    }

    /// Équivalent de `IntersectRect` : renvoie `.zero` lorsqu'il n'y a pas de
    /// recouvrement (comportement de la RTL Pascal).
    public func intersect(_ other: IntRect) -> IntRect {
        let l = max(left, other.left)
        let t = max(top, other.top)
        let r = min(right, other.right)
        let b = min(bottom, other.bottom)
        if r <= l || b <= t { return .zero }
        return IntRect(left: l, top: t, right: r, bottom: b)
    }
}

extension IntRect: CustomStringConvertible {
    /// Équivalent de `RectToStr` : `[left,top,right,bottom]`.
    public var description: String { "[\(left),\(top),\(right),\(bottom)]" }
}

/// Rectangle flottant (équivalent de `TFloatRect`).
public struct FloatRect: Equatable, Sendable {
    public var left: Float
    public var top: Float
    public var right: Float
    public var bottom: Float

    public init(left: Float, top: Float, right: Float, bottom: Float) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// Équivalent de `NullFloatRect`.
    public static let zero = FloatRect(left: 0, top: 0, right: 0, bottom: 0)

    /// Équivalent de `IsFloatRectNull`.
    public var isNull: Bool { left == 0 && top == 0 && right == 0 && bottom == 0 }

    /// Équivalent de `MakeScaledRect` : multiplie puis arrondit (Round Pascal).
    public func scaled(widthFactor: Double, heightFactor: Double) -> IntRect {
        IntRect(
            left: DeskewMath.pascalRound(Double(left) * widthFactor),
            top: DeskewMath.pascalRound(Double(top) * heightFactor),
            right: DeskewMath.pascalRound(Double(right) * widthFactor),
            bottom: DeskewMath.pascalRound(Double(bottom) * heightFactor)
        )
    }
}
