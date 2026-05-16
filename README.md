# voltapeak_loopsApp

> Analyse par lot de voltampérogrammes SWV — itérations en boucles et dosages. Application macOS native (SwiftUI).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift 5.0](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![macOS 26.1+](https://img.shields.io/badge/macOS-26.1+-blue.svg)](https://www.apple.com/macos/)
[![CI](https://github.com/scadinot/voltapeak_loopsApp/actions/workflows/build-artifact.yml/badge.svg)](https://github.com/scadinot/voltapeak_loopsApp/actions/workflows/build-artifact.yml)
[![Release](https://github.com/scadinot/voltapeak_loopsApp/actions/workflows/release.yml/badge.svg)](https://github.com/scadinot/voltapeak_loopsApp/actions/workflows/release.yml)

---

## Table des matières

1. [À quoi sert cet outil ?](#à-quoi-sert-cet-outil)
2. [Écosystème voltapeak](#écosystème-voltapeak)
3. [Fonctionnalités](#fonctionnalités)
4. [Prérequis](#prérequis)
5. [Installation](#installation)
6. [Build & lancement](#build--lancement)
7. [Format des fichiers d'entrée](#format-des-fichiers-dentrée)
8. [Utilisation — interface graphique](#utilisation--interface-graphique)
9. [Résultats produits](#résultats-produits)
10. [Chaîne de traitement par fichier](#chaîne-de-traitement-par-fichier)
11. [Paramètres algorithmiques](#paramètres-algorithmiques)
12. [Architecture du code](#architecture-du-code)
13. [Performance & concurrence](#performance--concurrence)
14. [Tests](#tests)
15. [CI/CD](#cicd)
16. [Algorithmes & références](#algorithmes--références)
17. [Dépannage](#dépannage)
18. [Feuille de route](#feuille-de-route)
19. [Licence et auteur](#licence-et-auteur)

---

## À quoi sert cet outil ?

La **voltammétrie à vagues carrées** (Square Wave Voltammetry, SWV) est une technique électrochimique qui mesure le courant traversant une électrode en fonction d'un potentiel imposé. Le signal obtenu présente un **pic** caractéristique de l'espèce analysée, superposé à une **ligne de base** (*baseline*) qui dérive lentement avec le potentiel.

Pour exploiter le pic, il faut :

1. **lisser** le signal pour atténuer le bruit de mesure ;
2. **estimer puis soustraire** la ligne de base ;
3. **relever** les coordonnées (tension, courant) du pic corrigé.

`voltapeak_loopsApp` automatise ces trois étapes en s'appuyant sur :

- **Savitzky-Golay** pour le lissage (convolution polynomiale locale) ;
- **asPLS Whittaker** (*asymmetric Penalized Least Squares*, port Swift de [`pybaselines.whittaker.aspls`](https://pybaselines.readthedocs.io/)) pour l'estimation robuste de la baseline, avec une pondération réduite autour du pic afin d'éviter que la baseline ne « suive » et n'efface le pic.

> **Convention de signe.** Le pipeline est calibré pour des **SWV cathodiques** : le signe du courant est systématiquement inversé avant la détection de pic, donc le pic doit apparaître **en courant négatif** dans le fichier d'entrée. Un fichier où le pic est déjà en courant positif (orientation anodique) sera mal traité — il faut alors inverser la colonne en amont.

`voltapeak_loopsApp` cible les **plans d'expérience structurés** où plusieurs scans sont accumulés selon une dimension expérimentale — itérations dans le temps (*loops*) ou paliers de concentration (*dosage*). Le format des noms de fichiers porte cette information ; l'outil détecte automatiquement la convention utilisée et produit un classeur Excel à **en-tête hiérarchique sur trois niveaux** (Canal / Variante / Mesure) — équivalent Swift d'un `MultiIndex` pandas. Pour l'exploration interactive d'un seul fichier, voir [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) ; pour le simple traitement par lot multi-électrodes sans dimension expérimentale supplémentaire, voir [`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp).

---

## Écosystème voltapeak

Cette application fait partie d'une suite de 3 outils macOS dédiés à l'analyse de signaux de voltampérométrie à ondes carrées (SWV) :

- **[voltapeakApp](https://github.com/scadinot/voltapeakApp)** — analyseur interactif fichier-par-fichier (source de vérité des algorithmes).
- **[voltapeak_batchApp](https://github.com/scadinot/voltapeak_batchApp)** — traitement par lot multi-électrodes, agrégation Excel par canal (`*_C<NN>.txt`).
- **[voltapeak_loopsApp](https://github.com/scadinot/voltapeak_loopsApp)** — traitement par lot pour expériences en boucles ou dosages (`*_loopZZ.txt`, `ZZ_<concentration>_*`).

Les 3 applications partagent le même pipeline scientifique et les mêmes implémentations Swift natives.

Elles sont des **portages natifs** de leurs équivalents Python ([`scadinot/voltapeak`](https://github.com/scadinot/voltapeak), [`scadinot/voltapeak_batch`](https://github.com/scadinot/voltapeak_batch), [`scadinot/voltapeak_loops`](https://github.com/scadinot/voltapeak_loops)) — avec parité numérique stricte : coefficients Savitzky-Golay identiques à `scipy.signal.savgol_coeffs(11, 2)` et solveur asPLS aligné sur `pybaselines.whittaker.aspls`.

---

## Fonctionnalités

- Traitement de **tous les `.txt` d'un dossier**, sélectionné via la GUI.
- **Parallélisation Swift Concurrency** (`TaskGroup` sliding-window borné à `ProcessInfo.activeProcessorCount`), basculable en mode séquentiel pour le débogage.
- **Deux formats de nommage** supportés et **détectés automatiquement fichier par fichier** :
  - format *loops* (`*_XX_SWV_CYY_loopZZ.txt`) — itérations sur une même condition ;
  - format *dosage* (`ZZ_<concentration>_XX_SWV_CYY.txt`) — série de concentrations.
- **Séparateur de colonnes** (tabulation, virgule, point-virgule, espace) et **séparateur décimal** (point ou virgule) configurables dans l'interface.
- **Lissage** Savitzky-Golay (fenêtre 11, ordre 2) avec coefficients pré-calculés depuis `scipy.signal.savgol_coeffs` — parité numérique stricte.
- **Détection de pic robuste** : exclusion des 10 % de bords du scan et filtre de pente `maxSlope = 500`.
- **Estimation de ligne de base asPLS** avec zone d'exclusion ±3 % centrée sur le pic, résolution via solveur LAPACK banded `dgbsv_` (Accelerate, O(n)).
- **Export Excel hiérarchique** : en-tête à 3 niveaux (Canal / Variante / Tension+Courant), `mergeCells` OOXML sur les paires de colonnes — une ligne par itération (loops) ou par concentration (dosage), avec tri numérique de l'index.
- **Exports optionnels par fichier** : graphique PNG (`ImageRenderer`, scale 3, ~3000×1800), CSV ou XLSX nettoyé (signe original conservé).
- **Journal de traitement** auto-scrollable et **barre de progression** en temps réel.
- Bouton **« Ouvrir le dossier de résultats »** à la fin du traitement (`NSWorkspace.open`).
- **Zéro dépendance externe** : 100 % Swift + frameworks Apple (`SwiftUI`, `Charts`, `Accelerate`, `AppKit`, `Foundation`, `Observation`), y compris le générateur XLSX (mini-ZIP store-only + CRC32 PKZIP maison).

---

## Prérequis

- **macOS 26.1** ou supérieur (Tahoe — cible définie par `MACOSX_DEPLOYMENT_TARGET = 26.1`).
- **Xcode 16** ou supérieur (`objectVersion = 77`).
- **Swift 5.0**.

Aucune dépendance externe : tout repose sur les frameworks Apple (`SwiftUI`, `AppKit`, `Charts`, `Accelerate`, `Foundation`, `Observation`).

---

## Installation

```bash
git clone https://github.com/scadinot/voltapeak_loopsApp.git
cd voltapeak_loopsApp
open voltapeak_loops.xcodeproj
```

Aucune installation de dépendance, aucun `pod install`, aucun `swift package resolve`.

Pour récupérer une `.app` pré-construite (non signée Developer ID), télécharger l'archive depuis l'onglet [Releases](https://github.com/scadinot/voltapeak_loopsApp/releases) du dépôt.

---

## Build & lancement

Avec Xcode : ouvrir `voltapeak_loops.xcodeproj` et lancer (⌘R).

En ligne de commande :

```bash
xcodebuild build \
  -project voltapeak_loops.xcodeproj \
  -scheme voltapeak_loops
```

> Le projet Xcode et le scheme s'appellent `voltapeak_loops` (sans suffixe `App`) — seul le **repo** porte le suffixe `App`.

---

## Format des fichiers d'entrée

| Caractéristique          | Valeur                                                       |
|--------------------------|--------------------------------------------------------------|
| Extension                | `.txt`                                                       |
| Encodage                 | `ISO Latin-1` (par défaut des potentiostats BioLogic / PalmSens européens) |
| Nombre de colonnes       | ≥ 2 (seules les 2 premières sont lues)                       |
| Première ligne           | en-tête — **ignorée**                                        |
| Colonne 1                | Potentiel en volts (`Double`)                                |
| Colonne 2                | Courant en ampères — **pic attendu en valeur négative** (convention SWV cathodique : le pipeline inverse le signe avant la détection) |
| Séparateur de colonnes   | configurable : tabulation / virgule / point-virgule / espace |
| Séparateur décimal       | configurable : point / virgule                               |
| Nombre minimal de lignes | ~11 (fenêtre Savitzky-Golay)                                 |
| Nombre maximum de points | **200 000** par fichier (garde-fou anti-DoS du solveur asPLS — `FileError.tooManyPoints`) |

### Conventions de nommage

L'outil reconnaît **deux formats** de noms de fichiers, détectés automatiquement fichier par fichier par deux `NSRegularExpression` (case-insensitive). Le format *loops* est testé en premier car plus restrictif ; *dosage* sert ensuite de fallback.

#### Format `loops` — itérations sur une même condition

```
<n'importe-quoi>_XX_SWV_CYY_loopZZ.txt
```

| Groupe   | Signification                                       | Exemple  |
|----------|-----------------------------------------------------|----------|
| `XX`     | Variante sur 2 chiffres (souvent une fréquence Hz)  | `05`     |
| `CYY`    | Identifiant de canal (`C` + 2 chiffres)             | `C03`    |
| `loopZZ` | Numéro d'itération (1 chiffre ou plus)              | `loop7`  |

Exemples valides : `echantillon_A_05_SWV_C00_loop1.txt`, `run2_15_SWV_C12_loop10.txt`.

#### Format `dosage` — série de concentrations

```
ZZ_<concentration>_XX_SWV_CYY.txt
```

| Groupe            | Signification                                                   | Exemple   |
|-------------------|-----------------------------------------------------------------|-----------|
| `ZZ`              | Préfixe numérique servant au tri (ordre expérimental)           | `10`      |
| `<concentration>` | Libellé de concentration (forme libre, ne contient pas `_`)     | `250nm`   |
| `XX`              | Variante sur 2 chiffres (souvent un réplica)                    | `01`      |
| `CYY`             | Identifiant de canal (`C` + 2 chiffres)                         | `C05`     |

Exemples valides : `01_0nm_01_SWV_C05.txt`, `10_250nm_01_SWV_C05.txt`, `13_1000nm_02_SWV_C05.txt`.

> Le tri des lignes du tableau Excel final s'effectue selon le préfixe `ZZ` (numérique), **pas** selon l'ordre alphabétique du libellé : `0nm, 0.1nm, 0.25nm, …, 1000nm` apparaissent dans l'ordre expérimental.

#### Règles d'inclusion

> ⚠️ Tout fichier ne respectant **aucun** des deux motifs est **ignoré** (une ligne `« Fichier ignoré ou invalide : <nom> »` apparaît dans le journal de traitement). Vérifier le nommage si certains fichiers n'apparaissent pas dans les résultats.

> ❌ Un dossier qui mélange les deux formats provoque l'**annulation de l'export Excel agrégé** : le journal affiche un message d'erreur explicite et aucun classeur agrégé n'est produit. Séparer les deux types de fichiers dans des dossiers distincts.

### Exemple de contenu (tabulation, point décimal)

```
Potential	Current
-0.500	-1.2e-6
-0.490	-1.1e-6
-0.480	-0.9e-6
...
```

---

## Utilisation — interface graphique

La fenêtre principale (760×620) s'organise en sections SwiftUI :

1. **Sélecteur de dossier** — bouton **Parcourir** (`NSOpenPanel`), chemin affiché tronqué au milieu.
2. **GroupBox « Paramètres de lecture »** (Grid) — 5 `Picker(.segmented)` :
   - *Séparateur de colonnes* : `Tabulation` (défaut), `Virgule`, `Point-virgule`, `Espace`,
   - *Séparateur décimal* : `Point` (défaut) ou `Virgule`,
   - *Export des fichiers traités* : `Ne pas exporter` (défaut), `CSV` ou `Excel`,
   - *Export des graphiques* : `Non` (défaut) ou `PNG`,
   - *Mode* : `Multi-thread (un Task par cœur)` (défaut) ou `Séquentiel`.
3. **GroupBox « Progression du traitement »** — `ProgressView` linéaire.
4. **GroupBox « Journal de traitement »** — `ScrollView` + `LazyVStack` monospace, lignes d'erreur en rouge, auto-scroll vers le bas via `ScrollViewReader`.
5. **Boutons d'action** :
   - **Ouvrir le dossier de résultats** (`NSWorkspace.shared.open`) — s'active une fois le traitement terminé,
   - **Lancer l'analyse** (`borderedProminent` + `keyboardShortcut(.defaultAction)`).

> L'app fonctionne **App Sandbox désactivé** : accès libre au dossier choisi et à son frère `(results)`.

---

## Résultats produits

À chaque exécution, un dossier frère du dossier d'entrée est créé (ou nettoyé s'il existe déjà) :

```
<dossier_entrée>            ← vos fichiers .txt
<dossier_entrée> (results)  ← sortie générée
```

### Classeur Excel agrégé

Fichier : `<nom_du_dossier>.xlsx` (feuille `Resume`). **Produit lorsque deux conditions sont réunies** :

1. au moins un fichier valide a été traité avec succès (sinon aucun classeur n'est écrit) ;
2. tous les fichiers détectés appartiennent au **même format** (loops *ou* dosage). En cas de mélange, un message d'erreur est journalisé et l'export est annulé.

Lorsque ces conditions sont remplies, la structure obtenue est hiérarchique sur trois niveaux (équivalent Swift d'un `pandas.MultiIndex` ; `mergeCells` OOXML sur les paires Tension+Courant) :

| *Index*   | Canal `C00`         |                     | Canal `C01`         |                     | … |
|-----------|---------------------|---------------------|---------------------|---------------------|---|
|           | Variante `05`       |                     | Variante `05`       |                     |   |
|           | Tension (V)         | Courant (A)         | Tension (V)         | Courant (A)         |   |
| *L₁*      | *v₁*                | *c₁*                | *v₁'*               | *c₁'*               |   |
| *L₂*      | *v₂*                | *c₂*                | *v₂'*               | *c₂'*               |   |
| …         | …                   | …                   | …                   | …                   |   |

- **Chaque ligne** = une itération (loops) ou une concentration (dosage), selon le format détecté.
- **Le libellé d'index varie selon le format** :
  - format *loops* → en-tête de colonne `Itération`, valeurs `loop0, loop1, loop2, …` ;
  - format *dosage* → en-tête de colonne `Concentration`, valeurs `0nm, 0.1nm, 250nm, …` (triées dans l'ordre expérimental).
- **Chaque bloc de deux colonnes** = un couple (canal, variante), avec tension et courant du pic corrigé. Selon le format, *variante* représente une fréquence (loops) ou un réplica (dosage).
- Les colonnes sont triées **numériquement** par canal (`C00 → C99`), puis par variante, puis Tension avant Courant.

> En cas de doublon `(canal, variante)` pour la même itération, la **première occurrence est conservée** et un avertissement est journalisé.

### Par fichier traité — optionnel

| Fichier      | Toujours produit ? | Contenu                                                                                                                         |
|--------------|:------------------:|---------------------------------------------------------------------------------------------------------------------------------|
| `<nom>.png`  | si *Export graphique = PNG*  | Rendu `ImageRenderer` (scale 3, ~3000×1800, palette matplotlib tab10) : signal brut, lissé, baseline asPLS, signal corrigé, marqueur de pic. |
| `<nom>.csv`  | si *Export traités = CSV*    | Colonnes `Potential`, `Current` après nettoyage (courant nul retiré, tri croissant — **signe original conservé**).         |
| `<nom>.xlsx` | si *Export traités = Excel*  | Mêmes colonnes que le CSV.                                                                                                  |

---

## Chaîne de traitement par fichier

```
┌──────────────────────────┐
│ Fichier *.txt (entrée)   │
└────────────┬─────────────┘
             │ FileNameParser.parse()      regex loops puis dosage (case-insensitive)
             ▼
┌──────────────────────────┐
│ SWVFileMetadata          │
└────────────┬─────────────┘
             │ SWVFileReader.read()        ISO Latin-1, séparateurs configurables
             ▼
┌──────────────────────────┐
│ [VoltammetryPoint] brut  │
└────────────┬─────────────┘
             │ processData()               tri par potentiel, inversion du signe (-I)
             ▼
┌──────────────────────────┐
│ Signal nettoyé           │
└────────────┬─────────────┘
             │ SavitzkyGolay.apply()       window=11, polyorder=2, coeffs scipy
             ▼
┌──────────────────────────┐
│ Signal lissé             │
└────────────┬─────────────┘
             │ SignalProcessing.detectPeak()   marge 10 %, maxSlope=500
             ▼
┌───────────────────────────┐
│ (x_pic, y_pic) provisoires│
└────────────┬──────────────┘
             │ WhittakerASPLS.baseline()   asPLS, exclusion ±3 %, dgbsv_ banded
             ▼
┌──────────────────────────┐
│ Baseline estimée         │
└────────────┬─────────────┘
             │ signal_corrigé = signal_lissé - baseline
             ▼
┌──────────────────────────┐
│ Signal corrigé           │
└────────────┬─────────────┘
             │ SignalProcessing.detectPeak()   pic final
             ▼
┌──────────────────────────┐
│ (x_pic, y_pic) corrigés  │
└────────────┬─────────────┘
             │ PerFileExporters / ChartPNGRenderer  (MainActor, optionnel)
             ▼
┌──────────────────────────┐
│ BatchFileResult          │  → agrégé par AggregatedXLSXWriter (en-tête 3 niveaux)
└──────────────────────────┘
```

---

## Paramètres algorithmiques

Les hyperparamètres sont actuellement **codés en dur** dans le code Swift. Leur exposition dans l'interface graphique est prévue (voir [Feuille de route](#feuille-de-route)).

| Paramètre               | Valeur     | Rôle                                                                                         |
|-------------------------|------------|----------------------------------------------------------------------------------------------|
| `windowLength`          | `11`       | Largeur de la fenêtre Savitzky-Golay (nombre impair de points).                              |
| `polyorder`             | `2`        | Ordre du polynôme ajusté localement par Savitzky-Golay.                                      |
| `marginRatio`           | `0.10`     | Fraction de points exclus aux deux bords lors de la recherche du pic.                        |
| `maxSlope`              | `500`      | Pente absolue maximale tolérée pour un candidat-pic (filtre les fronts).                     |
| `exclusionWidthRatio`   | `0.03`     | Demi-largeur (fraction de la plage de potentiel) de la zone protégée autour du pic.          |
| `lambdaFactor`          | `1e3`      | Facteur multiplicatif du paramètre de lissage Whittaker : `lam = lambdaFactor · n²`.         |
| `diffOrder`             | `2`        | Ordre de différence dans l'ajustement Whittaker (matrice pentadiagonale).                    |
| `tol`                   | `1e-2`     | Tolérance de convergence asPLS (sur Δ poids, pas Δ baseline — comme pybaselines).            |
| `maxIter`               | `25`       | Nombre maximum d'itérations de réajustement des poids (boucle `0...maxIter`).                |
| `maxN`                  | `200 000`  | Nombre maximum de points accepté par le solveur asPLS (garde-fou anti-DoS).                  |

---

## Architecture du code

Source dans `voltapeak_loops/` :

| Fichier                          | Rôle                                                                                          |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `voltapeak_loopsApp.swift`       | `@main struct VoltapeakLoopsApp: App` — `WindowGroup` 760×620, supprime `CommandGroup(.newItem)`. |
| `ContentView.swift`              | Vue racine SwiftUI : `inputFolder`, `settings`, `progress`, `log`, `action`.                  |
| `VoltapeakLoopsViewModel.swift`  | `@MainActor @Observable final class` — orchestrateur batch ; gère `TaskGroup`, agrège, écrit le XLSX final. |
| `LoopsBatchProcessor.swift`      | `enum` namespace : `enumerateInputFiles`, `cleanOutputFolder`, `processOne(url:options:)` (pipeline compute-only). Définit `BatchOptions`, `BatchFileResult`, `ProcessedSignals`. |
| `FileNameParser.swift`           | Détection format `loops` vs `dosage` via 2 `NSRegularExpression`. Produit `SWVFileMetadata{format, iterationKey, iterationLabel, variante, canal}`. |
| `SWVFileReader.swift`            | Lecture `.txt` (ISO Latin-1), `SWVFileConfiguration` (séparateurs), erreurs `LocalizedError`. |
| `VoltammetryData.swift`          | Modèles `Sendable` : `VoltammetryPoint`, `VoltammetryAnalysis`, `SWVFileConfiguration` (enums `ColumnSeparator` / `DecimalSeparator`). |
| `SavitzkyGolay.swift`            | 11 jeux de coefficients pré-calculés depuis `scipy.signal.savgol_coeffs(11, 2)` (`mode='interp'`). |
| `WhittakerASPLS.swift`           | `enum WhittakerASPLS` — port Swift exact (Zhang 2020), matrice pentadiagonale `D^T D` en banded LAPACK (KL=KU=2, LDAB=7), `dgbsv_` via Accelerate. |
| `SignalProcessing.swift`         | `detectPeak()` (marge + filtre de pente), `gradient()` (reproduit `numpy.gradient` pour pas non uniformes). |
| `AggregatedXLSXWriter.swift`     | Classeur final à 3 lignes d'en-tête (Canal / Variante / Tension+Courant), `mergeCells` sur paires, `Key{canal,variante}` triée numériquement, `indexLabel` = "Itération" (loops) ou "Concentration" (dosage). |
| `PerFileExporters.swift`         | `writeCleanedCSV`, `writeCleanedXLSX` (par-fichier, signe original conservé).                 |
| `ChartPNGRenderer.swift`         | Rendu PNG offscreen via `Swift Charts` + `ImageRenderer` (`@MainActor`, scale 3, ~300 dpi). `autoreleasepool` explicite. |
| `XLSXBoilerplate.swift`          | XML statiques OOXML (`Content_Types`, rels, workbook, workbook.rels), helpers `columnLetter` / `xmlEscape`, `packageSheet`. |
| `ZIPStore.swift`                 | Mini-ZIP store-only (compression = 0, CRC32 maison) suffisant pour `.xlsx`.                   |
| `Assets.xcassets/`               | `AccentColor`, `AppIcon`, `Contents.json`.                                                    |

Chaînage des appels :

```
VoltapeakLoopsApp
 └── ContentView
      ├── Picker → VoltapeakLoopsViewModel.options (séparateurs, exports, useMultiThread)
      ├── Bouton Parcourir → NSOpenPanel → VoltapeakLoopsViewModel.inputFolder
      └── Bouton Lancer l'analyse → VoltapeakLoopsViewModel.run() [async, @MainActor]
           ├── Task.detached(.utility) { enumerate + clean }
           ├── withTaskGroup(...) sliding-window borné à activeProcessorCount
           │     pour chaque fichier (nonisolated) :
           │     └── LoopsBatchProcessor.processOne(url:, options:)
           │           ├── FileNameParser.parse(url:)
           │           ├── SWVFileReader.read()
           │           ├── processData()
           │           ├── SavitzkyGolay.apply()
           │           ├── SignalProcessing.detectPeak()    (signal lissé)
           │           ├── WhittakerASPLS.baseline()
           │           └── SignalProcessing.detectPeak()    (signal corrigé)
           │     puis (@MainActor) exports optionnels : ChartPNGRenderer / PerFileExporters
           ├── AggregatedXLSXWriter.write(_:to:)            classeur récap 3 niveaux
           └── append au journal + activation "Ouvrir le dossier de résultats"
```

---

## Performance & concurrence

- `async/await` partout ; `run()` est `async` sur `@MainActor`.
- **Toggle séquentiel / multi-thread exposé dans la GUI** (`useMultiThread`).
- En mode multi-thread : `withTaskGroup` avec **pool borné = `ProcessInfo.processInfo.activeProcessorCount`**, géré en **sliding-window** — la fenêtre est ré-amorcée **avant** `didFinish` pour ne pas dégrader le parallélisme pendant les exports MainActor (PNG ~200-500 ms).
- Le **calcul CPU-bound est hors MainActor** : les `group.addTask` s'exécutent en contexte `nonisolated`. Modèles partagés conformes `Sendable` pour traverser le `TaskGroup`.
- Les **exports par-fichier (PNG / CSV / XLSX) sont sérialisés sur le MainActor** après chaque `group.next()` (contrainte `ImageRenderer`). `autoreleasepool` explicite autour du rendu PNG pour borner la heap (sinon les `NSImage` / `NSBitmapImageRep` s'accumulent sur batch de plusieurs centaines de fichiers).
- En mode séquentiel : chaque fichier passe par `Task.detached(priority: .utility)`, awaité. Utile en débogage (exceptions parfois absorbées par le `TaskGroup`) ou sur environnement contraint (1 vCPU).
- Préparation disque (clean + enumerate) déportée sur `Task.detached(.utility)` hors MainActor.
- Pattern aligné sur `BatchViewModel.runParallel` de [`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp) (référence canonique de la suite).

---

## Tests

**Pas encore de target de tests** dans ce repo : les algorithmes scientifiques (Savitzky-Golay, Whittaker asPLS, détection de pic) sont vérifiés en amont dans [`voltapeakApp`](https://github.com/scadinot/voltapeakApp), qui en héberge la suite `Testing` complète (`SavitzkyGolayTests`, `WhittakerASPLSTests`, `SignalProcessingTests`). Comme le code algorithmique est partagé à l'identique, les garanties s'étendent à cette app.

---

## CI/CD

| Workflow              | Déclencheur                | Action                                      | Artefact                    |
|-----------------------|----------------------------|---------------------------------------------|-----------------------------|
| `build-artifact.yml`  | `push` sur `main`, `workflow_dispatch` | Détection auto du scheme + `xcodebuild archive` Release **non signé** (`CODE_SIGN_IDENTITY="-"`), sortie `xcpretty` | `voltapeak_loops-unsigned-<sha>` (`.app` via `actions/upload-artifact@v4`) |
| `release.yml`         | tag `v*` ou `[0-9]*`       | `xcodebuild archive` + `ditto -c -k --keepParent` → zip + `gh release create --generate-notes` (ou `upload --clobber` si tag existe) | `voltapeak_loops-<TAG>.zip` (release GitHub, runner `macos-26`) |

> Les `.app` produites sont **ad-hoc signed** (`CODE_SIGN_IDENTITY="-"`) — ni signature Developer ID, ni notarisation. Au premier lancement, Gatekeeper bloque : faire un clic droit → *Ouvrir*, puis confirmer.

---

## Algorithmes & références

- **Savitzky-Golay** : implémentation Swift native avec **coefficients pré-calculés** depuis `scipy.signal.savgol_coeffs(window_length=11, polyorder=2)`. Les 11 jeux de coefficients (bord gauche pos 0-4, centre symétrique pos 5, bord droit pos 6-10) reproduisent `mode='interp'` de scipy **bit-pour-bit** sur le cas (11, 2).
- **Whittaker asPLS** (*Adaptive Smoothness Penalized Least Squares*) : port Swift de [`pybaselines.whittaker.aspls`](https://pybaselines.readthedocs.io/en/latest/api/whittaker/index.html#pybaselines.whittaker.aspls), résolu par un solveur **LAPACK banded `dgbsv_`** (Accelerate, KL=KU=2, LDAB=7) en O(n) — au lieu de O(n³) d'un Gauss dense — ce qui rend tractable des signaux jusqu'à 200 000 points. Itération `0...maxIter` (reproduction de `range(max_iter+1)` Python), convergence sur Δ poids (et non Δ baseline), mise à jour sigmoïde `expit(-(k/σ)·(r-σ))` avec `σ = std(résidus négatifs, ddof=1)`, `α[i] = |r[i]| / max|r|`.
  - Référence : Zhang, F., et al. (2020). *Baseline correction for Raman spectra using an improved asymmetric least squares method.*

Les détails d'implémentation (paramètres, garde-fous, conventions de signe) sont préservés à l'identique entre les 3 applications Swift et leurs origines Python.

---

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Certains fichiers sont ignorés (ligne `« Fichier ignoré ou invalide »` dans le journal) | Nom ne respectant aucun des deux motifs supportés | Vérifier le nommage — variante et canal **obligatoirement** sur 2 chiffres. |
| L'analyse s'arrête avec « le dossier mélange plusieurs formats de fichiers » | Mix de fichiers *loops* et *dosage* dans le même dossier | Séparer les deux types dans des dossiers distincts. |
| `Erreur dans le fichier … : Error tokenizing data` | Mauvais séparateur de colonnes | Choisir le bon séparateur dans la GUI. |
| Toutes les valeurs sont lues comme chaînes ou zéro | Mauvais séparateur décimal | Basculer entre *Point* et *Virgule*. |
| Pic « inversé » ou détecté loin du sommet visible | Fichier avec pic déjà en courant positif (orientation anodique) | Pré-inverser la colonne courant en amont — le pipeline attend une convention cathodique (cf. [Format des fichiers d'entrée](#format-des-fichiers-dentrée)). |
| `FileError.tooManyPoints` | Fichier > 200 000 lignes (garde-fou asPLS) | Décimer le signal en amont. |
| Le pic détecté est sur un bord | Bruit important aux extrémités | Augmenter `marginRatio` dans le code (exposition UI prévue). |
| La baseline épouse le pic | `lambdaFactor` trop bas ou zone d'exclusion trop étroite | Augmenter `lambdaFactor` ou `exclusionWidthRatio` dans le code (exposition UI prévue). |
| Les graphiques PNG ne sont pas générés | Option *Export des graphiques* sur *Non* (défaut) | Basculer sur *PNG* dans la GUI. |
| Le bouton *Ouvrir le dossier de résultats* reste grisé | Aucun fichier valide traité | Vérifier les nommages et le contenu du dossier. |
| Avertissement « doublon (canal, variante) » dans le journal | Deux fichiers résolvent à la même itération | La première occurrence est conservée — vérifier le nommage si non intentionnel. |
| Premier lancement bloqué par Gatekeeper | `.app` non signée Developer ID | Clic droit sur l'app → *Ouvrir* → confirmer. |

---

## Feuille de route

Voir [`ROADMAP.md`](ROADMAP.md) pour l'ensemble des évolutions prévues (à venir : exposition des hyperparamètres dans l'UI, signature Developer ID, etc.).

---

## Licence et auteur

- **Auteur** : Stéphane Cadinot ([@scadinot](https://github.com/scadinot)).
- **Licence** : [MIT](LICENSE) — Copyright (c) 2026 Stéphane Cadinot.

Pour toute question ou contribution, ouvrir une *issue* sur le dépôt GitHub.
