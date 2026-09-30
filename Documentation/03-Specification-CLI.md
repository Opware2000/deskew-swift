# 03 — Spécification de l'interface en ligne de commande

Référence : `CmdLineOptions.pas`, `MainUnit.pas`, `Tests/TestCmdLineArgs.pas`.

## 1. Usage

```text
Usage:
deskew [-o output] [-a angle] [-b color] [..] input
    input:         Input image file

  Options:
    -o output:     Output image file name (default: prefixed input as png)
    -b color:      Background color in hex format RRGGBB|LL|AARRGGBB (default: black)
    -q filter:     Resampling filter used for rotations (default: linear
                   values: nearest|linear|cubic|lanczos)
    -a angle:      Maximal expected skew angle (both directions) in degrees (default: 10)

  Ext. options:
    -d angle:      Angle step during detection in degrees (default: 0.1)
    -t a|treshold: Auto threshold or value in 0..255 (default: auto)
    -m margins:    Skew detection only outside page margins:
                   L,T,R,B[,unit] or H,V[,unit] or A[,unit] (default: whole page)
                   unit: px|%|mm|cm|in (default: px)
    -r rect:       Skew detection only in content rectangle:
                   L,T,R,B[,unit] (default: whole page)
                   unit: px|%|mm|cm|in (default: px)
    -f format:     Force output pixel format (values: b1|g8|rgb24|rgba32)
    -p dpi:        Print resolution override
    -l angle:      Skip deskewing step if skew angle is smaller (default: 0.01)
    -g flags:      Operational flags (any combination of):
                   c - crop to input size, d - detect only (no output to file)
    -s info:       Info dump (any combination of):
                   s - skew detection stats, p - program parameters, t - timings,
                   w - save work/thresholded image
    -c specs:      Output compression specs for some file formats. Several specs
                   can be defined - delimited by commas. Supported specs:
                   jXX - JPEG compression quality, XX in range [1,100(best)]
                   tSCHEME - TIFF compression scheme: none|lzw|rle|deflate|jpeg|g4|input

  Extension (port Swift) :
    --version, -V  Affiche la version du port et quitte
```

## 2. Options et valeurs par défaut

| Option | Champ | Défaut | Validation |
| ------ | ----- | ------ | ---------- |
| *(positionnel)* | `InputFileName` | `''` | exactement un fichier |
| `-o` | `OutputFileName` | *(dérivé)* | — |
| `-a` | `MaxAngle` (Double) | `10` | doit être `> 0` pour `IsValid` |
| `-d` | `AngleStep` (Double) | `0.1` | `TryStrToFloat` **et** `0.01 ≤ valeur ≤ 5` |
| `-l` | `SkipAngle` (Double) | `0.01` | `TryStrToFloat` ; `≥ 0` pour `IsValid` |
| `-t` | `ThresholdingMethod` + `ThresholdLevel` | Otsu / `128` | `a` → Otsu ; sinon entier ; explicite ⇒ `> 0` pour `IsValid` |
| `-b` | `BackgroundColor` (TColor32) | `$FF000000` | voir § 4 |
| `-q` | `ResamplingFilter` | `rfLinear` | `nearest\|linear\|cubic\|lanczos` |
| `-r` | `ContentRect` (TFloatRect) + `ContentSizeUnit` | nul / `suPixels` | 4 valeurs + unité optionnelle |
| `-m` | `ContentMargins` (TFloatRect) + `ContentSizeUnit` | nul / `suPixels` | 1, 2 ou 4 valeurs + unité optionnelle |
| `-f` | `ForcedOutputFormat` | `ifUnknown` | `b1\|g8\|rgb24\|rgba32` |
| `-p` | `DpiOverride` (Integer) | `0` | entier `≥ 1` |
| `-c` | `JpegCompressionQuality`, `TiffCompressionScheme` | `-1`, `-1` | voir § 5 |
| `-g` | `OperationalFlags` | `{}` | contient `c` et/ou `d` |
| `-s` | `ShowDetectionStats`, `ShowParams`, `ShowTimings`, `SaveWorkImage` | `false` | contient `s`, `p`, `t`, `w` |
| — | `ErrorMessage` | `''` | — |

> `ifUnknown` = format d'image « inconnu » (aucune conversion forcée).

### `IsValid`

```text
InputFileName != ''                       ET
MaxAngle > 0                              ET
SkipAngle >= 0                            ET
(ThresholdingMethod == tmOtsu
 OU (ThresholdingMethod == tmExplicit ET ThresholdLevel > 0)) ET
ErrorMessage == ''
```

## 3. Algorithme de parsing

Paramètres sensibles à la casse : **les noms d'options sont sensibles à la casse**
(`-a` connu, `-A` inconnu). En revanche :

- les valeurs textuelles (`-q`, `-f`, `-t a`, unités, noms de compression, couleurs)
  sont comparées **insensiblement à la casse** (`Lowered` / `ContainsText`) ;
- les drapeaux `-g` et `-s` utilisent une recherche de caractère **insensible à la
  casse** (`ContainsText`).

```text
Reset()
I = 0
tant que I <= High(Args) :
  Param = Args[I]
  si Param commence par '-' :
    si I+1 <= High(Args) :
      Value = Args[I+1] ; I += 1
      si !CheckParam(Param, Value) : ÉCHEC
    sinon :
      ErrorMessage = 'Missing value for parameter: ' + Param ; ÉCHEC
  sinon :                          // fichier d'entrée
    si InputFileName != '' :
      ErrorMessage = 'Multiple input files specified (' + Param + ', ' + InputFileName + ')' ; ÉCHEC
    InputFileName = Param
  I += 1

si InputFileName == '' : ErrorMessage = 'No input file given' ; ÉCHEC

si OutputFileName == '' :
  OutputFileName = EnsureTrailingPathDelimiter(Dir(InputFileName)) +
                   'deskewed-' + BasenameSansExtension(InputFileName) + '.png'
```

Notes de comportement (issues des tests) :

- Un paramètre **après** le fichier d'entrée est accepté : `in.jpg -a 1` fonctionne.
- Les guillemets autour d'un chemin sont **conservés tels quels** :
  `"input with space.png"` reste `"input with space.png"` (le shell les retire
  normalement).
- `EnsureTrailingPathDelimiter('')` retourne `''` (pas de séparateur parasite).

## 4. Analyse de `-b` (couleur de fond)

```text
ValLower = LowerCase(Value)
si Length(ValLower) <= 8 ET TryStrToInt64('$' + ValLower, Val64) :
  TempColor = Cardinal(Val64 AND $FFFFFFFF)
  si TempColor <= $FF ET Longueur <= 2 :
      // un seul canal → répliqué sur R,G,B, alpha opaque
      BackgroundColor = Color32($FF, c, c, c)      // c = byte(TempColor)
  sinon si TempColor <= $FFFFFF ET Longueur <= 6 :
      // RRGGBB → alpha opaque
      BackgroundColor = $FF000000 OR TempColor
  sinon :
      // AARRGGBB complet
      BackgroundColor = TempColor
sinon :
  ErrorMessage = 'Invalid value for background color parameter: ' + Value
```

Vecteurs de test :

| Entrée | Résultat |
| ------ | -------- |
| `FF8000` | `$FFFF8000` |
| `C0` | `$FFC0C0C0` |
| `8000FF80` | `$8000FF80` |
| `1` | `$FF010101` |
| `FF80` | `$FF00FF80` |
| `AFF0080` | `$0AFF0080` |
| `0` | `$FF000000` |
| `00000000` | `$00000000` |
| `GGG`, `white`, `123456789`, `-FF`, `35.2`, `0xff`, `$ff`, `#ff` | erreurs |

> Aucun préfixe `0x`, `$` ou `#` n'est accepté en entrée.

## 5. Analyse de `-c` (compression)

`Value` est découpé sur `,`, puis **minusculisé**. Chaque spéc ème :

- commence par `t` → compression TIFF. Noms autorisés :
  `none`, `lzw`, `rle`, `deflate`, `jpeg`, `g4`, `input`.
  Une deuxième spéc TIFF → erreur `'TIFF output compression already set but received: …'`.
- commence par `j` → qualité JPEG, entier `1..100`.
  Une deuxième spéc JPEG → erreur `'JPEG output compression already set but received: …'`.
- sinon → `'Invalid output compression parameter: ' + S`.

Erreurs exactes :

| Cas | Message |
| --- | ------- |
| `jABC` | `Invalid JPEG output compression spec: abc` |
| `j101` | `Invalid JPEG output compression spec: 101` |
| `tXYZ` | `Invalid TIFF output compression spec: XYZ` |
| `x99` | `Invalid output compression parameter: x99` |
| `j80,trle,tlzw` | `TIFF output compression already set but received: lzw` |
| `j80,trle,j99` | `JPEG output compression already set but received: 99` |

Constantes internes : `TiffCompressionOptionAsInput = TiffCompressionOptionGroup4 + 1`.
L'ordre des noms TIFF est `none, lzw, rle, deflate, jpeg, g4, input`.

## 6. Analyse de `-r` (rectangle de contenu)

Format : `L,T,R,B` **ou** `L,T,R,B,unit`. Exactement 4 valeurs numériques (Float), la
5e token optionnelle est une unité. L'absence d'unité reste acceptée (compatibilité).

Erreurs : `'Invalid definition of content rectangle: ' + Value`.
Un `-r` après un `-m` déjà défini → `'Cannot accept content rectangle when content
margins are already defined'`.

## 7. Analyse de `-m` (marges)

Le nombre de valeurs détermine l'interprétation :

| Tokens | Interprétation |
| ------ | -------------- |
| `A` | 1 valeur → `(A,A,A,A)` (marge identique sur les 4 côtés) |
| `H,V` | 2 valeurs → `(H,V,H,V)` (marges horizontale/verticale) |
| `L,T,R,B` | 4 valeurs |
| `A,unit` | 1 valeur + unité |
| `H,V,unit` | 2 valeurs + unité |
| `L,T,R,B,unit` | 4 valeurs + unité |

Désambiguïsation du cas 2 tokens : si le 2e token est une unité reconnue
(`px|%|mm|cm|in`), alors `A,unit` ; sinon `H,V`.

Erreurs : `'Invalid definition of content margins: ' + Value`.
Un `-m` après un `-r` déjà défini → `'Cannot accept content margins when content
rectangle is already defined'`.

Vecteurs de test (`ImageBounds = (0,0,500,1000)`) :

| Options | Rect final |
| ------- | ---------- |
| *(aucune)* | `(0,0,500,1000)` |
| `-m 100,120,140,80` | `(100,120,360,920)` |
| `-m 100` | `(100,100,400,900)` |
| `-m 10,%` | `(50,100,450,900)` |
| `-m 1,20,%` | `(5,200,495,800)` |
| `-r 100,120,440,800` | `(100,120,440,800)` |
| `-r 10,20,90,80,%` | `(50,200,450,800)` |
| `-m 1,in` sans DPI | échec |
| `-r -10,-20,-90,-80` | échec (hors image) |
| `-m 50.1,%` | échec (marges trop grandes) |
| DPI 50×100 in, `-m 1,in` | `(50,100,450,900)` |
| DPI 50×100 dpcm, `-m 1,cm` | `(50,100,450,900)` |
| DPI 50×100 dpcm, `-m 1,mm` | `(5,10,495,990)` |

## 8. Autres options

```text
-f  b1→ifBinary  g8→ifGray8  rgb24→ifR8G8B8  rgba32→ifA8R8G8B8
    sinon 'Invalid value for format parameter: ' + Value

-q  nearest→rfNearest  linear→rfLinear  cubic→rfCubic  lanczos→rfLanczos
    sinon 'Invalid value for resampling filter parameter: ' + Value

-t  'a' → Otsu ; sinon TryStrToInt → explicite
    sinon 'Invalid value for treshold parameter: ' + Value   // orthographe d'origine

-p  entier ≥ 1 sinon 'Invalid value for DPI override parameter: ' + Value

-d  Float ET 0.01 ≤ v ≤ 5
    sinon 'Invalid value for angle step parameter: ' + Value

-l  Float sinon 'Invalid value for skip angle parameter: ' + Value

-a  Float, **fini** et dans `]0, 90]` (durcissement) sinon 'Invalid value for max angle parameter: ' + Value

paramètre inconnu → 'Unknown parameter: ' + Param
```

### Extension du port Swift

| Option | Effet |
| ------ | ----- |
| `--version` / `-V` | affiche `deskew-swift <version> — portage Swift de Deskew 1.33` puis quitte (code 0). **Hors parité** : l'original n'a pas cette option. |

> `-p dpi` (override de résolution) est appliqué **à l'entrée et à la sortie** :
> la résolution effective est utilisée pour la zone de détection **et** écrite dans
> les métadonnées du fichier produit (corrigé en v0.4.0).

## 9. Formats d'image forcés et compression

Dans `DoDeskew`, `ChangeOutputFormatIfNeeded` :

```text
si ForcedOutputFormat != ifUnknown ET OutputImage.Format != ForcedOutputFormat :
  OutputImage.Format = ForcedOutputFormat ; changed = true

si le fichier de sortie est un TIFF :
  si TiffCompressionScheme == 'input' :
    tenter de reprendre la compression depuis les métadonnées ;
    échec → message 'Could not set TIFF output compression from input, using default.'
  si TiffCompressionScheme == 'g4' :
    OutputImage.Format = ifBinary ; changed = true
```

## 10. Sortie console

Titre :

```text
Deskew 1.33 (2025-06-02)[ x64|x86|ARM][ (DEBUG)] by Marek Mauder
https://github.com/galfar/deskew
https://galfar.vevb.net/deskew
```

Messages principaux (libellés exacts à conserver pour la parité des scripts) :

```text
Preparing input image (<nom> [<W>x<H>/<format>]) ...
Calculating skew angle[ (in [L,T,R,B])] using threshold <N>...
Skew angle found [deg]: <angle:4.3f>
Rotating image...
Skipping deskewing step, skew angle lower than threshold of <skip:4.2f>
Saving output (<chemin absolu> [<W>x<H>/<format>]) ...
Done!
```

Statistiques (option `-s s`) :

```text
Skew detection stats:
  pixel count:        <n>
  tested pixels:      <n>
  accumulator size:   <n>
  accumulated counts: <n>
  best count:         <n>
```

Timings (option `-s t`) : `<étape> - time taken: <µs> us`.

Erreurs : préfixées `ERROR: `, suivies de `Options.ErrorMessage` si présent, puis de
l'usage (`ReportBadInput`), avec `ExitCode = 1`.

## 11. Codes de sortie

| Code | Sens |
| ---- | ---- |
| `0` | succès |
| `1` | paramètres invalides, format non supporté, image invalide, exception |

## 12. Formats supportés (affichage d'usage)

Le texte d'usage énumère dynamiquement les formats connus de la bibliothèque Imaging.
En Swift, il faut fixer une liste équivalente basée sur ImageIO (voir
[04-Entrees-Sorties-Images.md](04-Entrees-Sorties-Images.md)).

## 13. Notes de mise en œuvre Swift

- `swift-argument-parser` gère les options nommées et positionnelles, mais le
  comportement d'origine a des **particularités à répliquer** : options sensibles à la
  casse côté nom, valeurs insensibles à la casse, `-g`/`-s` en « flags combinés »
  (`cd`, `sptw`). Le plus sûr est un `ParsableCommand` avec des options `String` et une
  **réutilisation directe de la logique `CheckParam`** dans `DeskewCore.Options`.
- Les messages d'erreur doivent rester identiques pour ne pas casser les scripts.
- Le mode `-g d` (detect-only) doit continuer à n'écrire aucun fichier.
