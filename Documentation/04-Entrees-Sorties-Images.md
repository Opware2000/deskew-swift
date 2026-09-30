# 04 — Entrées-sorties d'images

Référence : `MainUnit.pas`, `ImageUtils.pas`, `CmdLineOptions.pas`, `Imaging/`.

La version Pascal s'appuie sur la bibliothèque **Vampyre Imaging** (lecture/écriture,
palettes, métadonnées, conversions, codecs ZLib/JPEG/TIFF). La version Swift remplace
cette couche par les frameworks natifs de macOS : **ImageIO** + **Core Graphics**
(et un éventuel codec maison minimal pour les formats non couverts).

## 1. Formats reconnus par Imaging

| Format | Lecture | Écriture |
| ------ | ------- | -------- |
| BMP | oui | oui |
| JPG / JPEG | oui | oui |
| PNG | oui | oui |
| JNG | oui | oui |
| GIF | oui | oui |
| DDS | oui | oui |
| TGA | oui | oui |
| PBM / PGM / PPM / PAM / PFM (Netpbm) | oui | oui (sauf PBM) |
| TIF / TIFF | oui | oui |
| PSD | oui | oui |
| QOI | (codec présent) | (codec présent) |

## 2. Correspondance avec ImageIO / Core Graphics (macOS)

| Format | UTI / type ImageIO | Lecture | Écriture | Remarque |
| ------ | ------------------ | ------- | -------- | -------- |
| PNG | `public.png` | ✅ | ✅ | natif |
| JPEG | `public.jpeg` | ✅ | ✅ | qualité via `kCGImageDestinationLossyCompressionQuality` |
| TIFF | `public.tiff` | ✅ | ✅ | compression via `kCGImagePropertyTIFFCompression` |
| GIF | `com.compuserve.gif` | ✅ | ✅ | première image pour lecture |
| BMP | `com.microsoft.bmp` | ✅ | ✅ | natif |
| PSD | `com.adobe.photoshop-image` | ✅ | ❌ (écriture limitée) | lecture seule en pratique |
| HEIC/HEIF | `public.heic` / `public.heif` | ✅ | ✅ | bonus non présent dans l'original |
| DDS | — | ❌ | ❌ | à exclure ou codec tiers |
| TGA | — | ❌ | ❌ | codec simple à écrire si nécessaire |
| JNG | — | ❌ | ❌ | à exclure |
| PBM / PGM / PPM / PAM / PFM | — | ❌ | ❌ | Netpbm : codec texte/binaire simple si nécessaire |
| QOI | — | ❌ | ❌ | à exclure ou implémenter (spécification courte) |

**Stratégie recommandée** :

1. v1 : supporter **PNG, JPEG, TIFF, GIF, BMP** (couvre `Bin/runtests.sh` sauf TIFF
   spécifique) + lecture PSD.
2. v2 : ajouter les codecs Netpbm (PGM/PPM/PBM/PFM) et TGA, qui sont simples et sans
   dépendance.
3. Exclure explicitement JNG, DDS, QOI, écriture PSD (documenter comme non supporté).

### Décision v1 (formats)

| Format | Décision v1 | Motif |
| ------ | ----------- | ----- |
| PNG, JPEG, TIFF, GIF, BMP | **Supportés** (lecture + écriture) | natifs ImageIO, couvrent le cas d'usage |
| PSD | **Lecture seule** | ImageIO lit PSD, écriture non fiable |
| DDS, TGA, JNG, QOI | **Exclus** | non supportés par ImageIO ; codecs tiers hors périmètre |
| PBM, PGM, PPM, PAM, PFM (Netpbm) | **Exclus en v1**, candidats v2 | codecs texte/binaire simples à ajouter si besoin |
| HEIC/HEIF | Bonus (lecture/écriture) | présent nativement, non demandé |

Le message d'erreur pour un format non supporté est
`ERROR: Input/Output file format not supported: <fichier>`, identique à l'original.

## 3. Chargement d'une image (équivalent `LoadFromFile`)

En Swift :

```swift
let src = CGImageSourceCreateWithURL(url as CFURL, nil)
let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
```

Puis on convertit vers un format de travail connu. Deux familles :

- **Image de travail grise** : convertir en `Gray8` (une composante, `stride = width`),
  c'est l'entrée de Otsu et de la détection d'inclinaison.
- **Image de sortie « couleur »** : conserver le format d'origine si possible
  (`Gray8`, `RGB24`, `ARGB32`) pour ne pas dégrader la qualité ; sinon convertir selon
  la logique `EnsurePixelFormatForRotation` (§ 6).

Conversions Core Graphics utiles :

- `CGContext(data:width:height:bitsPerComponent:bytesPerRow:space:bitmapInfo:)` avec
  `CGColorSpaceCreateDeviceGray()` / `CGColorSpaceCreateDeviceRGB()`.
- Pour Gray8 : `bitsPerComponent = 8`, `bytesPerRow = width`, `bitmapInfo = .none`.
- Pour RGB24 : `bitmapInfo = CGImageAlphaInfo.none` (pas d'alpha), 3 octets/pixel.
- Pour ARGB32 : `bitmapInfo = [.byteOrder32Little, .premultipliedFirst]` → ordre mémoire
  B,G,R,A (compatible `TColor32Rec`).

> Attention : Core Graphics travaille souvent en prémultiplié. La rotation + fond doit
> rester cohérente avec la sémantique du code Pascal (alpha non prémultiplié).
> Valider par tests sur images avec alpha.

## 4. Métadonnées de résolution (DPI)

Le code utilise `TMetadata.GetPhysicalPixelSize` / `SetPhysicalPixelSize` et
`TranslateUnits` :

| Unité demandée | Conversion |
| -------------- | ---------- |
| `ruDpi` | `UnitSize = 25400` (µm/inch) → retourne **pixels par inch** |
| `ruDpcm` | `UnitSize = 1e4` → retourne **pixels par cm** |
| `ruDpm` | `UnitSize = 1e6` → pixels par mètre |
| `ruSizeInMicroMeters` | pas de division (taille en µm) |

Le stockage interne des métadonnées est donc une **taille de pixel physique en µm**
(µm/pixel), et les getters effectuent la conversion inverse.

En Swift, via ImageIO :

```swift
let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
let dpiX = props?[kCGImagePropertyDPIWidth]  as? Double
let dpiY = props?[kCGImagePropertyDPIHeight] as? Double
```

- Lecture : récupérer DPI largeur/hauteur. Si absent, la conversion en unités
  physiques (`mm`, `cm`, `in`) doit **échouer** (comportement identique à l'original :
  exception « Could not determine content rectangle in pixels »).
- Écriture : réinjecter `kCGImagePropertyDPIWidth/DPIHeight` dans les propriétés de
  destination, pour préserver la résolution (exigence historique v1.10).
- Override CLI `-p dpi` : utiliser cette valeur pour l'entrée **et** la sortie.

## 5. Contrôle d'écriture (qualité / compression)

Options Pascal :

```pascal
Imaging.SetOption(ImagingJpegQuality, q);        // [1..100]
Imaging.SetOption(ImagingTiffJpegQuality, q);
Imaging.SetOption(ImagingJNGQuality, q);
Imaging.SetOption(ImagingTiffCompression, scheme);
```

Équivalents ImageIO (passés à `CGImageDestinationSetProperties` /
`CGImageDestinationAddImage`) :

| Besoin | Clé ImageIO | Valeurs |
| ------ | ----------- | ------- |
| Qualité JPEG | `kCGImageDestinationLossyCompressionQuality` | `0.0 … 1.0` (convertir `q/100`) |
| Compression TIFF | `kCGImagePropertyTIFFCompression` | `1` = none, `5` = LZW, `4` = CCITT G4, `7` = JPEG, `8` = Deflate |
| Qualité JPEG dans TIFF | `kCGImageDestinationLossyCompressionQuality` | `0.0 … 1.0` |
| DPI | `kCGImagePropertyDPIWidth`, `kCGImagePropertyDPIHeight` | entier/float |

Mapping des schémas TIFF (noms CLI → valeur Imaging → valeur TIFF) :

| CLI | Imaging | TIFF `Compression` |
| --- | ------- | ------------------ |
| `none` | `TiffCompressionOptionNone` | `1` |
| `lzw` | `TiffCompressionOptionLzw` | `5` |
| `rle` | `TiffCompressionOptionPackbitsRle` | `32773` (PackBits) |
| `deflate` | `TiffCompressionOptionDeflate` | `8` |
| `jpeg` | `TiffCompressionOptionJpeg` | `7` |
| `g4` | `TiffCompressionOptionGroup4` | `4` (impose `ifBinary`) |
| `input` | `TiffCompressionOptionAsInput` | repris des métadonnées d'entrée |

> La compression « input » nécessite de lire la compression TIFF d'entrée
> (`kCGImagePropertyTIFFCompression`) et de la remapper. Si impossible → message
> `Could not set TIFF output compression from input, using default.`

### Contrôle de compression TIFF : libtiff (chargé dynamiquement)

ImageIO **n'expose pas** de contrôle d'écriture de la compression TIFF. Pour
reproduire exactement `-c tlzw|trle|tdeflate|tjpeg|tg4`, la sortie TIFF passe par
**libtiff**, chargé **dynamiquement** (`dlopen`/`dlsym`) via un petit shim C
(`Sources/CTiffShim`) — **aucune dépendance de build**.

| libtiff présent | Comportement TIFF |
| --- | --- |
| oui (`brew install libtiff`) | compression **exacte** : `none` (1), LZW (5), PackBits/RLE (32773), Deflate (8), JPEG (7), CCITT **G4** (4) |
| non | repli sur ImageIO : G4 automatique pour le 1 bit ; compression non contrôlée pour les autres schémas |

- **Compression par défaut** (comme l'original) : **1 bit → G4**, sinon **LZW**.
- **RGBA** : pris en charge (canal alpha non associé, `ExtraSamples`), la compression
  demandée est donc aussi appliquée aux sorties avec transparence
  (`-f rgba32 -c tlzw`, etc.).
- **G4** : libtiff attend `Photometric = WhiteIsZero` (0) ; nos bits valent `1 = blanc`,
  ils sont donc **inversés** avant écriture.
- libtiff écrit ses diagnostics sur `stderr` ; le shim installe un handler silencieux
  pour ne pas polluer la sortie console (parité).
- `Deflate` est écrit avec le codec **Adobe Deflate (8)**, plus largement supporté
  que l'identifiant « legacy » 32946 (même codec).

> ImageIO reste utilisé pour les autres formats (PNG, JPEG, GIF, BMP) et pour le
> TIFF lorsque libtiff est absent.

## 6. Formats de pixels et conversions

### 6.1 Formats de travail

| Format | Bpp | Description |
| ------ | --- | ----------- |
| `ifBinary` (b1) | 1 bit | noir/blanc, utilisé pour TIFF G4 |
| `ifGray8` (g8) | 1 octet | image de travail, Otsu, détection |
| `ifIndex8` | 1 octet + palette | converti avant rotation |
| `ifR8G8B8` (rgb24) | 3 octets | ordre mémoire R,G,B (`TColor24Rec = B,G,R`) |
| `ifA8R8G8B8` (rgba32) | 4 octets | ordre mémoire B,G,R,A (`TColor32Rec`) |

### 6.2 `EnsurePixelFormatForRotation`

Avant rotation, on ramène la sortie vers un format supporté
(`Gray8`, `RGB24`, `ARGB32`) :

```text
si Format ∉ {Gray8, RGB24, ARGB32} :
  si Format == ifIndex8 :
    si palette contient de l'alpha      → ARGB32
    sinon si palette est en niveaux de gris → Gray8
    sinon                                    → RGB24
  sinon si le format a un canal alpha  → ARGB32
  sinon si Format == ifBinary OU format a un canal gris → Gray8
  sinon                                                  → RGB24

// Couleur de fond explicite avec alpha ?
si (BackgroundColor AND $FF000000) != $FF000000 :
  Format = ARGB32
sinon si Format == Gray8 ET fond non gris (R≠G ou B≠G) :
  Format = RGB24
```

### 6.3 Palettes

ImageIO n'expose jamais d'image indexée : un PNG/GIF à palette est **étendu** en
RGB (ou en niveaux de gris). On reproduit néanmoins la décision d'Imaging
« palette en niveaux de gris → Gray8 » en analysant le contenu décodé : si tous les
pixels sont gris (R == G == B), l'image est chargée en `Gray8`, sinon en `RGB24`.

Le type `Palette` (`DeskewCore`) fournit `hasAlpha` et `isGrayScale`
(équivalents de `PaletteHasAlpha` / `PaletteIsGrayScale`), et
`PixelFormat.rotationFormat(palette:background:)` reproduit la branche `ifIndex8`
de `EnsurePixelFormatForRotation` (alpha → ARGB32 ; gris → Gray8 ; sinon RGB24,
avec les ajustements liés à la couleur de fond).

### 6.4 `-f` (format forcé)

Appliqué **juste avant sauvegarde**. Cas particulier : `-f b1` (binaire) accepté même
si la rotation a introduit des niveaux de gris (l'utilisateur l'a demandé
explicitement). `g4` force automatiquement `ifBinary`.

`-f b1` et `-c tg4` produisent une **vraie image 1 bit** (`BinaryImage`, bits
empaquetés, `1` = blanc) : seuillage d'Imaging `> 128 → blanc`, comme `EncodeBinary`.
Le TIFF résultant est en G4 (cf. §5).

> **Limite connue** : le 1 bit n'est réellement obtenu que pour **PNG** et **TIFF**.
> Pour **GIF** et **BMP**, ImageIO ré-encode en 8 bits (ces formats n'ont pas de
> chemin 1 bit dans notre writer). Le rendu est identique, seule la profondeur
> diffère. Voir l'issue #6.

## 7. Copie « sans changement »

Si aucun traitement n'a modifié l'image et que l'extension de sortie est identique à
celle d'entrée, le fichier est **copié tel quel** (pas de ré-encodage) :

```text
Changed = Changed OR (ext(Input) != ext(Output))
si Changed : ré-encoder
sinon      : CopyFile(Input, Output)
```

À reproduire pour éviter toute perte de qualité inutile.

## 8. Chemins et répertoires

- Le dossier de sortie est créé si nécessaire (`ForceDirectories`).
- `EnsureTrailingPathDelimiter('') == ''` : pas de séparateur pour un fichier dans le
  répertoire courant.
- `GetFileDir` / `GetFileName` gèrent indépendamment `/` et `\` (portabilité multi-OS) ;
  en Swift, `URL` suffit puisque l'on cible macOS.

## 9. Points de vigilance pour la parité

- **Ordre des canaux** : le code Pascal suppose B,G,R(,A) en mémoire. Core Graphics
  peut produire R,G,B(,A) selon `bitmapInfo`. Choisir un layout unique et convertir
  explicitement.
- **Alpha prémultiplié** : Core Graphics prémultiplie fréquemment ; le code original ne
  prémultiplie pas. Décider explicitement du comportement et tester.
- **Profils colorimétriques** : Core Graphics peut appliquer une gestion des couleurs
  (sRGB, etc.) qui change les valeurs. Pour la détection et la parité, travailler en
  espace **device** (non géré) ou documenter l'écart.
- **Palettes** : `ifIndex8` doit être converti avant rotation ; la détection de palette
  grise/alpha doit reproduire la logique Imaging (`PaletteIsGrayScale`,
  `PaletteHasAlpha`).
