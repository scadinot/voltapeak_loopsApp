# voltapeak_loops (macOS / Swift)

Application SwiftUI macOS, conversion native du script Python
[`scadinot/voltapeak_loops`](https://github.com/scadinot/voltapeak_loops).
Elle traite **en masse** des fichiers de voltampérométrie à vagues carrées
(SWV) puis agrège les résultats dans un classeur Excel hiérarchique.

L'application s'inspire de :

- [`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp) pour les **fonctions d'analyse reprises à l'identique** (Savitzky-Golay scipy, détection de pic, asPLS Whittaker pybaselines) ;
- [`scadinot/voltapeak_batchApp/voltapeak_batch/ChartPNGRenderer.swift`](https://github.com/scadinot/voltapeak_batchApp/blob/main/voltapeak_batch/ChartPNGRenderer.swift) pour le rendu PNG (SwiftUI `Chart` + `ImageRenderer`).

## Fonctionnalités

- Sélection d'un dossier d'entrée contenant des fichiers `.txt`.
- Détection automatique de deux formats de nommage (regex identiques au Python) :
  - **loops** — `*_XX_SWV_CYY_loopZZ.txt`
  - **dosage** — `ZZ_<concentration>_XX_SWV_CYY.txt`
- Paramètres de lecture configurables : séparateur de colonnes
  (`Tabulation` / `Virgule` / `Point-virgule` / `Espace`) et séparateur décimal
  (`Point` / `Virgule`).
- Mode multi-thread (un `Task` par fichier via `TaskGroup`, parallélisme natif
  sur tous les cœurs) ou séquentiel pour le débogage.
- Exports optionnels par fichier : `.png` du graphique, `.csv` ou `.xlsx` des
  données nettoyées. Les échecs d'écriture sont logués en rouge dans la GUI
  sans bloquer l'analyse.
- Classeur Excel agrégé final, hiérarchique sur trois niveaux :
  **Canal / Variante / Mesure (Tension, Courant)**, une ligne par itération
  (loops) ou par concentration (dosage), tri numérique préservant l'ordre
  expérimental, refus des dossiers à formats mixtes.
- Journal en temps réel + barre de progression + bouton « Ouvrir le dossier de
  résultats ».

## Arborescence

```
voltapeak_loops.xcodeproj/         # Projet Xcode 26
voltapeak_loops/                   # Sources Swift
  voltapeak_loopsApp.swift         # Entrée @main SwiftUI
  ContentView.swift                # Interface
  VoltapeakLoopsViewModel.swift    # Orchestration batch (MainActor)
  LoopsBatchProcessor.swift        # Pipeline pure compute par fichier
  FileNameParser.swift             # Regex loops / dosage
  AggregatedXLSXWriter.swift       # XLSX final hiérarchique
  PerFileExporters.swift           # CSV / XLSX par fichier
  ChartPNGRenderer.swift           # PNG par fichier (SwiftUI ImageRenderer)
  ZIPStore.swift                   # ZIP store-only OOXML
  XLSXBoilerplate.swift            # XML communs OOXML
  SWVFileReader.swift              # Lecture .txt (identique voltapeakApp)
  VoltammetryData.swift            # Modèles (identique voltapeakApp)
  SavitzkyGolay.swift              # Lissage SG (identique voltapeakApp)
  WhittakerASPLS.swift             # asPLS (identique voltapeakApp)
  SignalProcessing.swift           # Détection pic (identique voltapeakApp)
  Assets.xcassets/                 # AppIcon (placeholders) + AccentColor
```

## Build

Ouvrir `voltapeak_loops.xcodeproj` avec Xcode 26 et lancer la cible
`voltapeak_loops` (macOS 26.1+). L'App Sandbox est désactivé afin de pouvoir
lire/écrire dans un dossier arbitraire choisi par l'utilisateur, comme dans
`voltapeakApp`.

## Architecture concurrence

- `VoltapeakLoopsViewModel` est `@MainActor @Observable`.
- `LoopsBatchProcessor.processOne(...)` est nonisolated par défaut (le pbxproj
  **ne pose pas** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) ; il s'exécute
  donc librement sur les Tasks du `TaskGroup`.
- Les exports par fichier (PNG via `ChartPNGRenderer` qui nécessite
  `ImageRenderer` sur le MainActor, CSV/XLSX du dataframe nettoyé) sont
  exécutés côté ViewModel dès qu'un résultat de calcul est reçu du TaskGroup.

## Documentation complémentaire

- [ARCHITECTURE.md](ARCHITECTURE.md) — pipeline batch + d'analyse, fichiers Swift, modèles de données, concurrence, choix de design.
- [ALGORITHMS.md](ALGORITHMS.md) — détails mathématiques de chaque étape (Savitzky-Golay, detectPeak, asPLS Zhang 2020, rendu PNG).
- [VALIDATION.md](VALIDATION.md) — méthodologie de validation : parité numérique vs voltapeakApp, parsing, cohérence multi-thread, structure XLSX.
- [DEVELOPMENT.md](DEVELOPMENT.md) — prérequis, build CLI, conventions de code, débogage, ajout de fonctionnalités.
- [DISTRIBUTION.md](DISTRIBUTION.md) — CI GitHub Actions (build-artifact + release), signature ad-hoc, notarisation Apple, DMG.
- [CHANGELOG.md](CHANGELOG.md) — historique versionné (Keep-a-Changelog / SemVer).

## Crédits

- Script Python original : [`scadinot/voltapeak_loops`](https://github.com/scadinot/voltapeak_loops).
- App macOS mono-fichier de référence : [`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp).
- App macOS batch (autre lot) inspirant le rendu PNG : [`scadinot/voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp).
- Auteur : GROUPE TRACE.
