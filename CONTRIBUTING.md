# Contribuer

Merci de votre intérêt pour **deskew-swift**, la réimplémentation en Swift de
[Deskew](https://github.com/galfar/deskew).

## Nature du projet

Travail dérivé de Deskew (auteur original : Marek Mauder), distribué sous
**Mozilla Public License 2.0** (voir [`LICENSE`](LICENSE)). Toute contribution doit
conserver cette licence et l'attribution d'origine.

Objectif : reproduire **fidèlement** les algorithmes du projet original (parité des
résultats) tout en modernisant la base technique (Swift natif arm64, multithreading,
ImageIO).

## Prérequis

- macOS avec **Swift ≥ 5.9** (Xcode 15+). Si la commande `swift` du `PATH` est plus
  ancienne, utiliser `xcrun swift`.
- *(optionnel)* Free Pascal pour régénérer l'oracle : `brew install fpc`.
- *(optionnel)* `libtiff` pour le support TIFF de l'oracle : `brew install libtiff`.

## Compiler et tester

```bash
Scripts/build_swift_release.sh          # binaire release
xcrun swift test -c release             # tests de parité (quelques secondes)
```

> Les tests en mode debug sont lents (cas de stress `cubic` sur une grande image) :
> toujours privilégier `swift test -c release`.

## Golden files (références de parité)

Les tests de parité comparent la sortie Swift aux références produites par le binaire
Pascal d'origine, versionnées dans `Tests/DeskewParityTests/reference/`.

Régénération (rare, uniquement si l'oracle change) :

```bash
Scripts/compile_local.sh
Tests/DeskewParityTests/generate_reference.sh
```

Détails : [`Tests/DeskewParityTests/README.md`](Tests/DeskewParityTests/README.md).

## Conventions de code

- **Structure** : `DeskewCore` = algorithmes purs (aucune entrée-sortie) ;
  `DeskewImageIO` = pont ImageIO/CoreGraphics ; `DeskewCLI` = exécutable.
- **Parité** : ne pas « améliorer » un algorithme sans le signaler. Les
  particularités de l'original (arrondi bancaire, offset `(I+1)` d'Otsu, biais des
  20 lignes, lecture hors buffer au bord `nearest`) sont **intentionnelles** et
  documentées.
- **Précision** : `Float` (32 bits) là où l'original utilise `Single` ; `Double` pour
  la trigonométrie de Hough.
- **Performance** : `withUnsafeMutableBufferPointer` dans les boucles chaudes,
  parallélisation par bandes disjointes (pas de verrou).
- **Tests** : toute logique non triviale laisse un test ; les cas de parité se
  comparent aux golden files.

## Conventions de commit

Messages **en français**, format **Conventional Commits**, emoji de type en tête :

```
<emoji> <type>(<scope>): <résumé à l'impératif>

[corps optionnel expliquant le pourquoi]
```

| Emoji | Type | Usage |
| ----- | ---- | ----- |
| ✨ | `feat` | nouvelle fonctionnalité |
| 🐛 | `fix` | correction de bug |
| ♻️ | `refactor` | refactorisation |
| ⚡️ | `perf` | performance |
| 🧪 | `test` | tests |
| 📝 | `docs` | documentation |
| 👷 | `ci` | CI/CD |
| 🔨 | `chore` | maintenance |
| 🔧 | `build` | dépendances / build |

Scopes recommandés : `core`, `options`, `rotation`, `skew`, `io`, `pipeline`, `cli`,
`ci`, `docs`, `todo`.

## Workflow

1. Créer une branche (`feat/…`, `fix/…`).
2. `xcrun swift test -c release` doit passer (58 tests).
3. Commits atomiques (un commit = une idée), message conforme ci-dessus.
4. Ouvrir une pull request en décrivant le « pourquoi » et l'impact sur la parité.

## Signaler un problème de parité

Si un cas diverge de l'original, préciser dans l'issue :

- l'image et les options utilisées ;
- l'angle / les statistiques / l'écart pixel observés ;
- si possible, la sortie du binaire Pascal (`-g d -s sp`) pour comparaison.
