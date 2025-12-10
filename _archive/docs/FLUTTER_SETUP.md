# 📱 Setup App Flutter

Guida per configurare e compilare l'app mobile.

## Prerequisiti

- Flutter SDK 3.0+ installato ([Installa Flutter](https://flutter.dev/docs/get-started/install))
- Xcode (per iOS) o Android Studio (per Android)
- Account Firebase

## 1. Installazione Flutter

Verifica che Flutter sia installato correttamente:

```bash
flutter doctor
```

## 2. Configurazione Firebase

### 2.1 Aggiungi l'app alla Firebase Console

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Seleziona il tuo progetto
3. Aggiungi un'app iOS e/o Android

### 2.2 Configurazione iOS

1. Nella Firebase Console, aggiungi un'app iOS
2. Inserisci il Bundle ID (es. `com.tuonome.messaging`)
3. Scarica `GoogleService-Info.plist`
4. Copia il file in `flutter-app/ios/Runner/`

**Modifica `ios/Runner/Info.plist`** per aggiungere:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### 2.3 Configurazione Android

1. Nella Firebase Console, aggiungi un'app Android
2. Inserisci il Package Name (es. `com.tuonome.messaging`)
3. Scarica `google-services.json`
4. Copia il file in `flutter-app/android/app/`

**Modifica `android/build.gradle`** (progetto root):

```gradle
buildscript {
    dependencies {
        // ... altre dipendenze
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
```

**Modifica `android/app/build.gradle`**:

```gradle
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
    id "com.google.gms.google-services"  // Aggiungi questa riga
}
```

## 3. Configurazione Backend URL

Modifica i file per puntare al tuo server:

**`lib/services/auth_service.dart`**
```dart
static const String baseUrl = 'https://your-backend-url.com'; // Cambia qui
```

**`lib/services/chat_service.dart`**
```dart
static const String baseUrl = 'https://your-backend-url.com'; // Cambia qui
```

## 4. Installazione Dipendenze

```bash
cd flutter-app
flutter pub get
```

## 5. Build e Run

### iOS (Simulatore)

```bash
flutter run -d ios
```

### Android (Emulatore o dispositivo fisico)

```bash
flutter run -d android
```

### Build per Release

#### iOS
```bash
flutter build ios --release
```

Poi apri Xcode per archiviare e caricare su App Store:
```bash
open ios/Runner.xcworkspace
```

#### Android (APK)
```bash
flutter build apk --release
```

L'APK sarà in `build/app/outputs/flutter-apk/app-release.apk`

#### Android (App Bundle per Play Store)
```bash
flutter build appbundle --release
```

## 6. Configurazione Notifiche Push

### iOS

1. Vai su [Apple Developer Portal](https://developer.apple.com/)
2. Crea un **APNs Key** per le notifiche push
3. Scarica il file `.p8`
4. Nella Firebase Console:
   - Vai su **Impostazioni Progetto** → **Cloud Messaging**
   - Carica la chiave APNs

### Android

Le notifiche push sono già configurate tramite `google-services.json`.

## 7. Test dell'App

1. Avvia il backend (vedi [BACKEND_SETUP.md](./BACKEND_SETUP.md))
2. Lancia l'app su due dispositivi/simulatori
3. Registra due utenti diversi
4. Inizia a chattare!

## 🔍 Struttura Progetto

```
flutter-app/
├── lib/
│   ├── main.dart                    # Entry point
│   ├── models/
│   │   └── message.dart             # Modelli dati
│   ├── screens/
│   │   ├── login_screen.dart        # Schermata login
│   │   └── chat_screen.dart         # Schermata chat
│   └── services/
│       ├── auth_service.dart        # Autenticazione
│       ├── chat_service.dart        # Messaggistica
│       ├── encryption_service.dart  # Crittografia E2E
│       └── notification_service.dart # Push notifications
└── pubspec.yaml
```

## 🐛 Troubleshooting

### Errore: "MissingPluginException"
```bash
flutter clean
flutter pub get
```

### Errore Firebase su iOS
- Verifica che `GoogleService-Info.plist` sia in `ios/Runner/`
- Fai `pod install` nella cartella `ios/`

### Errore Firebase su Android
- Verifica che `google-services.json` sia in `android/app/`
- Controlla che i plugin siano aggiunti correttamente in `build.gradle`

### Socket.io non si connette
- Verifica che il backend sia avviato
- Controlla che l'URL in `chat_service.dart` sia corretto
- Su Android, aggiungi permessi internet in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## 📝 Permessi Richiesti

### iOS (`Info.plist`)
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Per inviare foto nella chat</string>
<key>NSCameraUsageDescription</key>
<string>Per scattare foto</string>
```

### Android (`AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```
