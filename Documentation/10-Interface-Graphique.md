# 10 — Interface graphique (note de conception)

> **Statut : proposé, non implémenté.** Ce document décrit *si* et *comment* ajouter
> une interface graphique à `deskew-swift`, en s'inspirant de l'UX de la GUI Pascal
> d'origine. Aucune décision d'implémentation n'est prise ici ; c'est une note
> d'architecture (ADR) à valider avant d'écrire du code.

## 1. Contexte

L'upstream fournit une GUI (`Gui/` chez [galfar/deskew](https://github.com/galfar/deskew)),
retirée de notre dépôt car elle est écrite en Object Pascal/LCL. Son rôle est **le
traitement par lot** : sélectionner plusieurs fichiers, régler les options une fois,
lancer le traitement sur toute la liste. C'est le manque principal du CLI pour un
public non technicien.

Deux constats orientent la conception :

1. **La GUI Pascal n'est pas une GUI de traitement** : `Gui/runner.pas` lance le
   **processus CLI un fichier à la fois** et recopie stdout dans un mémo. C'est un
   *frontend de sous-processus*.
2. **Nous n'avons pas besoin de ce montage** : `DeskewCore` et `DeskewImageIO` sont
   déjà des bibliothèques. Une app Swift peut appeler `ImageLoader.load` →
   `Pipeline.run` → `ImageWriter.save` **directement**, sans `Process` ni parsing
   de sortie console.

## 2. Décision

- **Ajouter une app graphique macOS native** (SwiftUI) à terme, si l'usage le
  justifie.
- **Reproduire l'UX** de la GUI Pascal, pas son architecture.
- **Appeler le cœur Swift en direct** (pas de sous-processus).
- **Livrer d'abord un MVP non signé** (fenêtre unique + options avancées) ; le
  packaging `.app` signé/notarisé et le cask Homebrew sont une étape ultérieure,
  distincte et conditionnelle.

## 3. Pourquoi ne pas porter l'architecture Pascal

| Aspect | GUI Pascal | App Swift proposée |
| --- | --- | --- |
| Traitement | Sous-processus CLI par fichier | Appel direct à `Pipeline` |
| Progression | Lecture de stdout | Callback / `AsyncSequence` |
| Erreurs | Codes de sortie + texte | `throws` typé (`PipelineError`, `ImageIOError`) |
| Options | Reconstruites en arguments CLI | `DeskewOptions` en mémoire |
| Dépendance | Binaire CLI à côté de la GUI | Aucune (même processus) |

Appeler le cœur directement supprime une couche entière (lancement de processus,
gestion des pipes, parsing de texte) et donne un meilleur retour d'erreur.

## 4. UX cible (d'après la GUI Pascal)

Fenêtre unique, deux écrans (équivalent du `Notebook` Pascal) :

**Écran « Entrée »**
- Liste des fichiers : drag & drop + bouton *Ajouter*, bouton *Vider*.
- Dossier de sortie (+ *Parcourir*).
- Format de sortie : `Same as input`, PNG, JPEG, TIFF, BMP, PSD, TGA, JNG, PPM.
- Couleur de fond (sélecteur de couleur, défaut blanc).
- Case *Crop to input*.
- Case *Use default output file options* (désactive les réglages par format).
- Bouton **Options avancées** (sheet).
- Bouton principal **Deskew** (et *Stop* pendant le traitement).

**Écran « Sortie »**
- Barre de progression + fichier courant (`nom.ext [n/total]`).
- Journal console (sortie du pipeline, ligne par ligne).
- Bouton *Terminer*.

**Sheet « Options avancées »** (équivalent `advoptionsform`) :

| Option Pascal | Champ Swift |
| --- | --- |
| Max angle / Angle step / Skip angle | `maxAngle`, `angleStep`, `skipAngle` |
| Seuil auto ou valeur | `thresholdingMethod`, `thresholdLevel` |
| Filtre de rééchantillonnage | `resamplingFilter` |
| Format de sortie forcé | `forcedOutputFormat` |
| Qualité JPEG | `jpegCompressionQuality` |
| Compression TIFF (dont `input`/`input-lossless`) | `tiffCompression` |
| DPI override | `dpiOverride` |
| Detect only | `detectOnly` |
| Marge / rectangle de détection | `contentMargins`, `contentRect`, `contentSizeUnit` |
| Paramètres additionnels | *(sans objet : plus de CLI intermédiaire)* |

Le format de sortie Pascal « TIFF (support depends on platform) » devient simplement
« TIFF » chez nous (libtiff embarqué via `CTiffShim`).

## 5. Architecture technique

```text
deskew-swift/
├── Sources/
│   ├── DeskewCore/          (inchangé)
│   ├── DeskewImageIO/       (inchangé)
│   ├── DeskewCLI/           (inchangé)
│   └── DeskewApp/           (nouveau, SwiftUI)
│       ├── DeskewApp.swift          @main, App/WindowGroup
│       ├── MainView.swift           liste fichiers + options + progression
│       ├── AdvancedOptionsView.swift
│       └── BatchRunner.swift        boucle séquentielle sur le core
```

- **Package** : ajouter un produit exécutable `deskew-app` et une cible
  `DeskewApp` dépendant de `DeskewCore` + `DeskewImageIO`. `Package.swift`
  n'exige aucun outil supplémentaire (plateforme macOS 13 déjà déclarée).
- **Traitement** : boucle séquentielle sur les fichiers (comme le runner Pascal),
  exécutée dans une tâche de fond ; l'UI reste réactive. Un seul fichier en mémoire
  à la fois.
- **Pas de sandbox** : distribution hors Mac App Store, accès disque via drag & drop
  et `NSOpenPanel`/`NSSavePanel`. Évite les entitlements et les *security-scoped
  bookmarks*.
- **Réutilisation de l'icône** : `deskewgui.icns` de l'upstream (MPL 2.0), attribution
  conservée.

## 6. Périmètre

| Étape | Contenu |
| --- | --- |
| **MVP** | Fenêtre unique, drag & drop, dossier/format/couleur/crop, sheet avancé, progression + log, appel direct au core. |
| **Différé** | Marge/rectangle de détection (saisie en unités), préférences persistantes (équivalent du `.ini`), traitement parallèle. |
| **Hors périmètre** | Mac App Store, sandbox, localisation multi-langue, édition d'image. |

## 7. Distribution

Le coût réel n'est pas l'UI (~400–600 lignes de SwiftUI) mais la **chaîne de
distribution macOS** :

1. SwiftPM ne produit pas de `.app` : prévoir `Info.plist` + `Scripts/build_app.sh`
   qui emballe le binaire et les ressources dans `Deskew.app`.
2. Signature ad-hoc pour un usage local, puis *Developer ID* + **notarisation** si
   distribution publique.
3. Un **cask Homebrew** (`brew install --cask Opware2000/tap/deskew-swift`) en
   complément de la formule CLI existante.

Ces étapes sont **conditionnelles** : elles ne se justifient que si le MVP est
réellement utilisé.

## 8. Alternatives écartées

| Alternative | Pourquoi écartée |
| --- | --- |
| **Quick Action Finder / Raccourcis** | La plus paresseuse, mais pas l'UX demandée (pas de liste, pas de progression, pas d'options). Pertinente comme complément, pas comme substitut. |
| **Porter la GUI Pascal** (LCL) | Object Pascal/LCL : hors de la base technique du projet. |
| **Wrapper web (Electron/Tauri)** | Dépendance lourde pour un outil local déjà natif. |
| **Garder uniquement le CLI** | Reste valide ; le CLI couvre les utilisateurs avancés. La GUI vise un public différent. |

## 9. Coûts, risques et maintenance

- **Nouvelle surface à maintenir** : l'app doit suivre les évolutions de
  `DeskewOptions` (une option ajoutée au CLI doit apparaître dans le sheet).
  Mitigation : l'UI lit les mêmes types, le compilateur signale les champs manquants.
- **Distribution** : signature/notarisation à refaire à chaque release, outillage
  supplémentaire (certificats, `notarytool`).
- **Parité** : la GUI ne doit pas réimplémenter de logique ; elle se contente
  d'alimenter `DeskewOptions` et d'appeler `Pipeline`. Aucun algorithme dupliqué.

## 10. Critères de sortie (avant de s'engager)

1. Besoin confirmé : au moins un utilisateur non-terminal cible.
2. MVP validé en interne sur un lot de fichiers (mêmes résultats que le CLI).
3. Décision explicite sur la distribution (locale seulement vs publique).

Tant que ces critères ne sont pas réunis, **le CLI reste le seul produit** et cette
note reste une proposition.
