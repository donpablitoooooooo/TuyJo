#!/bin/bash
# Setup git hooks to automatically fix build phases

HOOK_DIR="../.git/hooks"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create post-merge hook (runs after git pull)
cat > "$HOOK_DIR/post-merge" << 'HOOK'
#!/bin/bash
# Auto-fix Xcode build phases after pull
cd "$(git rev-parse --show-toplevel)/flutter-app"
if [ -f "scripts/fix_xcode_build_phases.sh" ]; then
    ./scripts/fix_xcode_build_phases.sh
fi
HOOK
chmod +x "$HOOK_DIR/post-merge"

# Create post-checkout hook (runs after git checkout)
cat > "$HOOK_DIR/post-checkout" << 'HOOK'
#!/bin/bash
# Auto-fix Xcode build phases after checkout
cd "$(git rev-parse --show-toplevel)/flutter-app"
if [ -f "scripts/fix_xcode_build_phases.sh" ]; then
    ./scripts/fix_xcode_build_phases.sh
fi
HOOK
chmod +x "$HOOK_DIR/post-checkout"

echo "✅ Git hooks installed!"
echo "Build phases will be auto-fixed after pull/checkout"
