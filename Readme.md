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
| Squelette du package Swift | ⬜ à faire |
| Algorithmes (Otsu, binarisation, rotation, Hough) | ⬜ à faire |
| Entrées-sorties ImageIO | ⬜ à faire |
| Multithreading et optimisation | ⬜ à faire |

Suivi détaillé des tâches restantes : [`TODO.md`](TODO.md).

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

## Licence

Ce projet est distribué sous **Mozilla Public License 2.0** (MPL 2.0), comme le projet
original. Voir [`LICENSE`](LICENSE).

Le code Pascal présent dans ce dépôt provient de
[galfar/deskew](https://github.com/galfar/deskew) et reste soumis à sa licence et à son
attribution :

- **Auteur original :** Marek Mauder
- **Site :** <https://galfar.vevb.net/deskew>
- **Code source :** <https://github.com/galfar/deskew>
