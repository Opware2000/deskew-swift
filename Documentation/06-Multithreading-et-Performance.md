# 06 — Multithreading et performance

Ce document décrit où et comment paralléliser, et quelles optimisations spécifiques
arm64/Accelerate sont pertinentes. L'objectif est de garder la **parité** tout en
exploitant les cœurs.

## 1. Vue d'ensemble du coût

| Étape | Complexité dominante | Nature | Parallélisable |
| ----- | -------------------- | ------ | -------------- |
| Chargement + conversion Gray8 | `O(W·H)` | mémoire / Core Graphics | partiellement |
| Otsu (histogramme) | `O(W·H)` + `O(256²)` | mémoire + petit | oui (histogramme) |
| Binarisation | `O(W·H)` | mémoire | oui (trivial) |
| Préparation pixels testés (Hough) | `O(W·H)` | accès mémoire | oui |
| Accumulation Hough | `O(N_testés · AlphaSteps)` | calcul intensif | oui (par angle) |
| Sélection 20 meilleures lignes | `O(AccumulatorSize)` | mémoire | non (négligeable) |
| Rotation (nearest/linear) | `O(W·H)` | mémoire | oui (lignes) |
| Rotation (cubic/lanczos) | `O(W·H·k²)` | calcul intensif | oui (lignes) |
| Écriture fichier | I/O | disque | non |

Les deux postes vraiment lourds sont **l'accumulation Hough** et la **rotation avec
filtre cubic/lanczos**.

## 2. Accumulation Hough (parallélisation sans contention)

### 2.1 Constat clé

Dans `CalcLines`, l'indice d'écriture est `Index = DIndex * AlphaSteps + I`. Pour un
`I` (pas angulaire) donné, on écrit toujours dans la **colonne `I`** de l'accumulateur.
Deux `I` distincts ne se recouvrent **jamais**.

### 2.2 Stratégie recommandée : partition par plage d'angles

```text
1. Pré-calculer  Sin[0..AlphaSteps-1], Cos[0..AlphaSteps-1]   (une fois)
   → ce sont EXACTEMENT les mêmes valeurs que SinCos recalculés par pixel.
2. Collecter les pixels testés (noir, non noir en dessous) — parallèle par lignes.
3. Partitionner [0, AlphaSteps) en T plages contiguës (T = nombre de cœurs).
4. Chaque thread t :
     - alloue un tableau local de TAILLE PLEINE (ou n'écrit que sa plage) ;
     - itère sur tous les pixels testés ;
     - pour chaque pas I de sa plage, fait le vote.
5. Fusion : aucun chevauchement → pas de fusion nécessaire si chaque thread possède
   sa propre plage ; sinon additionner des accumulateurs partiels.
```

Variante mémoire : chaque thread possède un accumulateur **local complet** et itère sur
**une bande de pixels** (une seule lecture image, mais T accumulateurs complets).
Coût mémoire = `T · AccumulatorSize · 4` octets. Pour une image 10 000×10 000
(`AccumulatorSize ≈ 8e6`), cela fait `32 Mo · T` : à arbitrer.

> Recommandation : pour les images usuelles (≤ A3 600 dpi), l'accumulateur complet fait
> quelques dizaines de Mo ; la partition par angles évite toute duplication mémoire et
> toute synchronisation. La pré-génération de la liste de pixels testés évite de
> rescanner l'image T fois.

### 2.3 Optimisations arithmétiques

- **Pré-calcul de `Sin`/`Cos`** : l'original appelle `SinCos` pour chaque `(pixel,
  angle)`. Les valeurs ne dépendent que de `I`. Pré-calculer un tableau de `Float`/`Double`
  supprime des centaines de millions d'appels trigonométriques — gain majeur, résultat
  identique.
- `D = Y·Cos − X·Sin` : multiplications/accumulations simples, vectorisables par SIMD
  sur la plage d'angles.
- Éviter les divisions dans la boucle : `Index = DIndex·AlphaSteps + I` nécessite
  `DIndex = Trunc(D − MinDist)` (pas de division). Le décodage des 20 meilleures lignes
  (`div AlphaSteps`) est hors boucle chaude.

### 2.4 Garde-fou d'indice

Ajouter un clamp/vérification `0 ≤ DIndex < DistCount`. L'original ne le fait pas et
repose sur la petitesse de `MaxAngle`. Un débordement serait une écriture mémoire
silencieuse — inacceptable en Swift. Voir [02](02-Algorithmes.md) § 1.3.

## 3. Rotation (parallélisation par bandes de lignes)

Chaque pixel destination est indépendant : c'est un cas **embarrassingly parallel**.

```swift
let bandHeight = 64
let bandCount = (dstHeight + bandHeight - 1) / bandHeight
DispatchQueue.concurrentPerform(iterations: bandCount) { band in
    let y0 = band * bandHeight
    let y1 = min(y0 + bandHeight, dstHeight)
    for y in y0..<y1 {
        for x in 0..<dstWidth {
            // écriture dans la région [y] du buffer partagé, disjointes entre bandes
        }
    }
}
```

Écriture dans des régions **disjointes** → pas de verrou. Alternatives modernes :
`TaskGroup` (concurrence structurée) ou un simple `Task.detached` par bande avec
`await` du groupe. `concurrentPerform` reste le plus simple et le plus prévisible pour
du calcul pur.

### 3.1 Cache et localité

- Traiter **des bandes**, pas des lignes isolées, pour réutiliser les lignes source
  voisines dans la fenêtre du noyau (cubic/lanczos lisent `±3` lignes).
- Ordre de parcours : `y` externe, `x` interne (comme l'original), ce qui maximise la
  localité en écriture destination.
- Pour lanczos/cubic, la lecture source fait `k²` accès par pixel ; un **bloc source**
  (tuilage) réduit les défauts de cache si les images sont grandes.

### 3.2 Table de poids

`PrecomputeFilterWeights` doit être appelé **une fois** avant les bandes, puis la table
est partagée en lecture seule (`let` / `withUnsafePointer`). Elle ne dépend que du
filtre et de `KernelWidth`.

### 3.3 SIMD / Accelerate

- **Filtres par canaux** : accumuler les 4 canaux (R,G,B,A) dans un `SIMD4<Float>` par
  échantillon, ou accumuler 4 pixels de sortie en parallèle (les coordonnées source
  évoluent linéairement avec `x`). C'est le plus gros levier pour cubic/lanczos.
- **Nearest / linear** : les coordonnées source par pas de `x` sont affines ; on peut
  calculer `SrcX` de manière incrémentale (une addition par pixel au lieu de deux
  `SinCos`) — l'original le fait déjà implicitement via `CalcSourceCoordinates` avec
  `BackwardCos/Sin` constants, mais recalcule les deux produits :
  `SrcX += BackwardCos` et `SrcY += BackwardSin` à chaque `x` est possible et
  **numériquement proche** (attention : la somme flottante peut dériver ; à valider par
  test de parité ou à recalculer périodiquement).
- **vDSP** : peu utile pour la convolution à noyau spatial arbitraire ; utile pour les
  conversions de format (normalisation, mise à l'échelle des canaux) et l'histogramme.
- **vImage** : `vImageRotate_ARGB8888` gère nearest/linear avec fond, mais **pas**
  cubic/lanczos, et son mapping peut différer de 1 pixel. Utilisable comme accélération
  optionnelle **seulement** si la parité est vérifiée ; sinon garder le code maison.

## 4. Otsu

- **Histogramme parallèle** : découper le rectangle en bandes, histogramme local
  (`[Int32]` de 256) par bande, puis fusion. Pour rester bit-identique :
  l'original accumule en `Float` ; des compteurs entiers convertis en `Float` donnent
  des valeurs identiques tant que `< 2^24` pixels (largement le cas).
- La recherche du seuil (`O(256²)`) se fait en séquentiel, coût négligeable.
- Alternative system : `vImageHistogramCalculation_Planar8` (vérifier que l'échelle
  correspond). L'optimisation par sommes cumulées change les arrondis `Float` :
  à ne faire que si les tests de parité la valident.

## 5. Binarisation et conversions de format

- Boucles simples `O(W·H)` : parallélisables par bandes, **ou** laissées séquentielles
  (souvent négligeables devant Hough/rotation). Éviter de sur-paralléliser les petites
  images (overhead de dispatch).
- Utiliser `vDSP_vthres`/`vDSP_vclip` ou `Accelerate` pour le seuillage si validation
  par tests.
- Conversions Core Graphics → buffers : une passe, non parallélisée.

## 6. Seuils et granularité

- **Ne pas paralléliser** les petites images (< quelques centaines de milliers de
  pixels) : le coût de dispatch dépasse le gain.
- Définir un seuil : p. ex. rotation parallèle seulement si `W·H > 500 000`.
- Granularité des bandes : ~32–128 lignes selon la largeur, pour équilibrer la charge.
- Nombre de workers : `ProcessInfo.processInfo.activeProcessorCount` (borne par le
  nombre de cœurs disponibles, cohérent avec les Mac Apple Silicon P/E cores).

## 7. Benchmarks

Comparaison `Scripts/benchmark.sh` (meilleur de 5 essais, Apple Silicon arm64,
build release) :

| Cas | Pascal v1.33 (s) | Swift (s) | Gain |
| --- | --- | --- | --- |
| Détection 1big.png (4152×6172) | 1,135 | 0,195 | **5,8×** |
| Rotation cubic 1big.png | 3,600 | 1,183 | **3,0×** |
| Rotation lanczos 5.png | 0,209 | 0,116 | **1,8×** |
| Rotation linear 3.png | 0,475 | 0,156 | **3,0×** |
| Détection F1550.jpg | 0,412 | 0,083 | **5,0×** |

Le gain provient du multithreading (Hough, rotation, histogramme Otsu), de la
vectorisation des canaux (SIMD) sur cubic/lanczos et de la compilation native
Swift. La détection inclut le décodage ImageIO, la conversion en niveaux de gris
et Otsu.

Reproduire :

```bash
Scripts/compile_local.sh        # oracle Pascal (une fois)
Scripts/benchmark.sh 5          # tableau ci-dessus
```


## 8. Pièges spécifiques arm64

- **Pas de `Extended` 80 bits** : utiliser `Double` ; la trigonométrie différera
  légèrement de l'original x86 (tolérance à définir dans les tests).
- **Dénormalisés** : les `Float` proches de zéro peuvent être plus lents ; normaliser ou
  utiliser `Float` est en général suffisant avec Accelerate.
- **Alignement** : allouer les buffers alignés (`UnsafeMutableRawPointer.allocate`
  aligné 64 octets) pour profiter de NEON.
- **`-Ounchecked`** : à éviter en production (masque les débordements, change la
  sémantique). Préférer `-O` + `withUnsafe…` + `@inlinable` sur les noyaux.
- **Bounds checking** : à chaud, utiliser `UnsafeMutableBufferPointer` pour le
  supprimer sans désactiver la sécurité globale.

## 9. Résumé des décisions

| Étape | Décision |
| ----- | -------- |
| Hough accumulation | Pré-calcul `Sin/Cos` ; partition **par plage d'angles** ; liste de pixels testés pré-générée ; garde-fou d'indice |
| Rotation | `concurrentPerform` par **bandes de lignes** ; table de poids partagée ; SIMD `SIMD4<Float>` sur cubic/lanczos |
| Otsu | Histogramme par bandes + fusion entière ; recherche du seuil séquentielle |
| Binarisation / conversions | Séquentiel par défaut, parallèle seulement si image grande |
| Petites images | Tout séquentiel (seuil de taille) |
