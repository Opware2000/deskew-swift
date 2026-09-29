//
//  ResolutionInfo.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Unité de résolution, comme `TResolutionUnit` de la bibliothèque Imaging.
public enum ResolutionUnit: Sendable {
    /// Pixels par pouce.
    case dpi
    /// Pixels par centimètre.
    case dpcm
    /// Pixels par mètre.
    case dpm
    /// Taille physique du pixel, en micromètres (pas de conversion).
    case sizeInMicrometers
}

/// Informations de résolution physique d'une image.
///
/// Reproduit la sémantique de `TMetadata.GetPhysicalPixelSize` /
/// `SetPhysicalPixelSize` : la résolution est stockée comme **taille du pixel en
/// micromètres**, et les getters effectuent la conversion inverse.
public struct ResolutionInfo: Equatable, Sendable {

    /// Taille du pixel en micromètres. `nil` = inconnue.
    public var pixelSizeXMicrometers: Double?
    public var pixelSizeYMicrometers: Double?

    public init(pixelSizeXMicrometers: Double? = nil, pixelSizeYMicrometers: Double? = nil) {
        self.pixelSizeXMicrometers = pixelSizeXMicrometers
        self.pixelSizeYMicrometers = pixelSizeYMicrometers
    }

    /// Aucune information de résolution.
    public static let unknown = ResolutionInfo()

    /// Construit depuis une résolution en points par pouce (1 inch = 25 400 µm).
    public static func from(dpiX: Double, dpiY: Double) -> ResolutionInfo {
        ResolutionInfo(pixelSizeXMicrometers: 25400 / dpiX,
                       pixelSizeYMicrometers: 25400 / dpiY)
    }

    /// Construit depuis une résolution en points par centimètre (1 cm = 10 000 µm).
    public static func from(dpcmX: Double, dpcmY: Double) -> ResolutionInfo {
        ResolutionInfo(pixelSizeXMicrometers: 10000 / dpcmX,
                       pixelSizeYMicrometers: 10000 / dpcmY)
    }

    /// Equivalent de `GetPhysicalPixelSize`.
    ///
    /// Renvoie la taille **d'un pixel** dans l'unité demandée (donc des pixels
    /// par unité pour `dpi`/`dpcm`/`dpm`), ou `nil` si aucune information n'est
    /// disponible. Si une seule dimension est connue, l'autre est dupliquée.
    public func physicalPixelSize(_ unit: ResolutionUnit) -> (x: Double, y: Double)? {
        guard pixelSizeXMicrometers != nil || pixelSizeYMicrometers != nil else {
            return nil
        }
        var x = pixelSizeXMicrometers ?? pixelSizeYMicrometers!
        var y = pixelSizeYMicrometers ?? pixelSizeXMicrometers!

        switch unit {
        case .dpi:
            x = 25400 / x
            y = 25400 / y
        case .dpcm:
            x = 10000 / x
            y = 10000 / y
        case .dpm:
            x = 1_000_000 / x
            y = 1_000_000 / y
        case .sizeInMicrometers:
            break
        }
        return (x, y)
    }
}
