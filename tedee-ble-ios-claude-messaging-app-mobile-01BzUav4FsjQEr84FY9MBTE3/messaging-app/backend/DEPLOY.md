# 🚀 Deploy Guide - Backend

Questa guida ti aiuta a fare il deploy del backend Node.js e delle regole Firestore.

## Prerequisiti

1. **Firebase CLI installato**:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

2. **Project ID Firebase**:
   - Vai su https://console.firebase.google.com
   - Seleziona il tuo progetto
   - Copia il **Project ID** (es: `my-project-12345`)

## Step 1: Configurazione Firebase

### Opzione A: Automatica (Consigliata)

```bash
cd backend

# Inizializza Firebase (seleziona progetto esistente)
firebase use --add

# Ti chiederà di selezionare il progetto dalla lista
# Questo aggiorna .firebaserc automaticamente
```

### Opzione B: Manuale

Modifica `backend/.firebaserc`:

```json
{
  "projects": {
    "default": "il-tuo-project-id"
  }
}
```

## Step 2: Deploy Firestore Rules

```bash
cd backend

# Deploy solo le regole
firebase deploy --only firestore:rules

# Verifica che sia andato a buon fine
# Output atteso: ✔ Deploy complete!
```

## Step 3: Setup Variabili d'Ambiente

### Locale (per test)

Crea `.env` nella directory `backend/`:

```env
PORT=3000
NODE_ENV=development
JWT_SECRET=your_super_secret_jwt_key_change_this
GOOGLE_CLOUD_PROJECT_ID=il-tuo-project-id
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
```

### Produzione (Cloud Run)

Se usi **Google Cloud Run**:

```bash
# Deploy con env vars
gcloud run deploy private-messaging-backend \
  --source ./backend \
  --region europe-west1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "NODE_ENV=production,JWT_SECRET=your_secret,GOOGLE_CLOUD_PROJECT_ID=your-project-id"
```

Se usi **Firebase Functions**:

```bash
cd backend

# Setup Firebase Functions
firebase init functions

# Deploy
firebase deploy --only functions
```

Se usi **Heroku**:

```bash
cd backend

# Login
heroku login

# Crea app
heroku create your-app-name

# Set env vars
heroku config:set JWT_SECRET=your_secret
heroku config:set GOOGLE_CLOUD_PROJECT_ID=your-project-id
heroku config:set NODE_ENV=production

# Deploy
git push heroku main
```

## Step 4: Service Account Key

Per il backend serve il **service account key** di Firebase Admin:

1. Vai su Firebase Console → Project Settings → Service Accounts
2. Click "Generate new private key"
3. Scarica il file JSON

### Locale:
```bash
# Sposta il file nella directory backend
mv ~/Downloads/service-account-key.json backend/

# Aggiorna .env
GOOGLE_APPLICATION_CREDENTIALS=./service-account-key.json
```

### Produzione (Cloud Run):
```bash
# Il service account viene gestito automaticamente da GCP
# Non serve specificare GOOGLE_APPLICATION_CREDENTIALS
```

## Step 5: Test Backend

```bash
cd backend

# Installa dipendenze
npm install

# Avvia in locale
npm start

# Test health endpoint
curl http://localhost:3000/health
```

## Step 6: Aggiorna URL nel Flutter

Dopo il deploy, aggiorna l'URL del backend nel Flutter:

**File da modificare**:
- `flutter-app/lib/services/auth_service.dart`
- `flutter-app/lib/services/chat_service.dart`

```dart
static const String baseUrl = 'https://your-backend-url';
```

**Esempi URL**:
- Cloud Run: `https://private-messaging-backend-abc123-ew.a.run.app`
- Heroku: `https://your-app-name.herokuapp.com`
- Firebase Functions: `https://us-central1-your-project.cloudfunctions.net`

## Verifica Deploy

### 1. Firestore Rules

```bash
# Vai su Firebase Console
# Firestore Database → Rules
# Verifica che le regole siano aggiornate
```

### 2. Backend API

```bash
# Health check
curl https://your-backend-url/health

# Test register
curl -X POST https://your-backend-url/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"publicKey": "test_key"}'

# Dovresti ricevere backend_token + firebase_token
```

## Troubleshooting

### Errore: "Cannot find module 'uuid'"

```bash
cd backend
npm install
```

### Errore: "Permission denied" su Firestore

Verifica che le regole siano deployate:

```bash
firebase deploy --only firestore:rules
```

### Errore: "Invalid credentials"

Verifica il service account:

```bash
# Check che il file esista
ls -la backend/service-account-key.json

# Verifica GOOGLE_APPLICATION_CREDENTIALS in .env
cat backend/.env | grep GOOGLE_APPLICATION_CREDENTIALS
```

### Errore 403 su API calls

- Verifica CORS settings in `server.js`
- Controlla che JWT_SECRET sia uguale tra deploy e test

## Rollback

Se qualcosa va storto:

```bash
# Rollback Firestore rules
firebase deploy --only firestore:rules

# Rollback Cloud Run
gcloud run revisions list --service private-messaging-backend
gcloud run services update-traffic private-messaging-backend \
  --to-revisions=REVISION_NAME=100
```

## Monitoraggio

### Cloud Run Logs

```bash
gcloud run services logs read private-messaging-backend \
  --region europe-west1 \
  --limit 50
```

### Firebase Console

- Firestore Usage: https://console.firebase.google.com/project/_/firestore
- Auth Users: https://console.firebase.google.com/project/_/authentication
- Functions Logs: https://console.firebase.google.com/project/_/functions

## Checklist Deploy Completo

- [ ] `.firebaserc` configurato con project ID
- [ ] Firestore rules deployate (`firebase deploy --only firestore:rules`)
- [ ] Service account key scaricato e configurato
- [ ] `.env` creato con tutte le variabili
- [ ] `npm install` eseguito
- [ ] Backend deployato (Cloud Run / Heroku / Functions)
- [ ] URL backend aggiornato in Flutter app
- [ ] Health check funzionante
- [ ] Test register/login funzionanti

---

Per domande o problemi, consulta:
- `backend/README.md` - API documentation
- `MIGRATION_GUIDE.md` - Breaking changes
