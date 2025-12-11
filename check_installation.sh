#!/bin/bash

echo "🔍 Script di verifica installazione YouAndMe"
echo "=============================================="
echo ""

# 1. Mostra directory corrente
echo "📁 Directory corrente:"
pwd
echo ""

# 2. Verifica se siamo nella root del progetto
if [ -f "README.md" ] && [ -d "flutter-app" ]; then
    echo "✅ Sei nella root del progetto youandme"
else
    echo "❌ NON sei nella root del progetto youandme"
    echo "   Naviga alla directory dove hai clonato il repository"
    exit 1
fi

# 3. Verifica presenza flutter-app
echo ""
echo "📂 Contenuto della directory flutter-app:"
ls -la flutter-app/ | head -15
echo ""

# 4. Verifica pubspec.yaml
if [ -f "flutter-app/pubspec.yaml" ]; then
    echo "✅ File flutter-app/pubspec.yaml TROVATO!"
    echo ""
    echo "📄 Prime righe del file:"
    head -10 flutter-app/pubspec.yaml
else
    echo "❌ File flutter-app/pubspec.yaml NON TROVATO"
fi

# 5. Verifica git status
echo ""
echo "📊 Git status:"
git status -s

# 6. Verifica branch
echo ""
echo "🌿 Branch corrente:"
git branch --show-current

echo ""
echo "=============================================="
echo "✅ Verifica completata!"
echo ""
echo "🚀 Per installare le dipendenze Flutter, esegui:"
echo "   cd flutter-app"
echo "   flutter pub get"
