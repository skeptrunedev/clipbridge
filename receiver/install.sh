#!/usr/bin/env bash
# Linux (SSH target) half of clipbridge: Xvfb display :99, the receiver, and a
# DISPLAY default for shells that have no display of their own.
set -euo pipefail
cd "$(dirname "$0")"

dpkg -s xvfb xclip python3-xcffib >/dev/null 2>&1 || sudo apt-get install -y xvfb xclip python3-xcffib

install -Dm755 clipbridge-recv ~/.local/bin/clipbridge-recv
install -Dm644 clipbridge-xvfb.service ~/.config/systemd/user/clipbridge-xvfb.service
systemctl --user daemon-reload
systemctl --user enable --now clipbridge-xvfb.service
loginctl enable-linger "$USER"

marker='# clipbridge: image paste over SSH'
grep -qF "$marker" ~/.bashrc || cat >> ~/.bashrc <<'RC'

# clipbridge: image paste over SSH (github.com/skeptrunedev/clipbridge)
[ -z "$DISPLAY" ] && [ -S /tmp/.X11-unix/X99 ] && export DISPLAY=:99
RC
echo "clipbridge (linux) installed; new shells get DISPLAY=:99"
