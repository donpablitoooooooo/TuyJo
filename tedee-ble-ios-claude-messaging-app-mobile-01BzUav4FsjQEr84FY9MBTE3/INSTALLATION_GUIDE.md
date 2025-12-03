# 📦 Guida Completa di Installazione

Guida step-by-step per installare e configurare l'app di messaggistica.

## 📋 Indice

1. [Prerequisiti](#prerequisiti)
2. [Setup Backend](#setup-backend)
3. [Setup Flutter App](#setup-flutter-app)
4. [Test Locale](#test-locale)
5. [Troubleshooting](#troubleshooting)

---

## Prerequisiti

Prima di iniziare, assicurati di avere:

- ✅ Node.js 18+ installato
- ✅ Flutter SDK 3.0+ installato
- ✅ Account Google Cloud (free tier è sufficiente)
- ✅ Account Firebase

### Verifica installazione

```bash
# Verifica Node.js
node --version  # Deve essere >= 18

# Verifica Flutter
flutter --version  # Deve essere >= 3.0
flutter doctor    # Controlla che tutto sia configurato
```

---

## Setup Backend

### 1️⃣ Installa dipendenze

```bash
cd messaging-app/backend
npm install
```

### 2️⃣ Configura Google Cloud/Firebase

**Segui la guida dettagliata:** [`backend/SETUP_CREDENTIALS.md`](messaging-app/backend/SETUP_CREDENTIALS.md)

In breve:
1. Crea un progetto su [Google Cloud Console](https://console.cloud.google.com/)
2. Abilita Firestore Database
3. Vai su [Firebase Console](https://console.firebase.google.com/)
4. Scarica `serviceAccountKey.json` e mettilo in `backend/`

### 3️⃣ Configura variabili d'ambiente

```bash
# Copia il template
cp .env.example .env

# Modifica .env con i tuoi valori
nano .env
```

Compila:
- `JWT_SECRET` - genera con: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
- `GOOGLE_CLOUD_PROJECT_ID` - trovalo nella Firebase Console

### 4️⃣ Avvia il server

```bash
npm run dev
```

Se tutto ok, vedrai:
```
Server running on port 3000
Firestore initialized successfully
```

✅ **Backend completato!**

---

## Setup Flutter App

### 1️⃣ Configura Firebase

**Segui la guida dettagliata:** [`flutter-app/SETUP_FIREBASE.md`](messaging-app/flutter-app/SETUP_FIREBASE.md)

In breve:
1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Aggiungi app iOS: scarica `GoogleService-Info.plist` → metti in `flutter-app/ios/Runner/`
3. Aggiungi app Android: scarica `google-services.json` → metti in `flutter-app/android/app/`

### 2️⃣ Configura URL Backend

Modifica questi file per puntare al tuo backend:

**`lib/services/auth_service.dart`**
```dart
static const String baseUrl = 'http://localhost:3000';  // Per sviluppo locale
```

**`lib/services/chat_service.dart`**
```dart
static const String baseUrl = 'http://localhost:3000';  // Per sviluppo locale
```

### 3️⃣ Installa dipendenze Flutter

```bash
cd messaging-app/flutter-app
flutter pub get
```

### 4️⃣ (Solo iOS) Installa CocoaPods

```bash
cd ios
pod install
cd ..
```

### 5️⃣ Compila e avvia l'app

**iOS (Simulatore):**
```bash
flutter run -d ios
```

**Android (Emulatore):**
```bash
flutter run -d android
```

✅ **Flutter app completata!**

---

## Test Locale

### Scenario di Test Completo

1. **Avvia il backend** (se non è già avviato):
   ```bash
   cd backend
   npm run dev
   ```

2. **Avvia l'app su 2 dispositivi/simulatori**:
   - Dispositivo 1: iPhone Simulator
   - Dispositivo 2: Android Emulator

   Oppure 2 simulatori iOS/Android separati

3. **Registra il primo utente**:
   - Username: `mario`
   - Password: `password123`

4. **Registra il secondo utente** (su altro dispositivo):
   - Username: `luigi`
   - Password: `password456`

5. **Invia messaggi tra i due utenti**

6. **Verifica**:
   - ✅ Messaggi arrivano in tempo reale
   - ✅ Crittografia E2E funzionante
   - ✅ Cronologia persistente

---

## Troubleshooting

### Backend

**Errore: "Could not load credentials"**
- Verifica che `serviceAccountKey.json` esista in `backend/`
- Controlla che `.env` sia configurato correttamente

**Porta 3000 già in uso**
```bash
# Cambia porta in .env
PORT=3001
```

### Flutter

**Errore: "MissingPluginException"**
```bash
flutter clean
flutter pub get
```

**Socket.io non si connette**
- Verifica che il backend sia avviato su `localhost:3000`
- Controlla che l'URL in `auth_service.dart` e `chat_service.dart` sia corretto
- Su Android: verifica permesso INTERNET in AndroidManifest.xml

**Firebase non inizializza (iOS)**
- Verifica che `GoogleService-Info.plist` sia in `ios/Runner/`
- Esegui `pod install` nella directory `ios/`

**Firebase non inizializza (Android)**
- Verifica che `google-services.json` sia in `android/app/`
- Controlla che i plugin siano in `build.gradle`

---

## 🎉 Completato!

Ora hai un'app di messaggistica privata con crittografia E2E funzionante!

### Prossimi Step

- 📚 Leggi [`messaging-app/README.md`](messaging-app/README.md) per capire l'architettura
- 🔐 Leggi [`docs/SECURITY.md`](messaging-app/docs/SECURITY.md) per dettagli sulla sicurezza
- 🚀 Leggi [`docs/DEPLOYMENT.md`](messaging-app/docs/DEPLOYMENT.md) per il deploy su Google Cloud

---

## 📞 Supporto

Per problemi o domande:
- Controlla la documentazione in `messaging-app/docs/`
- Verifica di aver seguito tutti gli step correttamente
- Controlla i log del backend e dell'app per errori specifici
