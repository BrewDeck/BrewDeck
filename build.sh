#!/bin/bash

# Exit on error
set -e

echo "--------------------------------------------------------"
echo "Initializing Native Swift BrewDeck App Bundle Builder"
echo "--------------------------------------------------------"

# 1. Structure the macOS App Bundle directory layout
mkdir -p BrewDeck.app/Contents/MacOS
mkdir -p BrewDeck.app/Contents/Resources


echo "==> Compiling Swift sources using swiftc..."
# Optional external Swift toolchain with its own SDK
if [ -n "$TOOLCHAIN_PATH" ] && [ -d "$TOOLCHAIN_PATH" ]; then
  echo "Using external Swift toolchain at $TOOLCHAIN_PATH"
  export PATH="$TOOLCHAIN_PATH/usr/bin:$PATH"
  SDK_PATH="$TOOLCHAIN_PATH/SDKs/MacOSX.sdk"
else
  # Fallback to Command Line Tools SDK
  SDK_PATH=$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
fi
# Create a local module cache to avoid sandbox writes
mkdir -p ModuleCache
# Compile with chosen SDK and custom module cache
swiftc -parse-as-library Sources/BrewDeck.swift \
  -sdk "$SDK_PATH" \
  -module-cache-path $(pwd)/ModuleCache \
  -target arm64-apple-macos26.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework FoundationModels \
  -o BrewDeck.app/Contents/MacOS/BrewDeck

# 2b. Copy app icon asset into bundle
if [ -f "/Users/yousefenab/Downloads/BrewDeck-iOS-Default-1024x1024@1x.png" ]; then
  echo "==> Copying app icon into bundle Resources..."
  cp "/Users/yousefenab/Downloads/BrewDeck-iOS-Default-1024x1024@1x.png" BrewDeck.app/Contents/Resources/AppIcon.png
else
  echo "WARNING: App icon not found at /Users/yousefenab/Downloads/BrewDeck-iOS-Default-1024x1024@1x.png"
fi

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
    <string>26.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF
codesign --remove-signature BrewDeck.app

echo "==> BrewDeck.app successfully built!"
echo "--------------------------------------------------------"
