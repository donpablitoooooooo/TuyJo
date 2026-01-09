# Widgets Riutilizzabili

Questa cartella contiene widget condivisi utilizzati in tutta l'applicazione per garantire consistenza UI/UX e facilitare la manutenzione.

## 📦 Widget Disponibili

### 1. TodoMessageBubble (`todo_bubble.dart`)

Widget per visualizzare bubble di messaggi TODO, utilizzato sia in `chat_screen` che in `calendar_screen`.

#### Utilizzo

```dart
TodoMessageBubble(
  message: message,                    // Oggetto Message con tipo 'todo'
  isMe: isMe,                          // true se creato da me, false se dal partner
  isCompleted: isCompleted,            // true se TODO completato
  onComplete: () => _completeTodo(),   // Callback per completare il TODO
  formattedDate: "25 gennaio, 10:00",  // Data formattata (opzionale)
  attachmentService: attachmentService, // Per mostrare allegati (opzionale)
  senderId: message.senderId,          // ID mittente per decrypt allegati
  currentUserId: myUserId,             // ID utente corrente per decrypt
)
```

#### Caratteristiche

- **Colori automatici**: Gradient viola/blu per `isMe: true`, grigio per `isMe: false`
- **Allegati integrati**: Se presenti, vengono mostrati automaticamente
- **Gestione completamento**: Long press per completare, con hint visivo
- **Icons contestuali**: Campanello per reminder, calendario per eventi
- **Strikethrough automatico**: Quando `isCompleted: true`

---

### 2. AttachmentImage (`attachment_widgets.dart`)

Widget per visualizzare immagini cifrate con thumbnail e visualizzazione fullscreen.

#### Utilizzo

```dart
AttachmentImage(
  attachment: attachment,              // Oggetto Attachment con type='photo'
  isMe: isMe,                         // Per determinare colori placeholder
  currentUserId: currentUserId,       // Per decifrare (chiave corretta)
  senderId: senderId,                 // Mittente originale
  attachmentService: attachmentService, // Service per download/decrypt
)
```

#### Caratteristiche

- **Thumbnail automatico**: Usa `useThumbnail: true` per performance
- **Click per fullscreen**: Apre `FullscreenImageViewer` con zoom
- **Loading state**: CircularProgressIndicator durante download
- **Error handling**: Icona errore rossa se decrypt fallisce
- **Encryption aware**: Gestisce chiavi separate per mittente/destinatario

---

### 3. AttachmentVideo (`attachment_widgets.dart`)

Widget placeholder per video cifrati (player in sviluppo).

#### Utilizzo

```dart
AttachmentVideo(
  attachment: attachment,              // Oggetto Attachment con type='video'
  isMe: isMe,
  currentUserId: currentUserId,
  senderId: senderId,
)
```

#### Caratteristiche

- **Placeholder visivo**: Icona play + nome file
- **Gradient overlay**: Gradiente nero trasparente
- **Click handler**: Mostra messaggio "In sviluppo"

---

### 4. AttachmentDocument (`attachment_widgets.dart`)

Widget per visualizzare e aprire documenti cifrati.

#### Utilizzo

```dart
AttachmentDocument(
  attachment: attachment,              // Oggetto Attachment con type='document'
  isMe: isMe,
  currentUserId: currentUserId,
  senderId: senderId,
  attachmentService: attachmentService,
)
```

#### Caratteristiche

- **PDF integrato**: Apre `PdfViewerScreen` per file .pdf
- **Documenti generici**: Download + apertura con app esterna (OpenFilex)
- **Progress indicator**: Mostra loading durante download
- **File info**: Nome file + dimensione formattata
- **Lock icon**: Indica cifratura E2E

---

### 5. FullscreenImageViewer (`attachment_widgets.dart`)

Visualizzatore fullscreen per immagini con zoom e overlay informativi.

#### Utilizzo

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (context) => FullscreenImageViewer(
      attachment: attachment,
      attachmentService: attachmentService,
      currentUserId: currentUserId,
      senderId: senderId,
    ),
  ),
);
```

#### Caratteristiche

- **InteractiveViewer**: Zoom 0.5x - 4.0x con gesture
- **Full resolution**: Carica immagine a risoluzione completa (non thumbnail)
- **Overlay animati**: Tap per mostrare/nascondere UI
- **Info file**: Nome, dimensione, stato cifratura
- **Close button**: IconButton in alto a destra

---

## 🎨 Design System

### Colori

```dart
// TODO creati da me
const myTodoGradient = LinearGradient(
  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// TODO del partner
final partnerTodoGradient = LinearGradient(
  colors: [Colors.grey[200]!, Colors.grey[100]!],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
```

### Border Radius

```dart
// Bubble TODO/messaggi
BorderRadius.only(
  topLeft: Radius.circular(20),
  topRight: Radius.circular(20),
  bottomLeft: isMe ? Radius.circular(20) : Radius.circular(4),
  bottomRight: isMe ? Radius.circular(4) : Radius.circular(20),
)

// Allegati
BorderRadius.circular(12)
```

### Shadows

```dart
BoxShadow(
  color: isMe
    ? Color(0xFF667eea).withOpacity(0.3)
    : Colors.black.withOpacity(0.08),
  blurRadius: 8,
  offset: Offset(0, 2),
)
```

---

## 🔐 Cifratura E2E

Tutti i widget allegati gestiscono automaticamente la cifratura end-to-end:

### Chiavi Separate

```dart
// Mittente usa la propria chiave privata
final decryptedBytes = await attachmentService.downloadAndDecryptAttachment(
  attachment,
  currentUserId,  // Se currentUserId == senderId, usa encryptedKeySender
  senderId,
  useThumbnail: true,
);

// Destinatario usa chiave cifrata per lui
// Se currentUserId != senderId, usa encryptedKeyRecipient
```

### Thumbnail vs Full Resolution

```dart
// Nelle griglie/liste: usa thumbnail
useThumbnail: true   // Scarica versione ottimizzata

// In fullscreen viewer: full res
useThumbnail: false  // Scarica immagine originale
```

---

## 📝 Best Practices

### 1. Quando usare TodoMessageBubble

✅ **Usa questo widget quando**:
- Visualizzi messaggi di tipo `'todo'` o `'reminder'`
- Vuoi consistenza tra chat e calendario
- Hai bisogno di mostrare allegati nel TODO

❌ **Non usare per**:
- Messaggi di testo normali (usa `_MessageBubble`)
- Liste semplici senza bubble (usa `ListTile`)

### 2. Gestione AttachmentService

```dart
// ✅ CORRETTO: Inizializza AttachmentService nello State
class _MyScreenState extends State<MyScreen> {
  AttachmentService? _attachmentService;

  @override
  void initState() {
    super.initState();
    _attachmentService = AttachmentService(
      encryptionService: encryptionService,
    );
  }
}

// ❌ SBAGLIATO: Non passare null se hai allegati
TodoMessageBubble(
  attachmentService: null,  // Gli allegati non verranno mostrati!
)
```

### 3. Performance

```dart
// ✅ Usa thumbnail per griglie/liste
AttachmentImage(..., useThumbnail: true)

// ✅ Usa full res solo per fullscreen
FullscreenImageViewer(..., useThumbnail: false)

// ✅ Usa ValueKey per rebuild efficienti
TodoMessageBubble(
  key: ValueKey('${message.id}_${message.read}'),
  ...
)
```

---

## 🔄 Aggiungere Nuovi Widget

Quando crei nuovi widget riutilizzabili:

1. **Crea file in questa cartella**
   ```
   flutter-app/lib/widgets/
   ├── todo_bubble.dart
   ├── attachment_widgets.dart
   └── nuovo_widget.dart  ← QUI
   ```

2. **Documenta parametri e utilizzo**
   - Aggiungi commenti Dart
   - Aggiorna questo README

3. **Segui il design system**
   - Usa colori/dimensioni consistenti
   - Border radius standard
   - Shadows uniformi

4. **Testa in più contesti**
   - Chat screen
   - Calendar screen
   - Altre schermate future

---

## 🐛 Debug

### Widget con allegati non mostrati

```dart
// 1. Verifica AttachmentService sia inizializzato
if (kDebugMode) {
  print('AttachmentService: ${_attachmentService != null}');
}

// 2. Verifica allegati nel messaggio
if (kDebugMode) {
  print('Attachments: ${message.attachments?.length ?? 0}');
}

// 3. Controlla userId corretti
if (kDebugMode) {
  print('Current: $currentUserId, Sender: $senderId');
}
```

### Immagini non decifrate

```dart
// Verifica chiavi di cifratura
final hasRecipientKey = attachment.encryptedKeyRecipient.isNotEmpty;
final hasSenderKey = attachment.encryptedKeySender.isNotEmpty;
final hasIV = attachment.iv.isNotEmpty;

if (kDebugMode) {
  print('Keys present: recipient=$hasRecipientKey, sender=$hasSenderKey, iv=$hasIV');
}
```

---

## 📚 Risorse

- **Flutter Docs**: [Building layouts](https://docs.flutter.dev/ui/layout)
- **Material Design**: [Cards](https://m3.material.io/components/cards)
- **InteractiveViewer**: [Zoom & Pan](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html)

---

**Ultimo aggiornamento**: 2026-01-09
**Versione app**: 1.11.0
