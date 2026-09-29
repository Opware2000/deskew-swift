# 02 — Spécification des algorithmes

Ce document est la **référence d'implémentation**. Chaque algorithme est décrit avec sa
signature, ses paramètres, son pseudo-code fidèle au Pascal et ses cas limites.

> Convention de notation : le pseudo-code reprend les noms de variables Pascal pour
> faciliter la traçabilité. `Floor`/`Ceil`/`Trunc`/`Round` désignent les opérations
> Pascal (voir § 8 pour les pièges de parité).

---

## 1. Détection d'inclinaison — `CalcRotationAngle`

**Source** : `RotationDetector.pas`
**But** : estimer l'angle de rotation (en degrés) d'un document à texte, par
transformée de Hough appliquée aux **pixels de la ligne de base du texte**.

### 1.1 Signature

```pascal
function CalcRotationAngle(const MaxAngle, AngleStep: Double; Threshold: Integer;
  Width, Height: Integer; Pixels: PByteArray; DetectionArea: PRect = nil;
  Stats: PCalcSkewAngleStats = nil): Double;
```

| Paramètre | Type | Rôle |
| --------- | ---- | ---- |
| `MaxAngle` | Double (deg) | Angle max attendu en valeur absolue. La plage balayée est `[-MaxAngle, +MaxAngle]`. |
| `AngleStep` | Double (deg) | Pas angulaire de quantification. |
| `Threshold` | Integer 0..255 | Un pixel est « noir » si sa valeur **strictement** `< Threshold`. |
| `Width`, `Height` | Integer | Dimensions de l'image. |
| `Pixels` | `PByteArray` | Pointeur sur image **Gray8** contiguë, `stride = Width` (index `y*Width + x`). |
| `DetectionArea` | `PRect` optionnel | Rectangle `(Left,Top,Right,Bottom)` de détection. `nil` = image entière. |
| `Stats` | sortie optionnelle | Statistiques de détection. |

### 1.2 Statistiques (`TCalcSkewAngleStats`)

| Champ | Formule |
| ----- | ------- |
| `PixelCount` | `PageWidth * PageHeight` |
| `TestedPixels` | `AccumulatedCounts div AlphaSteps` |
| `AccumulatorSize` | `DistCount * AlphaSteps` |
| `AccumulatedCounts` | Somme de **toutes** les cases de l'accumulateur |
| `BestCount` | Nombre de votes de la meilleure ligne |

### 1.3 Initialisation

```text
ContentRect = DetectionArea ?? (0, 0, Width, Height)
PageWidth   = ContentRect.Right  - ContentRect.Left
PageHeight  = ContentRect.Bottom - ContentRect.Top
si ContentRect.Bottom == Height : PageHeight -= 1   // évite de lire la ligne y+1 hors image

AlphaStart   = -MaxAngle
AlphaSteps   = Ceil(2 * MaxAngle / AngleStep)        // nombre de pas angulaires
MinDist      = -Max(PageWidth, PageHeight)
DistCount    = 2 * (PageWidth + PageHeight)
AccumulatorSize = DistCount * AlphaSteps
HoughAccumulator[0 .. AccumulatorSize-1] = 0         // entiers
AccumulatedCounts = 0
```

> Les angles effectivement testés sont `AlphaStart + I·AngleStep` pour
> `I = 0 .. AlphaSteps-1`, soit `[-MaxAngle, -MaxAngle + (AlphaSteps-1)·AngleStep]`.
> La borne supérieure `+MaxAngle` n'est donc **généralement pas atteinte**
> (p. ex. `MaxAngle = 10`, `AngleStep = 0.1` → dernier angle `9.9°`).

> **Invariant à vérifier** : dans `CalcLines`, l'indice `DIndex = Trunc(D - MinDist)`
> doit rester dans `[0, DistCount-1]`. Avec les valeurs par défaut (`MaxAngle = 10`),
> c'est toujours le cas. Pour des angles plus grands, `DistCount` reste suffisant dans
> la pratique, mais l'implémentation Swift **doit** ajouter un garde-fou (clamp ou
> validation) pour éviter un débordement mémoire silencieux.

### 1.4 Classification des pixels testés

Un pixel n'est retenu que s'il forme une **ligne de base** de texte : il est noir et le
pixel **juste en dessous** ne l'est pas.

```text
IsPixelBlack(x, y) = Pixels[y * Width + x] < Threshold

pour Y de 0 à PageHeight-1 :
  pour X de 0 à PageWidth-1 :
    px = ContentRect.Left + X
    py = ContentRect.Top  + Y
    si IsPixelBlack(px, py) ET NON IsPixelBlack(px, py + 1) :
      CalcLines(X, Y)
```

### 1.5 Accumulation (`CalcLines`)

Pour chaque pas angulaire `I`, on calcule l'ordonnée à l'origine `D` de la droite
passant par `(X, Y)` d'angle `alpha = AlphaStart + I*AngleStep`, puis on vote.

```text
CalcLines(X, Y) :
  pour I de 0 à AlphaSteps-1 :
    alphaDeg = AlphaStart + I * AngleStep
    Rads     = alphaDeg * PI / 180
    (Sin, Cos) = SinCos(Rads)
    D        = Y * Cos - X * Sin          // D = d * cos(alpha) où d = ordonnée à l'origine
    DIndex   = Trunc(D - MinDist)
    Index    = DIndex * AlphaSteps + I     // ligne = distance, colonne = angle
    HoughAccumulator[Index] += 1
```

> Remarque géométrique : la droite est paramétrée sous la forme `y = tan(alpha)·x + d`
> avec `d = (Y·cos − X·sin) / cos`. Le code quantifie directement la quantité
> `D = d·cos(alpha)`.

### 1.6 Sélection des 20 meilleures lignes (`GetBestLines`)

```text
BestLinesCount = 20
Result[0..19] = { Count: 0, Index: 0, Alpha: 0, Distance: 0 }

pour I de 0 à AccumulatorSize-1 :
  si HoughAccumulator[I] > Result[19].Count :
    Result[19] = { Count: HoughAccumulator[I], Index: I }
    J = 19
    // tri par insertion, décroissant selon Count
    tant que J > 0 ET Result[J].Count > Result[J-1].Count :
      échanger Result[J] et Result[J-1]
      J -= 1
  AccumulatedCounts += HoughAccumulator[I]

pour I de 0 à 19 :
  DistIndex  = Result[I].Index div AlphaSteps
  AlphaIndex = Result[I].Index - DistIndex * AlphaSteps
  Result[I].Alpha    = AlphaStart + AlphaIndex * AngleStep
  Result[I].Distance = DistIndex + MinDist
```

> **Comportement à conserver** : s'il y a moins de 20 lignes « utiles », les emplacements
> restants gardent `Alpha = 0`. La moyenne finale est donc **biaisée vers 0**. C'est le
> comportement de référence ; le reproduire garantit la parité.

### 1.7 Résultat

```text
SumAngles = somme des Result[I].Alpha pour I = 0..19
Result    = SumAngles / 20
```

`RotationDetector` retourne ainsi l'angle à appliquer en degrés.

### 1.8 Parallélisation possible

- `CalcLines` écrit uniquement dans la colonne `I` de l'accumulateur. **Deux angles
  distincts ne collisionnent jamais.** On peut donc partitionner les `AlphaSteps` entre
  threads sans atomique.
- Alternative : partitionner les lignes de l'image avec un accumulateur local par thread
  puis fusionner (`+`). Une seule lecture mémoire de l'image ; coût mémoire ≈
  `AccumulatorSize * 4 octets` par thread.

Voir [06-Multithreading-et-Performance.md](06-Multithreading-et-Performance.md).

---

## 2. Seuillage d'Otsu — `OtsuThresholding`

**Source** : `ImageUtils.pas`
**But** : calculer un seuil `[0..255]` minimisant la variance intra-classe, sur une
image **Gray8** et éventuellement dans un sous-rectangle.

### 2.1 Signature

```pascal
function OtsuThresholding(var Image: TImageData; AContentRect: PRect = nil): Integer;
```

Précondition : `Image.Format = ifGray8`.

### 2.2 Pseudo-code exact

```text
ImageBounds = (0, 0, Width, Height)
si AContentRect fourni :
  si AContentRect non vide : EffectiveRect = Intersection(AContentRect, ImageBounds)
  sinon                    : EffectiveRect = (0,0,0,0)      // vide
sinon :
  EffectiveRect = ImageBounds

NumPixelsInRect = RectWidth(EffectiveRect) * RectHeight(EffectiveRect)
si NumPixelsInRect <= 0 : retourner 128                      // défaut

// Histogramme en Single (Float32)
Histogram[0..255] = 0
Min = 255 ; Max = 0
pour Y de EffectiveRect.Top à EffectiveRect.Bottom-1 :
  pour X de EffectiveRect.Left à EffectiveRect.Right-1 :
    v = Bits[Y * Width + X]
    Histogram[v] += 1
    si v < Min : Min = v
    si v > Max : Max = v

pour I de Min à Max : Histogram[I] /= NumPixelsInRect

// Moyenne et variance (noter le « +1 »)
Mean = 0
pour I de Min à Max : Mean += (I + 1) * Histogram[I]

Variance = 0
pour I de Min à Max : Variance += (I + 1 - Mean)^2 * Histogram[I]

// Recherche du seuil maximisant Mu
LargestMu = 0 ; Level = 0
pour I de Min à Max :
  Omega = 0 ; LevelMean = 0
  pour J de Min à I-1 :
    Omega     += Histogram[J]
    LevelMean += (J + 1) * Histogram[J]
  Mu = (Mean * Omega - LevelMean)^2
  Omega = Omega * (1 - Omega)
  si Omega > 1E-6 ET Omega < 1 - 1E-6 : Mu = Mu / Omega
  sinon                                : Mu = 0
  si Mu > LargestMu : LargestMu = Mu ; Level = I

si Min == Max : Level = Min
retourner Level
```

Points à reproduire fidèlement :

- l'offset **`(I + 1)`** dans `Mean` et `LevelMean` (particularité du code original) ;
- `Histogram` est en **simple précision** (`Single`) ;
- le cas rectangle vide → `128` ;
- `Min == Max` → `Level = Min` (rectangle de couleur unie → seuil = la couleur).

### 2.3 Complexité

`O(Max-Min+1)²` à cause de la double boucle `I/J` (au pire 256² = 65 536 opérations),
plus une passe linéaire sur les pixels du rectangle. L'optimisation par somme cumulée
est possible mais **altère potentiellement les arrondis en `Float32`** : à valider par
tests de parité.

### 2.4 Vecteurs de test (issus de `Tests/TestImageUtils.pas`)

| Cas | Entrée | Seuil attendu |
| --- | ------ | ------------- |
| Séparation simple pleine image | moitié 50 / moitié 200 | `50 < seuil < 200` |
| Couleur unie | tout 150 | `150` |
| Rectangle de contenu | contenu 30 / 180 sur fond 255 | `30 < seuil < 180` |
| Contenu uni | contenu 100 sur fond 255 | `100` |
| Hors rectangle ignoré | bruit 10/240 hors rect, 120 dans rect | `120` |
| Rect largeur nulle | `(10,10,10,20)` | `128` |
| Rect hauteur nulle | `(10,10,20,10)` | `128` |
| Rect inversé | `Left > Right` ou `Top > Bottom` | `128` |
| Rect hors image (clippé) | valide `(10,10,20,20)` uni 50 | `50` |

---

## 3. Binarisation — `BinarizeImage`

**Source** : `ImageUtils.pas`

```pascal
procedure BinarizeImage(var Image: TImageData; Threshold: Integer; AContentRect: PRect = nil);
```

Précondition : `Image.Format = ifGray8`.

```text
ImageBounds = (0, 0, Width, Height)
si AContentRect fourni ET RectWidth > 0 ET RectHeight > 0 :
  EffectiveRect = Intersection(AContentRect, ImageBounds)
sinon :
  EffectiveRect = ImageBounds

pour Y de EffectiveRect.Top à EffectiveRect.Bottom-1 :
  pour X de EffectiveRect.Left à EffectiveRect.Right-1 :
    Bits[Y*Width + X] = (Bits[Y*Width + X] >= Threshold) ? 255 : 0
```

Les pixels **hors** du rectangle effectif restent inchangés (comportement vérifié par
`TestBinarize_ContentRect_LeavesOutsideUnchanged`).

---

## 4. Rotation d'image — `RotateImage`

**Source** : `ImageUtils.pas`
**But** : faire tourner une image d'un angle quelconque, avec couleur de fond pour les
zones « vides », en choisissant de recadrer ou d'agrandir.

### 4.1 Filtres de rééchantillonnage

```pascal
TResamplingFilter = (rfNearest, rfLinear, rfCubic, rfLanczos);
SupportedRotationFormats = [ ifGray8, ifR8G8B8, ifA8R8G8B8 ];
```

### 4.2 Signature

```pascal
procedure RotateImage(var Image: TImageData; Angle: Double; BackgroundColor: TColor32;
  ResamplingFilter: TResamplingFilter; FitRotated: Boolean);
```

### 4.3 Enchaînement global

```text
Assert(Image.Format in SupportedRotationFormats)
norm. Angle dans [0, 360) :  while Angle >= 360 : Angle -= 360
                             while Angle <  0   : Angle += 360
si |Angle - 0| < 1E-6 OU |Angle - 360| < 1E-6 : sortir (inchangé)

// Cas multiples de 90 (à 1E-6 près) → RotateImageMul90 (voir § 5)
si SameValue(Angle,  90, 1e-6) : RotateImageMul90(Image,  90) ; sortir
si SameValue(Angle, 180, 1e-6) : RotateImageMul90(Image, 180) ; sortir
si SameValue(Angle, 270, 1e-6) : RotateImageMul90(Image, 270) ; sortir

AngleRad = Angle * PI / 180
(ForwardSin, ForwardCos)   = SinCos( AngleRad)
(BackwardSin, BackwardCos) = SinCos(-AngleRad)

SrcWidth, SrcHeight       = dimensions source
SrcWidthHalf              = (SrcWidth  - 1) / 2
SrcHeightHalf             = (SrcHeight - 1) / 2

si FitRotated :
  DstWidth  = Ceil(|SrcWidth * ForwardCos| + |SrcHeight * ForwardSin|)
  DstHeight = Ceil(|SrcWidth * ForwardSin| + |SrcHeight * ForwardCos|)
  si Filtre != rfNearest : DstWidth += 1 ; DstHeight += 1   // marge antialiasing
sinon :
  DstWidth  = SrcWidth
  DstHeight = SrcHeight

si DstWidth  <= 0 : DstWidth  = 1
si DstHeight <= 0 : DstHeight = 1
DstWidthHalf  = (DstWidth  - 1) / 2
DstHeightHalf = (DstHeight - 1) / 2

allouer DstImage (même format que source)
BackColor32 = TColor32Rec(BackgroundColor)   // stockage B,G,R,A ; valeur 0xAARRGGBB

// Remplissage selon le filtre (voir 4.4, 4.5, 4.6)
```

### 4.4 Calcul des coordonnées source (`CalcSourceCoordinates`)

Appliqué pour **chaque** pixel destination `(dstX, dstY)` :

```text
DstCoordX = dstX - DstWidthHalf
DstCoordY = DstHeightHalf - dstY          // axe Y inversé

SrcCoordX = BackwardCos * DstCoordX - BackwardSin * DstCoordY
SrcCoordY = BackwardSin * DstCoordX + BackwardCos * DstCoordY

SrcX = SrcCoordX + SrcWidthHalf
SrcY = SrcHeightHalf - SrcCoordY
```

(`Forward…` sert au calcul de la boîte englobante, `Backward…` au mapping inverse
destination → source.)

### 4.5 Filtre `rfNearest`

```text
pour chaque (X, Y) destination :
  (SrcX, SrcY) = CalcSourceCoordinates(X, Y)
  si 0 <= SrcX < SrcWidth ET 0 <= SrcY < SrcHeight :
    copier le pixel source [Round(SrcY), Round(SrcX)]
  sinon :
    copier BackgroundColor
```

### 4.6 Filtre `rfLinear` (bilinéaire)

Deux chemins selon le format :

**RGB24 :**

```text
si -1 <= SrcX <= SrcWidth ET -1 <= SrcY <= SrcHeight :
  Dst = Bilinear24(SrcX, SrcY)
sinon :
  Dst = BackColor24            // composantes B,G,R de la couleur de fond
```

**Gray8 / ARGB32 :**

```text
si -1 <= SrcX <= SrcWidth ET -1 <= SrcY <= SrcHeight :
  Dst = (Bpp == 1) ? Bilinear8(SrcX, SrcY) : Bilinear32(SrcX, SrcY)
sinon :
  Dst = BackgroundColor
```

Helpers :

```text
FastFloor(X) = Trunc(X + 65536) - 65536        // valide pour |X| < 65536
FastCeil(X)  = 65536 - Trunc(65536 - X)

GetBilinearPixelCoords(X, Y) :
  TopLeftPt     = (FastFloor(X), FastFloor(Y))
  HorzWeight    = X - TopLeftPt.X
  VertWeight    = Y - TopLeftPt.Y
  BottomLeftPt  = (TopLeftPt.X,     TopLeftPt.Y + 1)
  TopRightPt    = (TopLeftPt.X + 1, TopLeftPt.Y)
  BottomRightPt = (TopLeftPt.X + 1, TopLeftPt.Y + 1)

InterpolateBytes(HW, VW, C11, C12, C21, C22) :
  ClampToByte( Trunc(
      (1-HW)*(1-VW)*C11 + (1-HW)*VW*C12 + HW*(1-VW)*C21 + HW*VW*C22 )) 
```

Où `C11 = haut-gauche`, `C12 = bas-gauche`, `C21 = haut-droite`, `C22 = bas-droite`
(attention à l'ordre réel des arguments dans le code : `TopLeft, BottomLeft, TopRight,
BottomRight`).

Lecture hors bornes → couleur de fond (`GetPixelColor24/8/32`).

### 4.7 Filtres `rfCubic` et `rfLanczos` (convolution séparable)

Sélection du noyau :

| Filtre requête | Noyau Imaging | Rayon | `KernelWidth = Ceil(Rayon)` |
| -------------- | ------------- | ----- | ---------------------------- |
| `rfCubic` | `sfCatmullRom` | `2.0` | `2` |
| `rfLanczos` | `sfLanczos` | `3.0` | `3` |

**Table de poids précalculée** (`USE_FILTER_TABLE` défini) :

```text
TableSize    = 32        // 33 colonnes (0..32), seules 0..31 utilisées
MaxTablePos  = 31
MaxKernelRadius = 3
WeightTable[-MaxKernelRadius .. MaxKernelRadius, 0 .. TableSize] = 0

pour I de 0 à TableSize :                       // 0..32
  Fraction = I / (TableSize - 1)                // = I / 31
  pour J de -KernelWidth à KernelWidth :
    WeightTable[J, I] = FilterFunction(J + Fraction)
```

Fonctions de noyau (source `ImagingFormats.pas`, à reproduire) :

```text
FilterCatmullRom(t) :
  t = |t|
  si t < 1 : 0.5 * (2 + t^2 * (-5 + 3t))
  si t < 2 : 0.5 * (4 + t * (-8 + t * (5 - t)))
  sinon    : 0

FilterLanczos(t) :
  t = |t|
  si t < 3 : SinC(t) * SinC(t/3)   où SinC(u) = (u != 0) ? sin(u*PI)/(u*PI) : 1
  sinon    : 0
```

**`FilterPixel(X, Y, Bpp)`** — convolution 2D séparable avec gestion des bords :

```text
ClipRect = (0, 0, SrcWidth, SrcHeight)
Edge = false
CeilX = FastCeil(X) ; CeilY = FastCeil(Y)

si NON (CeilX < 0 OU CeilX > SrcWidth OU CeilY < 0 OU CeilY > SrcHeight) :
  // déterminer bornes du noyau dans l'image
  si CeilX - KernelWidth < 0      : LoX = -CeilX                ; Edge = true  sinon LoX = -KernelWidth
  si CeilX + KernelWidth >= SrcWidth : HiX = SrcWidth-1-CeilX   ; Edge = true  sinon HiX = KernelWidth
  si CeilY - KernelWidth < 0      : LoY = -CeilY                ; Edge = true  sinon LoY = -KernelWidth
  si CeilY + KernelWidth >= SrcHeight : HiY = SrcHeight-1-CeilY ; Edge = true  sinon HiY = KernelWidth
sinon :
  retourner BackgroundColor

XFilterTablePos = Round((CeilX - X) * MaxTablePos)
YFilterTablePos = Round((CeilY - Y) * MaxTablePos)

VertEntry = {0,0,0,0}
pour I de LoY à HiY :                       // colonnes verticales
  WeightVert = WeightTable[I, YFilterTablePos]
  pointeur SrcPixel = base + (LoX + CeilX + (I + CeilY)*SrcWidth) * Bpp
  si WeightVert != 0 :
    HorzEntry = {0,0,0,0}
    pour J de LoX à HiX :                   // lignes horizontales
      WeightHorz = WeightTable[J, XFilterTablePos]
      HorzEntry.B += SrcPixel.B * WeightHorz
      si Bpp > 1 : HorzEntry.R/G += ...
      si Bpp > 3 : HorzEntry.A   += ...
      SrcPixel += Bpp
    VertEntry += HorzEntry * WeightVert

si Edge :                                   // ajouter les contributions de fond hors bornes
  pour I de -KernelWidth à KernelWidth :
    WeightVert = WeightTable[I, YFilterTablePos]
    si WeightVert != 0 :
      HorzEntry = {0,0,0,0}
      pour J de -KernelWidth à KernelWidth :
        si J < LoX OU J > HiX OU I < LoY OU I > HiY :
          WeightHorz = WeightTable[J, XFilterTablePos]
          HorzEntry += BackgroundColor * WeightHorz
      VertEntry += HorzEntry * WeightVert

résultat = { A,R,G,B = ClampToByte(Trunc(composante + 0.5)) }
```

Puis pour chaque pixel destination : `Dst = FilterPixel(SrcX, SrcY, Bpp)`.

> **Ordre des canaux** : `TColor32Rec` est un record `packed` d'octets `B, G, R, A`
> (ordre mémoire petit-boutiste d'un `TColor32 = 0xAARRGGBB`). Reporté en Swift :
> buffer `[UInt8]` en ordre **BGRA** ou bien un type avec accès nommé.

### 4.8 Filtres disponibles (pour extension éventuelle)

Le code original n'expose que 4 filtres, mais `ImagingFormats.pas` définit des noyaux
supplémentaires réutilisables : `FilterNearest`, `FilterLinear`, `FilterCosine`,
`FilterHermite`, `FilterQuadratic`, `FilterGaussian`, `FilterSpline`, `FilterLanczos`,
`FilterMitchell`, `FilterCatmullRom` (rayons `sfMitchell = 2`, `sfSpline = 2`,
`sfQuadratic = 1.5`, `sfGaussian = 1.25`, `sfCosine = 1`, `sfHermite = 1`).

---

## 5. Rotation 90/180/270 — `RotateImageMul90`

**Source** : `Imaging.pas` (appelée par `RotateImage`).
**But** : rotation exacte, sans interpolation, par permutation de lignes/colonnes.

Pour une image `W × H`, `bpp` octets par pixel, l'image de sortie a pour dimensions :

- 90° ou 270° avec `W != H` → `(H, W)` ;
- sinon → `(W, H)`.

Mappings destination ← source (`new(X, Y) = src(...)`) :

| Angle | Dimensions | Mapping |
| ----- | ---------- | ------- |
| 90 | `(H, W)` si non carrée | `new(X, Y) = src(W - 1 - Y, X)` |
| 180 | `(W, H)` | `new(X, Y) = src(W - 1 - X, H - 1 - Y)` |
| 270 | `(H, W)` si non carrée | `new(X, Y) = src(H - 1 - X, Y)` |

Le sens de rotation effectif est **anti-horaire** (CCW) conforme aux tests :
`Test_Rotate90Degrees_Gray8_Nearest` vérifie que le quadrant haut-droit devient
haut-gauche après 90°.

---

## 6. `IsImageDataEqual`

**Source** : `ImageUtils.pas` (utilitaire, testé).
Compare deux images : existence des bits, `Width`, `Height`, `Format`, `Size`,
palettes (`ifIndex8`), puis `CompareMem` sur tout le tampon. Utilisé seulement par les
tests dans la version actuelle, mais utile pour les tests de parité Swift.

---

## 7. Géométrie et unités — `Utils.pas`

### 7.1 `TSizeUnit`

```pascal
TSizeUnit = (suPixels, suPercent, suMm, suCm, suInch);
```

Jetons CLI associés : `px`, `%`, `mm`, `cm`, `in`.

### 7.2 `CalcRectInPixels`

Convertit un rectangle exprimé dans une unité (`TFloatRect`) en pixels
(`TRect`), relativement aux bornes de l'image et aux métadonnées de résolution.

```text
MakeScaledRect(R, WidthFactor, HeightFactor) =
  Rect( Round(R.Left  * WidthFactor),
        Round(R.Top   * HeightFactor),
        Round(R.Right * WidthFactor),
        Round(R.Bottom* HeightFactor) )

CalcRectInPixels(RectInUnits, SizeUnit, ImageBoundsPx, Metadata) :

  suPixels :
    MakeScaledRect(RectInUnits, 1, 1)

  suPercent :
    MakeScaledRect(RectInUnits, RectWidth(ImageBoundsPx)/100, RectHeight(ImageBoundsPx)/100)

  suMm :
    (PixX, PixY) = Metadata.GetPhysicalPixelSize(ruDpcm)     // pixels par cm
    si échec : retourner NullRect
    MakeScaledRect(RectInUnits, PixX/10, PixY/10)            // pixels par mm

  suCm :
    (PixX, PixY) = Metadata.GetPhysicalPixelSize(ruDpcm)     // pixels par cm
    si échec : retourner NullRect
    MakeScaledRect(RectInUnits, PixX, PixY)

  suInch :
    (PixX, PixY) = Metadata.GetPhysicalPixelSize(ruDpi)      // pixels par inch
    si échec : retourner NullRect
    MakeScaledRect(RectInUnits, PixX, PixY)
```

`MakeScaledRect` n'est pas exporté (fonction interne d'implémentation) — en Swift, il
peut être une fonction privée/`static`.

### 7.3 Helpers de rectangles

```text
IsRectNull(R)      : R.Left == 0 ET R.Top == 0 ET R.Right == 0 ET R.Bottom == 0
IsFloatRectNull(R) : idem en Single
RectToStr(R)       : '[' + Left + ',' + Top + ',' + Right + ',' + Bottom + ']'
```

### 7.4 `CalcContentRectForImage` (CmdLineOptions)

Combinaison **marges** ou **rectangle** de contenu avec les bornes de l'image :

```text
si ContentRect et ContentMargins sont tous deux nuls : FinalRect = ImageBounds ; OK

si ContentMargins non nul :
  MarginsInPx = CalcRectInPixels(ContentMargins, unit, ImageBounds, Metadata)
  si MarginsInPx est nul : échec
  FinalRect = ( MarginsInPx.Left,
                MarginsInPx.Top,
                ImageBounds.Right  - MarginsInPx.Right,
                ImageBounds.Bottom - MarginsInPx.Bottom )

sinon si ContentRect non nul :
  FinalRect = CalcRectInPixels(ContentRect, unit, ImageBounds, Metadata)

si FinalRect vide OU Intersection(FinalRect, ImageBounds) échoue : échec
OK
```

Cas de test de référence : voir `Tests/TestCmdLineArgs.pas::TestCalcDetectionRect`
(`ImageBounds = (0,0,500,1000)`).

---

## 8. Pièges numériques à connaître

| Sujet | Pascal | Piège / recommandation Swift |
| ----- | ------ | ---------------------------- |
| Précision filtres / Otsu | `Single` = 32 bits | Utiliser **`Float`** partout, pas `Double`, pour approcher les arrondis |
| Trigonométrie Hough | `Sin, Cos: Extended` (80 bits sur x86) | Non reproductible exactement ; utiliser `Double` et accepter une tolérance |
| `Trunc` | Tronque vers zéro | `Int(x)` (tronque aussi vers zéro) ; attention aux négatifs |
| `Round` | Arrondi « bancaire » ou au plus proche (dépend du compilateur) | Vérifier la parité empiriquement ; possible `rounded()` / `(x + 0.5).rounded(.down)` |
| `FastFloor` / `FastCeil` | Astuce `±65536` | Ne pas répliquer tel quel (approximatif) ; `Int(x.rounded(.down))` est correct mais pas bit-identique |
| `ClampToByte` | Borne dans `[0,255]` | `min(max(v,0),255)` |
| Ordre des canaux | `packed record` B,G,R,A | Choisir explicitement un layout et le documenter |

Détails et stratégie de test : [07-Parite-et-Tests.md](07-Parite-et-Tests.md).
