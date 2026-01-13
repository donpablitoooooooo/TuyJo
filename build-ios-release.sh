#!/bin/bash

# Script automatico per build iOS release TuyJo
# Colori per output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🍎 TuyJo - Build iOS Release Script${NC}"
echo "======================================"

# Vai nella directory flutter-app (usa percorso relativo allo script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/flutter-app" || exit 1

# 1. Pulizia
echo -e "\n${YELLOW}📦 Step 1: Pulizia progetto...${NC}"
flutter clean
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Errore durante flutter clean${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Pulizia completata${NC}"

# 2. Dipendenze
echo -e "\n${YELLOW}📥 Step 2: Download dipendenze Flutter...${NC}"
flutter pub get
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Errore durante flutter pub get${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Dipendenze Flutter scaricate${NC}"

# 3. CocoaPods
echo -e "\n${YELLOW}🍫 Step 3: Installazione CocoaPods...${NC}"
cd ios
pod install
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Errore durante pod install${NC}"
    echo -e "${YELLOW}💡 Suggerimento: Assicurati che CocoaPods sia installato (sudo gem install cocoapods)${NC}"
    exit 1
fi
cd ..
echo -e "${GREEN}✅ CocoaPods installati${NC}"

# 4. Build IPA
echo -e "\n${YELLOW}🔨 Step 4: Build IPA release...${NC}"
echo -e "${YELLOW}⚠️  Questo richiede Xcode e un account Apple Developer configurato${NC}"
flutter build ipa --release
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Errore durante build IPA${NC}"
    echo -e "${YELLOW}💡 Possibili cause:${NC}"
    echo "   - Team Apple Developer non configurato in Xcode"
    echo "   - Signing certificate mancante"
    echo "   - Bundle ID non registrato"
    echo ""
    echo -e "${YELLOW}📖 Consulta app-store-guide.md per la configurazione${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Build completata!${NC}"

# 5. Verifica output
IPA_PATH="build/ios/ipa/TuyJo.ipa"
if [ -f "$IPA_PATH" ]; then
    IPA_SIZE=$(ls -lh "$IPA_PATH" | awk '{print $5}')
    echo -e "\n${GREEN}🎉 SUCCESS!${NC}"
    echo "======================================"
    echo -e "📦 IPA creato: ${GREEN}$IPA_PATH${NC}"
    echo -e "📏 Dimensione: ${GREEN}$IPA_SIZE${NC}"
    echo -e "🔑 Bundle ID: ${GREEN}com.tuyjo.app${NC}"
    echo -e "📱 Versione: ${GREEN}1.12.0+13${NC}"
    echo ""
    echo "🚀 Prossimi passi:"
    echo "1. Apri Transporter app"
    echo "2. Trascina il file IPA"
    echo "3. Clicca 'Deliver' per caricare su App Store Connect"
    echo "4. Compila le informazioni su appstoreconnect.apple.com"
    echo "5. Aggiungi screenshot (minimo 3)"
    echo "6. Invia per revisione"
    echo ""
    echo -e "${YELLOW}📖 Guida completa: app-store-guide.md${NC}"
else
    echo -e "${RED}❌ IPA non trovato!${NC}"
    exit 1
fi
