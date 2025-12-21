# Build e Deploy - Firebase App Distribution

Istruzioni per il build e deploy dell'app su Firebase App Distribution.

## 📋 Pre-requisiti

### Tools Necessari
- Flutter SDK 3.x+
- Android Studio con SDK Android
- Firebase CLI: `npm install -g firebase-tools`
- Account Firebase configurato

### Setup Firebase
```bash
# Login Firebase CLI
firebase login

# Verifica progetto
firebase projects:list
```

## 🔨 Build APK per Firebase Distribution

### 1. Clean e Preparazione
```bash
cd flutter-app
flutter clean
flutter pub get
```

### 2. Build Release APK
```bash
# Build APK release
flutter build apk --release

# APK si trova in:
# build/app/outputs/flutter-apk/app-release.apk
```

### 3. Build App Bundle (Opzionale)
```bash
# Per Google Play Store
flutter build appbundle --release

# Bundle si trova in:
# build/app/outputs/bundle/release/app-release.aab
```

## 🚀 Deploy su Firebase App Distribution

### Via Firebase CLI

#### Deploy APK
```bash
# Deploy con note di release
firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-release.apk \
  --app YOUR_FIREBASE_APP_ID \
  --release-notes "v1.7.0: URL cliccabili, condivisione file, viewer PDF" \
  --groups "testers"
```

#### Deploy con File Release Notes
```bash
# Crea file release-notes.txt con descrizione
firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-release.apk \
  --app YOUR_FIREBASE_APP_ID \
  --release-notes-file release-notes.txt \
  --groups "testers"
```

### Via Console Firebase

1. Vai su [Firebase Console](https://console.firebase.google.com)
2. Seleziona il progetto
3. Nel menu laterale: **Release & Monitor** → **App Distribution**
4. Click **Release** → **Upload new release**
5. Drag & drop `app-release.apk`
6. Inserisci release notes:
```
v1.7.0 - Nuove Funzionalità

✨ URL e indirizzi cliccabili nei messaggi
📤 Condivisione file da altre app
📄 Viewer PDF integrato
🎨 Pagina Media unificata
💾 Cache offline foto profilo
⚡ Caricamento messaggi ottimizzato

Bug Fix:
- Schermo bianco quando si condividono PDF
- Foto profilo non visibile offline
- Layout documenti con titoli lunghi
```
7. Seleziona gruppo tester
8. Click **Distribute**

## 📝 Release Notes Template

### v1.7.0

```markdown
# Private Messaging v1.7.0

## Novità
- ✨ **URL Cliccabili**: Tap sui link nei messaggi per aprirli nel browser
- 📤 **Condividi da Altre App**: Condividi foto/PDF da qualsiasi app
- 📄 **Viewer PDF**: Visualizza PDF direttamente nell'app
- 🎨 **Media Unificati**: Tutti i media in un'unica pagina
- 💾 **Offline Cache**: Foto profilo visibile anche offline

## Miglioramenti
- Caricamento messaggi più veloce con placeholder
- Layout documenti ottimizzato
- Performance generali migliorate

## Bug Fix
- Risolto schermo bianco con PDF condivisi
- Fix cache foto profilo offline
- Fix layout titoli documenti lunghi

## Note Tecniche
- Richiede rebuild completo dopo aggiornamento
- Compatibilità: Android 6.0+ (API 23)
- Dimensione APK: ~XX MB
```

## 🔍 Testing Pre-Release

### Checklist Test
Prima del deploy, verifica:

- [ ] Build completa senza errori
- [ ] App si avvia correttamente
- [ ] Login e pairing funzionano
- [ ] Invio/ricezione messaggi
- [ ] **Nuovo**: Tap su URL apre il browser
- [ ] **Nuovo**: Condivisione file da altre app
- [ ] **Nuovo**: Apertura PDF nell'app
- [ ] **Nuovo**: Media page mostra tutti i file
- [ ] **Nuovo**: Foto profilo visibile offline
- [ ] Notifiche push funzionano
- [ ] Cache offline funziona

### Test su Dispositivo Fisico
```bash
# Installa APK su dispositivo connesso
adb install build/app/outputs/flutter-apk/app-release.apk

# Oppure usa Flutter
flutter install --release
```

## 📊 Info Build Corrente

**Versione**: 1.7.0 (Build 8)
**Data Build**: 2024-12-21
**Flutter Version**: 3.x
**Kotlin Version**: 2.1.0
**Gradle Version**: 8.9.1
**Min SDK**: 23 (Android 6.0)
**Target SDK**: 36 (Android 14)
**Compile SDK**: 36

## 🐛 Troubleshooting Build

### Errore JVM Incompatibility
```
Inconsistent JVM-target compatibility detected
```
**Soluzione**: Già configurato con `kotlin.jvm.target.validation.mode=warning` in `gradle.properties`

### Build Fallisce
```bash
# Reset completo
flutter clean
cd android && ./gradlew clean && cd ..
flutter pub get
flutter build apk --release
```

### APK Troppo Grande
```bash
# Build con split per ABI
flutter build apk --split-per-abi --release

# Genera 3 APK separati:
# - app-armeabi-v7a-release.apk
# - app-arm64-v8a-release.apk
# - app-x86_64-release.apk
```

## 📱 Distribuzione Tester

### Aggiungere Tester
```bash
# Via CLI
firebase appdistribution:testers:add \
  tester@example.com \
  --project YOUR_PROJECT_ID

# Oppure via Console Firebase
```

### Gruppi Tester Consigliati
- **alpha**: Testing iniziale (2-3 persone)
- **beta**: Testing esteso (5-10 persone)
- **prod**: Release candidate (tutti i tester)

## 🔐 Signing APK

L'APK usa il keystore di debug per Firebase Distribution.
Per production release su Play Store, usa keystore di release.

### Configurare Keystore Release
1. Crea `android/key.properties`:
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=<alias>
storeFile=<path-to-keystore>
```

2. Modifica `android/app/build.gradle` per usare release signing

## 📈 Monitoraggio Post-Release

Dopo il deploy, monitora:
- Firebase Crashlytics per crash
- Firebase Analytics per usage
- Feedback tester nel gruppo

## 🚦 Quick Commands

```bash
# Build + Deploy in un comando
flutter build apk --release && \
firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-release.apk \
  --app YOUR_FIREBASE_APP_ID \
  --groups "testers"

# Check versione build
grep "version:" pubspec.yaml

# List releases Firebase
firebase appdistribution:releases:list \
  --app YOUR_FIREBASE_APP_ID
```

## 📞 Support

Per problemi con il build o deploy, controlla:
- [Firebase App Distribution Docs](https://firebase.google.com/docs/app-distribution)
- [Flutter Build Docs](https://docs.flutter.dev/deployment/android)
- CHANGELOG.md per dettagli modifiche
