#!/bin/bash

# Exit on error
set -e

echo "--------------------------------------------------------"
echo "Initializing Native Swift BrewDeck App Bundle Builder"
echo "--------------------------------------------------------"

# 1. Structure the macOS App Bundle directory layout
mkdir -p BrewDeck.app/Contents/MacOS
mkdir -p BrewDeck.app/Contents/Resources

# 2. Compile the Swift source into a native macOS arm64 executable
echo "==> Compiling Swift sources using swiftc..."
swiftc Sources/BrewDeck.swift \
  -sdk $(xcrun --show-sdk-path) \
  -target arm64-apple-macos13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -O \
  -parse-as-library \
  -o BrewDeck.app/Contents/MacOS/BrewDeck

# 3. Generate the app metadata Info.plist file
echo "==> Constructing Contents/Info.plist file..."
cat <<EOF > BrewDeck.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BrewDeck</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.brewdeck.swift.BrewDeck</string>
    <key>CFBundleName</key>
    <string>BrewDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

echo "==> BrewDeck.app successfully built!"
echo "--------------------------------------------------------"
