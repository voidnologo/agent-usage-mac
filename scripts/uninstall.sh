#!/bin/zsh
# Stops Agent Usage and removes the app and its login item.
set -euo pipefail

BUNDLE_ID="dev.agentusage.AgentUsage"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
pkill -x AgentUsage 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
rm -rf "$HOME/Applications/Agent Usage.app"
echo "Agent Usage removed."
