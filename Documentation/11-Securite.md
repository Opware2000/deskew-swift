# 11 — Sécurité

Analyse de sécurité de la réimplémentation Swift (démarche SAST + revue manuelle).

## 1. Résumé exécutif

Deskew est un **outil en ligne de commande local** : pas de réseau, pas
d'authentification, pas de base de données, pas de secrets. La surface d'attaque se
réduit à deux entrées non fiables :

1. **les arguments de la ligne de commande** (chaînes arbitraires) ;
2. **les fichiers images** décodés par ImageIO (données binaires arbitraires).

Le risque principal est le **déni de service local** (plantage ou épuisement
mémoire) sur une entrée malformée, pas l'exécution de code arbitraire.

**Bilan : 5 constats, tous corrigés.** Aucun secret, aucune dépendance tierce
(uniquement des frameworks système : ImageIO, CoreGraphics, Dispatch).

## 2. Tableau des constats

| ID | Sévérité | Titre | CWE | État |
| --- | --- | --- | --- | --- |
| FIND-001 | **Élevée** | Plantage sur angle max non fini / hors bornes | CWE-20, CWE-190 | ✅ corrigé |
| FIND-002 | **Élevée** | Plantage sur rectangle/marges non finis | CWE-20, CWE-704 | ✅ corrigé |
| FIND-003 | Moyenne | Accumulateur Hough non borné (mémoire) | CWE-770, CWE-400 | ✅ corrigé |
| FIND-004 | Faible | Déréférencements forcés (`!`) | CWE-617 | ✅ corrigé |
| FIND-005 | Faible | Dimensions d'image non bornées | CWE-770 | ✅ corrigé |

## 3. Constats détaillés

### FIND-001 — Plantage sur `-a` non fini / hors bornes (Élevée)

- **Fichier** : `DeskewOptions.parseOption` (`-a`) → `HoughSkewDetector.detect`.
- **Description** : `Double("inf")` est accepté ; `maxAngle = inf`. `isValid`
  n'imposait que `maxAngle > 0`, ce qui laisse passer `inf`. Ensuite
  `Int(ceil(2 * maxAngle / angleStep))` convertit `inf` (ou une valeur finie trop
  grande, ex. `1e15`) en `Int` → **trap** (SIGTRAP).
- **Impact** : un attaquant (ou un script) qui fournit `-a inf` **fait planter** le
  programme (déni de service local). Reproductible : `deskew -a inf in.png` → exit 133.
- **Correctif** : `parseFiniteDouble` rejette `nan`/`inf` ; `-a` est borné à
  `(0, 90]`. Défense en profondeur : `HoughSkewDetector.detect` **lève** une erreur
  sur paramètres non finis / `alphaSteps` hors bornes.
- **Divergence assumée** : l'original accepte `-a 100` (sans borne) ; on borne à 90°
  (un skew > 90° n'a pas de sens). Documenté.

### FIND-002 — Plantage sur `-r` / `-m` non finis (Élevée)

- **Fichier** : `DeskewOptions.parseFloatRect` → `FloatRect.scaled`.
- **Description** : `-r nan,0,10,10`, `-r inf,...`, `-r 1e300,...` (→ `Float` inf) et
  `-m inf`/`-m nan` passaient la validation (`isValid` ne vérifie pas les rectangles).
  `FloatRect.scaled` faisait `Int(x.rounded())` sur `nan`/`inf` → **trap**.
- **Impact** : déni de service local (exit 133) via `-r nan,0,10,10 in.png`.
- **Correctif** : `parseFloatRect` rejette les valeurs non finies (côté `Double` **et**
  `Float`, car `Float(1e300) == inf`) ; `FloatRect.scaled` est rendu **sûr** : produit
  non fini ou hors plage → renvoie `.zero` (échec propre) au lieu de planter.

### FIND-003 — Accumulateur Hough non borné (Moyenne)

- **Fichier** : `HoughSkewDetector.detect`.
- **Description** : `accumulatorSize = 2*(W+H) * alphaSteps`. Avec un grand angle
  (`-a 90`) et un petit pas (`-d 0.01`), sur une grande image, l'allocation peut
  dépasser la mémoire disponible → plantage/OOM.
- **Correctif** : arithmétique **sans débordement**
  (`multipliedReportingOverflow`) et borne `maxAccumulatorSize = 200 000 000` cases ;
  au-delà, `HoughError.detectionTooLarge` (message explicite) au lieu d'un crash.

### FIND-004 — Déréférencements forcés (Faible)

- **Fichiers** : `DeskewOptions.parse` (`inputFileName!`, `outputFileName!`),
  `main.swift` (`options.inputFileName!`).
- **Description** : sûrs aujourd'hui (post-`isValid`) mais fragiles — toute évolution
  de la logique peut les rendre atteignables.
- **Correctif** : remplacés par `guard let` / `?? ""`.

### FIND-005 — Dimensions d'image non bornées (Faible)

- **Fichier** : `ImageLoader.load`.
- **Description** : une image déclarant des dimensions démesurées pourrait entraîner
  un débordement de `width*height` ou une allocation massive.
- **Correctif** : `multipliedReportingOverflow` + bornes
  (`maxDimension = 100 000`, `maxPixels = 250 000 000`) → `ImageIOError.imageTooLarge`.

## 4. Points vérifiés sans problème

- **Secrets** : aucun identifiant, clé ou jeton dans le code ou la configuration.
- **Dépendances** : aucune tierce (uniquement frameworks système) → pas de risque de
  chaîne d'approvisionnement logicielle.
- **Injection SQL / XSS / CSRF** : sans objet (pas de base, pas de web).
- **Décodage d'images** : confié à ImageIO/CoreGraphics (frameworks Apple durcis) ;
  les erreurs de décodage sont gérées (exception, pas de crash).
- **Écritures de fichiers** : le chemin de sortie est fourni explicitement par
  l'utilisateur (pas de traversée de chemin à partir d'une donnée non fiable) ; le
  dossier est créé au besoin.
- **Bornes de tableaux** : l'accumulateur Hough a un garde-fou d'indice (cf.
  `Documentation/06` §10.4).

## 5. Recommandations prioritaires

1. **Maintenir la validation aux frontières** : tout nouvel argument numérique doit
   passer par `parseFiniteDouble` (+ bornes métier).
2. **Ne jamais convertir un `Double` non borné en `Int`** sans garde de plage.
3. **Garder les bornes de ressources** (`maxAccumulatorSize`, `maxPixels`,
   `maxDimension`) et les tester.
4. **Fuzzing** : mis en place (cf. §8) — parsing d'arguments, chargement et
   écriture d'images, exécution CLI bout-en-bout, plus un corpus de régression des
   vecteurs déjà trouvés.

## 6. Tests de non-régression

`Tests/DeskewCoreTests/SecurityTests.swift` vérifie que chaque vecteur identifié est
**rejeté proprement** (aucun plantage) :

- `-a` : `inf`, `nan`, `1e19`, `1e15`, `1e300`, `100`, `91`, `0`, `-5` → rejetés ;
  `0.1`, `10`, `45`, `90` → acceptés.
- `-l`, `-d`, `-r`, `-m` : valeurs non finies → rejetées.
- `FloatRect.scaled` : `nan`/`inf`/`1e300` → `.zero` (pas de trap).
- `ContentRect.forImage` : rectangle/marges non finis → `nil`.
- `HoughSkewDetector.detect` : `inf`/`1e9`/`angleStep 0` → erreur ; paramètres valides → OK.
- `Pipeline.run` : `maxAngle = inf` → erreur.

## 7. Divergences de durcissement vs l'original

| Point | Original (Pascal) | Swift (durci) |
| --- | --- | --- |
| `-a` | aucune borne (plante/échoue au-delà) | borné à `(0, 90]` |
| `-a inf`, `-r nan`, `-m inf` | comportement indéfini / plantage | rejet propre (exit 1) |
| Accumulateur trop grand | tentative d'allocation (OOM) | erreur explicite |
| Image démesurée | tentative d'allocation (OOM) | erreur explicite |

Ces durcissements **ne modifient pas** les cas d'usage légitimes : les 37 golden
cases et les 75 tests passent.

## 8. Fuzzing

`Tests/DeskewCoreTests/FuzzTests.swift` — fuzzers **déterministes** (PRNG SplitMix64
à graine fixe → reproductibles). Objectif : *aucune entrée non fiable ne doit
provoquer de trap ou de signal*. On ne vérifie pas la sémantique, seulement
l'absence de plantage.

| Fuzzer | Entrées | Volume | Méthode |
| --- | --- | --- | --- |
| Parsing d'arguments | jetons aléatoires (options, valeurs normales, limites, malveillantes : `inf`, `nan`, `1e300`, chaînes de 2000 car., NUL, Unicode…) | 5 000 tableaux | in-process `DeskewOptions.parse` |
| Chargement d'images | octets aléatoires, en-têtes PNG/JPEG/TIFF/GIF/BMP + charge aléatoire, mutations (bits inversés, troncature) d'une image réelle | ~700 fichiers | `ImageLoader.load` |
| CLI bout-en-bout | arguments aléatoires + image d'entrée | 80 exécutions | sous-processus `deskew` |
| Écriture d'images | petits rasters + qualités/compressions aléatoires | 25 écritures | `ImageWriter.save` puis relecture |
| **Corpus de régression** | vecteurs déjà trouvés (FIND-001 à FIND-005) | 31 vecteurs | sous-processus, doit rejeter proprement |

Points d'attention :

- **Bac à sable** : le fuzzer CLI s'exécute dans un dossier temporaire avec une copie
  de l'image d'entrée, et ses jetons excluent tout chemin — **aucune écriture hors du
  bac à sable** (pas de risque d'écraser `TestImages/`).
- **Détection des crashes** : pour les sous-processus, on teste
  `terminationReason != .uncaughtSignal` et `terminationStatus < 128`.
- **Corpus de régression** : il garantit qu'une réapparition de FIND-001/002 serait
  détectée même si le tirage aléatoire ne retombait pas sur le vecteur. Avant
  correctif, ces vecteurs provoquaient `SIGTRAP` (exit 133) — vérifié manuellement.
- **Graine fixe** : un échec est reproductible ; changer la graine élargit la
  couverture.

## 9. Sanitizers (data races et mémoire)

Le code parallélise (Hough, rotation, Otsu) et écrit dans des **tampons bruts**
(`UnsafeMutableBufferPointer`). On ne se contente pas de « croire » que c'est sûr :
on le **vérifie** avec les sanitizers Apple.

```bash
Scripts/sanitizers.sh
```

| Sanitizer | Cible | Résultat |
| --- | --- | --- |
| **ThreadSanitizer** (`--sanitize=thread`) | `ConcurrencyTests` (Otsu + Hough + rotation, tous filtres, 5 passes) | ✅ **aucune data-race** |
| **AddressSanitizer** (`--sanitize=address`) | `ConcurrencyTests` + `testLoadAllTestImages` (tous les chemins du loader) | ✅ **aucun débordement** |

**Pourquoi c'est concluant** : TSan confirme que les écritures concurrentes sont
réellement **disjointes** (colonnes d'angles distinctes pour Hough, bandes de lignes
distinctes pour la rotation) — aucun verrou nécessaire. ASan confirme qu'aucun accès
ne sort des tampons (allocations non initialisées, pointeurs, empaquetage 1 bit).

Un **job CI dédié** (`sanitizers`) exécute ces vérifications à chaque push. Le test
`ConcurrencyTests` sert de cible et vérifie aussi le **déterminisme** : le
multithreading ne modifie ni l'angle, ni les statistiques, ni le seuil Otsu.
