# Private Messaging - App di Messaggistica E2E Criptata per Coppie

App di messaggistica privata end-to-end criptata progettata per coppie. Comunicazione sicura con crittografia RSA/AES, condivisione media e funzionalità avanzate.

## 🚀 Funzionalità Principali

### 💬 Messaggistica
- **Crittografia E2E**: Tutti i messaggi sono criptati end-to-end con RSA (2048-bit) + AES (256-bit)
- **Messaggi di testo**: Invia e ricevi messaggi istantanei
- **Link cliccabili**: URL e indirizzi vengono rilevati automaticamente e si aprono nel browser esterno
- **Typing indicator**: Visualizza quando il partner sta scrivendo
- **Read receipts**: Vedi quando i messaggi sono stati consegnati e letti
- **Infinite scroll**: Caricamento automatico messaggi più vecchi scrollando verso l'alto

### 📎 Allegati e Media
- **Foto e Video**: Condividi foto dalla galleria o scatta nuove foto con la fotocamera
- **Documenti PDF**: Visualizza PDF direttamente nell'app con zoom e scroll
- **Viewer integrato**: PDF aperti in un viewer nativo dell'app
- **Thumbnail intelligenti**: Media mostrati in griglia 3x3 nella pagina Media
- **Caricamento ottimistico**: I messaggi appaiono immediatamente con placeholder di caricamento

### 📤 Condivisione da Altre App
- **Share intent**: Condividi file da qualsiasi app direttamente in Private Messaging
- **Supporto formati**: Immagini, video, PDF e documenti
- **Condivisione multipla**: Condividi più file contemporaneamente
- Disponibile su Android (iOS supporto base)

### ✅ Todo e Reminder
- **Todo list integrata**: Crea todo condivisi con il partner
- **Reminder**: Imposta notifiche per promemoria
- **Eventi**: Crea eventi con data e ora
- **Stato completamento**: Spunta todo come completati

### 🎨 Interfaccia
- **Design moderno**: UI pulita con gradients e animazioni fluide
- **Foto profilo coppia**: Selfie condiviso come foto profilo con cache offline
- **Pagina Media unificata**: Tutti i media (foto, video, documenti) in un'unica vista
- **Notifiche**: Notifiche push per nuovi messaggi

## 🔐 Sicurezza

### Crittografia
- **RSA 2048-bit**: Scambio chiavi e firma digitale
- **AES 256-bit**: Crittografia simmetrica dei messaggi
- **Double encryption**: Gli allegati sono criptati due volte (mittente + destinatario)
- **Zero-knowledge**: Il server non può leggere i tuoi messaggi

### Privacy
- **Pairing sicuro**: Connessione tramite QR code
- **Chiavi locali**: Le chiavi private rimangono sempre sul dispositivo
- **Cache offline**: Messaggi e foto cached localmente in modo sicuro

## 📱 Requisiti

### Android
- **Minimo**: Android 6.0 (API 23)
- **Target**: Android 14 (API 36)
- **JDK**: 17

### iOS
- **Minimo**: iOS 12.0+
- **Xcode**: 14.0+

## 🛠️ Setup Sviluppo

### 1. Prerequisiti
```bash
# Flutter SDK
flutter --version  # Richiede Flutter 3.x+

# Android Studio / Xcode installati
```

### 2. Clona il Repository
```bash
git clone <repository-url>
cd flutter-app
```

### 3. Installa Dipendenze
```bash
flutter pub get
```

### 4. Configura Firebase
1. Aggiungi `google-services.json` in `android/app/`
2. Aggiungi `GoogleService-Info.plist` in `ios/Runner/`
3. Configura Firebase Authentication, Firestore, Storage

### 5. Build

#### Android
```bash
# Debug
flutter run

# Release (APK)
flutter build apk --release

# Release (App Bundle)
flutter build appbundle --release
```

#### iOS
```bash
# Debug
flutter run

# Release
flutter build ios --release
```

## 📦 Dipendenze Principali

### Core
- `flutter` - Framework UI
- `provider` - State management
- `firebase_core` - Firebase SDK core
- `firebase_auth` - Autenticazione
- `cloud_firestore` - Database
- `firebase_storage` - Storage file
- `firebase_messaging` - Push notifications

### Crittografia
- `pointycastle` - Implementazione crittografia RSA/AES
- `encrypt` - Helper crittografia
- `crypto` - Hash e utilities

### Media
- `image_picker` - Selezione foto/video
- `image_cropper` - Crop immagini
- `file_picker` - Selezione documenti
- `pdfx` - Viewer PDF integrato
- `open_filex` - Apertura file con app esterne

### Condivisione
- `receive_sharing_intent` - Ricevi file condivisi da altre app
- `url_launcher` - Apri URL e indirizzi esterni
- `flutter_linkify` - Rilevamento automatico link

### UI/UX
- `intl` - Internazionalizzazione e formattazione date
- `qr_flutter` - Generazione QR code
- `mobile_scanner` - Scansione QR code
- `flutter_local_notifications` - Notifiche locali

## 🔧 Configurazione

### JVM Target (Android)
Il progetto usa Java/Kotlin JVM target 17. La validazione è impostata a `warning` per permettere compatibilità con package che usano versioni diverse:

```properties
# android/gradle.properties
kotlin.jvm.target.validation.mode=warning
```

### Permessi

#### Android
- `INTERNET` - Connessione rete
- `CAMERA` - Fotocamera
- `READ_MEDIA_IMAGES/VIDEO` - Accesso media (Android 13+)
- `READ/WRITE_EXTERNAL_STORAGE` - Storage (Android 12 e precedenti)
- `POST_NOTIFICATIONS` - Notifiche push

#### iOS
- `NSPhotoLibraryUsageDescription` - Accesso galleria
- `NSCameraUsageDescription` - Accesso fotocamera

## 🐛 Troubleshooting

### Build Android fallisce con JVM incompatibility
Assicurati che `kotlin.jvm.target.validation.mode=warning` sia in `android/gradle.properties`

### File condivisi non funzionano
1. Verifica gli intent-filter in `AndroidManifest.xml`
2. Controlla i permessi storage
3. Fai rebuild completo: `flutter clean && flutter pub get`

### PDF non si aprono
Il package `pdfx` richiede JVM 11+. La configurazione è già impostata per gestire le incompatibilità.

## 📝 Note di Versione

### v1.1.0 (Corrente)
**Nuove Funzionalità:**
- ✨ URL e indirizzi cliccabili nei messaggi
- 📤 Condivisione file da altre app (Android)
- 📄 Viewer PDF integrato nell'app
- 🎨 Pagina Media unificata (foto + video + documenti insieme)
- 💾 Cache offline foto profilo
- ⚡ Ottimizzazione caricamento messaggi con placeholder

**Miglioramenti:**
- Layout documenti compatto in Media page
- Titoli documenti troncati con ellipsis
- Gestione robusta file condivisi con PostFrameCallback
- Configurazione JVM per compatibilità package

**Bug Fix:**
- Schermo bianco quando si condividono PDF
- Foto profilo non visibile offline
- Titoli documenti lunghi che rompevano il layout

### v1.0.0
- Release iniziale con messaggistica E2E criptata
- Todo e reminder condivisi
- Condivisione foto e video
- Pairing con QR code

## 🤝 Contribuire

Questo è un progetto privato per uso personale.

## 📄 Licenza

Proprietario - Tutti i diritti riservati

## 👨‍💻 Autore

Sviluppato per uso privato
