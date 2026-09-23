#!/usr/bin/env bash
# Mac half of clipbridge: builds the agent and runs it as a LaunchAgent that
# pushes copied images to the given SSH hosts.  usage: ./install.sh <ssh-host>...
set -euo pipefail
cd "$(dirname "$0")"
[ $# -gt 0 ] || { echo "usage: $0 <ssh-host>..." >&2; exit 2; }

label=com.skeptrune.clipbridge
bin="$HOME/.local/bin/clipbridge"
plist="$HOME/Library/LaunchAgents/$label.plist"

mkdir -p "$(dirname "$bin")"
swiftc -O -o "$bin" clipbridge.swift

host_args=""
for host in "$@"; do host_args+="    <string>$host</string>"$'\n'; done
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bin</string>
$host_args  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/clipbridge.log</string>
</dict>
</plist>
PLIST

service="gui/$(id -u)/$label"
if launchctl print "$service" >/dev/null 2>&1; then
  launchctl bootout "$service"
  # bootout returns before the job is gone; bootstrapping early fails with EIO.
  while launchctl print "$service" >/dev/null 2>&1; do sleep 0.1; done
fi
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "clipbridge (mac) running for: $*  (log: ~/Library/Logs/clipbridge.log)"
