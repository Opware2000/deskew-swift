# TODO — Réimplémentation Swift de Deskew

Liste exhaustive des tâches restantes, dérivée de
[`Documentation/09-Plan-Implementation.md`](Documentation/09-Plan-Implementation.md).

**Légende :** `[x]` fait · `[ ]` à faire · `[~]` en cours

**Progression :** phase 0 partielle — l'oracle et les golden files sont prêts, le
package Swift reste à créer.

| Phase | Objet | État |
| ----- | ----- | ---- |
| 0 | Préparation (oracle, golden, squelette) | 🟡 partiel |
| 1 | Types et géométrie | ⬜ |
| 2 | Otsu et binarisation | ⬜ |
| 3 | Options et analyse CLI | ⬜ |
| 4 | Rotation et rééchantillonnage | ⬜ |
| 5 | Détection d'inclinaison (Hough) | ⬜ |
| 6 | Entrées-sorties ImageIO | ⬜ |
| 7 | Pipeline et exécutable | ⬜ |
| 8 | Multithreading et performance | ⬜ |
| 9 | Packaging et release | ⬜ |

---

## Phase 0 — Préparation

- [x] Oracle Pascal v1.33 : `Scripts/compile_local.sh` (nécessite FPC)
- [x] Golden files : `Tests/DeskewParityTests/generate_reference.sh` + `reference/` (37 cas)
- [x] Documentation complète : `Documentation/`
- [x] Dépôt GitHub public : <https://github.com/Opware2000/deskew-swift>
- [ ] Créer `Package.swift` (plateforme macOS, produits `DeskewCore`, `DeskewImageIO`, `deskew`)
- [ ] Créer l'arborescence `Sources/DeskewCore`, `Sources/DeskewImageIO`, `Sources/DeskewCLI`, `Tests/`
- [ ] Ajouter `.gitignore` Swift : `.build/`, `.swiftpm/`, `*.xcodeproj`, `DerivedData/`
- [ ] Dépendance `swift-argument-parser` (Package.swift)
- [ ] Vérifier que `LICENSE` (MPL 2.0) est à la racine et ajouter l'en-tête MPL dans chaque fichier Swift
- [ ] CI GitHub Actions : `swift build` + `swift test` sur `macos-latest` (arm64)
- [ ] `CONTRIBUTING.md` : conventions (scopes, langue des commits, format)

## Phase 1 — Types et géométrie

- [ ] `PixelFormat` (énumération : b1, g8, rgb24, rgba32, index8)
- [ ] `GrayImage` (buffer `[UInt8]`, width, height, stride = width)
- [ ] `RGBImage` (3 octets/pixel, layout à figer)
- [ ] `RGBAImage` (4 octets/pixel, layout B,G,R,A)
- [ ] `RGB24` et `RGBA32` (types couleur, accès nommé R/G/B/A)
- [ ] `IntRect` + helpers : `isNull`, `isEmpty`, `width`, `height`, `intersect`, `contains`
- [ ] `FloatRect` + `isNull`
- [ ] `IntPoint`, `FloatPoint`
- [ ] `SizeUnit` (px, %, mm, cm, in) + parsing du jeton
- [ ] `ResolutionInfo` : stockage µm/pixel, `physicalPixelSize(unit:)`
- [ ] Conversion DPI ← µm et dpcm ← µm (cf. `TranslateUnits`)
- [ ] `ContentRect.calcRectInPixels` (toutes les unités)
- [ ] `ContentRect.forImage` (marges vs rectangle, intersection, échec)
- [ ] Tests : `IntRect`/`FloatRect`/`RectToStr`, conversion d'unités
- [ ] Tests : `TestCalcDetectionRect` porté intégralement (DPI inclus)

## Phase 2 — Otsu et binarisation

- [ ] `clampToByte`
- [ ] `Otsu.threshold(image:rect:)` — reproduire le `(I+1)`, l'histogramme `Float`, l'epsilon `1E-6`
- [ ] Cas rectangle vide → `128`
- [ ] Cas `Min == Max` → `Level = Min`
- [ ] `Binarization.binarize(_:threshold:rect:)` (hors rectangle inchangé)
- [ ] Tests : 7 cas Otsu (`WholeImage_*`, `ContentRect_*`, `Invalid`, `Clipped`)
- [ ] Tests : 2 cas binarisation (`WholeImage`, `ContentRect_LeavesOutsideUnchanged`)
- [ ] Critère : **bit-exact** sur tous ces cas

## Phase 3 — Options et analyse CLI

- [ ] `DeskewOptions` (struct) + toutes les valeurs par défaut
- [ ] `DeskewOptions.isValid` (règles exactes)
- [ ] `parseOption(_:_:)` : `-o -a -d -l -t -b -f -q -g -s -r -m -p -c`
- [ ] `parseFloatRect` (1/2/4 valeurs)
- [ ] Parsing de la couleur `-b` (LL / RRGGBB / AARRGGBB + longueurs)
- [ ] Parsing de la compression `-c` (JPEG, TIFF, doublons en erreur)
- [ ] Boucle `parse(_:)` (paramètre après l'entrée, fichier unique, value manquante)
- [ ] Nom de sortie par défaut (`deskewed-<base>.png`)
- [ ] `EnsureTrailingPathDelimiter` (cas chaîne vide)
- [ ] `TiffCompression` (énumération + noms + mapping valeur TIFF)
- [ ] `DeskewOptions.description` (≡ `OptionsToString`)
- [ ] Messages d'erreur **identiques** à l'original
- [ ] Tests : porter tout `Tests/TestCmdLineArgs.pas` (parsing, défauts, couleur,
      compression, drapeaux, marges, rectangles)
- [ ] Facade `swift-argument-parser` (aide générée) branchée sur `DeskewOptions.parse`

## Phase 4 — Rotation et rééchantillonnage

- [ ] `ImageRotation.rotate90` (mappings 90/180/270 exacts)
- [ ] Normalisation de l'angle dans `[0,360)` + seuil `1E-6`
- [ ] Court-circuit multiples de 90
- [ ] Calcul de la boîte englobante (`FitRotated = true`, `+1` si filtre ≠ nearest)
- [ ] `FitRotated = false` → taille d'entrée
- [ ] Garde-fou dimensions `<= 0`
- [ ] `sourceCoordinates(dstX:dstY:)`
- [ ] Filtre `nearest` (bornes + `Round`)
- [ ] Filtre `linear` : `bilinearGray`, `bilinearRGB`, `bilinearRGBA`
- [ ] `interpolateByte` + `GetBilinearPixelCoords` équivalents
- [ ] Noyaux : `FilterCatmullRom`, `FilterLanczos` (+ autres de la bibliothèque)
- [ ] `FilterKernel` : table de poids 32 pas + `KernelWidth`
- [ ] `applyKernel` : boucle principale + gestion des bords (contributions de fond)
- [ ] Surcharges `rotate` par type (`GrayImage`, `RGBImage`, `RGBAImage`)
- [ ] Tests : dimensions (angles 90/180/270/-1/1/20/45/75/111/193/217/333)
- [ ] Tests : mapping quadrants (90/180, Gray8 et RGB24)
- [ ] Tests : couleur de fond dans les coins (linear)
- [ ] Tests : identité 0°
- [ ] Critère : bit-exact pour 90/nearest ; écart ≤ 2 hors zones unies pour les autres

## Phase 5 — Détection d'inclinaison (Hough)

- [ ] `HoughSkewDetector.rotationAngle(...)` + `SkewStats`
- [ ] Classification « ligne de base » (noir + pixel du dessous non noir)
- [ ] `PageHeight -= 1` si `ContentRect.Bottom == Height`
- [ ] Pré-calcul `Sin[]` / `Cos[]` (gain majeur, résultat identique)
- [ ] Accumulation `DIndex * AlphaSteps + I`
- [ ] Garde-fou d'indice `0 <= DIndex < DistCount`
- [ ] Sélection des 20 meilleures lignes (tri par insertion, top 20)
- [ ] Moyenne des 20 angles (biais vers 0 reproduit)
- [ ] Statistiques (`pixelCount`, `testedPixels`, `accumulatorSize`, `accumulatedCounts`, `bestCount`)
- [ ] Tests de parité vs golden `detect-*` (angle ± 0.05°, stats identiques)
- [ ] Test avec rectangle de contenu (`-r`) et seuil explicite

## Phase 6 — Entrées-sorties ImageIO

- [ ] `ImageLoader` : `CGImageSource` → `PixelImage` (Gray8 / RGB24 / ARGB32)
- [ ] Extraction des métadonnées de résolution (`kCGImagePropertyDPIWidth/Height`) → `ResolutionInfo`
- [ ] Décider et documenter l'espace colorimétrique (device neutre, non prémultiplié)
- [ ] `ImageWriter` : PNG, JPEG, TIFF, GIF, BMP
- [ ] Qualité JPEG (`kCGImageDestinationLossyCompressionQuality`)
- [ ] Compression TIFF (`kCGImagePropertyTIFFCompression`) + mapping des schémas
- [ ] Préservation des DPI à l'écriture
- [ ] `PixelConversion.ensureRotatable` (Index8 → Gray/RGB/RGBA, alpha, etc.)
- [ ] Gestion des palettes (`PaletteHasAlpha`, `PaletteIsGrayScale`)
- [ ] Conversion `PixelImage` → `CGImage`
- [ ] Détection des formats supportés (`canRead`/`canWrite`) pour l'usage CLI
- [ ] Décision produit sur les formats non couverts (DDS, TGA, Netpbm, JNG, QOI, PSD écriture)
- [ ] Tests : chargement de chaque `TestImages/`, vérification dimensions/format/DPI
- [ ] Tests : round-trip écriture/lecture
- [ ] Tests : sorties TIFF comparées aux golden

## Phase 7 — Pipeline et exécutable

- [ ] `Pipeline.run` (≡ `DoDeskew`) : copie couleur + image de travail grise
- [ ] DPI override (`-p`)
- [ ] Zone de détection (`CalcContentRectForImage`) + échec « image sans DPI »
- [ ] Seuil (explicite ou Otsu sur le rectangle)
- [ ] Appel Hough + statistiques
- [ ] `-s w` : binariser et sauver `work-image.png`
- [ ] `-g d` : detect-only (aucun fichier)
- [ ] Skip-angle (`-l`) : sauter la rotation si angle < seuil
- [ ] `EnsurePixelFormatForRotation`
- [ ] `ChangeOutputFormatIfNeeded` (format forcé, TIFF G4 → b1, compression « input »)
- [ ] Copie du fichier si aucun changement et extension identique
- [ ] `DeskewCommand` (`@main`) : bannière, journal, timings (`-s t`), codes de sortie
- [ ] Messages console **identiques** à l'original
- [ ] Création des dossiers de sortie
- [ ] Test runner de parité : lit `reference/index.tsv`, exécute, compare
      (stdout normalisé `<ROOT>`, images avec tolérance)
- [ ] Faire passer les **37 golden cases**

## Phase 8 — Multithreading et performance

- [ ] Seuil de taille : ne pas paralléliser les petites images
- [ ] Hough : partition par plages d'angles (sans contention)
- [ ] Hough : liste de pixels testés pré-générée (un seul scan)
- [ ] Rotation : `concurrentPerform` par bandes de lignes
- [ ] Rotation : table de poids partagée en lecture seule
- [ ] Rotation : `SIMD4<Float>` sur cubic/lanczos
- [ ] Otsu : histogramme par bandes + fusion entière
- [ ] Binarisation / conversions : parallélisation si image grande
- [ ] Vérifier la **déterminisme** (rejouer tous les tests de parité)
- [ ] Benchmarks vs binaire Pascal (`-s t`), consigner les résultats
- [ ] Vérifier l'absence de débordement d'indice dans Hough

## Phase 9 — Packaging et release

- [ ] Script `Scripts/build_release.sh` (`swift build -c release`)
- [ ] Éventuel binaire universel (x86_64 + arm64) ou décision arm64 seul
- [ ] Section installation/usage dans le README
- [ ] CI : artefacts de build, tests en release
- [ ] Tag de version + release GitHub
- [ ] Notes sur les formats supportés et les exclusions

---

## Définition de « terminé » (v1)

- [ ] L'exécutable reproduit options, messages et codes de sortie de l'original
- [ ] Les 37 cas de parité passent aux tolérances prévues
- [ ] Otsu, binarisation, géométrie, rotation 90/180/270/nearest : bit-exacts
- [ ] Le multithreading n'altère aucun résultat
- [ ] La documentation est à jour et suffit à un nouveau contributeur

## Non couvert volontairement (v1)

- Interface graphique (le dépôt original a un GUI)
- Réécriture des codecs tiers (ZLib, JPEG, LibTIFF) — remplacés par ImageIO
- Formats non supportés par ImageIO : DDS, TGA, PBM/PGM/PPM/PAM/PFM, JNG, QOI,
  écriture PSD
