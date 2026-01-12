#!/bin/bash

# Script automatico per build release TuyJo
# Colori per output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 TuyJo - Build Release Script${NC}"
echo "================================="

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
echo -e "\n${YELLOW}📥 Step 2: Download dipendenze...${NC}"
flutter pub get
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Errore durante flutter pub get${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Dipendenze scaricate${NC}"

# 3. Verifica configurazione
echo -e "\n${YELLOW}🔍 Step 3: Verifica configurazione...${NC}"
if [ ! -f "../tuyjo-release-key.jks" ]; then
    echo -e "${RED}❌ Keystore non trovato: tuyjo-release-key.jks${NC}"
    exit 1
fi
if [ ! -f "android/key.properties" ]; then
    echo -e "${RED}❌ File key.properties non trovato${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Configurazione OK${NC}"

# 4. Build AAB
echo -e "\n${YELLOW}🔨 Step 4: Build AAB release...${NC}"
flutter build appbundle --release
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Errore durante build AAB${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Build completata!${NC}"

# 5. Verifica output
AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
if [ -f "$AAB_PATH" ]; then
    AAB_SIZE=$(ls -lh "$AAB_PATH" | awk '{print $5}')
    echo -e "\n${GREEN}🎉 SUCCESS!${NC}"
    echo "================================="
    echo -e "📦 AAB creato: ${GREEN}$AAB_PATH${NC}"
    echo -e "📏 Dimensione: ${GREEN}$AAB_SIZE${NC}"
    echo -e "🔑 Bundle ID: ${GREEN}com.tuyjo.app${NC}"
    echo -e "📱 Versione: ${GREEN}1.12.0+13${NC}"
    echo ""
    echo "🚀 Prossimi passi:"
    echo "1. Upload su Google Play Console"
    echo "2. Aggiungi descrizioni (vedi play-store-descriptions.md)"
    echo "3. Carica screenshot (minimo 2)"
    echo "4. Invia per revisione"
else
    echo -e "${RED}❌ AAB non trovato!${NC}"
    exit 1
fi
