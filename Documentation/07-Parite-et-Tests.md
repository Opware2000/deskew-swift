# 07 — Parité et tests

La réimplémentation doit produire des résultats **équivalents** à l'original. Ce
document liste les risques numériques, la méthode de génération de données de référence,
et le plan de tests.

## 1. Risques de parité numérique

| # | Risque | Cause | Impact | Mitigation |
| - | ------ | ----- | ------ | ---------- |
| 1 | Précision des filtres | `Single` (32 bits) en Pascal | Arrondis pixel à pixel | Utiliser `Float` en Swift, pas `Double` |
| 2 | Trigonométrie Hough | `Extended` 80 bits sur x86, `Double` sur ARM | Léger décalage de `D` → index de vote | Tolérance sur l'angle final ; pré-calcul `Sin/Cos` en `Double` |
| 3 | `Round` | Arrondi « bancaire » vs « au plus proche » selon compilateur | Décalage d'un pixel | Vérifier empiriquement ; adapter un helper `pascalRound` |
| 4 | `Trunc` | Tronque vers zéro | Coordonnées source | Swift `Int(x)` tronque aussi vers zéro ✔ |
| 5 | Otsu `(I+1)` | Décalage volontaire dans le code | Seuil décalé si « corrigé » | **Ne pas corriger** ; reproduire |
| 6 | Otsu `Float` | Histogramme normalisé en simple précision | Seuil | Reproduire la même séquence d'opérations `Float` |
| 7 | `FastFloor`/`FastCeil` | Astuce `±65536` approximative | Off-by-one possible en bord | Implémenter `floor`/`ceil` corrects, tolérer 1 pixel d'écart |
| 8 | Sens de rotation | Formules `Forward`/`Backward` | Image miroir | Reproduire `CalcSourceCoordinates` à l'identique |
| 9 | Ordre des canaux | `B,G,R,A` en mémoire | Couleurs inversées | Fixer le layout B,G,R,A |
| 10 | Alpha prémultiplié | Core Graphics | Couleurs semi-transparentes | Travailler non prémultiplié, tester |
| 11 | Gestion colorimétrique | Core Graphics (sRGB) | Valeurs légèrement différentes | Espace device neutre, documenter |
| 12 | Biais des 20 lignes | Moyenne incluant des zéros | Angle biaisé vers 0 | Reproduire (ne pas « améliorer ») |

### Tolérances proposées

| Grandeur | Tolérance |
| -------- | --------- |
| Angle de skew | `± 0.05°` (ou `± AngleStep`) |
| Seuil Otsu | `± 1` (idéalement 0) |
| Dimensions de l'image tournée | 0 |
| Pixels (nearest) | écart sur les bords uniquement, toléré |
| Pixels (linear/cubic/lanczos) | `± 1..2` sur les bords, 0 sur zones unies |
| Composantes couleur | `± 1` |

## 2. Données de référence (golden files) — déjà générées

Les golden files sont **générés** et versionnés dans
`Tests/DeskewParityTests/reference/` (voir `Tests/DeskewParityTests/README.md`).

Le binaire oracle (v1.33) est compilé localement depuis le source du dépôt :

```bash
brew install fpc                # si nécessaire
Scripts/compile_local.sh        # → Bin/deskew
Tests/DeskewParityTests/generate_reference.sh
```

37 cas couvrent : détection seule pour toutes les images de `TestImages/`, rotations
avec différents filtres/thresholds/couleurs/formats, marges/rectangles de contenu,
mode `-g c`, `-g d`, sauvegarde de l'image de travail (`-s w`) et sorties TIFF.

Chaque cas contient `cmd.txt`, `stdout.txt` (chemins normalisés `<ROOT>`),
`exit_code.txt` et l'image de sortie le cas échéant. Les timings (`-s t`) sont exclus
(non déterministes).

Le binaire v1.30 fourni par ailleurs (`…/SCAN/deskew`) peut servir de contrôle croisé
mais **ne doit pas** générer les références : ses options et son comportement de
recadrage diffèrent (voir historique ci-dessus).


### 2.1 Valeurs de référence à extraire

Pour chaque image de `TestImages/` et chaque jeu d'options de `runtests.sh` :

1. `Preparing input image (…)` → format et dimensions d'entrée ;
2. `Skew angle found [deg]: …` → angle attendu ;
3. `Skew detection stats:` → `pixel count`, `tested pixels`, `accumulator size`,
   `accumulated counts`, `best count` ;
4. l'image de sortie, à comparer pixel à pixel.

Conseil : écrire un **petit script** qui exécute le binaire Pascal sur toutes les
commandes et stocke les sorties console + images dans
`Tests/DeskewParityTests/reference/`. Ces fichiers deviennent les golden files du projet
Swift.

### 2.2 Diff d'images

Comparer avec :

- dimensions identiques (strict) ;
- écart maximal par composante (`maxAbsDiff`) ;
- écart moyen (`meanAbsDiff`) ;
- % de pixels identiques.

Un seuil `maxAbsDiff ≤ 2` et `≥ 99 %` de pixels identiques sur les zones non-bords est
un bon critère de succès.

## 3. Tests unitaires à porter

Les tests Pascal existants définissent les comportements de référence. À porter
directement en XCTest / Swift Testing.

### 3.1 Otsu (`TestOtsu_*`)

| Test | Attendu |
| ---- | ------- |
| `WholeImage_SimpleSplit` | `50 < seuil < 200` pour une image moitié 50 / moitié 200 |
| `WholeImage_SolidColor` | `150` |
| `ContentRect_SimpleSplit` | `30 < seuil < 180` |
| `ContentRect_SolidColor` | `100` |
| `ContentRect_IgnoresOutside` | `120` |
| `ContentRect_Invalid` | `128` pour rect largeur/hauteur nulle ou inversé |
| `ContentRect_Clipped` | `50` (rect partiellement hors image) |

### 3.2 Binarisation (`TestBinarize_*`)

| Test | Attendu |
| ---- | ------- |
| `WholeImage_SimpleSplit` | `< Threshold → 0`, `≥ Threshold → 255` |
| `ContentRect_LeavesOutsideUnchanged` | pixels hors rect inchangés |

### 3.3 Rotation (`Test_Rotate*`, `Test_*`)

Image de test : `50 × 100`, motif en quadrants.

| Test | Attendu |
| ---- | ------- |
| `Rotate0Degrees_NoChange` | dimensions et contenu identiques |
| `Rotate90Degrees_Gray8_Nearest` | dimensions `(100,50)` ; mapping quadrant haut-droit → haut-gauche |
| `Rotate180Degrees_Gray8_Nearest` | quadrant haut-gauche → bas-droit |
| `Rotate45Degrees_FitFalse_Gray8_Nearest` | dimensions `(50,100)`, coins = fond blanc |
| `FitTrue_Dimensions_Gray8` | dimensions de la boîte englobante +1 hors multiples de 90 pour cubic |
| `BackgroundColor_Gray8_Linear` | coins = couleur de fond pour 1, 45, 75, 233, 359° |
| `Rotate90Degrees_FitTrue_RGB24_Nearest` | positions des quadrants couleur |

Formule de dimension attendue (FitRotated) :

```text
W' = Ceil(|W·cosθ| + |H·sinθ|)   (+1 si filtre ≠ nearest et angle non multiple de 90)
H' = Ceil(|W·sinθ| + |H·cosθ|)
multiples de 90 : 90/270 → (H, W) ; 180 → (W, H)
```

### 3.4 Options CLI (`TestCmdLine*`)

Porter l'intégralité de `Tests/TestCmdLineArgs.pas` : parsing, défauts, entrée/sortie,
angles, seuil, filtre, formats, couleur, compression, drapeaux, contenu/marges,
`CalcContentRectForImage` (avec les DPI). Les valeurs exactes sont dans
[03-Specification-CLI.md](03-Specification-CLI.md).

> `TestSkewDetection.pas` est **vide** dans l'original : il n'y a pas de test unitaire
> de Hough. C'est justement là que les golden files d'intégration sont précieux.

## 4. Tests d'intégration CLI

Reproduire les commandes de `Bin/runtests.sh` :

```text
2.png                             (défauts)
-t a -a 10                        (Otsu explicite)
-a 10
-q lanczos -a 10
-g c                              (crop)
-t 128
-t 180
-q nearest -b 00FFFF
-r 214,266,933,1040
-t 100 -a 11 -b aa55cc -r … -s sp
-f b1
-f rgba32 -b 40ff00ff
-f g8 -b 77 -s t
-g d                              (detect-only, aucun fichier)
TIFF : -t a -a 5 ; -b DD -c j95,tjpeg ; -t 128 -c tinput ; -b FF0000 -c tdeflate ;
       -f b1 ; -a 5 -l 2
```

Vérifier pour chacune : code de sortie, absence de fichier en detect-only, existence et
format du fichier de sortie, angle affiché.

## 5. Propriétés à tester

En complément des golden files :

- **Idempotence de la binarisation** : binariser une image déjà binaire ne change rien.
- **Neutralité de la rotation 0° / 360°** : image inchangée.
- **Cohérence 90° + 90° + 90° + 90°** : retour à l'original (nearest).
- **Otsu hors rectangle** : modifier les pixels hors rect ne change pas le seuil.
- **Invariance de détection** : ajouter une bordure uniforme hors de la zone de
  détection ne change pas l'angle.
- **Determinisme** : deux exécutions donnent le même angle (indépendant du
  parallélisme). Important à valider après introduction du multithreading.

## 6. Structure des tests Swift

```text
Tests/DeskewParityTests/            # déjà présent : golden files (Pascal)
    generate_reference.sh
    reference/
        summary.txt
        index.tsv
        <cas>/{cmd.txt,exit_code.txt,stdout.txt,out.*,work-image.png}
```

Le futur package Swift ajoutera ses propres cibles de test :

```text
Tests/DeskewCoreTests/              # tests unitaires portés du Pascal
Tests/DeskewCLITests/               # comparaison aux golden files
```

Un test de parité lit `reference/index.tsv`, exécute le binaire Swift avec les mêmes
arguments, normalise les chemins absolus en `<ROOT>`, compare `stdout.txt` (hors
lignes de timing), puis charge `out.*` et le compare à l'image produite (dimensions
strictes, écart toléré).

## 7. Stratégie de validation progressive

1. **Otsu + binarisation** : doivent être `bit-exact` (facile).
2. **Géométrie / options** : `bit-exact` (calculs entiers/rationnels).
3. **Rotation nearest** : `bit-exact` attendu aux multiples de 90°.
4. **Rotation linear/cubic/lanczos** : tolérance `± 1..2`.
5. **Hough** : tolérance `± AngleStep`.
6. **Pipeline complet CLI** : comparaison aux golden files.

En cas d'écart à l'étape 3–5, distinguer : écart sur les **bords** (gestion du fond,
acceptable) vs écart en zone unie (bug d'algorithme, inacceptable).

## 8. Journalisation et traçabilité

Le pipeline doit rester capable de reproduire le **journal** exact (`-s p`, `-s s`,
`-s t`) afin de comparer les sorties console. Le format `OptionsToString` est décrit en
[03](03-Specification-CLI.md) § 10.
