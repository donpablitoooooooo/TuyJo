# Guida Pubblicazione App Store (iOS)

## Prerequisiti

✅ Account Apple Developer (99$ all'anno)
✅ Mac con Xcode installato
✅ Bundle ID: `com.tuyjo.app`

---

## Step 1: Configurazione Xcode

### 1.1 Apri il progetto
```bash
cd flutter-app
open ios/Runner.xcworkspace
```

**IMPORTANTE:** Se non esiste `Runner.xcworkspace`, esegui prima:
```bash
cd flutter-app
flutter pub get
cd ios
pod install
```

### 1.2 Configura Bundle Identifier
1. In Xcode, seleziona **Runner** nel navigator (a sinistra)
2. Seleziona il target **Runner**
3. Nella tab **General**:
   - **Bundle Identifier**: `com.tuyjo.app`
   - **Display Name**: `TuyJo`
   - **Version**: `1.12.0`
   - **Build**: `13`

### 1.3 Configura Signing & Capabilities
1. Nella tab **Signing & Capabilities**:
   - ☑️ **Automatically manage signing**
   - **Team**: Seleziona il tuo team Apple Developer
   - **Provisioning Profile**: Automatic

Se hai errori, assicurati di:
- Aver pagato l'Apple Developer Program
- Aver aggiunto il tuo Apple ID in Xcode > Preferences > Accounts

---

## Step 2: Build per App Store

### Opzione A: Da terminale (consigliato)
```bash
cd flutter-app
flutter build ipa --release
```

Il file IPA sarà in:
```
build/ios/ipa/TuyJo.ipa
```

### Opzione B: Da Xcode
1. In Xcode, seleziona **Product > Archive**
2. Quando finisce, si apre Organizer
3. Clicca **Distribute App**
4. Scegli **App Store Connect**
5. Segui la procedura guidata

---

## Step 3: Crea App su App Store Connect

1. Vai su [App Store Connect](https://appstoreconnect.apple.com)
2. Clicca **My Apps** > **+** > **New App**
3. Compila:
   - **Platform**: iOS
   - **Name**: TuyJo
   - **Primary Language**: Italian
   - **Bundle ID**: com.tuyjo.app
   - **SKU**: com.tuyjo.app (o altro codice univoco)
4. Clicca **Create**

---

## Step 4: Upload dell'IPA

### Metodo 1: Transporter (più semplice)
1. Apri l'app **Transporter** (preinstallata su Mac)
2. Accedi con il tuo Apple ID
3. Trascina il file `TuyJo.ipa` nella finestra
4. Clicca **Deliver**

### Metodo 2: Da terminale
```bash
xcrun altool --upload-app --type ios --file build/ios/ipa/TuyJo.ipa \
  --username "TUO_APPLE_ID" \
  --password "PASSWORD_SPECIFICO_APP"
```

**Nota:** Usa una password specifica per app da appleid.apple.com

---

## Step 5: Informazioni App Store

Torna su App Store Connect e compila:

### 5.1 App Information
- **Name**: TuyJo
- **Subtitle** (30 chars): Chat sicura per due persone
- **Privacy Policy URL**: https://tuyjo.com/privacy (o il tuo)
- **Category**: Social Networking
- **Secondary Category**: (opzionale)

### 5.2 Pricing and Availability
- **Price**: Free
- **Availability**: All countries

### 5.3 App Privacy
Devi rispondere alle domande sulla privacy. Per TuyJo:
- ☑️ **Raccogli dati?** Sì (foto, messaggi)
- **Dati raccolti**: User Content, Photos
- **Scopo**: App Functionality
- **I dati vengono condivisi?** No
- **I dati sono crittografati?** Sì (end-to-end)

### 5.4 Versione per la revisione

1. Clicca sulla versione `1.12.0`
2. **Screenshots** (obbligatori):
   - iPhone 6.5": 1242×2688 (minimo 3)
   - iPhone 6.7": 1290×2796 (minimo 3)
   - iPhone 5.5": 1242×2208 (minimo 3 se supporti iOS vecchi)

   Usa lo stesso metodo degli screenshot Android.

3. **App Descriptions**:

**Italiano** (usa le descrizioni da `play-store-descriptions.md`):
```
Messaggistica privata, solo per voi due

TuyJo è l'app di messaggistica crittografata progettata per due persone.
Un'esperienza intima e sicura dove condividere i vostri momenti speciali.

CARATTERISTICHE PRINCIPALI
• Crittografia end-to-end (RSA-2048 + AES-256)
• Accoppiamento sicuro tramite codice univoco
• Chat, foto e video criptati
• Selfie di coppia sincronizzati
• Completamente privato - i tuoi dati restano tuoi
• Interfacce pulita e moderna

SICUREZZA E PRIVACY
I tuoi messaggi sono protetti con crittografia militare.
Solo tu e il tuo partner potete leggerli.

PERFETTO PER
• Coppie che vogliono privacy totale
• Amici che condividono momenti speciali
• Chiunque cerchi una comunicazione veramente privata

Scarica TuyJo e inizia a comunicare in totale sicurezza.
```

4. **Keywords** (100 chars max):
```
chat,coppia,messaggi,crittografia,privacy,sicuro,privato,due,love
```

5. **Support URL**: https://tuyjo.com/support
6. **Marketing URL**: https://tuyjo.com

7. **Build**: Seleziona la build che hai caricato

8. **Age Rating**:
   - **17+** (per contenuti generati dagli utenti non moderati)

9. **Copyright**: 2025 TuyJo

10. **Contact Information**:
    - Il tuo nome, email, telefono

---

## Step 6: Invia per Revisione

1. Verifica che tutto sia compilato (pallino verde ✓)
2. Clicca **Add for Review** in alto a destra
3. Rispondi alle domande finali:
   - **Advertising Identifier**: No
   - **Content Rights**: Yes, hai i diritti
   - **Export Compliance**: Sì, l'app usa crittografia (devi rispondere)
4. Clicca **Submit for Review**

---

## Timeline

- **Processing**: 10-30 minuti (dopo upload)
- **Waiting for Review**: 1-3 giorni di solito
- **In Review**: 24-48 ore
- **Approved**: Pubblicata automaticamente o quando scegli tu

---

## Comandi Utili

### Verifica bundle identifier corrente
```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" ios/Runner/Info.plist
```

### Incrementa build number
```bash
flutter build ipa --release --build-number=14
```

### Pulisci e rebuilda
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```

---

## Troubleshooting

### "No signing certificate found"
- Vai su Xcode > Preferences > Accounts
- Aggiungi il tuo Apple ID
- In **Signing & Capabilities**, seleziona il Team

### "Bundle identifier is not available"
- Verifica di aver pagato l'Apple Developer Program
- Prova con un bundle ID diverso (es. com.tuyjo.app.ios)

### "Upload failed"
- Verifica di aver accettato i nuovi Terms su appstoreconnect.apple.com
- Usa password specifica per app, non la password principale

### "Missing compliance"
Devi rispondere alle domande sulla crittografia:
1. La tua app usa crittografia? **Sì**
2. La tua app usa crittografia standard? **Sì** (iOS/Android standard)
3. La tua app è crittografia proprietaria? **No**

---

## Checklist Finale

Prima di sottomettere:
- ☐ Bundle ID: `com.tuyjo.app`
- ☐ Versione: `1.12.0 (13)`
- ☐ Icone: tutte le dimensioni presenti
- ☐ Screenshots: minimo 3 per dimensione
- ☐ Descrizioni: in almeno 1 lingua
- ☐ Privacy Policy: URL funzionante
- ☐ Build caricata e selezionata
- ☐ Tutte le info compilate (pallini verdi)

---

## Note Importanti

1. **Privacy Policy obbligatoria**: Devi avere un URL pubblico con la privacy policy
2. **Export Compliance**: Devi dichiarare l'uso della crittografia
3. **Revisione**: Apple è più restrittiva di Google, potrebbero rifiutare per:
   - Privacy policy mancante/inadeguata
   - Content generato da utenti non moderato
   - Funzionalità non complete/rotte
4. **Update**: Per aggiornamenti futuri, incrementa solo il build number se sono bugfix, o la version se sono nuove feature

---

## Link Utili

- [App Store Connect](https://appstoreconnect.apple.com)
- [Apple Developer](https://developer.apple.com)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Flutter iOS Deployment](https://docs.flutter.dev/deployment/ios)
