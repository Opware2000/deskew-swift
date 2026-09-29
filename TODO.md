# TODO — Réimplémentation Swift de Deskew

Liste des tâches, dérivée de
[`Documentation/09-Plan-Implementation.md`](Documentation/09-Plan-Implementation.md).

**Légende :** `[x]` fait · `[ ]` à faire · `[~]` en cours

**Progression :** phases 0 à 7 réalisées ; phase 8 en cours ; phase 9 à faire.

| Phase | Objet | État |
| ----- | ----- | ---- |
| 0 | Préparation (oracle, golden, squelette) | 🟢 |
| 1 | Types et géométrie | 🟢 |
| 2 | Otsu et binarisation | 🟢 |
| 3 | Options et analyse CLI | 🟢 |
| 4 | Rotation et rééchantillonnage | 🟢 |
| 5 | Détection d'inclinaison (Hough) | 🟢 |
| 6 | Entrées-sorties ImageIO | 🟢 |
| 7 | Pipeline et exécutable | 🟢 |
| 8 | Multithreading et performance | 🟡 |
| 9 | Packaging et release | 🟡 |

---

## Phase 0 — Préparation

- [x] Oracle Pascal v1.33 : `Scripts/compile_local.sh`
- [x] Golden files : `Tests/DeskewParityTests/` (37 cas)
- [x] Documentation complète : `Documentation/`
- [x] Dépôt GitHub public : <https://github.com/Opware2000/deskew-swift>
- [x] `Package.swift` + arborescence `Sources/DeskewCore`, `DeskewImageIO`, `DeskewCLI`
- [x] `.gitignore` Swift (`.build/`, `.swiftpm/`, `DerivedData/`)
- [x] `LICENSE` (MPL 2.0) à la racine
- [ ] Dépendance `swift-argument-parser` (remplacée par un parsing maison fidèle)
- [ ] CI GitHub Actions `swift build` + `swift test` (macOS ARM)
- [ ] `CONTRIBUTING.md`

## Phase 1 — Types et géométrie

- [x] `PixelFormat`, `GrayImage`, `RGBImage`, `RGBAImage`, `RGB24`, `RGBA32`
- [x] `IntRect`, `FloatRect`, `IntPoint`, helpers
- [x] `SizeUnit` + parsing du jeton
- [x] `ResolutionInfo` (µm/pixel, conversions DPI/dpcm/dpm)
- [x] `ContentRect.calcRectInPixels` et `forImage`
- [x] Tests : géométrie, unités, `TestCalcDetectionRect` (DPI inclus)

## Phase 2 — Otsu et binarisation

- [x] `clampToByte`, `pascalRound` (arrondi bancaire vérifié sur FPC arm64)
- [x] `Otsu.threshold` (offset `(I+1)`, histogramme `Float`, epsilon `1E-6`)
- [x] `Binarization.binarize`
- [x] Tests : 7 cas Otsu + 2 cas binarisation (bit-exact)

## Phase 3 — Options et analyse CLI

- [x] `DeskewOptions` + défauts + `isValid`
- [x] `parseOption` : `-o -a -d -l -t -b -f -q -g -s -r -m -p -c`
- [x] Parsing couleur `-b`, compression `-c`, marges `-m`, rectangle `-r`
- [x] Nom de sortie par défaut, `EnsureTrailingPathDelimiter`
- [x] `TiffCompression`, `ResamplingFilter`, `ThresholdingMethod`
- [x] `optionsDescription` (≡ `OptionsToString`)
- [x] Tests : `TestCmdLineArgs.pas` porté intégralement

## Phase 4 — Rotation et rééchantillonnage

- [x] `rotate90` (90/180/270) + court-circuit
- [x] Boîte englobante (`FitRotated`), `sourceCoordinates`
- [x] Filtres `nearest`, `linear`, `cubic` (Catmull-Rom), `lanczos`
- [x] Table de poids 32 pas, `filterPixel` (bords via couleur de fond)
- [x] Tests : dimensions, quadrants, fond, identité

## Phase 5 — Détection d'inclinaison (Hough)

- [x] `HoughSkewDetector.detect` + `SkewStats`
- [x] Pré-calcul `sin`/`cos`, garde-fou d'indice
- [x] Top 20 lignes (tri par insertion), moyenne
- [x] Tests de parité `detect-*` : angles ± 0.05°, statistiques exactes
      (tolérance 0,1 % pour les JPEG)

## Phase 6 — Entrées-sorties ImageIO

- [x] `ImageLoader` : `CGImageSource` → Gray8/RGB24/ARGB32
- [x] Métadonnées de résolution → `ResolutionInfo`
- [x] Espace colorimétrique source (évite les conversions)
- [x] `ImageWriter` : PNG/JPEG/TIFF/GIF/BMP + qualité/compression/DPI
- [x] `PixelImage.converted` et `ensureRotatable`
- [ ] Gestion explicite des palettes (`PaletteHasAlpha`, `PaletteIsGrayScale`)
- [ ] Décision produit documentée pour DDS/TGA/Netpbm/JNG/QOI
- [ ] Tests de round-trip écriture/lecture
- [ ] Comparaison stricte des sorties TIFF compressées

## Phase 7 — Pipeline et exécutable

- [x] `Pipeline.run` (copie couleur, image de travail, seuil, détection, rotation)
- [x] DPI override, zone de détection, skip-angle
- [x] `-s w` (work-image), `-g d` (detect-only)
- [x] Format forcé, compression TIFF G4 → binaire (approximé Gray8)
- [x] Copie du fichier si inchangé
- [x] Exécutable `deskew` (bannière, journal, codes de sortie)
- [x] Test de parité des images de sortie (rotation)
- [x] Faire passer les **37 golden cases** (13 détection + 24 rotation)
- [ ] Parité stricte de la sortie console (bannière, `-s p`)
- [x] Compression binaire réelle (`-f b1`, G4, `tinput`)

## Phase 8 — Multithreading et performance

- [x] Hough : collecte des pixels testés puis partition par angles
- [x] Rotation : `concurrentPerform` par bandes de lignes
- [x] Seuil de taille (pas de parallélisme sur les petites images)
- [x] Vérifier le déterminisme (48/48 tests verts, résultats identiques)
- [ ] Otsu : histogramme par bandes
- [ ] SIMD (`SIMD4<Float>`) sur cubic/lanczos
- [ ] Benchmarks consignés (release vs Pascal)
- [ ] Optimiser le décodage/conversion (coût dominant en debug)

## Phase 9 — Packaging et release

- [x] `Scripts/build_swift_release.sh`
- [x] Section compilation/utilisation du README
- [x] CI GitHub Actions : build + tests en release (macOS ARM)
- [ ] Binaire universel ou arm64 seul (décision)
- [ ] Tag de version + release GitHub

---

## Définition de « terminé » (v1)

- [x] L'exécutable reproduit options, messages et codes de sortie de l'original
- [x] Les 37 cas de parité passent aux tolérances prévues
- [x] Otsu, binarisation, géométrie : bit-exacts
- [x] Le multithreading n'altère aucun résultat
- [x] La documentation suffit à un nouveau contributeur

## Non couvert volontairement (v1)

- Interface graphique
- Réécriture des codecs tiers — remplacés par ImageIO
- Formats non supportés par ImageIO : DDS, TGA, PBM/PGM/PPM/PAM/PFM, JNG, QOI,
  écriture PSD
