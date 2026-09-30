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
| Détection 1big.png (4152×6172) | 0,957 | 0,190 | **5,0×** |
| Rotation cubic 1big.png | 3,012 | 0,818 | **3,7×** |
| Rotation lanczos 5.png | 0,193 | 0,086 | **2,2×** |
| Rotation linear 3.png | 0,430 | 0,134 | **3,2×** |
| Détection F1550.jpg | 0,383 | 0,075 | **5,1×** |

Détail par phase (`-s t`, 2.png) : Hough **14,7 ms vs 259 ms** (17×),
rotation **6,0 ms vs 57 ms** (9×).

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

> Le **détail de chaque optimisation** (principe, efficacité, impact mesuré,
> limites et optimisation rejetée) est en [§10](#10-journal-des-optimisations).

---

## 10. Journal des optimisations

Chaque optimisation est décrite avec son principe, **pourquoi elle est efficace**
(raisonnement algorithmique ou matériel) et son impact mesuré. Démarche suivie :
**mesurer d'abord** (instrumentation `-s t`), optimiser le poste dominant, puis
**re-vérifier la parité** (59 tests) et re-benchmarker.

### 10.1 Multithreading de l'accumulation Hough (partition par angles)

- **Où** : `HoughSkewDetector.detect`.
- **Principe** : l'accumulateur est indexé `DIndex * AlphaSteps + I`. Pour un pas
  angulaire `I` donné, on écrit toujours dans la **colonne `I`**. On partitionne donc
  `[0, AlphaSteps)` entre threads : deux threads ne touchent jamais le même indice.
- **Pourquoi c'est efficace** : c'est un cas de parallélisme **sans contention** —
  aucune synchronisation, aucun verrou, aucune fusion. On transforme une boucle
  `O(pixels_testés × AlphaSteps)` (le poste le plus lourd de la détection) en travail
  réparti sur tous les cœurs. Sur Apple Silicon, on exploite les cœurs P et E.
- **Impact** : Hough 259 ms → **14,7 ms** (≈17×) sur 2.png.
- **Limite** : chaque thread relit la liste des pixels testés (coût mémoire faible
  car la liste est compacte), et le résultat est **déterministe** (l'accumulateur ne
  dépend pas de l'ordre des écritures ; la somme des compteurs entiers est
  associative).

### 10.2 Pré-calcul des `sin`/`cos` (Hough)

- **Où** : `HoughSkewDetector.detect`.
- **Principe** : `sin(α)` et `cos(α)` ne dépendent que du pas `I`, pas du pixel. On
  les calcule une fois dans deux tableaux de taille `AlphaSteps`.
- **Pourquoi c'est efficace** : l'original appelle `SinCos` **pour chaque couple
  (pixel, angle)** — des centaines de millions d'appels trigonométriques. Les
  remplacer par deux lectures de tableau supprime tout le coût trigonométrique.
  Les valeurs sont **identiques** (même angle → même résultat), donc la parité est
  conservée.
- **Impact** : combiné à 10.1, contribue au 17× sur la détection.

### 10.3 Pré-collecte des pixels testés (Hough)

- **Où** : `HoughSkewDetector.detect`.
- **Principe** : on effectue **une seule** passe sur l'image pour construire la liste
  des pixels « ligne de base » (noir avec pixel du dessous non noir), stockée dans
  deux tableaux `Int32` `x`/`y`.
- **Pourquoi c'est efficace** : les threads d'accumulation itèrent ensuite sur cette
  liste compacte au lieu de rescanner l'image entière. On évite de relire `W×H`
  pixels `T` fois (T = nombre de cœurs) : le balayage image, coûteux en bande
  passante mémoire, est fait **une fois**.
- **Limite** : mémoire `2 × 4 octets × pixels_testés` (quelques Mo au plus).

### 10.4 Garde-fou d'indice (Hough)

- **Où** : `HoughSkewDetector.detect`.
- **Principe** : `0 ≤ index < AccumulatorSize` avant écriture.
- **Pourquoi** : ce n'est pas une optimisation de vitesse mais de **robustesse**.
  L'original suppose implicitement que `DIndex` reste dans les bornes (vrai pour de
  petits `MaxAngle`) ; sinon il écrit hors du tableau (comportement indéfini). En
  Swift, un débordement serait une écriture mémoire silencieuse.

### 10.5 Rotation parallèle par bandes de lignes

- **Où** : `ImageRotation.renderParallel`.
- **Principe** : chaque pixel de destination est indépendant ; on découpe la hauteur
  en bandes, chaque thread écrivant dans une **région disjointe** du tampon.
- **Pourquoi c'est efficace** : problème *embarrassingly parallel* — accès source en
  lecture seule, écritures sans recouvrement → aucun verrou. La rotation
  (surtout cubic/lanczos, `O(W·H·k²)`) est le poste le plus lourd après la
  sauvegarde.
- **Impact** : rotation 57 ms → **6,0 ms** (≈9×) sur 2.png ; `cubic 1big`
  1,18 s → **0,82 s**.
- **Limite** : bandes assez hautes pour réutiliser les lignes source voisines dans la
  fenêtre du noyau (`±k`), et seuil de taille pour ne pas pénaliser les petites
  images (10.9).

### 10.6 Table de poids partagée (cubic/lanczos)

- **Où** : `KernelTable`, `ImageRotation`.
- **Principe** : la table de poids (noyau quantifié sur 32 pas) est construite **une
  fois** avant les bandes, puis lue en lecture seule par tous les threads.
- **Pourquoi c'est efficace** : sans cela, chaque pixel recalculerait `k²` évaluations
  de noyau (sinus, polynômes). La table remplace ce calcul par une simple lecture.
  Partagée en lecture seule → sûre et sans duplication mémoire.

### 10.7 SIMD sur les canaux (cubic/lanczos)

- **Où** : `Sampler.pixelVector`, `ImageRotation.filterPixel`.
- **Principe** : accumuler `(B, G, R, A)` dans un `SIMD4<Float>` au lieu de quatre
  scalaires `Float`.
- **Pourquoi c'est efficace** : ARM64 dispose de registres SIMD (NEON) ; une
  multiplication-accumulation vectorielle traite les 4 canaux en une instruction au
  lieu de quatre. Le noyau étant appliqué `k²` fois par pixel, le gain est multiplié
  par le nombre de taps.
- **Limite** : l'ordre d'accumulation reste identique au scalaire → résultats
  bit-identiques (parité préservée).

### 10.8 Allocation non initialisée des destinations de rotation

- **Où** : `GrayImage/RGBImage/RGBAImage.init(uninitializedWidth:height:)`,
  utilisés dans `ImageRotation` et `PixelImage.toGray`.
- **Principe** : `[UInt8](repeating: 0, count: n)` **met à zéro** tout le tampon ; or
  la boucle de rendu écrit **ensuite chaque pixel**. On alloue donc sans
  initialisation (`Array(unsafeUninitializedCapacity:)`).
- **Pourquoi c'est efficace** : on supprime une écriture mémoire complète inutile.
  Pour une destination `4300×6271` en gris (≈27 Mo) ou RGBA (≈108 Mo), c'est un
  passage mémoire évité.
- **Impact** : contribue au passage de `cubic 1big` à 0,82 s.
- **Condition de sûreté** : le tampon doit être **intégralement écrit** avant
  lecture — vrai pour la boucle de rendu (toutes les bandes couvrent toute l'image).

### 10.9 Seuil de taille (éviter le surcoût de dispatch)

- **Où** : `ImageRotation.parallelThreshold`, `Otsu.computeHistogram`,
  `HoughSkewDetector` (nombre de threads borné).
- **Principe** : en dessous d'un seuil (≈100–200 k pixels), rester séquentiel.
- **Pourquoi c'est efficace** : `DispatchQueue.concurrentPerform` a un coût fixe
  (réveil de threads, répartition). Sur une petite image, ce coût dépasse le travail
  économisé → le parallélisme *ralentit*. Le seuil garantit qu'on ne parallélise que
  quand le gain marginal est positif.

### 10.10 Histogramme Otsu par bandes + fusion déterministe

- **Où** : `Otsu.computeHistogram`.
- **Principe** : chaque bande de lignes calcule un histogramme local (`256` `Float`) ;
  on fusionne dans l'ordre des bandes. La recherche du seuil reste séquentielle
  (`O(256²)` négligeable).
- **Pourquoi c'est efficace** : l'histogramme est `O(W·H)` (lecture de chaque pixel) ;
  le répartir divise ce balayage par le nombre de cœurs. La fusion est
  **déterministe** car les compteurs sont des entiers stockés en `Float` (exacts
  < 2²⁴) : la somme ne dépend pas de l'ordre → résultat identique au séquentiel.
- **Impact** : Auto thresholding 13,5 ms → **1,2 ms** sur 2.png.

### 10.11 Conversion en niveaux de gris sur tampons plats

- **Où** : `PixelImage.toGray`.
- **Principe** : itérer sur `withUnsafeBufferPointer`/`withUnsafeMutableBufferPointer`
  au lieu de `image[x, y]`.
- **Pourquoi c'est efficace** : le subscript Swift effectue un **contrôle de bornes**
  et un calcul d'indice par accès ; en boucle chaude sur des millions de pixels, ce
  surcoût est réel. Les pointeurs plats suppriment le contrôle de bornes **sans**
  désactiver la sécurité globale du programme.

### 10.12 Build release et inlining

- **Où** : `Scripts/build_swift_release.sh`, `Package.swift`.
- **Principe** : compilation `-c release` (optimisations + *whole-module
  optimization*), `@inline(__always)` sur les accesseurs chauds
  (`Sampler.pixel`, `pixelVector`, `KernelTable.weight`, `sourceCoordinates`).
- **Pourquoi c'est efficace** : l'inlining supprime l'appel de fonction par pixel et
  permet au compilateur de propager les constantes et de vectoriser. En WMO, le
  compilateur voit tout le module et peut spécialiser les closures non échappantes.

### 10.13 Instrumentation `-s t` (mesurer avant d'optimiser)

- **Où** : `Stopwatch`, `Pipeline`, `DeskewCLI`.
- **Principe** : lignes de timing par phase (`Load`, `Auto thresholding`,
  `Skew detection`, `Rotate image`, `Save output file`), au format exact de
  l'original.
- **Pourquoi c'est efficace** : on ne devine pas le poste dominant — on le mesure.
  C'est ce qui a permis de cibler la rotation, puis de **rejeter** une optimisation
  (10.14). Accessoirement, `-s t` comble un écart de parité avec l'original.

### 10.14 Optimisation rejetée : tampons non initialisés dans `ImageLoader`

- **Principe tenté** : appliquer 10.8 aux tampons du loader.
- **Résultat** : **parité RGBA cassée** (écart max 191).
- **Cause** : `CGContext.draw` **composite** l'image sur le contenu existant du
  contexte ; avec un tampon non initialisé, les zones semi-transparentes mélangent
  l'image et des octets aléatoires. Le zéro est donc **requis** ici.
- **Leçon** : une optimisation mémoire n'est valide que si le tampon est réellement
  écrit en totalité. Mesurer, vérifier la parité, revenir en arrière si nécessaire —
  ne jamais optimiser à l'aveugle.

### 10.15 Pistes non retenues (à ce stade)

| Piste | Raison |
| --- | --- |
| Supprimer la closure `write` par pixel | gain incertain (WMO inline déjà la closure non échappante) |
| Spécialiser les noyaux par format (sortir le `switch`) | branche bien prédite ; gain à mesurer |
| Accélérer l'encodage PNG | contrôlé par ImageIO (zlib système), peu de leviers |
| `-Ounchecked` | rejeté : masque les débordements, change la sémantique |

