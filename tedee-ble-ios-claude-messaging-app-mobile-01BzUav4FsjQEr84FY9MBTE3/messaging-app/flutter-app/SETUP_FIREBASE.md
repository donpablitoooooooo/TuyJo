# 🔥 Setup File Firebase

Questa guida ti dice dove mettere i file Firebase scaricati dalla console.

## iOS

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Seleziona il tuo progetto
3. Vai su **Impostazioni Progetto** (⚙️) → **Le tue app**
4. Aggiungi un'app iOS (se non l'hai già fatto)
   - Bundle ID: `com.privatemessaging.private_messaging`
5. Scarica `GoogleService-Info.plist`
6. **Metti il file qui:**
   ```
   ios/Runner/GoogleService-Info.plist
   ```

## Android

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Seleziona il tuo progetto
3. Vai su **Impostazioni Progetto** (⚙️) → **Le tue app**
4. Aggiungi un'app Android (se non l'hai già fatto)
   - Package name: `com.privatemessaging.private_messaging`
5. Scarica `google-services.json`
6. **Metti il file qui:**
   ```
   android/app/google-services.json
   ```

## Verifica

Dopo aver copiato i file, la struttura dovrebbe essere:

```
flutter-app/
├── ios/
│   └── Runner/
│       ├── Info.plist
│       └── GoogleService-Info.plist  ← QUESTO FILE
└── android/
    └── app/
        ├── build.gradle
        └── google-services.json        ← QUESTO FILE
```

## ⚠️ IMPORTANTE

- **NON** committare questi file su Git (sono già nel .gitignore)
- Ogni progetto Firebase ha credenziali uniche
- Se cambi progetto Firebase, devi scaricare nuovi file

## Prossimi Step

Dopo aver copiato i file Firebase:

1. Configura l'URL del backend in:
   - `lib/services/auth_service.dart`
   - `lib/services/chat_service.dart`

2. Installa le dipendenze:
   ```bash
   flutter pub get
   ```

3. Per iOS, installa i pods:
   ```bash
   cd ios && pod install && cd ..
   ```

4. Compila l'app:
   ```bash
   flutter run
   ```
