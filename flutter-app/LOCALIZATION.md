# Localizzazione App - Guida Completa

## 📋 Panoramica

L'app ora supporta completamente la localizzazione tramite Flutter's `flutter_localizations` e file ARB (Application Resource Bundle) compatibili con **OneSkyApp**.

**Lingue supportate:**
- 🇬🇧 Inglese (en) - Lingua base/template
- 🇮🇹 Italiano (it)
- 🇪🇸 Spagnolo (es)
- Català (ca)

**Totale stringhe localizzate:** ~180+ chiavi

---

## 📁 Struttura File

```
flutter-app/
├── l10n.yaml                           # Configurazione generazione localizzazioni
├── lib/
│   ├── l10n/
│   │   ├── app_en.arb                 # English (template)
│   │   ├── app_it.arb                 # Italiano
│   │   ├── app_es.arb                 # Español
│   │   └── app_ca.arb                 # Català
│   └── [screens]/                     # Tutte le schermate localizzate
├── .dart_tool/
│   └── flutter_gen/
│       └── gen_l10n/
│           ├── app_localizations.dart  # Classe generata automaticamente
│           ├── app_localizations_en.dart
│           ├── app_localizations_it.dart
│           ├── app_localizations_es.dart
│           └── app_localizations_ca.dart
```

---

## 🔧 Come Funziona

### 1. File ARB (JSON)

I file `.arb` sono file JSON che contengono tutte le stringhe tradotte. Esempio:

```json
{
  "@@locale": "it",
  "loginTitle": "Messaggistica Privata",
  "@loginTitle": {
    "description": "Titolo della schermata di login"
  },
  "error": "Errore: {error}",
  "@error": {
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  }
}
```

### 2. Generazione Automatica

Quando esegui `flutter pub get` o `flutter build`, Flutter genera automaticamente le classi Dart in `.dart_tool/flutter_gen/gen_l10n/`.

### 3. Uso nel Codice

```dart
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// In un widget
@override
Widget build(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;

  return Text(l10n.loginTitle);  // "Messaggistica Privata"

  // Con parametri
  return Text(l10n.error("Connessione fallita"));  // "Errore: Connessione fallita"
}
```

---

## 🌍 Integrazione con OneSkyApp

### Preparazione File per OneSkyApp

I file ARB sono **già compatibili** con OneSkyApp. Segui questi passaggi:

#### 1. Carica File Template (Italiano)

1. Vai su [OneSkyApp](https://www.oneskyapp.com/)
2. Crea un nuovo progetto o apri quello esistente
3. Carica `lib/l10n/app_it.arb` come **file template**
4. OneSkyApp riconoscerà automaticamente il formato ARB

#### 2. Aggiungi Traduzioni

OneSkyApp supporta due modalità:
- **Manuale:** Traduci direttamente nell'interfaccia web
- **Import:** Carica `app_en.arb` (o altri) per inizializzare le traduzioni

#### 3. Esporta Traduzioni

1. Esporta le traduzioni completate da OneSkyApp
2. Scarica i file ARB per ogni lingua
3. Sostituisci i file in `lib/l10n/`:
   - `app_it.arb` (italiano)
   - `app_en.arb` (inglese)
   - `app_es.arb` (spagnolo - se aggiungi)
   - etc.

#### 4. Aggiungi Nuove Lingue

Per aggiungere una nuova lingua (es. Spagnolo):

1. Crea `lib/l10n/app_es.arb` con lo stesso formato
2. Aggiungi la locale in `main.dart`:
   ```dart
   supportedLocales: const [
     Locale('it', ''),
     Locale('en', ''),
     Locale('es', ''),  // ← Nuova lingua
   ],
   ```
3. Esegui `flutter pub get` per generare le classi

---

## 📝 Gestione Stringhe

### Categorie di Stringhe

Le stringhe sono organizzate per schermata:

| Categoria | Prefisso | Esempio |
|-----------|----------|---------|
| Comuni | - | `cancel`, `done`, `error` |
| Login | `login` | `loginTitle`, `loginFailedError` |
| Settings | `settings` | `settingsTitle`, `settingsPairedStatus` |
| Chat | `chat` | `chatEmptyMessage`, `chatTypingIndicator` |
| Pairing | `pairing` | `pairingChoiceTitle` |
| QR | `qr` | `qrScannerTitle`, `qrDisplayTitle` |
| Media | `media` | `mediaNoPhotos`, `mediaLoadingImage` |
| PDF | `pdfViewer` | `pdfViewerLoading` |

### Stringhe con Parametri

Per stringhe con valori dinamici, usa placeholder:

**ARB:**
```json
{
  "error": "Errore: {error}",
  "@error": {
    "placeholders": {
      "error": {"type": "String"}
    }
  }
}
```

**Dart:**
```dart
l10n.error("Connessione fallita")  // → "Errore: Connessione fallita"
```

### Stringhe Multilinea

Le stringhe con `\n` sono supportate:

```json
{
  "chatEmptyMessage": "Nessun messaggio.\nInvia il primo!"
}
```

---

## 🔄 Workflow di Traduzione

### Setup Iniziale
```bash
cd flutter-app
flutter pub get  # Genera le classi di localizzazione
```

### Aggiungere Nuove Stringhe

1. **Aggiungi al template italiano** (`app_it.arb`):
   ```json
   {
     "newFeatureTitle": "Nuova Funzionalità",
     "@newFeatureTitle": {
       "description": "Titolo della nuova funzionalità"
     }
   }
   ```

2. **Aggiungi alle altre lingue** (`app_en.arb`):
   ```json
   {
     "newFeatureTitle": "New Feature"
   }
   ```

3. **Rigenera le classi:**
   ```bash
   flutter pub get
   ```

4. **Usa nel codice:**
   ```dart
   Text(l10n.newFeatureTitle)
   ```

### Sincronizzazione con OneSkyApp

**Push (Upload):**
```bash
# 1. Carica app_it.arb su OneSkyApp (manuale via web)
# 2. I traduttori lavorano su OneSkyApp
```

**Pull (Download):**
```bash
# 1. Scarica file ARB tradotti da OneSkyApp
# 2. Sostituisci i file in lib/l10n/
# 3. Rigenera
flutter pub get
```

---

## 🛠️ Comandi Utili

```bash
# Genera/rigenera classi di localizzazione
flutter pub get

# Build con localizzazioni
flutter build apk
flutter build ios

# Run con locale specifica (per testing)
flutter run --locale=it
flutter run --locale=en

# Verifica che tutti i file ARB siano validi
flutter analyze
```

---

## ✅ Checklist File Localizzati

Tutti i seguenti file sono stati localizzati:

- ✅ `lib/main.dart` - Configurazione app
- ✅ `lib/screens/login_screen.dart`
- ✅ `lib/screens/main_screen.dart`
- ✅ `lib/screens/pairing_choice_screen.dart`
- ✅ `lib/screens/qr_display_screen.dart`
- ✅ `lib/screens/qr_scanner_screen.dart`
- ✅ `lib/screens/pairing_wizard_screen.dart`
- ✅ `lib/screens/settings_screen.dart`
- ✅ `lib/screens/couple_selfie_screen.dart`
- ✅ `lib/screens/chat_screen.dart`
- ✅ `lib/screens/media_screen.dart`
- ✅ `lib/screens/pdf_viewer_screen.dart`

---

## 📊 Statistiche

- **File ARB:** 4 (en, it, es, ca)
- **Chiavi totali:** ~180+
- **Schermate localizzate:** 12
- **Lingue supportate:** 4
- **Stringhe con parametri:** ~15
- **Compatibilità:** OneSkyApp, Crowdin, Lokalise, POEditor

---

## 🚀 Prossimi Passi

1. **Testa l'app** su dispositivo per verificare che tutte le stringhe siano localizzate
2. **Carica su OneSkyApp** per gestire le traduzioni
3. **Aggiungi altre lingue** se necessario (es. spagnolo, francese, tedesco)
4. **Automatizza** l'import/export con OneSkyApp API (opzionale)

---

## 📞 Supporto

Per problemi o domande sulla localizzazione:
- Controlla [Flutter Internationalization Guide](https://docs.flutter.dev/development/accessibility-and-localization/internationalization)
- Consulta [OneSkyApp Documentation](https://github.com/onesky/api-documentation-platform)
- Verifica i file ARB con [ARB Validator](https://github.com/google/app-resource-bundle)
