# Tests de parité — golden files

Ce dossier contient les **fichiers de référence** produits par l'implémentation
Pascal d'origine. Ils servent d'« oracle » aux tests de la réimplémentation Swift :
celle-ci doit produire les mêmes angles, statistiques et images (à tolérance près,
voir `Documentation/07-Parite-et-Tests.md`).

## Contenu

```text
Tests/DeskewParityTests/
├── generate_reference.sh      # (re)génère reference/ depuis le binaire Pascal
├── README.md                  # ce fichier
└── reference/
    ├── summary.txt            # nom du cas, code de sortie, angle détecté
    ├── index.tsv              # nom<TAB>extension<TAB>arguments
    └── <cas>/
        ├── cmd.txt            # arguments exacts passés au binaire
        ├── exit_code.txt      # code de sortie attendu
        ├── stdout.txt         # sortie console (chemins absolus → <ROOT>)
        ├── out.png|jpg|tif    # image de sortie (si le cas en produit une)
        └── work-image.png     # image binarisée (cas `work-*` avec `-s w`)
```

Les cas `detect-*` sont en mode `-g d` (détection seule) : ils ne produisent pas
d'image, seulement l'angle et les statistiques de détection.

## Régénérer les références

```bash
# 1. Compiler le binaire Pascal (v1.33 du dépôt) — nécessite FPC
brew install fpc                 # si nécessaire
Scripts/compile_local.sh         # → Bin/deskew

# 2. Générer les golden files
Tests/DeskewParityTests/generate_reference.sh
```

Le script accepte un chemin de binaire en argument :
`Tests/DeskewParityTests/generate_reference.sh /chemin/vers/deskew`.

## Déterminisme

- Les **timings** (`-s t`) ne sont jamais utilisés : ils sont non déterministes.
  Le cas `rot-6-g8` de `Bin/runtests.sh` utilisait `-s t`, il a été remplacé par
  `-s sp` ici.
- Les chemins absolus de la sortie console sont remplacés par `<ROOT>` (racine du
  dépôt) pour rendre les références portables entre machines.
- Les nombres sont formatés en `en-US` par le code Pascal (séparateur de milliers
  `,`, décimale `.`), donc indépendants de la locale système.

### Déduplication des sorties

Après génération, les images de sortie **identiques** sont remplacées par des
**liens symboliques** vers la première occurrence (détection par SHA-256). Cela
réduit la taille du corpus (≈11 Mo → ≈9,2 Mo) sans perte de couverture : les tests
suivent les liens.

### Cas non reproductible (`rot-5-nearest-bg`)

Le filtre `nearest` de l'original **lit hors du buffer** au bord droit/bas
(comportement indéfini) : sa sortie change à chaque exécution (vérifié : 3 hashes
différents). L'image de référence n'est donc **pas conservée** pour ce cas ; seul
`stdout.txt` (angle, statistiques — déterministes) l'est. Les tests qui comparent
les images **ignorent les cas sans fichier `out.*`**.


## Support TIFF

Sous macOS, Deskew charge `libtiff.dylib` dynamiquement. Le script ajoute
automatiquement le préfixe Homebrew de `libtiff` à `DYLD_LIBRARY_PATH`. Sans
`libtiff`, les cas TIFF échouent (comme avec l'option `--no-tiff` de
`Bin/runtests.sh`).

## Angles de référence (résumé)

| Cas | Angle (°) |
| --- | --- |
| detect-1big / detect-1-g4 / detect-1-lzw | -1.375 |
| detect-2 | -2.185 |
| detect-3 | -6.250 |
| detect-4 | 7.095 |
| detect-5 | 3.410 |
| detect-6 | -2.810 |
| detect-F1550 | -1.210 |
| detect-tiff-jpeg | 3.395 |
| detect-4-rect / -explicit | 7.075 |
| detect-5-explicit | 3.400 |

Voir `reference/summary.txt` pour la liste complète.
