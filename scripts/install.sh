#!/bin/zsh
# Builds Agent Usage, installs it to ~/Applications, and starts it at login via a LaunchAgent.
# Needs macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).
set -euo pipefail

APP_NAME="Agent Usage"
BUNDLE_ID="dev.agentusage.AgentUsage"
REPO_DIR="${0:A:h:h}"
APP_DIR="$HOME/Applications/$APP_NAME.app"
AGENT_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
VERSION="$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null || echo dev)"

echo "Building..."
swift build --package-path "$REPO_DIR" -c release --product AgentUsage
BINARY="$(swift build --package-path "$REPO_DIR" -c release --show-bin-path)/AgentUsage"

echo "Installing to $APP_DIR"
pkill -x AgentUsage 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BINARY" "$APP_DIR/Contents/MacOS/AgentUsage"
cat >| "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>AgentUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# Ad-hoc signing is enough for an app built on the machine that runs it.
codesign --force --sign - "$APP_DIR"

echo "Registering login item"
mkdir -p "${AGENT_PLIST:h}"
cat >| "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key><array><string>$APP_DIR/Contents/MacOS/AgentUsage</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"

echo "Installed. Look for the Claude mark in your menu bar."
