# 🚀 Quick Start Guide

Guida rapida per avviare l'app in 10 minuti.

## Prerequisiti Veloci

- Node.js 18+
- Flutter SDK
- Account Google Cloud (free tier va bene!)
- Account Firebase

## Step 1: Setup Google Cloud (5 min)

1. Vai su https://console.cloud.google.com/
2. Crea un progetto nuovo
3. Vai su Firestore → Crea database (modalità Native)
4. Vai su Firebase Console → Aggiungi progetto Google Cloud
5. Scarica `serviceAccountKey.json` e mettilo in `backend/`

## Step 2: Backend (2 min)

```bash
cd backend

# Installa dipendenze
npm install

# Configura .env
cp .env.example .env
# Modifica .env con i tuoi valori

# Avvia il server
npm run dev
```

Server in ascolto su `http://localhost:3000` ✅

## Step 3: Flutter App (3 min)

### iOS
```bash
cd flutter-app

# Firebase setup
# 1. Vai su Firebase Console → Aggiungi app iOS
# 2. Scarica GoogleService-Info.plist → metti in ios/Runner/

flutter pub get
flutter run -d ios
```

### Android
```bash
cd flutter-app

# Firebase setup
# 1. Vai su Firebase Console → Aggiungi app Android
# 2. Scarica google-services.json → metti in android/app/

flutter pub get
flutter run -d android
```

## Step 4: Test (1 min)

1. Registra primo utente (es. "Mario")
2. Registra secondo utente (es. "Luigi") su altro dispositivo/simulatore
3. Manda messaggi!

## 🎉 Fatto!

Hai un'app di messaggistica privata con crittografia E2E funzionante!

## Prossimi Step

- [ ] Leggi [DEPLOYMENT.md](docs/DEPLOYMENT.md) per mettere online il backend
- [ ] Leggi [SECURITY.md](docs/SECURITY.md) per capire come funziona la sicurezza
- [ ] Personalizza UI e colori nell'app Flutter

## Troubleshooting Rapido

**Backend non parte?**
```bash
# Controlla che il file .env sia configurato correttamente
# Verifica che serviceAccountKey.json esista
ls backend/serviceAccountKey.json
```

**Flutter non compila?**
```bash
flutter clean
flutter pub get
```

**Socket.io non si connette?**
- Verifica che il backend sia avviato
- In `lib/services/chat_service.dart` e `auth_service.dart`, cambia l'URL con `http://localhost:3000` (sviluppo) o il tuo URL Cloud Run (produzione)

## URL da Configurare

Ricordati di cambiare l'URL del backend in questi file Flutter:

1. `lib/services/auth_service.dart` → `baseUrl`
2. `lib/services/chat_service.dart` → `baseUrl`

```dart
// Sviluppo (locale)
static const String baseUrl = 'http://localhost:3000';

// Produzione (dopo deploy su Google Cloud)
static const String baseUrl = 'https://your-app.run.app';
```

## Help & Support

- Guida completa: [README.md](README.md)
- Setup backend: [docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md)
- Setup Flutter: [docs/FLUTTER_SETUP.md](docs/FLUTTER_SETUP.md)
- Deployment: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- Sicurezza: [docs/SECURITY.md](docs/SECURITY.md)
