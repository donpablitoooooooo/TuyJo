#!/bin/bash
# Script to fix Xcode build phases order automatically
# Run this after pod install if you get dependency cycle errors

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PBXPROJ="$SCRIPT_DIR/../ios/Runner.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "❌ project.pbxproj not found"
    exit 1
fi

# Check if fix is needed
BUILD_PHASES=$(grep -A 15 "97C146ED1CF9000F007C117D.*Runner" "$PBXPROJ" | grep -A 12 "buildPhases = (")
THIN_POS=$(echo "$BUILD_PHASES" | grep -n "Thin Binary" | cut -d: -f1)
EMBED_POS=$(echo "$BUILD_PHASES" | grep -n "Embed Frameworks" | cut -d: -f1)

if [ -z "$THIN_POS" ] || [ -z "$EMBED_POS" ]; then
    echo "⚠️  Could not find build phases"
    exit 1
fi

if [ "$THIN_POS" -gt "$EMBED_POS" ]; then
    echo "✅ Build phases order is already correct"
    exit 0
fi

echo "🔧 Fixing build phases order..."

# The fix: In the Runner target's buildPhases array, move Thin Binary line after Embed Frameworks
# We use sed to do this

# Create backup
cp "$PBXPROJ" "$PBXPROJ.backup"

# This is tricky with sed, so we use a Python script for safety
export PBXPROJ
python3 << 'PYTHON_SCRIPT'
import re, os

pbxproj_path = os.environ['PBXPROJ']

with open(pbxproj_path, "r") as f:
    content = f.read()

# Find the Runner target's buildPhases section
# Pattern: buildPhases = ( ... ); for the Runner target (97C146ED1CF9000F007C117D)
pattern = r'(97C146ED1CF9000F007C117D /\* Runner \*/ = \{[^}]*buildPhases = \()([^)]+)(\);)'

def fix_order(match):
    prefix = match.group(1)
    phases = match.group(2)
    suffix = match.group(3)

    # Split into lines
    lines = [l.strip() for l in phases.strip().split('\n') if l.strip()]

    # Find Thin Binary and Embed Frameworks
    thin_binary_line = None
    thin_binary_idx = None
    embed_frameworks_idx = None

    for i, line in enumerate(lines):
        if 'Thin Binary' in line:
            thin_binary_line = line
            thin_binary_idx = i
        if 'Embed Frameworks' in line and 'Embed Pods Frameworks' not in line:
            embed_frameworks_idx = i

    if thin_binary_idx is not None and embed_frameworks_idx is not None:
        if thin_binary_idx < embed_frameworks_idx:
            # Need to fix - remove from current position and insert after Embed Frameworks
            lines.pop(thin_binary_idx)
            # Recalculate embed_frameworks_idx since we removed an element before it
            embed_frameworks_idx -= 1
            lines.insert(embed_frameworks_idx + 1, thin_binary_line)
            print("Fixed: Moved Thin Binary after Embed Frameworks")

    # Reconstruct with proper formatting
    formatted_phases = '\n' + '\n'.join('\t\t\t\t' + l for l in lines) + '\n\t\t\t'
    return prefix + formatted_phases + suffix

new_content = re.sub(pattern, fix_order, content, flags=re.DOTALL)

if new_content != content:
    with open(pbxproj_path, "w") as f:
        f.write(new_content)
    print("✅ File updated successfully")
else:
    print("ℹ️  No changes needed or pattern not found")
PYTHON_SCRIPT

echo "Done. If the build still fails, restore backup with:"
echo "  cp $PBXPROJ.backup $PBXPROJ"
