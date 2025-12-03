# 🔐 Setup Credenziali Backend

Questa guida ti dice come ottenere e configurare le credenziali Google Cloud/Firebase.

## 1. Service Account Key (Firestore & Firebase Admin)

### Passo 1: Vai su Firebase Console

1. Apri [Firebase Console](https://console.firebase.google.com/)
2. Seleziona il tuo progetto (o creane uno nuovo)

### Passo 2: Genera la chiave

1. Vai su **Impostazioni Progetto** (⚙️ in alto a sinistra)
2. Clicca sulla tab **Account di servizio**
3. Clicca su **Genera nuova chiave privata**
4. Conferma e scarica il file JSON

### Passo 3: Salva il file

Rinomina il file scaricato in `serviceAccountKey.json` e mettilo qui:

```
backend/serviceAccountKey.json
```

⚠️ **IMPORTANTE**: Questo file contiene credenziali sensibili. NON committarlo su Git (è già nel .gitignore).

## 2. Configurazione .env

### Passo 1: Copia il template

```bash
cp .env.example .env
```

### Passo 2: Configura le variabili

Apri il file `.env` e modifica:

```env
# Porta del server
PORT=3000
NODE_ENV=development

# JWT Secret - genera una chiave casuale
# Esegui: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
JWT_SECRET=<inserisci-qui-chiave-generata>

# ID progetto Google Cloud (lo trovi nella Firebase Console)
GOOGLE_CLOUD_PROJECT_ID=<your-project-id>

FIRESTORE_ENABLED=true
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
```

### Trova il GOOGLE_CLOUD_PROJECT_ID

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Impostazioni Progetto → **Generali**
3. Copia l'**ID progetto** (non il nome!)

### Genera JWT_SECRET

Esegui questo comando nel terminale:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Copia l'output e mettilo in `JWT_SECRET`.

## 3. Verifica Setup

Controlla che i file siano al posto giusto:

```
backend/
├── .env                       ← File di configurazione (da creare)
├── .env.example              ← Template
├── serviceAccountKey.json    ← Credenziali Firebase (da scaricare)
└── ...
```

## 4. Test

Avvia il server:

```bash
npm run dev
```

Se tutto è ok, vedrai:

```
Server running on port 3000
Firestore initialized successfully
```

## ⚠️ Sicurezza

- **MAI** committare `.env` o `serviceAccountKey.json` su Git
- **MAI** condividere questi file pubblicamente
- Usa variabili d'ambiente diverse per sviluppo e produzione
- Su Google Cloud Run, usa Secret Manager invece di file .env

## Troubleshooting

### Errore: "Could not load the default credentials"

- Verifica che `serviceAccountKey.json` esista
- Controlla che `GOOGLE_APPLICATION_CREDENTIALS` punti al file corretto

### Errore: "Permission denied on Firestore"

- Vai su Firestore → **Regole**
- Per sviluppo, usa (SOLO temporaneo):
  ```
  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {
      match /{document=**} {
        allow read, write: if true;
      }
    }
  }
  ```

Per produzione, usa regole più restrittive!
