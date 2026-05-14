# voltapeak_loopsApp — analyse SWV batch loops/dosage (macOS / Swift)

**Application macOS native (Swift / SwiftUI) d'analyse par lot de fichiers
de voltampérométrie à onde carrée (SWV) avec agrégation hiérarchique
loops/dosage.**

`voltapeak_loopsApp` est la conversion Swift macOS du script Python
[`scadinot/voltapeak_loops`](https://github.com/scadinot/voltapeak_loops).
Les algorithmes d'analyse sont repris sans modification de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp), validé
bit-exact à la 6ᵉ décimale contre la référence Python ; le rendu PNG par
fichier est calqué sur celui de
[`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp).

## Famille de projets

| Repo | Rôle |
|---|---|
| [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) | **App GUI mono-fichier**, référence canonique des algorithmes |
| [`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp) | App batch multi-fichiers avec **agrégation multi-électrodes** |
| [`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp) | App batch multi-fichiers avec **agrégation loops/dosage hiérarchique** *(ce repo)* |

## Table des matières

1. [À quoi sert cet outil ?](#à-quoi-sert-cet-outil-)
2. [Fonctionnalités](#fonctionnalités)
3. [Prérequis](#prérequis)
4. [Build et lancement](#build-et-lancement)
5. [Architecture concurrence](#architecture-concurrence)
6. [Paramètres de l'algorithme](#paramètres-de-lalgorithme)
7. [Documentation complémentaire](#documentation-complémentaire)
8. [Crédits & licence](#crédits--licence)

## À quoi sert cet outil ?

Lors d'expériences de voltampérométrie à onde carrée, on mesure un courant
en fonction du potentiel. Le signal utile — un pic centré sur le potentiel
caractéristique de l'espèce électroactive — est superposé à une **ligne de
base** lentement variable. L'analyse quantitative nécessite donc de
soustraire cette ligne de base pour ne garder que le pic.

`voltapeak_loopsApp` automatise ce traitement pour des **campagnes
multi-itérations (loops) ou de dosage** : chaque dossier d'entrée contient
des dizaines ou centaines de fichiers `.txt` nommés selon l'une des deux
conventions reconnues (loops ou dosage). L'outil produit un graphique PNG
par fichier (300 dpi), éventuellement un CSV / XLSX par fichier, et un
**classeur Excel agrégé hiérarchique** organisé sur trois niveaux **Canal
/ Variante / Tension–Courant**, avec une ligne par itération (loops) ou
par concentration (dosage).

## Fonctionnalités

- Sélection d'un dossier d'entrée contenant des fichiers `.txt`.
- Détection automatique de deux formats de nommage (regex identiques au Python) :
  - **loops** — `*_XX_SWV_CYY_loopZZ.txt`
  - **dosage** — `ZZ_<concentration>_XX_SWV_CYY.txt`
- Paramètres de lecture configurables : séparateur de colonnes
  (*Tabulation* / *Virgule* / *Point-virgule* / *Espace*) et séparateur
  décimal (*Point* / *Virgule*).
- Mode multi-thread (un `Task` par fichier via `TaskGroup`, parallélisme
  natif sur tous les cœurs) ou séquentiel pour le débogage.
- Exports optionnels par fichier : `.png` du graphique, `.csv` ou `.xlsx`
  des données nettoyées. Les échecs d'écriture sont logués en rouge dans
  la GUI sans bloquer l'analyse.
- Classeur Excel agrégé final, hiérarchique sur trois niveaux **Canal /
  Variante / Tension–Courant**, une ligne par itération (loops) ou par
  concentration (dosage), tri numérique préservant l'ordre expérimental,
  refus des dossiers à formats mixtes.
- Journal en temps réel + barre de progression + bouton « Ouvrir le
  dossier de résultats ».

## Prérequis

- **macOS 26.1** ou supérieur (déploiement minimum)
- **Xcode 26** ou supérieur
- Aucune dépendance externe — tous les algorithmes scientifiques sont
  implémentés en pur Swift (cf. [ARCHITECTURE.md](ARCHITECTURE.md)).

## Build et lancement

### Depuis Xcode

```bash
git clone https://github.com/scadinot/voltapeak_loopsApp.git
cd voltapeak_loopsApp
open voltapeak_loops.xcodeproj
# ⌘R pour lancer
```

L'App Sandbox est désactivé afin de pouvoir lire/écrire dans un dossier
arbitraire choisi par l'utilisateur, comme dans `voltapeakApp`.

### Depuis la ligne de commande

```bash
xcodebuild -project voltapeak_loops.xcodeproj \
           -scheme voltapeak_loops \
           -configuration Release \
           build
```

## Architecture concurrence

- `VoltapeakLoopsViewModel` est `@MainActor @Observable`.
- `LoopsBatchProcessor.processOne(...)` est nonisolated par défaut (le
  pbxproj **ne pose pas** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) ;
  il s'exécute donc librement sur les Tasks du `TaskGroup`.
- Les exports par fichier (PNG via `ChartPNGRenderer` qui nécessite
  `ImageRenderer` sur le MainActor, CSV/XLSX du dataframe nettoyé) sont
  exécutés côté ViewModel dès qu'un résultat de calcul est reçu du
  TaskGroup.

Détails dans [ARCHITECTURE.md](ARCHITECTURE.md).

## Paramètres de l'algorithme

Identiques à la version Python et aux autres apps de la famille — détails
mathématiques dans [ALGORITHMS.md](ALGORITHMS.md) :

| Paramètre | Valeur | Rôle |
|---|---|---|
| `windowLength` (Savitzky-Golay) | **11** | largeur de la fenêtre de lissage |
| `polynomialOrder` (Savitzky-Golay) | **2** | ordre du polynôme local |
| `marginRatio` | **0,10** | fraction des bords exclue pour la détection de pic |
| `maxSlope` | **500** (`nil` pour désactiver) | plafond de pente `|dI/dV|` |
| `exclusionWidthRatio` | **0,03** | demi-largeur d'exclusion asPLS (fraction de l'étendue) |
| `lambdaFactor` | **1 000** | rigidité de la baseline : λ effectif = `lambdaFactor · n²` |
| `diffOrder` (asPLS) | **2** | ordre de la différence pénalisée |
| `tol` (asPLS) | **1e-2** | tolérance de convergence (sur les poids) |
| `maxIter` (asPLS) | **25** | nombre maximal d'itérations |
| `asymmetricCoef` (asPLS) | **0,5** | coefficient `k` du papier asPLS |

## Documentation complémentaire

| Document | Contenu |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Structure du projet, pipeline, fichiers Swift, modèles de données, concurrence |
| [ALGORITHMS.md](ALGORITHMS.md) | Algorithmes numériques (Savitzky-Golay, détection de pic, asPLS Zhang 2020) |
| [VALIDATION.md](VALIDATION.md) | Méthodologie de validation, parité avec la référence Python |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Guide développeur : build, debug, conventions, ajout de features |
| [DISTRIBUTION.md](DISTRIBUTION.md) | Signature, notarisation Apple, création de DMG, CI |
| [CHANGELOG.md](CHANGELOG.md) | Historique des versions (Keep-a-Changelog) |

## Crédits & licence

Algorithmes — portages directs des bibliothèques Python de référence :

- **scipy** (`scipy.signal.savgol_filter`) — lissage Savitzky-Golay
- **pybaselines** (`pybaselines.whittaker.aspls`) — baseline asPLS Zhang 2020
- **numpy** (`np.gradient`) — gradient 2ᵉ ordre non-uniforme
- **matplotlib** — palette **tab10** pour parité visuelle

Sources d'inspiration :

- [`scadinot/voltapeak_loops`](https://github.com/scadinot/voltapeak_loops) — script Python source
- [`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp) — référence canonique des fonctions d'analyse, validée bit-exact
- [`scadinot/voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp) — application batch sœur, source du rendu PNG par fichier

Références bibliographiques détaillées dans [ALGORITHMS.md](ALGORITHMS.md).

Auteur : GROUPE TRACE. © 2026 Stéphane Cadinot.
