# Deskew — Documentation de réimplémentation en Swift

Ce dossier contient la documentation complète nécessaire pour réimplémenter **Deskew**
(en Pascal / Object Pascal, v1.33) en **Swift** sur macOS ARM.

L'objectif n'est pas de traduire ligne à ligne, mais de **reproduire fidèlement les
algorithmes** (parité des résultats) tout en profitant de :

- la compilation native **arm64** (Apple Silicon),
- l'optimisation (Accelerate / vDSP / vImage, SIMD, layout mémoire),
- le **multithreading** aux endroits qui s'y prêtent,
- l'écosystème macOS natif (ImageIO / Core Graphics) pour les entrées-sorties d'images.

## Périmètre

| Inclus dans la réimplémentation | Exclu (hors périmètre v1) |
| ------------------------------- | ------------------------- |
| Détection d'inclinaison (transformée de Hough) | Interface graphique (`Gui/`) |
| Seuillage automatique (Otsu) et binarisation | Bibliothèque Vampyre Imaging (`Imaging/`) réécrite telle quelle |
| Rotation d'image + rééchantillonnage (nearest/linear/cubic/lanczos) | Codecs tiers embarqués (ZLib, JPEG, LibTIFF, JNG, QOI…) |
| Analyse de la ligne de commande | Formats propriétaires exotiques (DDS, TGA, PPM, PGM, PAM, PFM, JNG, PSD) |
| Gestion de la zone de détection (marges / rectangle + unités) | — |
| Métadonnées de résolution (DPI) et compression TIFF/JPEG | — |

## Index des documents

| Fichier | Contenu |
| ------- | ------- |
| [01-Architecture-et-Modules.md](01-Architecture-et-Modules.md) | Vue d'ensemble, flux d'exécution, cartographie Pascal → Swift |
| [02-Algorithmes.md](02-Algorithmes.md) | Spécification détaillée et pseudo-code de tous les algorithmes |
| [03-Specification-CLI.md](03-Specification-CLI.md) | Contrat complet de l'interface en ligne de commande |
| [04-Entrees-Sorties-Images.md](04-Entrees-Sorties-Images.md) | Formats d'images, conversions, métadonnées, mapping ImageIO |
| [05-Architecture-Swift-Cible.md](05-Architecture-Swift-Cible.md) | Structure du package Swift, types, API, dépendances |
| [06-Multithreading-et-Performance.md](06-Multithreading-et-Performance.md) | Parallélisation, Accelerate, SIMD, cache, repères de performance |
| [07-Parite-et-Tests.md](07-Parite-et-Tests.md) | Risques de parité numérique, golden tests, plan de tests |
| [08-Matrice-de-Tracabilite.md](08-Matrice-de-Tracabilite.md) | Table exhaustive fonction/procédure Pascal → symbole Swift |
| [09-Plan-Implementation.md](09-Plan-Implementation.md) | Découpage en phases, ordre de travail, critères de sortie |
| [11-Securite.md](11-Securite.md) | Analyse de sécurité : constats, correctifs, tests de non-régression |

## Sources de vérité (code analysé)

Le code original se trouve à la racine du dépôt. Les fichiers réellement concernés par
la réimplémentation sont :

| Fichier Pascal | Rôle |
| -------------- | ---- |
| `RotationDetector.pas` | Détection d'inclinaison (Hough) |
| `ImageUtils.pas` | Otsu, binarisation, rotation + filtres |
| `Utils.pas` | Géométrie de rectangles et conversion d'unités |
| `CmdLineOptions.pas` | Analyse des arguments et calcul de la zone de détection |
| `MainUnit.pas` | Orchestration (pipeline `RunDeskew` / `DoDeskew`) |
| `Tests/` | Comportements de référence à porter |
| `Bin/runtests.sh` | Scénarios d'intégration CLI de référence |

## Remarques importantes

- **Précision numérique** : le code Pascal utilise `Single` (= `Float`) pour les filtres
  et Otsu, et `Extended` (80 bits sur x86) pour la trigonométrie de Hough. La parité
  exacte des bits n'est pas garantie ; voir [07-Parite-et-Tests.md](07-Parite-et-Tests.md).
- **Licence** : Deskew est sous **MPL 2.0**. Toute réutilisation/distribution du code
  dérivé doit conserver la licence MPL 2.0 (fichiers modifiés restant sous MPL).
- **Auteur original** : Marek Mauder — <https://github.com/galfar/deskew>.

## Lecture recommandée

1. Comprendre le flux global : [01-Architecture-et-Modules.md](01-Architecture-et-Modules.md).
2. Lire la spécification des algorithmes : [02-Algorithmes.md](02-Algorithmes.md).
3. Définir l'API et le package Swift : [05-Architecture-Swift-Cible.md](05-Architecture-Swift-Cible.md).
4. Implémenter par phases : [09-Plan-Implementation.md](09-Plan-Implementation.md).
