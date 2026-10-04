# Instructions projet — deskew-swift

> Fichier chargé automatiquement par l'agent à chaque session dans ce dépôt.

## Langue

- Commits, documentation et commentaires **en français**.
- Conventional Commits avec emoji de type (voir [`CONTRIBUTING.md`](CONTRIBUTING.md)).

## Pousser du code — OBLIGATOIRE

`master` est protégée par un ruleset GitHub : **le push direct est refusé**, et le
merge exige les checks `build-and-test` **et** `sanitizers` verts (policy *strict*,
branche à jour). Toujours passer par une branche et une PR :

```bash
git switch -c <feat|fix|docs|ci|chore>/<sujet>
# ... commits atomiques ...
git push -u origin <branche>
gh pr create --fill              # ou avec une description « pourquoi »
gh pr checks --watch             # attendre build-and-test ET sanitizers
gh pr merge --squash --delete-branch
```

- **Ne jamais `git push origin master`** : c'est refusé par le serveur.
- Si `master` a divergé : rebaser la branche avant de relancer les checks.
- Le badge README reflète l'état des checks.

## Vérifier avant de pousser

```bash
xcrun swift build -c release
xcrun swift test -c release      # parité golden files
Scripts/sanitizers.sh            # TSan + ASan (code parallèle)
```

La commande `swift` du `PATH` peut être une version ancienne (swiftly 5.6.3) :
utiliser **`xcrun swift`** (Xcode).

## Parité

Le projet reproduit **fidèlement** les algorithmes Pascal d'origine. Ne pas
« améliorer » un algorithme sans le signaler explicitement. Les golden files sont
dans `Tests/DeskewParityTests/reference/`. Le code Pascal à la racine
(`RotationDetector.pas`, `ImageUtils.pas`, …) sert d'**oracle** : ne pas le modifier
pour faire passer un test Swift.

## Structure

- `Sources/DeskewCore` : algorithmes purs (aucune E/S).
- `Sources/DeskewImageIO` : pont ImageIO/CoreGraphics + `CTiffShim`.
- `Sources/DeskewCLI` : exécutable.
