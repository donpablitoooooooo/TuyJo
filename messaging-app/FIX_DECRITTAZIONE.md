# 🔧 Fix Problema Decrittazione Messaggi

## ✅ Problema Risolto

**Problema:** I messaggi mostravano "[Messaggio non decifrabile]"

**Causa:** `ChatService` creava una sua istanza separata di `EncryptionService` senza la chiave privata caricata, mentre `AuthService` aveva un'altra istanza con la chiave privata.

**Soluzione:** Condividere la STESSA istanza di `EncryptionService` tra `AuthService` e `ChatService`.

## 📝 File Modificati

### 1. `lib/main.dart` (linee 62-74)
```dart
Future<void> _initialize() async {
  final authService = Provider.of<AuthService>(context, listen: false);
  final encryptionService = Provider.of<EncryptionService>(context, listen: false);

  // IMPORTANTE: Imposta l'EncryptionService in AuthService
  // così tutti useranno la stessa istanza
  authService.setEncryptionService(encryptionService);

  await authService.initialize();
  setState(() {
    _isInitialized = true;
  });
}
```

### 2. `lib/services/auth_service.dart`
- Cambiato da: `final _encryptionService = EncryptionService();`
- A: `EncryptionService? _encryptionService;`
- Aggiunto getter: `EncryptionService? get encryptionService => _encryptionService;`
- Aggiunto setter: `void setEncryptionService(EncryptionService service)`

### 3. `lib/services/chat_service.dart` ⭐ FILE CRITICO
- Cambiato da: `final EncryptionService _encryptionService = EncryptionService();`
- A: `EncryptionService? _encryptionService;`
- Aggiunto: `void setEncryptionService(EncryptionService encryptionService)`
- Aggiunti null check prima di crittare/decrittare

### 4. `lib/screens/chat_screen.dart`
- Aggiunto passaggio di `encryptionService` da `AuthService` a `ChatService`

## 🚀 Come Aggiornare e Testare

### Passo 1: Ottieni le modifiche da GitHub

```bash
# Vai nella directory del progetto
cd /path/to/tedee-ble-ios

# Assicurati di essere sul branch corretto
git checkout claude/messaging-app-mobile-01BzUav4FsjQEr84FY9MBTE3

# Scarica le ultime modifiche
git pull origin claude/messaging-app-mobile-01BzUav4FsjQEr84FY9MBTE3
```

**Verifica che l'ultimo commit sia:**
```
bc8f7e3 Fix: Risolto problema decrittazione messaggi
```

### Passo 2: Pulisci e Ricompila Flutter

```bash
cd messaging-app/flutter-app

# Pulisci la cache di Flutter
flutter clean

# Reinstalla le dipendenze
flutter pub get

# Ricompila l'app
flutter run
```

### Passo 3: ⚠️ IMPORTANTE - Cancella i Dati Vecchi

**Le vecchie chiavi di crittografia sono incompatibili!**

**Su iOS Simulator:**
1. Cancella l'app dal simulatore (long press → X)
2. Reinstalla con `flutter run`

**Su Android Emulator:**
1. Settings → Apps → Private Messaging → Storage → Clear Data
2. Oppure disinstalla e reinstalla

### Passo 4: Registra Nuovi Utenti

1. Apri l'app sul primo dispositivo
2. Registrati con un nuovo username (es. `mario2`)
3. Apri l'app sul secondo dispositivo
4. Registrati con un altro username (es. `luigi2`)

### Passo 5: Testa la Chat

1. Invia un messaggio da Mario a Luigi
2. **Il messaggio DEVE essere leggibile!** ✅
3. Non deve più dire "[Messaggio non decifrabile]"

## 🐛 Se Ancora Non Funziona

### Controlla i Log Flutter

Guarda nel terminale dove hai eseguito `flutter run`. Dovresti vedere:

**All'avvio:**
```
🔐 Initializing AuthService...
🔑 Loading private key...
✅ Private key loaded successfully
```

**Quando invii un messaggio:**
```
🔐 [Encryption] Encrypting message...
✅ [Encryption] Message encrypted successfully
```

**Quando ricevi un messaggio:**
```
🔓 [Decryption] Decrypting message...
📝 [Decryption] Encrypted content (Base64): ...
🔑 [Decryption] Using private key
✅ [Decryption] Message decrypted successfully
```

### Verifica il Codice

Controlla che il file `lib/services/chat_service.dart` abbia:

**Linea 13:**
```dart
EncryptionService? _encryptionService;
```
(NON deve essere: `final EncryptionService _encryptionService = EncryptionService();`)

**Linee 19-21:**
```dart
void setEncryptionService(EncryptionService encryptionService) {
  _encryptionService = encryptionService;
}
```

**Linee 124-126 (in sendMessage):**
```dart
if (_encryptionService == null) {
  throw Exception('EncryptionService not initialized');
}
```

## 📊 Commit su GitHub

Puoi vedere tutti i commit su GitHub al branch:
`claude/messaging-app-mobile-01BzUav4FsjQEr84FY9MBTE3`

I 5 commit sono:
1. `bc8f7e3` - Fix: Risolto problema decrittazione messaggi ⭐ **QUESTO È IL FIX!**
2. `ee0958c` - Debug: Add detailed logging for encryption/decryption
3. `e517c67` - Fix: Risolto errore decodifica chiave privata RSA
4. `1f1860c` - Config: Update backend URL to Cloud Run deployment
5. `a553410` - Fix: Risolti problemi di login e logout automatico

## ✅ Test Superato

Se i messaggi si leggono correttamente, il problema è risolto! 🎉

La crittografia end-to-end funziona:
- ✅ Ogni utente genera le sue chiavi RSA-2048
- ✅ Le chiavi private sono salvate in modo sicuro (Keychain su iOS)
- ✅ I messaggi sono criptati con la chiave pubblica del destinatario
- ✅ Solo il destinatario può decriptarli con la sua chiave privata
- ✅ Il server vede solo dati criptati (non può leggere i messaggi)

## 🆘 Problemi?

Se dopo aver seguito questi passi i messaggi sono ancora "[Messaggio non decifrabile]":

1. Verifica di aver fatto `git pull` e che l'ultimo commit sia `bc8f7e3`
2. Verifica di aver fatto `flutter clean` e `flutter pub get`
3. Verifica di aver cancellato i dati vecchi dell'app
4. Verifica di aver registrato NUOVI utenti (non riusare quelli vecchi)
5. Guarda i log Flutter per vedere dove fallisce la decrittazione
6. Verifica che `lib/services/chat_service.dart` linea 13 sia `EncryptionService? _encryptionService;`

---

**Data Fix:** 2025-12-04
**Commit:** bc8f7e3
**Branch:** claude/messaging-app-mobile-01BzUav4FsjQEr84FY9MBTE3
