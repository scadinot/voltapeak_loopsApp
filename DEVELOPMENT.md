# Guide développeur

## Prérequis

| Outil | Version |
|---|---|
| **macOS** | 26.1+ (Tahoe) |
| **Xcode** | 26+ |
| **Python** (uniquement pour validation croisée) | 3.11+ avec `numpy`, `scipy`, `pybaselines`, `pandas`, `matplotlib`, `openpyxl` |

Toutes les bibliothèques Swift utilisées proviennent du SDK macOS
(`SwiftUI`, `Charts`, `Foundation`, `AppKit`, `Observation`).
**Aucun Swift Package Manager.**

## Build

```bash
git clone https://github.com/scadinot/voltapeak_loopsApp.git
cd voltapeak_loopsApp
open voltapeak_loops.xcodeproj
```

Dans Xcode : **⌘R** pour compiler et lancer.

En ligne de commande (utilisé par la CI) :

```bash
xcodebuild archive \
  -project voltapeak_loops.xcodeproj \
  -scheme voltapeak_loops \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/voltapeak_loops.xcarchive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual
```

### Resets utiles

| Symptôme | Action |
|---|---|
| Code modifié mais comportement inchangé | Product → Clean Build Folder (⌘⇧K) |
| Icône Dock incorrecte / placeholder blanc | Supprimer `~/Library/Developer/Xcode/DerivedData/voltapeak_loops-*` |
| Erreurs de fichiers « rouges » dans Xcode après pull | Quitter Xcode et relancer (le `PBXFileSystemSynchronizedRootGroup` se resync) |
| Erreurs Sendable / actor isolation après ajout d'un fichier | Vérifier qu'aucun `@MainActor` implicite n'a été introduit (le pbxproj ne pose **pas** `SWIFT_DEFAULT_ACTOR_ISOLATION`) |

## Structure du projet

Voir [ARCHITECTURE.md](ARCHITECTURE.md) pour la vue d'ensemble.

```
voltapeak_loopsApp/                # racine du dépôt
├── README.md
├── ARCHITECTURE.md
├── ALGORITHMS.md
├── VALIDATION.md
├── DEVELOPMENT.md       # ce fichier
├── DISTRIBUTION.md
├── CHANGELOG.md
├── .gitignore
├── .github/
│   ├── copilot-instructions.md
│   └── workflows/
│       ├── build-artifact.yml
│       └── release.yml
├── voltapeak_loops.xcodeproj/      # projet Xcode 26
└── voltapeak_loops/                # sources Swift + assets
    ├── *.swift                     # 16 fichiers core
    └── Assets.xcassets/            # AppIcon (placeholders) + AccentColor
```

## Conventions de code

| Aspect | Convention |
|---|---|
| Langue commentaires / UI | **Français** |
| Indentation | 4 espaces |
| Casing types | `PascalCase` |
| Casing fonctions / variables | `camelCase` |
| Constantes statiques | `camelCase` (Swift style, pas SCREAMING_CASE) |
| Organisation interne | Sections `// MARK: - Section` pour la navigation Xcode |
| Documentation d'API | Triple-slash `///` avec balises `- Parameters`, `- Returns`, `- Throws` |
| Acronymes scientifiques | Conservés en minuscules : `aspls`, `savgol`, etc. |
| Actor isolation | **Pas de** `@MainActor` au niveau target. Seuls `VoltapeakLoopsViewModel` et les vues SwiftUI sont explicitement `@MainActor`. Les compute namespaces (`SavitzkyGolay`, `WhittakerASPLS`, etc.) sont nonisolated. |

Les fichiers Swift sont écrits en français pour la cohérence avec l'UI et les
commentaires existants. C'est un projet francophone assumé.

## Ajouter une fonctionnalité

### Exemple : nouveau format de noms de fichiers

1. **Parser** (`FileNameParser.swift`) :
   - Ajouter une régex case-insensitive dans la même famille que `loopsRegex` /
     `dosageRegex`.
   - Étendre `FileNameFormat` avec un nouveau case.
   - Ajouter le pattern dans `parse(...)` (ordre : du plus restrictif au moins
     restrictif).
2. **Agrégation** (`AggregatedXLSXWriter.swift`) :
   - Si le tri/indexLabel doit différer, ajouter le case dans `build(rows:format:)`.
3. **Test manuel** : préparer un dossier mixant le nouveau format avec un ancien
   → vérifier le refus rouge ; préparer un dossier homogène → vérifier l'export.

### Exemple : nouveau format d'export par fichier (ex. JSON)

1. **PerFileExporters** : ajouter `writeCleanedJSON(potentials:currents:to:)`.
2. **BatchOptions.ProcessedExport** : ajouter le case `.json`.
3. **VoltapeakLoopsViewModel.performPerFileExports** : nouveau `case .json`.
4. **ContentView.settingsBox** : ajouter une option radio.

### Exemple : changer un paramètre d'algorithme

Les paramètres scientifiques sont hardcodés dans
`LoopsBatchProcessor.processOne` (mimant `voltapeakApp` pour conserver la
parité). Pour les rendre configurables :

- Étendre `SWVFileConfiguration` ou `BatchOptions`.
- Surfacer dans `ContentView.settingsBox`.
- Passer la valeur dans l'appel à `aspls` / `detectPeak`.

## Débugger

### Logs console Xcode

Le `VoltapeakLoopsViewModel.run` émet des `appendLog(...)` que l'utilisateur
voit dans la GUI :

```
Nettoyage du dossier de sortie...
Traitement : 010_05_SWV_C09_loop0.txt
Traitement : 010_05_SWV_C09_loop1.txt
...
Traitement terminé.
Fichiers traités : 24 / 24
Temps écoulé : 1.42 secondes.
```

Pour des détails plus fins (signal intermédiaire, baseline, etc.), ajouter
des `print(...)` directement dans `processOne`. Format recommandé pour la
comparaison avec voltapeakApp / Python :

```swift
print("=== aspls DEBUG (Swift) ===")
print("first5 : \(baseline.prefix(5).map { String(format: "%.6e", $0) })")
print("last5  : \(baseline.suffix(5).map { String(format: "%.6e", $0) })")
```

Visible dans la console Xcode lors du run (View → Debug Area → Show Debug
Area).

### Vérifier la parité numérique avec voltapeakApp

Les fonctions d'analyse étant reprises à l'identique, traiter un même fichier
individuel doit produire un pic strictement identique entre les deux apps.
Si ce n'est pas le cas, c'est un signe que quelque chose a divergué dans la
copie — voir [VALIDATION.md](VALIDATION.md) § « Parité numerique ».

## Tests

**État actuel** : aucun test unitaire automatisé. Les fonctions d'analyse
sont déjà validées dans `voltapeakApp` (bit-exact contre Python). La
validation propre au batch est manuelle, documentée dans
[VALIDATION.md](VALIDATION.md).

Pistes pour ajouter une cible de tests :

1. **Tests algorithmiques** (priorité faible — déjà validés dans voltapeakApp).
2. **Tests d'agrégation** : construire un `[BatchFileResult]` synthétique →
   appeler `AggregatedXLSXWriter.build` → vérifier l'XML produit
   (snapshot test).
3. **Tests de parsing** : `FileNameParser.parse` sur une table de cas
   (loops, dosage, casse, formats invalides).
4. **Tests d'intégration** : charger un mini-dossier de fixtures → lancer
   `LoopsBatchProcessor.processOne` sur chaque fichier → vérifier pic +
   métadonnées.

Pour démarrer : ajouter une cible `voltapeak_loopsTests` dans Xcode,
framework `Swift Testing` ou XCTest.

## Ressources externes

- [Apple SwiftUI documentation](https://developer.apple.com/documentation/swiftui)
- [Apple Charts framework](https://developer.apple.com/documentation/charts)
- [scipy.signal documentation](https://docs.scipy.org/doc/scipy/reference/signal.html)
- [pybaselines repo](https://github.com/derb12/pybaselines)
- [Zhang et al. 2020 paper (asPLS)](https://www.tandfonline.com/doi/full/10.1080/00387010.2020.1734588)
- [voltapeakApp — app de référence pour les fonctions d'analyse](https://github.com/scadinot/voltapeakApp)
- [voltapeak_batchApp — app de référence pour le rendu PNG](https://github.com/scadinot/voltapeak_batchApp)
