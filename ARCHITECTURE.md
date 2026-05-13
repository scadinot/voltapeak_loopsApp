# Architecture

`voltapeak_loopsApp` est l'**application batch loops/dosage** de la famille
`voltapeak*`. Les fonctions d'analyse (lecture SWV, Savitzky-Golay,
détection de pic, asPLS) sont reprises sans modification de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp) (référence
canonique mono-fichier) ; le rendu PNG par fichier est calqué sur celui de
[`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp).
Ce document décrit l'orchestration loops/dosage ajoutée par-dessus.

Détails numériques de chaque étape de calcul dans [ALGORITHMS.md](ALGORITHMS.md).

## Pipeline

Deux niveaux à distinguer.

### Niveau macro — orchestration batch

```
Utilisateur
     │
     ▼
ContentView (SwiftUI)
     │  Sélection dossier + options
     ▼
VoltapeakLoopsViewModel.run() (@MainActor)
     │
     ├▶ Task.detached (hors MainActor)
     │    │ cleanOutputFolder + enumerateInputFiles
     │    ▼
     │  files: [URL]
     │
     ├▶ withTaskGroup (parallèle)
     │    │ par fichier :
     │    │   LoopsBatchProcessor.processOne(...)
     │    │   (lecture + 7 étapes d'analyse)
     │    │   → BatchFileResult (Sendable)
     │    ▼
     │  collected: [BatchFileResult]
     │
     ├▶ pour chaque résultat (MainActor) :
     │    ├▶ ChartPNGRenderer.renderPNG (si option)
     │    ├▶ PerFileExporters.writeCSV/XLSX
     │    └▶ log + progression
     │
     ├▶ vérification format cohérent
     │    (refus dossiers loops + dosage mélangés)
     │
     ▼
AggregatedXLSXWriter.build → <dossier>.xlsx
```

### Niveau micro — pipeline d'analyse par fichier

Résumé : lecture latin-1 → tri/inversion → Savitzky-Golay scipy-exact →
détection pic brute → baseline asPLS Zhang 2020 → signal corrigé →
détection pic finale. Détails dans [ALGORITHMS.md](ALGORITHMS.md).

## Fichiers Swift

| Fichier | Rôle | Origine |
|---|---|---|
| `voltapeak_loopsApp.swift` | Entry point `@main`, fenêtre principale | nouveau |
| `ContentView.swift` | UI batch (sélecteur dossier, options, progression, journal) | nouveau |
| `VoltapeakLoopsViewModel.swift` | Orchestration TaskGroup, exports MainActor, agrégation finale | nouveau |
| `LoopsBatchProcessor.swift` | Pipeline d'analyse pur compute par fichier + types `BatchOptions`/`BatchFileResult`/`ProcessedSignals` | nouveau |
| `FileNameParser.swift` | Regex case-insensitive pour formats `loops` et `dosage` | nouveau |
| `AggregatedXLSXWriter.swift` | Classeur Excel final hiérarchique (3 lignes d'en-tête, fusions, tri canal/variante) | nouveau |
| `PerFileExporters.swift` | CSV/XLSX du dataframe nettoyé (un par fichier d'entrée) | nouveau |
| `ChartPNGRenderer.swift` | Rendu PNG offscreen via SwiftUI `Chart` + `ImageRenderer` (`@MainActor`) | calqué sur `voltapeak_batchApp` |
| `ZIPStore.swift` | Mini-ZIP store-only OOXML (compression method 0 + CRC32 PKZIP) | repris/généralisé |
| `XLSXBoilerplate.swift` | XML OOXML communs + helpers (`columnLetter`, `xmlEscape`, `packageSheet`) | nouveau |
| `SavitzkyGolay.swift` | Filtre Savitzky-Golay scipy-exact (window=11, ordre=2) | **identique** à `voltapeakApp` |
| `WhittakerASPLS.swift` | asPLS Zhang 2020 complet | **identique** à `voltapeakApp` |
| `SignalProcessing.swift` | Détection de pic + gradient `numpy` 2ᵉ ordre | **identique** à `voltapeakApp` |
| `VoltammetryData.swift` | Modèles partagés + `Sendable` | **identique** à `voltapeakApp` (+ `Sendable`) |
| `SWVFileReader.swift` | Lecture `.txt` SWV + helpers `processData`/`cleanedSignedData` | **identique** à `voltapeakApp` |

**16 fichiers Swift core**, dont 5 fonctions d'analyse reprises à
l'identique de `voltapeakApp` (parité numérique garantie).

## Dépendances

### Frameworks Apple (SDK)

| Framework | Utilisation |
|---|---|
| `SwiftUI` | UI déclarative + `Chart` (rendu PNG) |
| `Charts` | `Chart`, `LineMark`, `RuleMark`, `PointMark` pour le PNG offscreen |
| `Foundation` | Types de base, `URL`, `Data`, `String`, `FileManager`, regex |
| `AppKit` | `NSOpenPanel` (dossier), `NSWorkspace.open` (révéler résultats), `NSBitmapImageRep` (encodage PNG) |
| `Observation` (macro `@Observable`) | Réactivité ViewModel → UI |

### Dépendances externes

**Aucune.** Pas de Swift Package Manager, pas de CocoaPods, pas de
Carthage. L'export `.xlsx` est généré **sans bibliothèque tierce** :
`XLSXBoilerplate` + `ZIPStore` (~140 lignes au total) produisent un OOXML
valide ouvert sans warning par Excel, Numbers, Google Sheets, LibreOffice.

## Modèles de données

```swift
struct VoltammetryPoint: Identifiable, Sendable {
    let id = UUID()
    let potential: Double  // volts
    let current: Double    // ampères
}

struct VoltammetryAnalysis: Sendable {
    let rawData: [VoltammetryPoint]
    let smoothedSignal: [Double]
    let baseline: [Double]
    let correctedSignal: [Double]
    let peakPotential: Double
    let peakCurrent: Double
    let fileName: String
}

/// Vecteurs triés par potentiel croissant, deux conventions de signe.
struct ProcessedSignals: Sendable {
    let potentials: [Double]
    let processedCurrents: [Double]      // signe inversé (pipeline d'analyse)
    let cleanedSignedCurrents: [Double]  // signe original (export cleaned_df)
}

struct BatchFileResult: Sendable {
    enum Status: Sendable {
        case ok(metadata: SWVFileMetadata, peakPotential: Double, peakCurrent: Double)
        case skipped
        case error(String)
    }
    let url: URL
    let fileName: String
    let status: Status
    let analysis: VoltammetryAnalysis?
    let signals: ProcessedSignals?
}
```

## Concurrence

- **`VoltapeakLoopsViewModel`** : `@MainActor @Observable`. Source unique
  de vérité pour l'UI.
- **`LoopsBatchProcessor.processOne`** : nonisolated par défaut. Le
  `pbxproj` **ne pose volontairement pas**
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, ce qui permet aux compute
  namespaces d'être appelés depuis n'importe quel `Task` sans hop
  d'acteur.
- **`ChartPNGRenderer.renderPNG`** : `@MainActor` (contrainte
  `ImageRenderer`). Les exports PNG sont donc sérialisés sur le MainActor
  après réception de chaque résultat de calcul, ce qui est acceptable car
  le rendu est rapide (~50 ms par fichier en moyenne).
- **Préparation disque** : `cleanOutputFolder` + `enumerateInputFiles`
  sont exécutés sur un `Task.detached` pour ne pas bloquer le MainActor
  sur un volume réseau ou un dossier volumineux.

## Cycle de vie d'une analyse

1. L'utilisateur sélectionne le dossier → `VoltapeakLoopsViewModel.inputFolder`
   mis à jour.
2. Bouton « Lancer l'analyse » → `VoltapeakLoopsViewModel.run()` (async).
3. Sur `Task.detached` : création du dossier `<entrée> (results)`,
   nettoyage des artefacts, énumération triée des `.txt`,
   détermination du format (loops ou dosage) via `FileNameParser.parse`.
4. `withTaskGroup` : un `Task` par fichier exécute
   `LoopsBatchProcessor.processOne` → `BatchFileResult`.
5. Pour chaque résultat reçu (MainActor) : PNG, CSV/XLSX par fichier,
   log + progression.
6. Vérification du format cohérent (refus si loops + dosage mélangés).
7. `AggregatedXLSXWriter.build` → `<nom_dossier>.xlsx` hiérarchique.
8. Bouton « Ouvrir le dossier de résultats » activé.

## Choix de design

### Fonctions d'analyse copiées telles quelles de `voltapeakApp`

`SWVFileReader`, `SavitzkyGolay`, `SignalProcessing`, `WhittakerASPLS` et
le cœur de `VoltammetryData` sont importés sans modification depuis
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp) (seul ajout :
conformance `Sendable` requise pour `TaskGroup`). La parité numérique
avec la référence Python en découle automatiquement (cf.
[VALIDATION.md](VALIDATION.md)).

### `processOne` sans écriture disque

Le calcul (lecture + 7 étapes) est **pure compute** : il retourne un
`BatchFileResult` Sendable contenant toutes les données nécessaires aux
exports. Les écritures (PNG, CSV, XLSX par-fichier) sont déléguées au
ViewModel sur le MainActor. Avantages :

- Le `TaskGroup` parallélise du calcul, pas d'I/O concurrent.
- `ImageRenderer` (MainActor) peut fonctionner sans hop supplémentaire.
- Les échecs d'écriture sont logués en rouge dans la GUI sans bloquer
  l'analyse des fichiers restants.

### `ProcessedSignals` pour éviter le retri

Le tri par potentiel (`O(n log n)`) est fait **une seule fois** dans
`processOne` ; les trois vecteurs résultats (`potentials`, signe inversé,
signe original) sont attachés au résultat. Les exports réutilisent ces
vecteurs sans relancer ni tri ni inversion.

### Export `.xlsx` sans dépendance

`XLSXBoilerplate` + `ZIPStore` (~140 lignes au total) construisent :

1. Les 5 fichiers XML OOXML minimaux (`[Content_Types].xml`, `_rels/.rels`,
   `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`,
   `xl/worksheets/sheet1.xml`)
2. Un conteneur ZIP store-only (compression method = 0)
3. CRC32 PKZIP (polynôme inversé `0xEDB88320`)

### App Sandbox désactivé

L'App Sandbox est désactivé dans `voltapeak_loops.xcodeproj`, comme dans
`voltapeakApp`. L'app peut donc lire le dossier d'entrée et écrire son
voisin `<dossier> (results)/` sans demander de permission à l'utilisateur.
Signature ad-hoc locale (`CODE_SIGN_IDENTITY="-"`) suffisante pour la CI
et l'usage interne.

## Compatibilité

- **macOS 26.1+** — exigé pour aligner sur `voltapeakApp` et son framework
  `Charts`.
- **Xcode 26+** pour builder (le projet utilise
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`).
- **Architectures** : Universal (Intel x86_64 + Apple Silicon arm64).
- **App Sandbox** désactivé.

## Hors-scope (volontairement)

- Pas de tests unitaires (les fonctions d'analyse sont déjà validées dans
  [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) ; la
  validation propre au batch est documentée dans
  [VALIDATION.md](VALIDATION.md)).
- Pas de zoom/pan sur les PNG (rendu figé par fichier).
- Pas de prévisualisation in-app du graphique (l'aperçu individuel se
  fait via `voltapeakApp` sur un fichier donné).
- Pas de configuration des paramètres scientifiques via UI
  (`lam = 1e3·n²`, etc., hardcodés pour parité `voltapeakApp`).
- Pas d'agrégation multi-électrodes "à plat" — voir
  [`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp)
  pour ce cas d'usage.
