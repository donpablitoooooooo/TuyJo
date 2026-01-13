# Checklist App Store - TuyJo

## ⚠️ PREREQUISITI OBBLIGATORI

### 1. Account Apple Developer (99$/anno)
- [ ] Registrato su https://developer.apple.com
- [ ] Pagamento effettuato e account attivo
- [ ] Agreement accettato

### 2. Xcode configurato
- [ ] Xcode installato (dall'App Store)
- [ ] Command Line Tools installati: `xcode-select --install`
- [ ] Account Apple ID aggiunto in Xcode > Preferences > Accounts
- [ ] Team selezionato

### 3. CocoaPods installato
```bash
sudo gem install cocoapods
```

---

## 📋 PRIMA DI BUILDARE

### Setup progetto
```bash
cd flutter-app
flutter pub get
cd ios
pod install
cd ..
```

### Apri in Xcode
```bash
open ios/Runner.xcworkspace
```

### Configura in Xcode:
1. **Seleziona Runner** nel navigator
2. **General Tab**:
   - Bundle Identifier: `com.tuyjo.app`
   - Display Name: `TuyJo`
   - Version: `1.12.0`
   - Build: `13`

3. **Signing & Capabilities Tab**:
   - ☑️ Automatically manage signing
   - Team: [Il tuo team Developer]

---

## 🏗️ BUILD

### Esegui lo script:
```bash
./build-ios-release.sh
```

Oppure manualmente:
```bash
cd flutter-app
flutter build ipa --release
```

L'IPA sarà in: `flutter-app/build/ios/ipa/TuyJo.ipa`

---

## 📤 UPLOAD SU APP STORE

### Metodo 1: Transporter (più facile)
1. Apri app **Transporter**
2. Accedi con Apple ID
3. Trascina `TuyJo.ipa`
4. Clicca **Deliver**

### Metodo 2: Da Xcode
1. Product > Archive
2. Distribute App
3. App Store Connect
4. Upload

---

## 🌐 APP STORE CONNECT

### Vai su: https://appstoreconnect.apple.com

### 1. Crea nuova app
- My Apps > + > New App
- Name: **TuyJo**
- Bundle ID: **com.tuyjo.app**
- Language: **Italian**
- SKU: `tuyjo-ios`

### 2. Compila informazioni
- [ ] **App Name**: TuyJo
- [ ] **Subtitle**: Chat sicura per due persone
- [ ] **Description**: (usa play-store-descriptions.md)
- [ ] **Keywords**: chat,coppia,messaggi,crittografia,privacy,sicuro
- [ ] **Support URL**: https://tuyjo.com/support
- [ ] **Privacy Policy URL**: ⚠️ OBBLIGATORIO

### 3. Privacy Policy
**⚠️ DEVI AVERE UN URL PUBBLICO!**

Opzioni:
- Crea una pagina sul sito tuyjo.com/privacy
- Usa servizi come:
  - https://www.termsfeed.com (genera gratis)
  - https://www.freeprivacypolicy.com
  - https://www.privacypolicies.com

### 4. Screenshots (OBBLIGATORI)
Devi caricare almeno 3 screenshot per:
- iPhone 6.7" (1290×2796) - iPhone 14 Pro Max, 15 Pro Max
- iPhone 6.5" (1242×2688) - iPhone 11 Pro Max, XS Max

Come fare:
```bash
# Avvia simulatore
open -a Simulator

# Scegli iPhone 14 Pro Max o 15 Pro Max
# Apri l'app e premi CMD+S per screenshot
```

Screenshot da fare:
1. **Chat principale** - mostra conversazione
2. **Accoppiamento** - schermata codice
3. **Profilo coppia** - foto/info coppia

### 5. App Privacy Questions
- **Raccogli dati?** Sì
  - User Content (Messages)
  - Photos
- **Dati condivisi con terze parti?** No
- **Dati usati per tracciamento?** No
- **Crittografia?** Sì (end-to-end)

### 6. Age Rating
- Seleziona **17+** (per User Generated Content non moderato)

### 7. Seleziona Build
- Aspetta che la build sia "Processing" → "Ready to Submit"
- Selezionala nella sezione Build

### 8. Export Compliance
⚠️ **Domanda critica sulla crittografia:**

Domanda: "Is your app designed to use cryptography or does it contain or incorporate cryptography?"
Risposta: **YES**

Domanda: "Does your app qualify for any of the exemptions provided in Category 5, Part 2?"
Risposta: **YES** - perché usi standard encryption (iOS/Android)

Non serve documentazione aggiuntiva per crittografia standard.

---

## 🚀 SUBMIT PER REVISIONE

### Prima di cliccare Submit:
- [ ] Tutti i campi compilati (pallini verdi ✓)
- [ ] Build selezionata
- [ ] Screenshots caricati (min 3 per size)
- [ ] Privacy Policy URL valido
- [ ] Description in almeno 1 lingua
- [ ] Export Compliance risolta

### Clicca: **Submit for Review**

---

## ⏱️ TEMPI

- **Processing build**: 10-30 minuti
- **Waiting for Review**: 1-3 giorni
- **In Review**: 24-48 ore
- **Approved**: Pubblicata subito o quando scegli

**Nota:** Il primo submit di solito è più lento.

---

## ❌ PROBLEMI COMUNI

### "No signing certificate"
Soluzione: Xcode > Preferences > Accounts > Aggiungi Apple ID

### "Bundle ID not available"
Soluzione: Verifica di aver pagato Apple Developer Program

### "Export Compliance missing"
Soluzione: Rispondi alle domande sulla crittografia (vedi sopra)

### "Privacy Policy URL invalid"
Soluzione: Deve essere un URL pubblico HTTPS funzionante

### "Screenshots missing"
Soluzione: Devi caricare min 3 screenshot per iPhone 6.7" e 6.5"

---

## 📞 SUPPORTO

- **Apple Developer Support**: https://developer.apple.com/support/
- **App Store Guidelines**: https://developer.apple.com/app-store/review/guidelines/
- **Flutter iOS Deployment**: https://docs.flutter.dev/deployment/ios

---

## 🎯 QUICK START

Hai tutto pronto? Vai:

1. **Build**: `./build-ios-release.sh`
2. **Upload**: Apri Transporter, trascina IPA
3. **Configure**: https://appstoreconnect.apple.com
4. **Submit**: Clicca Submit for Review

Tempo stimato: 2-3 ore per la prima volta.

---

**⚠️ IMPORTANTE:**
- Apple è più restrittiva di Google
- Privacy Policy è OBBLIGATORIA
- Screenshots sono OBBLIGATORI
- Export Compliance va dichiarata

**Buona fortuna! 🚀**
