# Changelog

Toutes les modifications notables de `voltapeak_loopsApp` sont listées
ici. Le format suit
[Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la
numérotation respecte
[Semantic Versioning](https://semver.org/lang/fr/).

Pour le contexte famille `voltapeak*`, voir les CHANGELOG des dépôts
frères :
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp/blob/main/CHANGELOG.md),
[`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp/blob/main/CHANGELOG.md).

## [1.0.0] — 2026-05-13 — Portage initial du script Python en application macOS native

Première release de `voltapeak_loopsApp` : conversion Swift macOS native
de [`voltapeak_loops`](https://github.com/scadinot/voltapeak_loops)
(Python). Les fonctions d'analyse sont **reprises à l'identique** de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp), version déjà
validée bit-exact à la 6ᵉ décimale contre la référence Python ; le
rendu PNG est calqué sur celui de
[`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp).

### Ajouté

- **Application macOS SwiftUI batch** : sélecteur de dossier, options de
  lecture, mode multi-thread ou séquentiel, barre de progression,
  journal en temps réel, bouton « Ouvrir le dossier de résultats ».
- **Parsing automatique** des deux formats de noms de fichiers (regex
  case-insensitive identiques au Python) :
  - `loops` — `*_XX_SWV_CYY_loopZZ.txt`
  - `dosage` — `ZZ_<concentration>_XX_SWV_CYY.txt`
- **Pipeline d'analyse par fichier** : lecture latin-1 →
  tri/inversion → Savitzky-Golay (`window=11, order=2`, scipy-exact) →
  détection pic (margin=10 %, slope filter) → baseline asPLS Zhang 2020
  (`lam=1e3·n²`, exclusion `±3 %` autour du pic) → signal corrigé →
  re-détection du pic. Fonctions **reprises à l'identique** de
  `scadinot/voltapeakApp` (déjà validées bit-exact contre Python
  là-bas).
- **Orchestration concurrente** via `TaskGroup` : un `Task` par
  fichier, parallélisme natif sur tous les cœurs, mode séquentiel
  disponible pour le débogage.
- **Classeur Excel agrégé** : un onglet hiérarchique
  **Canal / Variante / Mesure**, une ligne par itération (loops) ou par
  concentration (dosage), tri numérique préservant l'ordre
  expérimental, fusions de cellules sur les deux premières lignes
  d'en-tête, refus des dossiers à formats mixtes.
- **Exports optionnels par fichier** :
  - PNG du graphique via SwiftUI `Chart` + `ImageRenderer` (échelle
    `3.0`, ≈ 3000×1800 px, palette matplotlib **tab10**), calqué sur
    [`scadinot/voltapeak_batchApp/voltapeak_batch/ChartPNGRenderer.swift`](https://github.com/scadinot/voltapeak_batchApp/blob/main/voltapeak_batch/ChartPNGRenderer.swift).
  - CSV ou XLSX du dataframe nettoyé (signe original du courant
    préservé).
  - Échecs d'écriture logués en rouge dans la GUI sans bloquer la
    suite.
- **Export OOXML autonome** : `XLSXBoilerplate` + `ZIPStore`
  (≈ 140 lignes au total), aucune dépendance tierce.
- **CI GitHub Actions** :
  - `build-artifact.yml` : archive un `.app` non signé sur push `main`,
    publie comme artifact.
  - `release.yml` : sur tag `v*` ou `[0-9]*`, archive + `ditto` zip +
    création de release GitHub avec asset attaché.
  - Les deux workflows : runner `macos-26`, signature ad-hoc, détection
    auto du scheme via
    `xcodebuild -list -project voltapeak_loops.xcodeproj -json`.
- **Documentation complète** : `README`, `ARCHITECTURE`, `ALGORITHMS`,
  `VALIDATION`, `DEVELOPMENT`, `DISTRIBUTION`, `CHANGELOG`.

### Choix de conception

- **`LoopsBatchProcessor.processOne` pur compute** : aucune écriture
  disque, retourne `BatchFileResult` Sendable. Les exports par-fichier
  sont délégués au ViewModel sur le `@MainActor` (contrainte
  `ImageRenderer`).
- **`ProcessedSignals` cache** : tri par potentiel fait **une seule
  fois** par fichier, les trois vecteurs (potentiels, courants
  inversés, courants signe original) sont attachés au résultat — pas de
  retri côté ViewModel.
- **Préparation disque hors MainActor** : `cleanOutputFolder` +
  `enumerateInputFiles` exécutés sur `Task.detached`.
- **Pas de `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** dans le
  pbxproj : les compute namespaces (`SavitzkyGolay`, `WhittakerASPLS`,
  etc.) restent nonisolated par défaut, donc appelables depuis
  `TaskGroup` sans hop d'acteur.
- **App Sandbox désactivé** : lecture/écriture libre du dossier de
  travail, comme `voltapeakApp`. Signature ad-hoc
  (`CODE_SIGN_IDENTITY="-"`).

### Compatibilité

- macOS 26.1+ requis.
- Xcode 26+ pour builder.
- Universal binary (Intel + Apple Silicon).

### Notes de validation

Les fonctions d'analyse (`SWVFileReader`, `SavitzkyGolay`,
`SignalProcessing`, `WhittakerASPLS`, `VoltammetryData`) sont **reprises
à l'identique** de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp) (à
l'enrichissement `Sendable` près), version déjà validée à la 6ᵉ
décimale par rapport à `scipy` / `pybaselines` — cf.
[`voltapeakApp/VALIDATION.md`](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md).
Voir [VALIDATION.md](VALIDATION.md) pour la procédure de validation
propre aux dossiers loops/dosage (parsing, parallélisme, structure
XLSX, gestion d'erreurs).

### Crédits

- Script Python source :
  [`scadinot/voltapeak_loops`](https://github.com/scadinot/voltapeak_loops).
- App macOS mono-fichier de référence pour les fonctions d'analyse :
  [`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp).
- App macOS batch (autre lot) inspirant le rendu PNG :
  [`scadinot/voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp).
- Auteur : GROUPE TRACE.
