#!/bin/bash
# Script to validate Xcode build phases order
# Thin Binary MUST come AFTER Embed Frameworks to avoid dependency cycle

PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "⚠️  project.pbxproj not found, skipping check"
    exit 0
fi

# Extract the Runner buildPhases section and check order
# Thin Binary ID: 3B06AD1E1E4923F5004D2608
# Embed Frameworks ID: 9705A1C41CF9048500538489

# Get line numbers
THIN_BINARY_LINE=$(grep -n "3B06AD1E1E4923F5004D2608.*Thin Binary" "$PBXPROJ" | grep "buildPhases" -A 20 | head -1 | cut -d: -f1)
EMBED_FRAMEWORKS_LINE=$(grep -n "9705A1C41CF9048500538489.*Embed Frameworks" "$PBXPROJ" | grep "buildPhases" -A 20 | head -1 | cut -d: -f1)

# Simpler approach: just check the buildPhases array order
BUILD_PHASES=$(grep -A 15 "97C146ED1CF9000F007C117D.*Runner" "$PBXPROJ" | grep -A 12 "buildPhases = (")

THIN_POS=$(echo "$BUILD_PHASES" | grep -n "Thin Binary" | cut -d: -f1)
EMBED_POS=$(echo "$BUILD_PHASES" | grep -n "Embed Frameworks" | cut -d: -f1)

if [ -z "$THIN_POS" ] || [ -z "$EMBED_POS" ]; then
    echo "⚠️  Could not find build phases, skipping check"
    exit 0
fi

if [ "$THIN_POS" -lt "$EMBED_POS" ]; then
    echo "❌ ERROR: Thin Binary is BEFORE Embed Frameworks!"
    echo ""
    echo "This will cause a dependency cycle error in Xcode."
    echo ""
    echo "FIX: In ios/Runner.xcodeproj/project.pbxproj, find the Runner target's"
    echo "buildPhases array and move 'Thin Binary' AFTER 'Embed Frameworks'."
    echo ""
    echo "Correct order should be:"
    echo "  1. [CP] Check Pods Manifest.lock"
    echo "  2. Run Script"
    echo "  3. Sources"
    echo "  4. Frameworks"
    echo "  5. Resources"
    echo "  6. Embed Frameworks"
    echo "  7. Thin Binary  <-- MUST be here"
    echo "  8. [CP] Embed Pods Frameworks"
    echo "  9. [CP] Copy Pods Resources"
    echo "  10. Embed Foundation Extensions"
    exit 1
fi

echo "✅ Build phases order is correct (Thin Binary after Embed Frameworks)"
exit 0
