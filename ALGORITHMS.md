# Algorithmes numériques

Ce document détaille les algorithmes mathématiques utilisés dans
`voltapeak_loopsApp` et leur correspondance avec la référence Python
(`scipy`, `numpy`, `pybaselines`).

Le pipeline d'analyse (sections 1-7) est strictement **identique** à
celui de [`voltapeakApp`](https://github.com/scadinot/voltapeakApp),
validé bit-exact à la 6ᵉ décimale contre la référence Python. Les
paramètres sont hérités de
[`voltapeak_loops`](https://github.com/scadinot/voltapeak_loops)
(Python). Les sections 8 et 9 décrivent l'orchestration propre aux
dossiers loops/dosage : parsing, exécution parallèle, agrégation XLSX
hiérarchique et rendu PNG par fichier.

La validation propre au batch (parité multi-thread vs séquentiel,
parsing loops/dosage, structure XLSX) est documentée dans
[VALIDATION.md](VALIDATION.md).

## 1. Lecture du fichier SWV

**Implémentation :** `SWVFileReader.readFile(at:config:)`

- **Encodage** : ISO Latin-1 (les potentiostats francophones produisent des entêtes avec accents)
- **Format attendu** :
  ```
  [Entête — 1 ligne, ignorée]
  potentiel<sep>courant
  potentiel<sep>courant
  ...
  ```
- **Séparateurs configurables** : tabulation, virgule, point-virgule, espace
- **Décimale configurable** : point ou virgule
- **Filtrage anticipé** : les lignes à courant nul sont écartées dès la lecture. L'équivalence avec la référence Python tient au fait que celle-ci applique le même filtre, plus tard, dans `processData` ; les opérations en aval (tri, indices, taille `n` utilisée dans `lam = 1e3·n²`, marges `floor(n × marginRatio)`, gradient non-uniforme) ne dépendent que de l'ensemble final des points retenus, pas de l'étape où le filtre est appliqué.

## 2. Traitement des données

**Implémentation :** `SWVFileReader.processData(_:)`, inliné dans
`LoopsBatchProcessor.processOne(...)` pour le pipeline batch.

Trois opérations en chaîne :

1. **Tri** par potentiel croissant (le fichier peut être en scan retour)
2. **Inversion de signe** du courant : `signal = -current`
   - Convention SWV cathodique : le courant mesuré est négatif
   - L'inversion permet à `argmax` de trouver le sommet du pic comme un maximum
3. **Conservation parallèle du signe original** dans
   `ProcessedSignals.cleanedSignedCurrents`, pour les exports par fichier
   (équivalent `cleaned_df` du Python).

Sortie : `(potentials: [Double], processedCurrents: [Double], cleanedSignedCurrents: [Double])`,
tableaux alignés et triés. Le tri est fait **une seule fois** par fichier et
les trois vecteurs sont attachés au `BatchFileResult` pour être réutilisés
sans retri par les exports.

## 3. Lissage Savitzky-Golay

**Implémentation :** `SavitzkyGolay.filter(_:windowLength:polynomialOrder:)`

Équivalent strict à `scipy.signal.savgol_filter(signal, 11, 2, mode='interp')`.

### Principe

Pour chaque point, on ajuste localement un polynôme de degré 2 (parabole) sur
une fenêtre de 11 points et on évalue ce polynôme à la position centrale. Cela
atténue le bruit haute fréquence tout en préservant la position et l'amplitude
du pic.

### Coefficients centraux (mode `dot`, position 5, symétrique)

Pour les points où une fenêtre complète est disponible (indices `5..n-6`), la
convolution centrée utilise :

```
coeffs = [−36, 9, 44, 69, 84, 89, 84, 69, 44, 9, −36] / 429
```

Somme = `429 / 429 = 1` (préservation des constantes).

### Bords : mode `'interp'`

Aux bords du signal (5 premiers et 5 derniers points), scipy mode `'interp'`
n'extrapole pas mais ajuste un polynôme de degré 2 sur les 11 premiers (resp.
derniers) points et évalue ce polynôme à la position du point cherché.

Cela donne **10 jeux de coefficients spécifiques** pour `pos ∈ {0, 1, 2, 3, 4, 6, 7, 8, 9, 10}`
— obtenus avec `scipy.signal.savgol_coeffs(11, 2, pos=p, use='dot')` et codés
en dur dans `SavitzkyGolay.boundaryCoeffs`.

### Référence

Savitzky, A., & Golay, M. J. E. (1964). *Smoothing and Differentiation of Data
by Simplified Least Squares Procedures*. **Analytical Chemistry**, 36(8),
1627-1639.

## 4. Détection de pic

**Implémentation :** `SignalProcessing.detectPeak(signal:potentials:marginRatio:maxSlope:)`

Appliquée deux fois dans le pipeline :

1. sur le signal lissé pour positionner la zone d'exclusion asPLS,
2. sur le signal corrigé pour la valeur finale retenue.

### Étape 1 : exclusion des bords

`margin = floor(n × marginRatio)` (avec `marginRatio = 0.10` par défaut, soit 10 %)

La recherche du pic se fait uniquement dans `signal[margin ..< n-margin]`. Cela
évite de détecter les artefacts de démarrage/arrêt du potentiostat.

### Étape 2 : filtre de pente (optionnel)

`maxSlope` est de type `Double?` ; le pipeline le fixe à `500` par défaut,
mais passer `nil` désactive entièrement cette étape (cas couvert par les
tests). Quand il est fourni, on calcule le gradient numérique et on ne garde
comme candidats que les indices où `|gradient| < maxSlope`.

### Gradient numpy 2ᵉ ordre non-uniforme

`numpy.gradient(y, x)` utilise pour les pas non-uniformes (intérieur) :

```
hd = x[i] − x[i−1]                                 (pas gauche)
hs = x[i+1] − x[i]                                  (pas droite)
grad[i] = −hs / (hd·(hd+hs)) · y[i−1]
       + (hs − hd) / (hd·hs) · y[i]
       + hd / (hs·(hd+hs)) · y[i+1]
```

Aux bords : différence finie 1ᵉʳ ordre (`grad[0] = (y[1]−y[0])/(x[1]−x[0])`,
`grad[n−1]` symétrique).

Cette formulation est plus précise que la simple différence centrée
`(y[i+1]−y[i−1])/(x[i+1]−x[i−1])` quand les pas ne sont pas égaux.

### Étape 3 : argmax

Parmi les candidats (filtrés ou pas), `argmax(signal)` donne l'indice du
sommet. Si aucun candidat ne passe le filtre, le premier point de la zone de
recherche est retourné (repli défensif).

### Référence

Documentation numpy : `numpy.gradient` — *second order accurate central differences in the interior points*.

## 5. Estimation de baseline asPLS (Zhang 2020)

**Implémentation :** `WhittakerASPLS.aspls(y:lam:diffOrder:maxIter:tol:weights:alpha:asymmetricCoef:)`

Équivalent strict à `pybaselines.whittaker.aspls`.

### Principe

L'asPLS (**a**daptive **s**moothness **p**enalized **l**east **s**quares)
ajuste une courbe lisse sous le signal en minimisant :

```
Σᵢ wᵢ · (yᵢ − zᵢ)² + λ · z^T · D^T · diag(α) · D · z
```

où :
- `y` est le signal (lissé) d'entrée
- `z` est la baseline cherchée
- `w` est le vecteur des poids (chaque point pondéré séparément)
- `D` matrice de différences finies d'ordre 2 (pénalise la courbure)
- `α` vecteur de pénalité adaptative locale (clé de l'asPLS)
- `λ` paramètre de lissage global

### Système linéaire résolu à chaque itération

En notant `W = diag(w)`, la condition de stationnarité s'écrit :

```
(W + λ · diag(α) · D^T·D) · z = W · y
```

⚠️ La matrice **n'est pas symétrique** à cause de `diag(α)` à gauche (et pas
`D^T·diag(α)·D` comme dans certaines présentations du papier). Cette forme
reproduit exactement `pybaselines` qui multiplie le penalty banded par alpha
par broadcast. Le solveur Swift utilise une élimination de Gauss avec
pivotage partiel (`solveFallback`), pas une décomposition de Cholesky.

`D^T·D` est pentadiagonal (différences d'ordre 2) ; il est construit
directement par un helper interne (`buildDTD(n:diffOrder:)` dans
`WhittakerASPLS`, non exposé publiquement).

### Mise à jour itérative

À chaque itération :

1. **Solve** : `z = solveFallback(A, w·y)` où `A = W + λ·diag(α)·D^T·D`
2. **Résidus** : `d = y − z`
3. **Sortie anticipée** : si `card(d < 0) < 2`, on arrête (comme `pybaselines`)
4. **Mise à jour des poids** (sigmoïde) :
   ```
   neg = d[d < 0]
   σ = std(neg, ddof=1)
   w_new[i] = expit(−(k/σ) · (d[i] − σ))  =  1 / (1 + exp((k/σ)·(d[i] − σ)))
   ```
   où `k = asymmetric_coef = 0.5` (défaut pybaselines). Si `σ = 0`, on arrête.
5. **Convergence** : si `Σ|w − w_new| / Σ|w_new| < tol`, on s'arrête.
6. **Mise à jour de α** :
   ```
   α[i] = |d[i]| / max(|d|)
   ```
   Les points à fort résidu (pic) reçoivent un α proche de 1 → pénalité forte
   → la baseline reste lisse à cet endroit. Les points à faible résidu (zone
   baseline) ont α proche de 0 → pénalité faible → la baseline suit le
   signal.

### Paramètres utilisés

| Paramètre | Valeur | Origine |
|---|---|---|
| `lam` (lissage) | `1e3 × n²` | Mise à l'échelle empirique du Python (voltapeak.py) |
| `asymmetric_coef` (k) | `0.5` | Défaut pybaselines |
| `tol` | `1e-2` | Voltapeak Python |
| `max_iter` | `25` | Voltapeak Python |
| `diff_order` | `2` | Défaut |

### Zone d'exclusion autour du pic

Avant l'appel à `aspls`, `LoopsBatchProcessor.processOne` construit un
vecteur de poids initiaux :

```swift
weights = [Double](repeating: 1.0, count: n)
exclusionWidth = 0.03 × (potentials.last − potentials.first)
for i où potentials[i] ∈ [xPeak − exclusionWidth, xPeak + exclusionWidth]:
    weights[i] = 0.001
```

Cela évite que la baseline ne « remonte » vers le sommet du pic dès la
première itération. Le sigmoid update prend ensuite le relais pour maintenir
les poids bas dans cette zone.

### Référence

Zhang, F., Tang, X., Tong, A., Wang, B., & Wang, J. (2020). *Baseline
correction for infrared spectra using adaptive smoothness parameter penalized
least squares method*. **Spectroscopy Letters**, 53(3), 222-233.

Implémentation Python de référence : [`pybaselines.whittaker.aspls`](https://github.com/derb12/pybaselines).

### asPLS vs asLS — différence essentielle

| Aspect | asLS (Eilers 2005) | asPLS (Zhang 2020) |
|---|---|---|
| Pénalité | constante `λ` partout | adaptative `λ · α[i]` |
| Poids | binaire : `p` si `y > z`, `1−p` sinon | sigmoïde basée sur `std(résidus négatifs)` |
| Convergence | sur la baseline | sur les poids |
| Paramètre clé | `p` (asymétrie, ~0.01) | `k` (asymmetric_coef, 0.5) |

Une version précédente du port Swift implémentait **asLS** (par erreur). Le
résultat divergeait de ~22 % du Python. Le port actuel reproduit asPLS
exactement.

## 6. Signal corrigé

```
corrected[i] = smoothed[i] − baseline[i]
```

Opération élément par élément, triviale.

## 7. Re-détection du pic

Le pic final est obtenu en réappliquant `detectPeak` sur le signal corrigé. La
position du pic peut légèrement changer par rapport à la détection brute
(étape 4) — le signal corrigé étant plus « net » sans la dérive de la
baseline.

C'est cette deuxième détection (potentiel + courant corrigé) qui est
retenue pour la ligne du classeur Excel agrégé final (§8).

## 8. Pipeline batch et agrégation

Spécifique à `voltapeak_loopsApp` :

### Enumération et parsing

`LoopsBatchProcessor.enumerateInputFiles` liste les `.txt` du dossier d'entrée
(tri alphabétique). `FileNameParser.parse` tente deux regex (case-insensitive) :

- **loops** : `.*?_([0-9]{2})_SWV_(C[0-9]{2})_loop([0-9]+)\.txt$`
- **dosage** : `^([0-9]+)_([^_]+)_([0-9]{2})_SWV_(C[0-9]{2})\.txt$`

Le format loops est testé en premier (plus restrictif), dosage sert de
fallback. Un fichier qui ne matche aucun des deux formats est marqué
`.skipped`.

### Exécution parallèle

`VoltapeakLoopsViewModel.run` exécute le pipeline (étapes 1-7) en parallèle via
`withTaskGroup`, un `Task` par fichier. Chaque tâche retourne un
`BatchFileResult` Sendable contenant l'analyse complète + les vecteurs triés
`ProcessedSignals`. Le ViewModel déclenche ensuite les exports par fichier
(PNG, CSV, XLSX) sur le MainActor car `ChartPNGRenderer` nécessite
`ImageRenderer` qui est `@MainActor`.

### Agrégation hiérarchique

Après avoir collecté tous les résultats, le ViewModel construit un dictionnaire
`(iterationLabel) -> Row` où chaque `Row.measurements` est un dictionnaire
`(canal, variante) -> (peakV, peakC)`. `AggregatedXLSXWriter.build` génère un
XLSX OOXML avec trois lignes d'en-tête (Canal, Variante, Tension/Courant)
fusionnées par paires de colonnes, tri canal puis variante en colonnes, tri
itération en lignes. Un dossier qui mélange formats loops + dosage est refusé
avec un message rouge dans le journal.

## 9. Rendu PNG par fichier

**Implémentation :** `ChartPNGRenderer.renderPNG(analysis:potentials:rawCurrents:to:)`

Calqué sur [`scadinot/voltapeak_batchApp/voltapeak_batch/ChartPNGRenderer.swift`](https://github.com/scadinot/voltapeak_batchApp/blob/main/voltapeak_batch/ChartPNGRenderer.swift) :

- Vue SwiftUI `Chart` offscreen contenant 4 `LineMark` (brut, lissé, baseline
  tiretée, corrigé), 1 `RuleMark` (ligne verticale au pic) et 1 `PointMark`
  (marqueur magenta).
- Palette matplotlib **tab10** : bleu (#1f77b4), orange (#ff7f0e), vert
  (#2ca02c), rouge (#d62728), magenta pour le pic.
- `ImageRenderer` avec `scale = 3.0` sur frame 1000×600 → PNG ≈ 3000×1800 px,
  équivalent matplotlib `dpi=300`.
- Encodage TIFF → `NSBitmapImageRep` → PNG via AppKit.

Le rendu est exécuté sur le `@MainActor` (contrainte `ImageRenderer`) ; c'est
pourquoi il n'est pas appelé depuis les `Task` de calcul mais depuis le
ViewModel après réception de chaque `BatchFileResult`.

## Pseudocode du pipeline complet pour un fichier

> Le pseudocode adopte la nomenclature Python/pybaselines (`lam`,
> `weights`, `max_iter`, `tol`, `k`) par souci de lisibilité ; la
> signature Swift correspondante est
> `WhittakerASPLS.aspls(y:lam:diffOrder:maxIter:tol:weights:alpha:asymmetricCoef:)`
> (cf. §5, où `k` désigne `asymmetric_coef` / `asymmetricCoef`).

```
read SWV file                          → raw points
sort by potential, build              → (potentials, processedCurrents inverted,
  ProcessedSignals                         cleanedSignedCurrents original)

smoothed = savgol_filter(processedCurrents, 11, 2, mode='interp')

(xPeak, _) = detectPeak(smoothed, potentials, margin=0.10, maxSlope=500)

weights = ones(n)
weights[ potentials ∈ [xPeak ± 0.03·range] ] = 0.001
baseline = aspls(smoothed, lam=1e3·n², weights=weights,
                 max_iter=25, tol=1e-2, k=0.5)

corrected = smoothed − baseline

(xFinal, yFinal) = detectPeak(corrected, potentials, margin=0.10, maxSlope=500)

return BatchFileResult(analysis, signals, peakV=xFinal, peakC=yFinal)
```

## Parité avec la version Python

Toutes les valeurs numériques (paramètres, seuils, ordres) sont
**strictement identiques** à la version Python source
([`voltapeak_loops`](https://github.com/scadinot/voltapeak_loops)). La
validation à la 6ᵉ décimale de l'implémentation `voltapeakApp`
([voltapeakApp/VALIDATION.md](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md))
s'applique directement puisque les fonctions sont reprises sans
modification.
