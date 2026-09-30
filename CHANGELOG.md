# Journal des versions

Toutes les évolutions notables de **deskew-swift**, la réimplémentation en Swift de
[Deskew](https://github.com/galfar/deskew).

> Les entrées sont écrites du point de vue de l'utilisateur. Les changements purement
> internes (tests, outillage, documentation) sont regroupés sous « Améliorations
> internes ».

---

## v0.3.1 — 30 septembre 2026

Release d'hygiène. **Le binaire est identique à la v0.3.0** (même empreinte), aucune
modification de comportement.

### Améliorations internes

- **Corpus de référence allégé** : les images de test identiques sont stockées une
  seule fois (11 Mo → 9,2 Mo) ; un cas dont la sortie d'origine n'est pas
  reproductible a été retiré.
- **Tests plus rapides en développement** : les vérifications les plus lourdes
  (traitement d'une très grande image, lancement du binaire) ne s'exécutent plus par
  défaut en mode debug ; la couverture complète reste assurée en release et en
  intégration continue.
- **Audit des skills d'assistant** tierces : aucun contenu problématique.

---

## v0.3.0 — 30 septembre 2026

### ✨ Nouvelles fonctionnalités

- **Contrôle exact de la compression TIFF** : vous pouvez désormais choisir
  précisément le schéma de compression de vos sorties TIFF avec `-c` —
  `tlzw` (LZW), `trle` (RLE/PackBits), `tdeflate` (Deflate), `tjpeg` (JPEG),
  `tg4` (CCITT G4) et `tinput` (reprendre la compression du fichier d'entrée).
  Les fichiers produits sont **strictement conformes** à ceux de l'outil d'origine.

### 🔧 Améliorations

- **Compression par défaut alignée sur l'original** : image 1 bit → G4, sinon LZW.
- La prise en charge TIFF utilise la bibliothèque **libtiff**, chargée
  automatiquement si elle est présente (par exemple via `brew install libtiff`).
  Si elle est absente, l'outil continue de fonctionner normalement.

---

## v0.2.0 — 30 septembre 2026

### 🐛 Corrections

- **Sortie binaire réellement en 1 bit** : les options `-f b1` et `-c tg4`
  produisent maintenant de **vraies images noir et blanc 1 bit**, et non plus des
  images 8 bits. Le TIFF de sortie est compressé en **CCITT G4**. Résultat concret :
  sur un document scanné, un fichier de **2,35 Mo devient 24 Ko** (≈ 98× plus petit).
  Les PNG binaires sont eux aussi deux fois plus légers.
- Correction de l'inversion des canaux rouge/bleu sur les sorties avec transparence
  (`-f rgba32`).
- L'option `-c tinput` reprend correctement la compression du fichier d'entrée.

### 🔒 Sécurité

- **Plus de plantage sur des paramètres malformés** : `-a inf`, `-r nan`,
  `-m inf` (et valeurs hors limites) sont désormais **rejetés proprement** au lieu de
  faire planter le programme.
- Bornes de sécurité sur les ressources (taille d'image, mémoire de détection) pour
  éviter les épuisements mémoire.
- Ajout de **fuzzers** (arguments, images, exécution complète) et de **sanitizers**
  (détection de courses de données et de débordements mémoire) exécutés en
  intégration continue.

---

## v0.1.0 — 30 septembre 2026

Première version fonctionnelle.

### ✨ Nouvelles fonctionnalités

- **Détection d'inclinaison** (transformée de Hough) avec statistiques détaillées.
- **Seuillage automatique** (méthode d'Otsu) ou seuil explicite.
- **Redressement** avec quatre filtres de rééchantillonnage : `nearest`, `linear`,
  `cubic` (Catmull-Rom) et `lanczos`.
- **Zone de détection** au choix : page entière, rectangle (`-r`) ou marges (`-m`),
  en pixels, pourcentages, millimètres, centimètres ou pouces.
- **Formats d'images** en entrée et sortie via le système : PNG, JPEG, TIFF, GIF, BMP
  (lecture PSD).
- **Options identiques à l'outil d'origine** (`-o -a -b -q -d -t -m -r -f -p -l -g -s -c`),
  y compris `-g d` (détection seule) et `-s w` (enregistrer l'image de travail).

### 🔧 Améliorations

- **Parité complète** avec Deskew 1.33 : angles détectés, statistiques et **sortie
  console identiques** — utilisable en remplacement direct.
- **Performance** : de 1,8× à 5,8× plus rapide que l'original selon les cas
  (détection, rotation, seuillage parallélisés).
- **Binaire universel** macOS (Apple Silicon **arm64** + Intel **x86_64**).

### 🔒 Sécurité

- Entrées non fiables validées aux frontières ; aucune dépendance tierce obligatoire.

---

## Notes

- **Licence** : MPL 2.0, dérivé de [galfar/deskew](https://github.com/galfar/deskew)
  (auteur original : Marek Mauder).
- **Formats non pris en charge** (par rapport à l'original) : DDS, TGA, PBM/PGM/PPM/
  PAM/PFM, JNG, QOI, écriture PSD.
