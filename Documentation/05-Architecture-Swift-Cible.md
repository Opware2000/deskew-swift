# 05 — Architecture Swift cible

Ce document propose la structure du projet Swift, les types fondamentaux et l'API
publique. Il ne contient volontairement **pas** d'implémentation : seulement les
signatures et les décisions de conception.

## 1. Objectifs de conception

1. **Parité algorithmique** avec la version Pascal (mêmes résultats à tolérance près).
2. **Cœur pur et testable** : aucun accès disque dans les algorithmes.
3. **Performance arm64** : `Float` (32 bits) là où l'original utilise `Single`,
   **SIMD Swift** (`SIMD4<Float>`) pour les canaux, parallélisation
   (`DispatchQueue.concurrentPerform`). *Accelerate n'a finalement pas été nécessaire.*
4. **Multithreading** sans état partagé mutable (voir [06](06-Multithreading-et-Performance.md)).
5. **API macro raisonnable** : pas d'abstraction dont on n'a pas besoin (pas de
   protocole « PixelFormat » à trois niveaux, etc.).

## 2. Organisation du dépôt

```text
deskew-swift/
├── Package.swift
├── Sources/
│   ├── DeskewCore/              # bibliothèque pure, zéro I/O
│   │   ├── Pixel/
│   │   │   ├── GrayImage.swift
│   │   │   ├── RGBImage.swift          (RGB24)
│   │   │   ├── RGBAImage.swift         (ARGB32)
│   │   │   └── PixelFormat.swift       (énum des formats logiques)
│   │   ├── Geometry/
│   │   │   ├── Rect.swift              (IntRect, FloatRect)
│   │   │   ├── SizeUnit.swift
│   │   │   └── ContentRect.swift       (CalcContentRectForImage)
│   │   ├── Thresholding/
│   │   │   ├── Otsu.swift
│   │   │   └── Binarization.swift
│   │   ├── Skew/
│   │   │   └── HoughSkewDetector.swift
│   │   ├── Rotation/
│   │   │   ├── Rotate90.swift
│   │   │   ├── ImageRotation.swift
│   │   │   ├── Filters.swift           (noyaux + tables)
│   │   │   └── Interpolation.swift     (bilinéaire, nearest)
│   │   ├── Options.swift               # options + parsing identique (sans dépendance CLI)
│   │   ├── ResolutionInfo.swift        # DPI (structure indépendante d'ImageIO)
│   │   └── Pipeline.swift              # DoDeskew / RunDeskew (orchestration pure)
│   ├── DeskewImageIO/           # pont ImageIO/CoreGraphics
│   │   ├── ImageLoader.swift
│   │   ├── ImageWriter.swift
│   │   ├── PixelConversion.swift
│   │   └── Metadata.swift
│   └── DeskewCLI/               # exécutable
│       └── DeskewCommand.swift
├── Tests/
│   ├── DeskewCoreTests/
│   │   ├── OtsuTests.swift
│   │   ├── BinarizationTests.swift
│   │   ├── SkewDetectionTests.swift
│   │   ├── RotationTests.swift
│   │   ├── OptionsParsingTests.swift
│   │   └── GeometryTests.swift
│   └── DeskewParityTests/       # golden files générés depuis le binaire Pascal
└── Documentation/               # ce dossier
```

Dépendances : **aucune externe**. Le parsing CLI est fait maison (parité stricte avec
`CmdLineOptions.pas`), et `libtiff` est chargé **dynamiquement** (optionnel, via le
shim `CTiffShim`) pour le contrôle de compression TIFF. Aucun paquet tiers n'est requis
à la compilation.

## 3. Types fondamentaux

### 3.1 Précision

Reproduire la précision d'origine :

| Usage | Pascal | Swift |
| ----- | ------ | ----- |
| Filtres, Otsu, interpolation | `Single` | **`Float`** |
| Angles, trigonométrie Hough | `Double` / `Extended` | **`Double`** |
| Accumulateur Hough | `Integer` | `Int32` (ou `Int`) |
| Histogramme Otsu | `Single` | `Float` |

> Règle : ne pas « améliorer » la précision (pas de `Double` pour les filtres) sous
> peine de casser la parité d'arrondis. Voir [07](07-Parite-et-Tests.md).

### 3.2 Représentation des pixels

Le code Pascal opère sur des tampons plats, avec `stride` implicite = largeur. C'est un
point clé d'optimisation : conserver ce modèle.

```swift
/// Image Gray8 : 1 octet par pixel, ligne-contiguë, stride = width.
struct GrayImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]      // count == width * height
}

/// Image RGB24 : 3 octets/pixel. Layout mémoire à décider (R,G,B ou B,G,R).
struct RGBImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]      // count == width * height * 3
}

/// Image ARGB32 : 4 octets/pixel. Layout B,G,R,A pour coller au Pascal.
struct RGBAImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]      // count == width * height * 4
}
```

Pour les noyaux de performance, utiliser `pixels.withUnsafeMutableBufferPointer { ... }`
et éviter toute allocation par pixel. Pour la rotation multithread, un buffer par
bande de lignes, ou un unique buffer indexé par `y * dstWidth + x`.

### 3.3 Rectangle et unités

```swift
struct IntRect: Equatable { var left, top, right, bottom: Int }
struct FloatRect: Equatable { var left, top, right, bottom: Float }

enum SizeUnit: String, CaseIterable { case pixels = "px", percent = "%",
                                            mm, cm, inch = "in" }
```

### 3.4 Résolution (indépendant d'ImageIO)

```swift
/// Taille d'un pixel physique, stockée en µm (comme Imaging).
struct ResolutionInfo {
    var pixelSizeXMicrometers: Double?   // nil = inconnu
    var pixelSizeYMicrometers: Double?

    /// Équivalent de GetPhysicalPixelSize.
    func physicalPixelSize(_ unit: ResolutionUnit) -> (x: Double, y: Double)?
    static func from(dpiX: Double, dpiY: Double) -> ResolutionInfo     // 1 inch = 25400 µm
    static func from(dpcmX: Double, dpcmY: Double) -> ResolutionInfo   // 1 cm = 1e4 µm
}
```

## 4. API des algorithmes

### 4.1 Seuillage

```swift
enum ThresholdingMethod { case otsu, explicit(UInt8) }

enum Otsu {
    /// Retourne le seuil [0..255]. `rect` optionnel (découpe/clip).
    static func threshold(image: GrayImage, rect: IntRect?) -> Int
}

enum Binarization {
    static func binarize(_ image: inout GrayImage, threshold: Int, rect: IntRect?)
}
```

### 4.2 Détection d'inclinaison

```swift
struct SkewStats {
    var pixelCount: Int
    var testedPixels: Int
    var accumulatorSize: Int
    var accumulatedCounts: Int
    var bestCount: Int
}

enum HoughSkewDetector {
    /// Angle en degrés. `detectionArea` optionnel.
    static func rotationAngle(
        maxAngle: Double,
        angleStep: Double,
        threshold: Int,
        image: GrayImage,
        detectionArea: IntRect?,
        stats: inout SkewStats?
    ) -> Double
}
```

### 4.3 Rotation

```swift
enum ResamplingFilter { case nearest, linear, cubic, lanczos }

enum ImageRotation {
    static func rotate(
        _ image: inout RGBAImage,          // + surcharges Gray / RGB
        angleDegrees: Double,
        background: RGBA32,
        filter: ResamplingFilter,
        fitRotated: Bool
    )
}
```

Surcharges par type (`GrayImage`, `RGBImage`, `RGBAImage`) ou une seule fonction
générique sur un protocole `PixelImage` minimal. **Préférer les surcharges** (plus
simple, meilleure spécialisation du compilateur) tant qu'il n'y a que trois formats.

### 4.4 Options

```swift
struct DeskewOptions {
    var inputFileName: String?
    var outputFileName: String?
    var maxAngle: Double = 10
    var angleStep: Double = 0.1
    var skipAngle: Double = 0.01
    var resamplingFilter: ResamplingFilter = .linear
    var backgroundColor: RGBA32 = .opaqueBlack
    var thresholding: ThresholdingMethod = .otsu
    var contentRect: FloatRect? = nil
    var contentMargins: FloatRect? = nil
    var contentSizeUnit: SizeUnit = .pixels
    var forcedOutputFormat: PixelFormat? = nil
    var dpiOverride: Int = 0
    var jpegQuality: Int? = nil
    var tiffCompression: TiffCompression? = nil
    var cropToInput: Bool = false
    var detectOnly: Bool = false
    var showDetectionStats = false
    var showParams = false
    var showTimings = false
    var saveWorkImage = false
    var errorMessage: String = ""

    var isValid: Bool { /* cf. § 2 de 03 */ }

    /// Parse identique à TCmdLineOptions.CheckParam / Parse.
    mutating func parse(_ args: [String]) -> Bool

    func contentRect(inImageBounds: IntRect, resolution: ResolutionInfo) -> IntRect?
    var optionsDescription: String { /* équivalent OptionsToString */ }
}
```

Le parsing est identique à `CmdLineOptions.pas`. Il est **fait maison** (pas de
`swift-argument-parser`) afin de reproduire exactement la sémantique d'origine :
sensibilité à la casse des noms d'options, valeurs insensibles à la casse, drapeaux
combinés (`-g cd`, `-s sp`), messages d'erreur identiques (voir
[03](03-Specification-CLI.md) § 13).

### 4.5 Pipeline

```swift
struct DeskewResult {
    enum Output { case image(PixelImage), detectOnly }
    var skewAngle: Double
    var stats: SkewStats?
    var changed: Bool
    var log: [String]          // lignes à afficher (dans l'ordre)
}

enum Pipeline {
    static func run(
        input: PixelImage,
        workImage: GrayImage,
        resolution: ResolutionInfo,
        options: DeskewOptions
    ) -> DeskewResult
}
```

`Pipeline` est synchrone et sans I/O. La couche CLI :

1. charge l'image via `DeskewImageIO`,
2. produit l'image de travail grise,
3. appelle `Pipeline.run`,
4. écrit le résultat et affiche le journal.

## 5. Gestion d'erreurs

```swift
enum DeskewError: Error {
    case unsupportedInputFormat(String)
    case unsupportedOutputFormat(String)
    case invalidImage(String)
    case missingResolutionInfo
    case options(String)
    case io(String)
}
```

Les messages destinés à l'utilisateur doivent reprendre le **libellé exact** de
l'original (voir [03](03-Specification-CLI.md) § 10) pour ne pas casser les scripts.

## 6. Concurrence

- `DeskewCore` peut être marqué `Sendable` (structures de valeur).
- La parallélisation est **interne** aux algorithmes (voir [06](06-Multithreading-et-Performance.md)),
  pas au niveau du pipeline : le format d'entrée produit un seul résultat.
- Aucun état global mutable. Les poids de filtre sont calculés une fois par appel et
  passés aux workers (ou calculés par bande, coût négligeable).

## 7. Espace de couleurs

Pour la parité et la détection, travailler de préférence en **espace device** neutre.
Documenter explicitement l'espace utilisé pour chaque conversion `CGImage → GrayImage`
et `PixelImage → CGImage` (risque d'écart via gestion colorimétrique sRGB).

## 8. Licence

Projet dérivé de Deskew (MPL 2.0). Conserver l'en-tête de licence en tête des fichiers
dérivés et un fichier `LICENSE` avec le texte MPL 2.0.
