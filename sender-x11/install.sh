#!/usr/bin/env bash
# X11 desktop sender: runs clipbridge-send as a user service in the graphical
# session, pushing copied images to the given SSH hosts.
# usage: ./install.sh <ssh-host>...
set -euo pipefail
cd "$(dirname "$0")"
[ $# -gt 0 ] || { echo "usage: $0 <ssh-host>..." >&2; exit 2; }

dpkg -s xclip python3-xcffib >/dev/null 2>&1 || sudo apt-get install -y xclip python3-xcffib

install -Dm755 clipbridge-send ~/.local/bin/clipbridge-send
install -Dm644 clipbridge-send.service ~/.config/systemd/user/clipbridge-send.service
mkdir -p ~/.config/clipbridge
echo "CLIPBRIDGE_HOSTS=$*" > ~/.config/clipbridge/hosts.env
systemctl --user daemon-reload
systemctl --user enable clipbridge-send.service
systemctl --user restart clipbridge-send.service
echo "clipbridge (x11) running for: $*  (logs: journalctl --user -u clipbridge-send)"
