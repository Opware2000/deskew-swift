# Deskew Swift

Réimplémentation en **Swift** de [**Deskew**](https://github.com/galfar/deskew), l'outil
en ligne de commande qui redresse automatiquement (deskew) les documents numérisés.

> **Projet original :** Deskew, par Marek Mauder — <https://github.com/galfar/deskew>
> (licence MPL 2.0). Ce dépôt en est un travail dérivé ; il conserve l'historique Git
> complet et l'attribution d'origine.

## Pourquoi une réimplémentation ?

Deskew est écrit en Object Pascal (Free Pascal / Delphi). Ce dépôt vise une version
native **Swift** pour :

- profiter de la compilation native **arm64** (Apple Silicon) ;
- optimiser les algorithmes (Accelerate / vDSP / vImage, SIMD) ;
- **paralléliser** les étapes coûteuses (transformée de Hough, rotation, seuillage) ;
- s'appuyer sur les frameworks macOS natifs (ImageIO / Core Graphics) pour les
  entrées-sorties d'images.

L'objectif est de **reproduire fidèlement les algorithmes** du projet original
(parité des résultats) tout en modernisant la base technique.

## État du projet

| Étape | État |
| ----- | ---- |
| Analyse du code Pascal et documentation de réimplémentation | ✅ |
| Oracle v1.33 compilé + golden files de parité | ✅ |
| Squelette du package Swift | ✅ |
| Algorithmes (Otsu, binarisation, rotation, Hough) | ✅ |
| Entrées-sorties ImageIO | ✅ |
| Pipeline et exécutable CLI | ✅ |
| Multithreading et optimisation | ✅ |
| Packaging et release (`v0.1.0`) | ✅ |

Suivi détaillé des tâches restantes : [`TODO.md`](TODO.md).
Journal des versions : [`CHANGELOG.md`](CHANGELOG.md).

## Organisation du dépôt

| Chemin | Contenu |
| ------ | ------- |
| `Documentation/` | **Documentation de réimplémentation** (algorithmes, CLI, cible Swift, tests) |
| `Tests/DeskewParityTests/` | Golden files (références) produits par le binaire Pascal |
| `RotationDetector.pas` | Code Pascal d'origine : détection d'inclinaison (Hough) |
| `ImageUtils.pas` | Code Pascal d'origine : Otsu, binarisation, rotation |
| `CmdLineOptions.pas`, `MainUnit.pas`, `Utils.pas` | Code Pascal d'origine : CLI et orchestration |
| `Imaging/` | Bibliothèque tierce Vampyre Imaging (code du projet original) |
| `TestImages/` | Images de test |
| `Scripts/compile_local.sh` | Compile l'oracle Pascal (v1.33) en local |

La documentation de démarrage se trouve dans
[`Documentation/README.md`](Documentation/README.md).

## Golden files (tests de parité)

Les fichiers de référence sont générés depuis le binaire Pascal d'origine puis servent
d'oracle aux futurs tests Swift :

```bash
# Prérequis : Free Pascal (brew install fpc), et libtiff pour le support TIFF
brew install fpc

Scripts/compile_local.sh                                   # → Bin/deskew (oracle)
Tests/DeskewParityTests/generate_reference.sh              # → Tests/DeskewParityTests/reference/
```

Détails : [`Tests/DeskewParityTests/README.md`](Tests/DeskewParityTests/README.md).

## Compilation et utilisation (Swift)

Prérequis : macOS avec **Swift ≥ 5.9** (Xcode 15+). Si la commande `swift` du PATH
est plus ancienne, utiliser `xcrun swift` ou `Scripts/build_swift_release.sh`.

### Installation (binaire, sans compilation)

```bash
# Téléchargement direct (binaire universel arm64 + x86_64)
curl -L -o deskew https://github.com/Opware2000/deskew-swift/releases/download/v0.4.0/deskew-macos-universal
chmod +x deskew && sudo mv deskew /usr/local/bin/

# Homebrew (tap)
brew install Opware2000/tap/deskew-swift
```

### Compilation depuis les sources

```bash
# Optionnel : contrôle exact de la compression TIFF (LZW, RLE, Deflate, JPEG, G4)
brew install libtiff

# Compiler l'exécutable (release, binaire universel arm64 + x86_64)
Scripts/build_swift_release.sh
# ou : xcrun swift build -c release

# Lancer les tests de parité (release, quelques secondes)
xcrun swift test -c release
# Inclure le cas de stress (rotation cubic sur une grande image, lent en debug)
PARITY_HEAVY=1 xcrun swift test -c release

# Sanitizers (data races + mémoire)
Scripts/sanitizers.sh

# Utilisation
./.build/release/deskew -o sortie.png entree.png
./.build/release/deskew -q lanczos -a 10 -o sortie.png entree.png
./.build/release/deskew -g d -s sp entree.png     # détection seule + stats
./.build/release/deskew --version                 # version du port Swift
```

Options identiques à l'original (`-o -a -b -q -d -t -m -r -f -p -l -g -s -c`).
La sortie console (bannière, messages, statistiques, noms de format) reproduit
celle de Deskew 1.33 : l'outil est utilisable en **remplacement direct**.

`--version` (ou `-V`) est une **extension** propre au port Swift : elle affiche
`deskew-swift <version> — portage Swift de Deskew 1.33` et n'affecte pas la sortie
par défaut.

> Les tests en mode debug sont lents (traitement d'images sans optimisation) :
> privilégier `swift test -c release`.

## Signaler un problème

Ouvrir une issue : <https://github.com/Opware2000/deskew-swift/issues>.
Indiquer la commande, l'image (ou un extrait) et la sortie observée.

## Utilisation de l'original (rappel)

```console
Usage:
deskew [-o output] [-a angle] [-b color] [..] input
    input:         Input image file
  Options:
    -o output:     Output image file name (default: prefixed input as png)
    -b color:      Background color in hex format RRGGBB|LL|AARRGGBB (default: black)
    -q filter:     Resampling filter used for rotations (default: linear,
                   values: nearest|linear|cubic|lanczos)
    -a angle:      Maximal expected skew angle (both directions) in degrees (default: 10)
    -t a|treshold: Auto threshold or value in 0..255 (default: auto)
    -g flags:      Operational flags (any combination of):
                   c - crop to input size, d - detect only (no output to file)
    ...
```

Voir le [Readme du projet original](Readme-original.md) pour la documentation complète
du programme d'origine.

## Contribuer

Les conventions (code, commits, tests, golden files) sont décrites dans
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Licence

Ce projet est distribué sous **Mozilla Public License 2.0** (MPL 2.0), comme le projet
original. Voir [`LICENSE`](LICENSE).

Le code Pascal présent dans ce dépôt provient de
[galfar/deskew](https://github.com/galfar/deskew) et reste soumis à sa licence et à son
attribution :

- **Auteur original :** Marek Mauder
- **Site :** <https://galfar.vevb.net/deskew>
- **Code source :** <https://github.com/galfar/deskew>
