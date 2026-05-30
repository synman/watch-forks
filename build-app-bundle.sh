#!/usr/bin/env bash
# build-app-bundle.sh — package watch-forks-menubar as a macOS .app bundle
#
# Usage:
#   ./build-app-bundle.sh           # Build to build/watch-forks-menubar.app/
#   ./build-app-bundle.sh --install # Build and install to /Applications/

set -euo pipefail

# Resolve script's own physical directory (symlink-safe)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"

# Bundle paths
BUILD_DIR="$REPO_ROOT/build"
BUNDLE_DIR="$BUILD_DIR/watch-forks-menubar.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Flags
INSTALL_FLAG="${1:-}"
if [[ "$INSTALL_FLAG" != "" && "$INSTALL_FLAG" != "--install" ]]; then
    echo "Usage: $0 [--install]"
    exit 1
fi

echo "📦 Building watch-forks-menubar.app bundle..."

# Clean and create directory structure
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy the CLI and menubar script to Resources
echo "  • Copying watch-forks to Resources/"
cp "$REPO_ROOT/watch-forks" "$RESOURCES_DIR/watch-forks"

echo "  • Copying watch-forks-menubar.py to Resources/"
cp "$REPO_ROOT/watch-forks-menubar" "$RESOURCES_DIR/watch-forks-menubar.py"

# Resolve a python3 that actually has rumps installed and bake its ABSOLUTE path
# into the wrapper. LaunchServices/launchd start the bundle with a minimal PATH
# (/usr/bin:/bin:/usr/sbin:/sbin), so a bare `python3` resolves to the system
# interpreter — which lacks rumps/pyobjc when deps live in a venv. Override the
# auto-detected interpreter with WATCH_FORKS_PYTHON=/path/to/venv/bin/python3.
echo "  • Resolving a rumps-capable python3"
PYTHON_BIN="${WATCH_FORKS_PYTHON:-$(command -v python3 || true)}"
if [[ -z "$PYTHON_BIN" ]] || ! "$PYTHON_BIN" -c 'import rumps' 2>/dev/null; then
    echo "❌ No python3 with 'rumps' found."
    echo "   Install deps first:   python3 -m pip install -r requirements.txt"
    echo "   Or point at a venv:   WATCH_FORKS_PYTHON=/path/to/venv/bin/python3 $0 ${1:-}"
    exit 1
fi
# Canonicalize to the real interpreter path (resolves venv shim symlinks).
PYTHON_BIN="$("$PYTHON_BIN" -c 'import sys; print(sys.executable)')"
echo "    → $PYTHON_BIN"

# Create the MacOS wrapper executable (interpreter path baked at build time;
# runtime vars escaped so they expand when the wrapper runs, not now).
echo "  • Creating MacOS wrapper executable"
cat > "$MACOS_DIR/watch-forks-menubar" << EOF
#!/usr/bin/env bash
# Wrapper to launch watch-forks-menubar from the app bundle.
# Interpreter path is baked at build time — launchd has no venv on PATH.
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd -P)"
exec "$PYTHON_BIN" "\${SCRIPT_DIR}/../Resources/watch-forks-menubar.py" "\$@"
EOF
chmod +x "$MACOS_DIR/watch-forks-menubar"

# Create Info.plist
echo "  • Creating Info.plist"
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>watch-forks</string>
	<key>CFBundleExecutable</key>
	<string>watch-forks-menubar</string>
	<key>CFBundleIdentifier</key>
	<string>com.shellware.watch-forks-menubar</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>watch-forks</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# Validate the plist
if ! plutil -lint "$CONTENTS_DIR/Info.plist" > /dev/null 2>&1; then
    echo "❌ Info.plist validation failed"
    exit 1
fi

echo "✅ Bundle created: $BUNDLE_DIR"

# Install to /Applications if requested
if [[ "$INSTALL_FLAG" == "--install" ]]; then
    echo "📥 Installing to /Applications..."
    rsync -a --delete "$BUNDLE_DIR" /Applications/
    echo "✅ Installed to /Applications/watch-forks-menubar.app"
fi

echo ""
echo "📍 Launch the bundle:"
echo "  open $BUNDLE_DIR"
echo "  or"
echo "  $MACOS_DIR/watch-forks-menubar"
