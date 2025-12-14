# To Do & Reminders Feature

## Panoramica

Feature di promemoria per eventi importanti (compleanni, anniversari, appuntamenti) integrata nella chat di famiglia con crittografia end-to-end.

## Caratteristiche

### ✅ Implementato

- **To Do come messaggi cifrati**: I todo sono messaggi speciali con campi aggiuntivi (`messageType: 'todo'`, `dueDate`, `completed`)
- **Crittografia E2E**: Contenuto del todo cifrato con dual encryption (RSA-2048 + AES-256)
- **Notifiche duali**:
  - **Instant FCM**: quando il partner crea un todo (titolo: `📅 Nuovo To Do`)
  - **Scheduled local**: 1 ora prima dell'evento (titolo: `🔔 Nuovo To Do`)
- **UI distintiva**:
  - Bordo arancione: todo attivo
  - Bordo rosso: scaduto
  - Bordo verde: completato
- **Completamento bidirezionale**: entrambi i partner possono marcare completato
- **Modalità test**: slider 10-3600 secondi per testing rapido
- **Timezone auto-detection**: rileva automaticamente timezone dal device offset

### 🏗️ Architettura

```
┌─────────────────────────────────────────────────────┐
│                  CREATE TODO                        │
│  User A → CreateTodoDialog → ChatService.sendTodo  │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│              FIRESTORE MESSAGE                      │
│  {                                                  │
│    message_type: 'todo',  ← non cifrato            │
│    encrypted_key_recipient: '...',                 │
│    encrypted_key_sender: '...',                    │
│    iv: '...',                                      │
│    message: '...' ← plaintext cifrato:             │
│      {                                             │
│        sender: 'device_id',                        │
│        timestamp: 1234567890,                      │
│        type: 'todo',                               │
│        body: 'Nome del todo cifrato',              │
│        due_date: '2024-12-31T10:00:00.000'         │
│      }                                             │
│  }                                                 │
└──────────────────┬──────────────────────────────────┘
                   │
                   ├─────────────────────────────────┐
                   ▼                                 ▼
┌────────────────────────────┐   ┌──────────────────────────────┐
│    CLOUD FUNCTION (FCM)    │   │    FIRESTORE LISTENER        │
│  sendMessageNotification   │   │  ChatService.startListening  │
│                            │   │                              │
│  if (message_type='todo')  │   │  _decryptAndPopulateMessage  │
│    title: 📅 Nuovo To Do   │   │    ↓                         │
│    body: "Il tuo partner   │   │  scheduleReminderNotif       │
│           ha creato..."    │   │    ↓                         │
│                            │   │  NotificationService         │
│  → User B (instant)        │   │    .scheduleNotification     │
└────────────────────────────┘   │      ↓                       │
                                 │  flutter_local_notifications │
                                 │  (inexact, 1h before)        │
                                 │                              │
                                 │  → Both users at reminder    │
                                 │     time                     │
                                 └──────────────────────────────┘
```

### 📱 Componenti

**Flutter App:**
- `Message` model: campi `messageType`, `dueDate`, `completed`, `originalTodoId`
- `ChatService.sendTodo()`: encrypts & saves todo message
- `ChatService.sendTodoCompletion()`: marks todo as completed
- `ChatService._scheduleReminderNotification()`: schedules local notification
- `NotificationService.scheduleNotification()`: uses `flutter_local_notifications` with inexact alarms
- `TodoMessageBubble`: widget UI con colori diversi (orange/red/green)
- `CreateTodoDialog`: form con toggle test mode

**Cloud Function:**
- `sendMessageNotification()`: invia FCM push quando arriva un nuovo messaggio
- Distingue per `message_type`:
  - `'todo'` → `📅 Nuovo To Do`
  - `'todo_completed'` → nessuna notifica
  - `'text'` → `💬 Nuovo messaggio`

**Firestore Schema:**
```javascript
families/{familyChatId}/messages/{messageId}
{
  sender_id: string,
  encrypted_key_recipient: string,  // AES key encrypted with recipient RSA public
  encrypted_key_sender: string,     // AES key encrypted with sender RSA public
  iv: string,                       // AES IV
  message: string,                  // AES encrypted JSON plaintext
  created_at: string (ISO 8601),
  message_type: 'text' | 'todo' | 'todo_completed'  // ← UNENCRYPTED for Cloud Function filtering
}
```

### 🔧 Configurazione Notifiche

**FCM (Cloud Function):**
```javascript
android: {
  notification: {
    channelId: 'messages_channel',
    priority: 'default',
    sound: 'default',
  }
}
```

**Scheduled Local (Flutter):**
```dart
AndroidNotificationDetails(
  channelKey: 'todo_reminders',
  importance: Importance.defaultImportance,
  priority: Priority.defaultPriority,
  icon: 'ic_notification',  // ← CRITICO: stessa icona di FCM
)
androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle
```

### 🐛 Problemi Risolti

#### 1. **Icon Inflation Exception** ⚠️ CRITICO
- **Problema**: Scheduled notifications fallivano silenziosamente con `InflationException: Couldn't create icon`
- **Causa**: Usavano `icon: '@mipmap/ic_launcher'` invece di `icon: 'ic_notification'`
- **Fix**: Usare la stessa icona delle FCM notifications
- **Commit**: `7d1fc5d`

#### 2. **Timezone Detection**
- **Problema**: Hardcoded `Europe/Rome` causava problemi per utenti in altri timezone
- **Tentativi falliti**: `flutter_native_timezone` (namespace error), `flutter_timezone` (Kotlin error)
- **Soluzione**: Detect timezone da `DateTime.now().timeZoneOffset` e mapping manuale
- **Commit**: `3385a80`

#### 3. **Test Mode Reminder in the Past**
- **Problema**: Con 60 secondi, `dueDate = now + 60s`, poi `reminderTime = dueDate - 1h` (passato!)
- **Fix**: In test mode, `dueDate = now + seconds + 1h`, così `reminderTime = now + seconds`

#### 4. **Exact Alarms Permission**
- **Problema**: `AndroidScheduleMode.exactAllowWhileIdle` richiedeva permesso utente aggiuntivo
- **Decisione**: Usare `inexactAllowWhileIdle` (±15min acceptable per reminder 1h prima)
- **Commit**: `dc9cd40`

#### 5. **awesome_notifications Compatibility**
- **Problema**: `awesome_notifications 0.9.3+1` non compila con Flutter moderno (missing PluginRegistry symbols)
- **Soluzione**: Revert a `flutter_local_notifications 17.0.0`
- **Commits**: `d310994` (tentativo), `5617bd5` (revert)

### 📋 Dipendenze

```yaml
dependencies:
  flutter_local_notifications: ^17.0.0
  timezone: ^0.9.2
  intl: ^0.18.1
```

**Android Permissions:**
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/> <!-- unused with inexact -->
```

**Android Receivers:**
```xml
<receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
    </intent-filter>
</receiver>
```

### 🧪 Testing

**Test Mode (developer):**
1. Tap calendar icon nella chat
2. Toggle "Modalità Test" ON
3. Slider: 10-3600 secondi
4. Crea todo
5. Aspetta i secondi impostati → arriva notifica `🔔 Nuovo To Do`

**Normal Mode (production):**
1. Tap calendar icon
2. Inserisci nome todo
3. Seleziona data e ora
4. Crea
5. Partner riceve instant FCM: `📅 Nuovo To Do`
6. Entrambi ricevono scheduled: `🔔 Nuovo To Do` 1 ora prima

### 🎯 Limitazioni Note

- **Inexact Alarms**: possono ritardare ±15 minuti (Android battery optimization)
- **Device Spento**: se il dispositivo è spento al momento del reminder, la notifica **non arriva** (nessun catch-up)
- **Privacy Trade-off**: `message_type` e `due_date` **non cifrati** in Firestore (necessari per Cloud Function)

### 🚀 Future Enhancements (non implementati)

- **Cloud Scheduling**: per affidabilità 100% indipendente dal device
- **AI Todo Extraction**: analisi automatica messaggi per creare todo ("domani è il compleanno di Elena" → auto-crea todo)
- **Recurring Reminders**: eventi ripetuti (ogni anno, ogni mese)
- **Snooze**: posticipa reminder di X minuti/ore

### 📊 Commits Summary

| Commit | Descrizione |
|--------|-------------|
| `7d1fc5d` | 🐛 **FIX CRITICO**: Use ic_notification icon |
| `44a6461` | 🔍 Add pending notification IDs debug logs |
| `dbf5190` | 🧹 Use _todoChannel for consistency |
| `69ef8f6` | ⚙️ Use same settings as FCM (default priority) |
| `abfdc93` | 🎨 Add notification type differentiation |
| `3385a80` | 🌍 Timezone auto-detection from device offset |

---

**Total commits in feature**: 15
**Lines changed**: ~1200 additions, ~300 deletions
**Files modified**: 8 (Flutter app: 5, Cloud Function: 1, Android: 2)

## Deployment

1. **Flutter App**: `flutter build apk --release`
2. **Cloud Function**: `cd functions && firebase deploy --only functions`
3. **Verifica**: Crea todo in test mode (60s) → attendi 1 min → notifica deve arrivare

## Contatti Bug Report

Se le scheduled notifications non arrivano:
1. Controlla logcat per `InflationException`
2. Verifica `Pending IDs` nei log dopo creazione todo
3. Disabilita battery optimization per l'app
4. Considera cloud scheduling se persistente
