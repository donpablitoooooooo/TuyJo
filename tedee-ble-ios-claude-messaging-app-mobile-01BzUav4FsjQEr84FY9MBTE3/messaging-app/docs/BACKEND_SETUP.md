# 🔧 Setup Backend

Guida passo-passo per configurare il backend Node.js.

## Prerequisiti

- Node.js 18+ installato
- Account Google Cloud
- Progetto Firebase creato

## 1. Installazione Dipendenze

```bash
cd backend
npm install
```

## 2. Configurazione Google Cloud

### 2.1 Crea un progetto su Google Cloud

1. Vai su [Google Cloud Console](https://console.cloud.google.com/)
2. Crea un nuovo progetto
3. Abilita Firestore Database:
   - Vai su Firestore
   - Crea database in modalità Native
   - Seleziona una location (es. `europe-west1`)

### 2.2 Configura Firebase

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Aggiungi il tuo progetto Google Cloud
3. Vai su **Impostazioni Progetto** → **Account di servizio**
4. Clicca su **Genera nuova chiave privata**
5. Scarica il file JSON e salvalo come `serviceAccountKey.json` nella cartella `backend/`

### 2.3 Abilita Firebase Cloud Messaging

1. Nella Firebase Console, vai su **Cloud Messaging**
2. Copia la **Server Key** (ti servirà per l'app Flutter)

## 3. Configurazione Variabili d'Ambiente

Crea un file `.env` nella cartella `backend/`:

```bash
cp .env.example .env
```

Modifica il file `.env`:

```env
PORT=3000
NODE_ENV=development

# Genera una chiave segreta casuale (puoi usare: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
JWT_SECRET=tua-chiave-segreta-super-sicura-da-cambiare

# ID del tuo progetto Google Cloud
GOOGLE_CLOUD_PROJECT_ID=your-project-id

FIRESTORE_ENABLED=true

# Path al file JSON delle credenziali
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
```

## 4. Avvio Server (Sviluppo)

```bash
npm run dev
```

Il server sarà disponibile su `http://localhost:3000`

## 5. Test API

### Health Check
```bash
curl http://localhost:3000/health
```

### Registrazione
```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "mario",
    "password": "password123",
    "publicKey": "chiave-pubblica-rsa-qui"
  }'
```

### Login
```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "mario",
    "password": "password123"
  }'
```

## 6. Deployment su Google Cloud Run

Vedi [DEPLOYMENT.md](./DEPLOYMENT.md) per le istruzioni complete.

## 🔍 Struttura Database (Firestore)

### Collection: `users`
```json
{
  "id": "uuid",
  "username": "mario",
  "password": "hashed_password",
  "publicKey": "base64_public_key",
  "fcmToken": "firebase_token",
  "createdAt": "2025-01-01T00:00:00Z"
}
```

### Collection: `messages`
```json
{
  "id": "uuid",
  "senderId": "user_id",
  "receiverId": "user_id",
  "encryptedContent": "base64_encrypted_payload",
  "timestamp": "2025-01-01T00:00:00Z",
  "isDelivered": false,
  "isRead": false
}
```

## 🐛 Troubleshooting

### Errore: "Could not load the default credentials"
- Verifica che il file `serviceAccountKey.json` sia presente
- Controlla che `GOOGLE_APPLICATION_CREDENTIALS` punti al file corretto

### Errore: "Firebase app not initialized"
- Assicurati che `GOOGLE_CLOUD_PROJECT_ID` sia corretto
- Verifica le credenziali Firebase

### Porta già in uso
```bash
# Cambia la porta nel file .env
PORT=3001
```
