# 💬 App di Messaggistica Privata con Crittografia E2E

App di messaggistica privata per due persone con crittografia end-to-end, realizzata con Flutter e Node.js.

## 🏗️ Architettura

- **Frontend**: Flutter (iOS + Android)
- **Backend**: Node.js + Express + Socket.io
- **Database**: Google Cloud Firestore
- **Auth**: JWT
- **Crittografia**: RSA-2048 + AES-256 (E2E)
- **Push Notifications**: Firebase Cloud Messaging
- **Hosting**: Google Cloud Run

## 🔐 Sicurezza

### Crittografia End-to-End
- Ogni utente genera una coppia di chiavi RSA-2048 (pubblica/privata)
- La chiave privata è memorizzata SOLO sul dispositivo dell'utente
- I messaggi sono cifrati con:
  1. Chiave AES-256 casuale per il contenuto
  2. La chiave AES è cifrata con RSA usando la chiave pubblica del destinatario
- Il server memorizza SOLO messaggi cifrati e NON può leggerli

### Autenticazione
- JWT tokens con scadenza di 30 giorni
- Password hashate con bcrypt (10 rounds)
- Token memorizzati in Flutter Secure Storage

## 📁 Struttura del Progetto

```
messaging-app/
├── flutter-app/          # App mobile Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   ├── screens/
│   │   └── services/
│   └── pubspec.yaml
├── backend/              # Server Node.js
│   ├── server.js
│   ├── middleware/
│   ├── routes/
│   ├── services/
│   └── package.json
└── docs/                 # Documentazione
```

## 🚀 Setup e Deployment

Consulta i seguenti file per le istruzioni dettagliate:
- [Setup Backend](docs/BACKEND_SETUP.md)
- [Setup Flutter](docs/FLUTTER_SETUP.md)
- [Deployment Google Cloud](docs/DEPLOYMENT.md)

## 📱 Features

- ✅ Login/Registrazione sicuri
- ✅ Chat in tempo reale con Socket.io
- ✅ Crittografia end-to-end (RSA + AES)
- ✅ Notifiche push
- ✅ Indicatori di consegna e lettura
- ✅ Cronologia messaggi persistente
- ✅ Supporto iOS e Android

## 🛠️ Tecnologie Utilizzate

### Frontend
- Flutter 3.x
- Provider (state management)
- Socket.io Client
- PointyCastle (crittografia)
- Firebase Cloud Messaging

### Backend
- Node.js + Express
- Socket.io (WebSocket)
- Firestore (database)
- JWT (autenticazione)
- Firebase Admin SDK (push notifications)

## 📝 License

Uso privato personale.
