#!/bin/sh
set -e
cd "$(dirname "$0")"
A=LookAway.app
rm -rf $A && mkdir -p $A/Contents/MacOS
swiftc -O -o $A/Contents/MacOS/LookAway main.swift
cat > $A/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LookAway</string>
<key>CFBundleIdentifier</key><string>local.lookaway</string>
<key>CFBundleName</key><string>LookAway</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSCameraUsageDescription</key><string>Detect when you look away.</string>
<key>NSAppleEventsUsageDescription</key><string>Switch to your Teams tab in Chrome.</string>
</dict></plist>
EOF
codesign --force -s - $A
echo "built $PWD/$A"
