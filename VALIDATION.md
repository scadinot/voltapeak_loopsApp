# Validation

Ce document décrit la méthodologie utilisée pour valider que
`voltapeak_loopsApp` produit les bons résultats, en deux temps :

1. **Parité numérique avec voltapeakApp** — garantie structurelle, les
   fonctions d'analyse étant reprises à l'identique.
2. **Validation propre au batch** — spécifique à cette app : parsing
   loops/dosage, parallélisme, agrégation XLSX hiérarchique, gestion
   d'erreurs.

## 1. Parité numérique avec voltapeakApp (et donc Python)

Les cinq fichiers suivants sont **identiques byte-pour-byte** à ceux de
[`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp), à
l'enrichissement `Sendable` près :

| Fichier | Rôle |
|---|---|
| `SavitzkyGolay.swift` | Filtre Savitzky-Golay scipy-exact |
| `WhittakerASPLS.swift` | asPLS Zhang 2020 |
| `SignalProcessing.swift` | Détection de pic + gradient numpy |
| `SWVFileReader.swift` | Lecture/parse `.txt` SWV |
| `VoltammetryData.swift` | Modèles de données |

La validation bit-exact (à la 6ᵉ décimale) contre la référence Python
(`scipy`, `pybaselines`) a été réalisée dans `voltapeakApp` et est
documentée ici :
[voltapeakApp/VALIDATION.md](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md).

Cette validation n'est **pas rejouée** ici. Pour la vérifier en pratique :

1. Choisir un fichier SWV de test.
2. L'ouvrir dans `voltapeakApp` → noter le pic affiché.
3. Le placer seul dans un dossier et lancer l'app `voltapeak_loops`
   (scheme du repo `voltapeak_loopsApp`) dessus.
4. Ouvrir le `<dossier>.xlsx` produit : le pic dans l'unique ligne doit
   être identique à celui affiché par `voltapeakApp` (mêmes décimales).

Toute divergence indiquerait une régression dans la copie des fichiers
d'analyse — à corriger immédiatement (`diff` direct des `.swift` avec
`voltapeakApp`).

## 2. Validation propre au batch

### (a) Parsing des noms de fichiers

`FileNameParser.parse(_:)` est testé manuellement sur une matrice de cas :

| Cas | Entrée | Résultat attendu |
|---|---|---|
| loops valide | `BT16Mb-T16TAC_05_SWV_C09_loop3.txt` | `.loops`, variante=05, canal=C09, loop=3 |
| loops casse mixte | `bt16mb_05_swv_c09_loop3.TXT` | id. (regex `caseInsensitive`) |
| dosage valide | `10_250nm_01_SWV_C05.txt` | `.dosage`, ordre=10, concentration=250nm, variante=01, canal=C05 |
| dosage avec deux digits ordre | `01_blank_01_SWV_C05.txt` | id., ordre=1, concentration=blank |
| non reconnu | `random.txt` | `nil` → fichier `.skipped` dans le batch |
| non reconnu | `_SWV_C09_loop3.txt` (manque variante) | `nil` |

### (b) Cohérence multi-thread vs séquentiel

Lancer **deux fois** le même dossier d'entrée :
- une fois en mode multi-thread (case « Multi-thread » cochée),
- une fois en mode séquentiel.

Les deux `<dossier>.xlsx` produits doivent être **identiques** (mêmes
valeurs de pic dans toutes les cellules, même ordre de lignes et
colonnes), seul le temps écoulé affiché dans le journal diffère. Si ce
n'est pas le cas, c'est le signe d'un data-race — à corriger.

Le pipeline a été conçu pour être **déterministe** : `processOne` est
pur compute, le tri par potentiel est fait à l'intérieur de la tâche, et
l'agrégation finale trie les clés (canal, variante) avant génération
XLSX. L'ordre dans lequel les tâches du `TaskGroup` se terminent n'a
aucun impact sur le résultat **tant que le dossier ne contient pas de
doublons** (même `iterationKey` + même `(canal, variante)`). En présence
de doublons, l'agrégation conserve la **première occurrence reçue** par
le ViewModel : en multi-thread, « première » dépend alors de l'ordre de
complétion des tâches, et la sortie peut différer entre multi-thread et
séquentiel. Ce cas est signalé par un avertissement rouge dans le
journal (cf. § 2.e « Doublons ») ; pour une reproductibilité stricte sur
un dossier susceptible d'en contenir, utiliser le mode séquentiel.

### (c) Structure du classeur agrégé

Ouvrir un `<dossier>.xlsx` produit dans Excel / Numbers / LibreOffice et
vérifier :

| Élément | Attendu |
|---|---|
| Ligne 1 | Cellule A1 vide, puis canal (`Cxx`) sur la cellule de gauche de chaque paire |
| Ligne 2 | Cellule A2 vide, puis variante (`05`) sur la cellule de gauche de chaque paire |
| Ligne 3 | `Itération` (loops) ou `Concentration` (dosage) en A3, puis alternance `Tension (V)` / `Courant (A)` |
| Fusions | Pour chaque paire de colonnes, les cellules de ligne 1 ET ligne 2 doivent être **fusionnées** sur 2 colonnes |
| Tri colonnes | (canal numérique, variante numérique) croissant |
| Tri lignes | `iterationKey` numérique croissant (loop0, loop1, … ou 1, 2, … pour dosage) |
| Valeurs | Chaque cellule (tension, courant) doit matcher le pic du fichier correspondant tel que lu dans le journal |

### (d) Refus dossiers à formats mixtes

Placer dans un même dossier :
- un fichier loops (`*_SWV_C09_loop3.txt`),
- un fichier dosage (`10_250nm_01_SWV_C05.txt`).

Lancer l'analyse. Résultat attendu :
- Les deux fichiers sont analysés individuellement (PNG/CSV/XLSX
  par-fichier produits si activés).
- **Le `<dossier>.xlsx` final n'est PAS écrit**.
- Le journal affiche un message rouge : *« Erreur : le dossier mélange
  plusieurs formats de fichiers (loops, dosage). Export annulé pour
  préserver la cohérence du tableau récapitulatif. »*.
- Le bouton « Ouvrir le dossier de résultats » reste désactivé.

### (e) Cas d'erreur

| Scénario | Comportement attendu |
|---|---|
| Dossier d'entrée inexistant / pas un répertoire | Erreur rouge dans le journal, `isRunning = false`, pas de tentative d'écriture |
| Dossier d'entrée vide (aucun `.txt`) | Erreur rouge, terminaison propre |
| Dossier de sortie non créable (permission denied) | Erreur rouge, terminaison propre (grâce à `cleanOutputFolder` `throws`) |
| Fichier `.txt` avec entête uniquement (< 5 points) | `status = .error("Moins de 5 points de données.")`, ligne rouge dans le journal, autres fichiers continuent |
| Doublons (canal, variante, itération) | Avertissement rouge, **première occurrence reçue** conservée dans le classeur — l'ordre de réception dépend du mode (cf. § 2.b) |
| Export PNG/CSV/XLSX qui échoue (dossier résultats en lecture seule pendant l'exécution) | Avertissement rouge par fichier, l'analyse continue, le classeur agrégé final n'est pas affecté |

### (f) Performance approximative

Sur un MacBook M1 Pro, dossier de 24 fichiers SWV (n=85 points chacun) :

| Mode | Temps écoulé |
|---|---|
| Séquentiel | ≈ 1.4 s |
| Multi-thread (8 cœurs) | ≈ 0.5 s |

Le rendu PNG (`ImageRenderer` sur MainActor) représente ≈50 ms par
fichier ; activé sur tous les fichiers, il devient le facteur dominant
pour les gros lots.

## 3. Comment reproduire la validation

1. Cloner `voltapeak_loopsApp`.
2. Ouvrir dans Xcode 26+, lancer (⌘R).
3. Préparer trois dossiers de fixtures :
   - **loops-pur** : 6+ fichiers `*_XX_SWV_CYY_loopZZ.txt` couvrant
     plusieurs canaux et variantes ;
   - **dosage-pur** : 6+ fichiers `ZZ_concentration_XX_SWV_CYY.txt` ;
   - **mixte** : 1 fichier loops + 1 fichier dosage.
4. Lancer les trois dossiers tour à tour, en mode multi-thread puis
   séquentiel.
5. Vérifier les six points (a)-(f) ci-dessus.
6. Optionnel : comparer un pic individuel entre `voltapeak_loopsApp` et
   `voltapeakApp` sur le même fichier (cf. § 1).

## État de la validation

✅ Parité numérique avec `voltapeakApp` (donc Python) : structurellement
garantie par la reprise byte-pour-byte des fichiers d'analyse — cf.
[voltapeakApp/VALIDATION.md](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md).

✅ Parsing loops/dosage : couvert par les regex case-insensitive et la
conversion stricte de l'`iterationKey`.

✅ Agrégation XLSX : structure 3 lignes d'en-tête + fusions + tri validée
manuellement sur dossiers de fixtures.

✅ Cohérence parallèle vs séquentiel **en l'absence de doublons** :
`processOne` pur compute, agrégation finale triée → l'ordre de
complétion des tâches n'a pas d'impact sur la sortie. En présence de
doublons, voir § 2.b — le mode séquentiel est recommandé pour la
reproductibilité stricte.

⚠️ Tests unitaires automatisés : absents (dette technique consciente,
voir [DEVELOPMENT.md § Tests](DEVELOPMENT.md#tests) pour pistes).
