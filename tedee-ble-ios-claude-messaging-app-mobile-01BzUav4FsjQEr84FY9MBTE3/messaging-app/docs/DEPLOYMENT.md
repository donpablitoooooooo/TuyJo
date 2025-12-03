# 🚀 Deployment su Google Cloud

Guida per il deploy del backend su Google Cloud Run.

## Prerequisiti

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installato
- Progetto Google Cloud già configurato
- Docker installato (opzionale, ma consigliato)

## 1. Configurazione Google Cloud

### 1.1 Login e Configurazione Progetto

```bash
# Login
gcloud auth login

# Imposta il progetto
gcloud config set project YOUR_PROJECT_ID

# Abilita le API necessarie
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable firestore.googleapis.com
```

### 1.2 Crea Service Account per l'app

```bash
# Crea un service account
gcloud iam service-accounts create messaging-app-sa \
    --display-name="Messaging App Service Account"

# Assegna i permessi necessari
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:messaging-app-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/datastore.user"

# Genera la chiave
gcloud iam service-accounts keys create serviceAccountKey.json \
    --iam-account=messaging-app-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

## 2. Preparazione Backend per il Deploy

### 2.1 Crea un Dockerfile

Crea `backend/Dockerfile`:

```dockerfile
FROM node:18-alpine

WORKDIR /app

# Copia package files
COPY package*.json ./

# Installa dipendenze
RUN npm ci --only=production

# Copia il codice
COPY . .

# Porta
EXPOSE 8080

# Avvia il server
CMD ["node", "server.js"]
```

### 2.2 Crea `.dockerignore`

Crea `backend/.dockerignore`:

```
node_modules
npm-debug.log
.env
.git
.gitignore
serviceAccountKey.json
```

### 2.3 Crea `app.yaml` per configurazione

Crea `backend/app.yaml`:

```yaml
runtime: nodejs18
env: standard

env_variables:
  NODE_ENV: "production"
  JWT_SECRET: "your-production-jwt-secret"
  GOOGLE_CLOUD_PROJECT_ID: "your-project-id"
  FIRESTORE_ENABLED: "true"

automatic_scaling:
  min_instances: 1
  max_instances: 10
```

## 3. Deploy su Cloud Run

### 3.1 Build e Deploy con un comando

```bash
cd backend

gcloud run deploy messaging-app-backend \
    --source . \
    --platform managed \
    --region europe-west1 \
    --allow-unauthenticated \
    --set-env-vars NODE_ENV=production,JWT_SECRET=your-secret-key,GOOGLE_CLOUD_PROJECT_ID=your-project-id
```

### 3.2 Oppure: Build manuale con Docker

```bash
# Build dell'immagine
docker build -t gcr.io/YOUR_PROJECT_ID/messaging-app-backend .

# Push su Google Container Registry
docker push gcr.io/YOUR_PROJECT_ID/messaging-app-backend

# Deploy
gcloud run deploy messaging-app-backend \
    --image gcr.io/YOUR_PROJECT_ID/messaging-app-backend \
    --platform managed \
    --region europe-west1 \
    --allow-unauthenticated
```

## 4. Configurazione Post-Deploy

### 4.1 Ottieni l'URL del servizio

```bash
gcloud run services describe messaging-app-backend \
    --platform managed \
    --region europe-west1 \
    --format 'value(status.url)'
```

L'output sarà qualcosa come: `https://messaging-app-backend-xxx-ew.a.run.app`

### 4.2 Configura CORS (se necessario)

Se hai problemi con CORS, aggiungi nel `server.js`:

```javascript
app.use(cors({
  origin: ['https://your-frontend-domain.com'],
  credentials: true,
}));
```

### 4.3 Configura variabili d'ambiente

```bash
gcloud run services update messaging-app-backend \
    --update-env-vars JWT_SECRET=new-secret,GOOGLE_CLOUD_PROJECT_ID=your-project-id \
    --region europe-west1
```

## 5. Configurazione WebSocket (Socket.io)

Cloud Run supporta WebSocket, ma devi assicurarti che:

1. Il timeout sia configurato correttamente
2. Socket.io sia configurato per usare `transports: ['websocket']`

**Aggiorna `server.js`**:

```javascript
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
  transports: ['websocket', 'polling'], // Prova websocket prima
  pingTimeout: 60000,
  pingInterval: 25000,
});
```

## 6. Monitoraggio e Logging

### 6.1 Visualizza i log

```bash
gcloud run services logs read messaging-app-backend \
    --platform managed \
    --region europe-west1
```

### 6.2 Streaming dei log in tempo reale

```bash
gcloud run services logs tail messaging-app-backend \
    --platform managed \
    --region europe-west1
```

## 7. Scaling e Performance

### 7.1 Configura autoscaling

```bash
gcloud run services update messaging-app-backend \
    --min-instances=1 \
    --max-instances=10 \
    --region europe-west1
```

### 7.2 Configura memoria e CPU

```bash
gcloud run services update messaging-app-backend \
    --memory=512Mi \
    --cpu=1 \
    --region europe-west1
```

## 8. Dominio Personalizzato (Opzionale)

### 8.1 Mappa un dominio custom

```bash
gcloud run domain-mappings create \
    --service messaging-app-backend \
    --domain api.tuodominio.com \
    --region europe-west1
```

### 8.2 Configura DNS

Aggiungi i record DNS forniti da Google Cloud al tuo provider DNS.

## 9. SSL/TLS

Cloud Run fornisce automaticamente certificati SSL gratuiti per tutti i servizi!

## 10. Costi Stimati

Con Google Cloud Run:
- **Pricing**: Pay-per-use
- **Free tier**: 2 milioni di richieste/mese
- Per un'app privata con 2 utenti: **praticamente gratuita**

Firestore:
- **Free tier**: 1GB storage, 50K reads/day, 20K writes/day
- Per messaggistica privata: **rientra nel free tier**

## 🔒 Sicurezza

### Checklist Sicurezza Produzione

- [ ] Cambia `JWT_SECRET` con una chiave sicura
- [ ] Non committare `.env` o `serviceAccountKey.json`
- [ ] Abilita HTTPS only
- [ ] Configura CORS correttamente
- [ ] Abilita rate limiting
- [ ] Monitora i log per attività sospette
- [ ] Fai backup regolari di Firestore

### Rate Limiting (Consigliato)

Installa `express-rate-limit`:

```bash
npm install express-rate-limit
```

Aggiungi in `server.js`:

```javascript
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minuti
  max: 100, // max 100 richieste per finestra
});

app.use('/api/', limiter);
```

## 🐛 Troubleshooting

### Servizio non raggiungibile
```bash
# Verifica lo stato
gcloud run services describe messaging-app-backend --region europe-west1

# Controlla i log
gcloud run services logs read messaging-app-backend --region europe-west1
```

### Errori di autenticazione Firestore
- Verifica che il service account abbia i permessi corretti
- Controlla che `GOOGLE_CLOUD_PROJECT_ID` sia corretto

### WebSocket non funziona
- Cloud Run supporta WebSocket, ma verifica che la connessione usi HTTPS
- Controlla i timeout di Socket.io

## 📊 Monitoring

Vai su [Google Cloud Console](https://console.cloud.google.com/) → Cloud Run → messaging-app-backend

Qui puoi vedere:
- Richieste al secondo
- Latenza
- Errori
- Memoria/CPU usage
- Log in tempo reale

## 🔄 Aggiornamenti

Per aggiornare il servizio dopo modifiche:

```bash
cd backend
gcloud run deploy messaging-app-backend \
    --source . \
    --region europe-west1
```

## ✅ Checklist Finale

- [ ] Backend deployato su Cloud Run
- [ ] URL del backend ottenuto
- [ ] URL configurato nell'app Flutter
- [ ] Firestore configurato e funzionante
- [ ] Firebase Cloud Messaging abilitato
- [ ] Variabili d'ambiente configurate
- [ ] SSL/HTTPS attivo
- [ ] Log monitorati
- [ ] Test end-to-end completato

🎉 **Il tuo backend è online!**
