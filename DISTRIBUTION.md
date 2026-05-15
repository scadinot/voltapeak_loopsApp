# Distribution

Ce guide explique comment produire une version distribuable de
`voltapeak_loopsApp` (`.app`, `.zip`, `.dmg`). Trois options selon le
contexte : **CI automatisée**, **signature locale ad-hoc**, ou
**notarisation Apple**. Le canevas est identique entre les trois apps
de la famille `voltapeak*` ; voir
[`voltapeakApp/DISTRIBUTION.md`](https://github.com/scadinot/voltapeakApp/blob/main/DISTRIBUTION.md) et
[`voltapeak_batchApp/DISTRIBUTION.md`](https://github.com/scadinot/voltapeak_batchApp/blob/main/DISTRIBUTION.md).

## Prérequis communs

Dans Xcode, onglet **Signing & Capabilities** :

```
Team               : votre équipe Apple (pour notarisation seulement)
Bundle Identifier  : com.cadinot.voltapeak-loops

App Sandbox        : désactivé
```

Pour les versions distribuables, vérifier dans le pbxproj :

```
MARKETING_VERSION             = 1.0
CURRENT_PROJECT_VERSION       = 1
PRODUCT_BUNDLE_IDENTIFIER     = com.cadinot.voltapeak-loops
MACOSX_DEPLOYMENT_TARGET      = 26.1
```

Le projet est livré avec `CODE_SIGN_IDENTITY = "-"` (ad-hoc), suffisant
pour exécuter sur la machine de développement et pour les workflows CI.

---

## Option 0 — CI GitHub Actions (recommandé pour la diffusion habituelle)

Deux workflows committés à `.github/workflows/` :

### `build-artifact.yml`

Déclenché à chaque push sur `main` (ou manuellement via
`workflow_dispatch`), runner `macos-latest` :

1. Détecte le scheme par défaut via
   `xcodebuild -list -project voltapeak_loops.xcodeproj -json`.
2. Archive l'app avec signature ad-hoc (`CODE_SIGN_IDENTITY="-"`).
3. Upload du contenu de
   `build/voltapeak_loops.xcarchive/Products/Applications` comme
   artifact GitHub nommé d'après le scheme et le SHA :
   `${scheme}-unsigned-${github.sha}` (en pratique
   `voltapeak_loops-unsigned-<sha>`).

Utile pour le smoke-test continu : télécharger l'artifact, le
décompresser, lancer le `.app` sur un Mac de test.

### `release.yml`

Déclenché par un push de tag (`v*` ou `[0-9]*`), runner `macos-26` :

1. Archive l'app.
2. Empaquette via `ditto -c -k --keepParent` en
   `voltapeak_loops-<TAG>.zip`.
3. Crée (ou met à jour avec `--clobber`) la release GitHub
   correspondante, asset attaché, notes auto-générées.

```bash
# Publier une release v1.0
git tag -a v1.0 -m "first stable release"
git push origin v1.0
```

Le `.zip` produit contient un `.app` **non signé** (ad-hoc), donc soumis
au warning Gatekeeper au premier lancement (voir Option 1).

---

## Option 1 — Distribution locale ad-hoc (sans notarisation)

Pour usage personnel, prototype, ou diffusion au sein d'une équipe
restreinte.

### Étapes

1. **Archive** : `Product → Destination → Any Mac` puis `Product →
   Archive`.
2. **Export** dans Organizer : `Distribute App → Copy App → Next →
   choisir un dossier`.

Résultat : un fichier `voltapeak_loops.app`.

### Créer un ZIP

```bash
ditto -c -k --keepParent voltapeak_loops.app voltapeak_loops.zip
```

### Créer un DMG

```bash
hdiutil create -volname "voltapeak_loops" \
               -srcfolder voltapeak_loops.app \
               -ov -format UDZO \
               voltapeak_loops-1.0.dmg
```

### Limitation : warning au premier lancement

Sans notarisation, macOS affiche au premier lancement :

> *« voltapeak_loops ne peut pas être ouvert car il provient d'un
> développeur non identifié »*

L'utilisateur doit alors **clic droit → Ouvrir** puis confirmer dans la
boîte de dialogue. Les lancements suivants sont normaux.

---

## Option 2 — Distribution publique (avec notarisation Apple)

Pour diffusion large (site web, distribution à des partenaires externes,
etc.) sans warning au lancement.

### Prérequis additionnels

- Compte **Apple Developer Program** actif (99 €/an).
- Certificat **Developer ID Application** installé dans le Keychain.
- Hardened Runtime activé dans Signing & Capabilities :
  ```
  ✅ Hardened Runtime
  ```
- Profil de credentials `notarytool` créé une seule fois :
  ```bash
  xcrun notarytool store-credentials AC_PROFILE \
        --apple-id "<email>" \
        --team-id "<TEAM_ID>" \
        --password "<app-specific-password>"
  ```

### Étapes

1. **Archive** : `Product → Archive` (comme option 1).
2. **Distribute App** dans Organizer :
   - Choisir **« Developer ID »** (pas « Copy App »).
   - **Upload** pour notarisation (option par défaut).
   - Apple va signer + scanner + notariser (quelques minutes à quelques
     heures).
3. **Vérifier l'historique de notarisation** :
   ```bash
   xcrun notarytool history --keychain-profile "AC_PROFILE"
   ```
4. **Agrafer le ticket** sur le bundle :
   ```bash
   xcrun stapler staple voltapeak_loops.app
   ```
5. **Créer, signer, notariser et agrafer le DMG** (le DMG doit être
   notarisé séparément du `.app`) :
   ```bash
   hdiutil create -volname "voltapeak_loops" -srcfolder voltapeak_loops.app \
                  -ov -format UDZO voltapeak_loops-1.0.dmg
   codesign --force --options runtime --timestamp \
            --sign "Developer ID Application: <Votre nom> (<TEAM_ID>)" \
            voltapeak_loops-1.0.dmg
   xcrun notarytool submit voltapeak_loops-1.0.dmg \
         --keychain-profile "AC_PROFILE" --wait
   xcrun stapler staple voltapeak_loops-1.0.dmg
   ```

Résultat : `voltapeak_loops-1.0.dmg` notarisé, lancé sans warning sur
n'importe quel Mac.

---

## Vérifications post-build

```bash
# Signature
codesign -dv --verbose=4 voltapeak_loops.app

# Entitlements et hardened runtime
codesign -d --entitlements - voltapeak_loops.app

# Validation Gatekeeper (si notarisé)
spctl -a -vv -t install voltapeak_loops.app
```

---

## Résolution de problèmes

| Symptôme | Cause | Solution |
|---|---|---|
| « voltapeak_loops.app est endommagé » | Attributs de quarantaine après téléchargement | `xattr -cr voltapeak_loops.app` |
| Warning « développeur non identifié » | App non notarisée | Clic droit → Ouvrir, ou notariser (option 2) |
| `notarytool` échoue | Compte Developer non actif / mot de passe d'app | Régénérer mot de passe d'app sur appleid.apple.com |
| `stapler staple` du DMG échoue (« No ticket found ») | DMG non soumis à `notarytool submit` avant agrafage | Soumettre le DMG après l'avoir signé (cf. Option 2 §5) |
| L'app crashe sur d'autres Macs | macOS minimum incompatible | L'app exige macOS 26.1+ à cause de l'API et du framework Charts |

---

## Tailles indicatives

| Fichier | Taille |
|---|---|
| `voltapeak_loops.app` (bundle) | ≈ 5-10 Mo |
| `voltapeak_loops.dmg` (UDZO) | ≈ 3-7 Mo |
| `voltapeak_loops.zip` | ≈ 3-7 Mo |

---

## Méthodes de diffusion

| Canal | Pour |
|---|---|
| GitHub Releases (via `release.yml`) | Open source, publication officielle |
| Artifact GitHub Actions (via `build-artifact.yml`) | Smoke-test interne, builds intermédiaires |
| Email | < 25 Mo, audience restreinte |
| iCloud Drive / Dropbox | Diffusion interne via lien |
| Site web personnel | Distribution publique |

---

## Versioning

- `MARKETING_VERSION` (version publique, ex. `1.0` — valeur actuelle
  dans `project.pbxproj`) : modifiée à chaque release.
- `CURRENT_PROJECT_VERSION` (build number, ex. `1`) : incrémentée à
  chaque release.
- Mise à jour de [CHANGELOG.md](CHANGELOG.md) à chaque release.
- Tag git annoté : `git tag -a v1.0 -m "Release 1.0"` puis
  `git push origin v1.0` ; le workflow `release.yml` se déclenche
  automatiquement.

Le tag (`v1.0`), `MARKETING_VERSION` (`1.0`) et le
`CFBundleShortVersionString` de `Info.plist` doivent rester cohérents.

---

## Références Apple

- [Distributing your app outside the App Store](https://developer.apple.com/documentation/xcode/distributing-your-app-outside-the-app-store)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
