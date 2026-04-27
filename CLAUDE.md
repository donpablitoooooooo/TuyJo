# TuyJo — Guida al progetto e al rilascio

Questo file è la documentazione operativa per Claude Code e per gli sviluppatori
umani. Contiene la procedura completa per pubblicare una nuova versione
dell'app su Google Play e App Store.

## Struttura

- `flutter-app/` — app Flutter (Android + iOS)
- `functions/` — Firebase Cloud Functions
- `firestore.rules`, `storage.rules` — regole di sicurezza Firebase

## Requisiti per il rilascio

- Flutter SDK 3.6.0+
- Android: JDK 17, Android SDK con API 36, `android/key.properties` valido
- iOS: macOS + Xcode + CocoaPods, Apple Developer account nel team `PW2GC2RTH2`

## Dove si trova la versione

Unica fonte di verità: `flutter-app/pubspec.yaml`

```yaml
version: <versionName>+<versionCode>
```

Esempio: `version: 1.30.0+33` → `versionName=1.30.0`, `versionCode=33`.

- **Android**: legge versionName/versionCode da pubspec via
  `flutter.versionCode` / `flutter.versionName` in `android/app/build.gradle`.
- **iOS**: `Info.plist` usa `$(FLUTTER_BUILD_NAME)` e `$(FLUTTER_BUILD_NUMBER)`,
  ma `ios/Runner.xcodeproj/project.pbxproj` contiene anche
  `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` hardcoded per i target
  Runner e ShareExtension. **Vanno aggiornati a mano** per tenerli allineati
  (sia per chiarezza, sia perché alcuni flussi Xcode/App Store Connect li
  leggono direttamente).

## Procedura di release passo-passo

### 1. Bump versione

Incrementa in `flutter-app/pubspec.yaml`:

```yaml
version: X.Y.Z+N   # es. 1.30.0+33
```

Aggiorna anche il pbxproj iOS con **Edit + replace_all**:

- `MARKETING_VERSION = <vecchia>;` → `MARKETING_VERSION = X.Y.Z;`
- `CURRENT_PROJECT_VERSION = <vecchia>;` → `CURRENT_PROJECT_VERSION = N;`

**Attenzione**: nel pbxproj esistono anche occorrenze `MARKETING_VERSION = 1.0;`
e `CURRENT_PROJECT_VERSION = 1;` che appartengono al target di test. **NON toccarle**.

Dopo replace_all, verifica che il numero di occorrenze sia 6 per ciascuno
dei nuovi valori (Runner + ShareExtension × Debug/Release/Profile):

```bash
grep -c "MARKETING_VERSION = X.Y.Z" flutter-app/ios/Runner.xcodeproj/project.pbxproj
grep -c "CURRENT_PROJECT_VERSION = N" flutter-app/ios/Runner.xcodeproj/project.pbxproj
```

Aggiorna inoltre:

- `flutter-app/CHANGELOG.md` — nuova sezione `## [X.Y.Z] - YYYY-MM-DD`
- `flutter-app/release-notes.txt` — contenuto che finirà su Play/App Store

### 2. Reset pulito dei build artifact

Da `flutter-app/`:

```bash
flutter clean
flutter pub get
```

### 3. Pulizia specifica iOS (Pod + DerivedData)

Obbligatoria dopo un bump, dopo un cambio di dipendenze o se Xcode inizia a
produrre errori strani di cache. Da `flutter-app/`:

```bash
# Elimina Pod e lockfile
cd ios
rm -rf Pods Podfile.lock
rm -rf .symlinks
rm -rf Flutter/Flutter.framework Flutter/Flutter.podspec

# Torna alla root dell'app e rigenera i symlink Flutter
cd ..
flutter pub get
flutter precache --ios

# Reinstalla i Pod
cd ios
pod repo update
pod install

# Elimina DerivedData di Xcode
rm -rf ~/Library/Developer/Xcode/DerivedData/*

cd ..
```

Se usi Apple Silicon e hai problemi con pod architettura, esegui
`arch -x86_64 pod install` oppure assicurati che CocoaPods sia installato via
Homebrew nativo arm64.

### 4. Build Android (Google Play)

Da `flutter-app/`:

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

(Per test locale su device: `flutter build apk --release --split-per-abi`.)

### 5. Upload su Google Play Console

1. Play Console → TuyJo → *Test e rilascio* → *Produzione* (o *Test interno* prima)
2. "Crea nuova release" → carica `app-release.aab`
3. Note di rilascio in italiano (`it-IT`): incolla `release-notes.txt`
4. Verifica che `versionCode` e `versionName` siano quelli attesi
5. "Salva" → "Rivedi release" → "Avvia rollout in produzione"

### 6. Build iOS (App Store)

Da `flutter-app/`:

```bash
flutter build ipa --release
```

Output: `build/ios/ipa/*.ipa`

In alternativa, apri `ios/Runner.xcworkspace` in Xcode → *Product → Archive* →
*Distribute App → App Store Connect → Upload*.

### 7. Upload a App Store Connect

Via CLI:

```bash
xcrun altool --upload-app \
  -f build/ios/ipa/private_messaging.ipa \
  -t ios \
  -u <apple-id> \
  -p <app-specific-password>
```

Oppure via GUI: `Transporter.app` → trascina l'IPA.

### 8. Pubblica su App Store Connect

1. App Store Connect → TuyJo → *App Store* → "+" *Nuova versione iOS X.Y.Z*
2. Attendi processing della build (≈10-30 min) e selezionala
3. "Novità di questa versione" (it): incolla `release-notes.txt`
4. "Salva" → "Aggiungi alla revisione" → "Invia in revisione"

### 9. Tag git

Dopo che le release sono state inviate:

```bash
git tag -a vX.Y.Z -m "Release X.Y.Z (build N)"
git push origin vX.Y.Z
```

## Checklist rapida

- [ ] `pubspec.yaml` → nuova `version: X.Y.Z+N`
- [ ] `project.pbxproj` → `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` aggiornati (6+6 occorrenze)
- [ ] `CHANGELOG.md` aggiornato
- [ ] `release-notes.txt` aggiornato
- [ ] `flutter clean && flutter pub get`
- [ ] iOS: `rm -rf ios/Pods ios/Podfile.lock` + `pod install` + `rm -rf ~/Library/Developer/Xcode/DerivedData/*`
- [ ] `flutter build appbundle --release` → upload su Play Console
- [ ] `flutter build ipa --release` → upload su App Store Connect
- [ ] Tag git `vX.Y.Z` e push

## Note

- **Non** usare `--no-verify` sui commit.
- **Non** pushare forzato su `main`.
- Le release vanno sempre sviluppate su branch dedicato
  (es. `claude/bump-version-publish-*`) e poi mergiate.
