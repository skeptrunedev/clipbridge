#!/usr/bin/env bash
# clipbridge installer. Run it on the desktop you copy images on:
#
#   curl -fsSL https://raw.githubusercontent.com/skeptrunedev/clipbridge/main/install.sh | bash -s -- <ssh-host>...
#
# It installs the sender for this desktop (macOS or X11 Linux), then the
# receiver on each SSH host. Other modes:
#
#   install.sh --receiver              install only the receiver, on this machine
#   install.sh --doctor <ssh-host>...  check every hop and say what is broken
#   install.sh --uninstall [<ssh-host>...]
set -euo pipefail

REPO="skeptrunedev/clipbridge"
REF="${CLIPBRIDGE_REF:-main}"
SRC="$HOME/.local/share/clipbridge"
BIN="$HOME/.local/bin"
DISPLAY_NUM=99
MAC_LABEL="com.skeptrune.clipbridge"
RC_MARKER="# clipbridge: image paste over SSH"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Source files: this checkout when run from one, else a fresh download.
fetch_source() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [ -n "$here" ] && [ -f "$here/receiver/clipbridge-recv" ]; then
    SRC_DIR="$here"
    return
  fi
  say "Downloading clipbridge ($REF)"
  rm -rf "$SRC" && mkdir -p "$SRC"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar xz -C "$SRC" --strip-components=1
  SRC_DIR="$SRC"
}

# Installs distro packages named "<apt> <dnf> <pacman>" per argument.
ensure_packages() {
  local manager install=() spec apt dnf pacman
  if command -v apt-get >/dev/null; then manager=apt
  elif command -v dnf >/dev/null; then manager=dnf
  elif command -v pacman >/dev/null; then manager=pacman
  else die "no apt, dnf or pacman found; install these yourself: $*"
  fi
  for spec in "$@"; do
    read -r apt dnf pacman <<<"$spec"
    case $manager in
      apt) dpkg -s "$apt" >/dev/null 2>&1 || install+=("$apt") ;;
      dnf) rpm -q "$dnf" >/dev/null 2>&1 || install+=("$dnf") ;;
      pacman) pacman -Q "$pacman" >/dev/null 2>&1 || install+=("$pacman") ;;
    esac
  done
  [ ${#install[@]} -eq 0 ] && return
  say "Installing ${install[*]} (needs sudo)"
  case $manager in
    apt) sudo apt-get install -y "${install[@]}" ;;
    dnf) sudo dnf install -y "${install[@]}" ;;
    pacman) sudo pacman -S --needed --noconfirm "${install[@]}" ;;
  esac
}

check_ssh() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" true 2>/dev/null ||
    die "can't ssh to '$1' without a prompt. clipbridge needs key-based ssh (test: ssh -o BatchMode=yes $1 true)"
}

# --- receiver (the SSH host) -------------------------------------------------

install_receiver() {
  [ "$(uname -s)" = Linux ] || die "the receiver runs on Linux"
  fetch_source
  ensure_packages "xvfb xorg-x11-server-Xvfb xorg-server-xvfb" "xclip xclip xclip" \
    "python3-xcffib python3-xcffib python-xcffib"

  install -Dm755 "$SRC_DIR/receiver/clipbridge-recv" "$BIN/clipbridge-recv"
  install -Dm644 "$SRC_DIR/receiver/clipbridge-xvfb.service" \
    "$HOME/.config/systemd/user/clipbridge-xvfb.service"
  sed -i "s|^ExecStart=/usr/bin/Xvfb|ExecStart=$(command -v Xvfb)|" \
    "$HOME/.config/systemd/user/clipbridge-xvfb.service"
  systemctl --user daemon-reload
  systemctl --user enable --now clipbridge-xvfb.service
  # Keep the display up without an open login session.
  loginctl enable-linger "$USER" 2>/dev/null || true

  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -qF "$RC_MARKER" "$rc" && continue
    printf '\n%s (github.com/%s)\n%s\n' "$RC_MARKER" "$REPO" \
      "[ -z \"\$DISPLAY\" ] && [ -S /tmp/.X11-unix/X$DISPLAY_NUM ] && export DISPLAY=:$DISPLAY_NUM" >>"$rc"
  done
  ok "receiver installed on $(hostname): display :$DISPLAY_NUM, new shells get DISPLAY=:$DISPLAY_NUM"
}

install_remote_receivers() {
  local host
  for host in "$@"; do
    say "Installing the receiver on $host"
    # -t (with the real terminal) so sudo can prompt for missing packages.
    ssh -t "$host" "curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/install.sh | CLIPBRIDGE_REF=$REF bash -s -- --receiver" </dev/tty
  done
}

# --- senders (your desktop) ---------------------------------------------------

install_sender_mac() {
  xcode-select -p >/dev/null 2>&1 ||
    die "the Mac sender is compiled with swiftc; run 'xcode-select --install' first"
  local plist="$HOME/Library/LaunchAgents/$MAC_LABEL.plist" service="gui/$(id -u)/$MAC_LABEL"
  local host_args="" host
  mkdir -p "$BIN" "$(dirname "$plist")"
  say "Building the sender"
  swiftc -O -o "$BIN/clipbridge" "$SRC_DIR/sender-mac/clipbridge.swift"
  for host in "$@"; do host_args+="    <string>$host</string>"$'\n'; done
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$MAC_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN/clipbridge</string>
$host_args  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/clipbridge.log</string>
</dict>
</plist>
PLIST
  if launchctl print "$service" >/dev/null 2>&1; then
    launchctl bootout "$service"
    # bootout returns before the job is gone; bootstrapping early fails with EIO.
    while launchctl print "$service" >/dev/null 2>&1; do sleep 0.1; done
  fi
  launchctl bootstrap "gui/$(id -u)" "$plist"
  ok "sender running (log: ~/Library/Logs/clipbridge.log)"
}

install_sender_x11() {
  [ -n "${DISPLAY:-}" ] || die "no DISPLAY; run this from a terminal in your desktop session"
  ensure_packages "xclip xclip xclip" "python3-xcffib python3-xcffib python-xcffib"
  install -Dm755 "$SRC_DIR/sender-x11/clipbridge-send" "$BIN/clipbridge-send"
  install -Dm644 "$SRC_DIR/sender-x11/clipbridge-send.service" \
    "$HOME/.config/systemd/user/clipbridge-send.service"
  mkdir -p "$HOME/.config/clipbridge"
  echo "CLIPBRIDGE_HOSTS=$*" >"$HOME/.config/clipbridge/hosts.env"
  systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable clipbridge-send.service
  systemctl --user restart clipbridge-send.service
  ok "sender running (log: journalctl --user -u clipbridge-send)"
}

install_sender() {
  [ $# -gt 0 ] || die "usage: install.sh <ssh-host>...   (the machine(s) running Claude Code / Codex)"
  local host
  for host in "$@"; do check_ssh "$host"; done
  fetch_source
  install_remote_receivers "$@"
  say "Installing the sender on this desktop"
  case "$(uname -s)" in
    Darwin) install_sender_mac "$@" ;;
    Linux) install_sender_x11 "$@" ;;
    *) die "unsupported desktop OS: $(uname -s)" ;;
  esac
  cat <<EOF

$(printf '\033[1m')Done.$(printf '\033[0m') Copy an image here, then press Ctrl+V in Claude Code or Codex on: $*
Shells opened on the host before this install lack DISPLAY; open a new one (or run: exec \$SHELL).
EOF
}

# --- doctor / uninstall --------------------------------------------------------

doctor() {
  [ $# -gt 0 ] || die "usage: install.sh --doctor <ssh-host>..."
  local host failed=0
  say "This desktop"
  case "$(uname -s)" in
    Darwin)
      launchctl print "gui/$(id -u)/$MAC_LABEL" 2>/dev/null | grep -q "state = running" &&
        ok "sender running" || { bad "sender not running (see ~/Library/Logs/clipbridge.log)"; failed=1; } ;;
    Linux)
      systemctl --user is-active --quiet clipbridge-send &&
        ok "sender running" || { bad "sender not running (journalctl --user -u clipbridge-send)"; failed=1; } ;;
  esac
  for host in "$@"; do
    say "$host"
    if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" true 2>/dev/null; then
      bad "key-based ssh fails (ssh -o BatchMode=yes $host true)"; failed=1; continue
    fi
    ok "key-based ssh works"
    ssh -o BatchMode=yes "$host" "bash -s" <<EOF || failed=1
ok() { printf '  \033[32m✓\033[0m %s\n' "\$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "\$*"; failed=1; }
failed=0
[ -x ~/.local/bin/clipbridge-recv ] && ok "receiver installed" || bad "receiver missing (install.sh --receiver on $host)"
systemctl --user is-active --quiet clipbridge-xvfb && ok "display :$DISPLAY_NUM running" || bad "display down (systemctl --user status clipbridge-xvfb)"
targets=\$(DISPLAY=:$DISPLAY_NUM timeout 3 xclip -selection clipboard -t TARGETS -o 2>/dev/null)
case "\$targets" in
  *image/png*) ok "an image is on the clipboard, ready to paste" ;;
  *) echo "  - no image on the clipboard right now (copy one, then re-run)" ;;
esac
echo "  - apps must run with DISPLAY=:$DISPLAY_NUM; shells opened before install need restarting"
exit \$failed
EOF
  done
  return $failed
}

uninstall() {
  local host
  case "$(uname -s)" in
    Darwin)
      launchctl bootout "gui/$(id -u)/$MAC_LABEL" 2>/dev/null || true
      rm -f "$HOME/Library/LaunchAgents/$MAC_LABEL.plist" "$BIN/clipbridge" ;;
    Linux)
      systemctl --user disable --now clipbridge-send clipbridge-xvfb 2>/dev/null || true
      rm -f "$HOME/.config/systemd/user/clipbridge-send.service" \
        "$HOME/.config/systemd/user/clipbridge-xvfb.service" \
        "$BIN/clipbridge-send" "$BIN/clipbridge-recv"
      rm -rf "$HOME/.config/clipbridge"
      local rc
      for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] && sed -i "/^$RC_MARKER/,+1d" "$rc"
      done
      systemctl --user daemon-reload ;;
  esac
  rm -rf "$SRC"
  ok "removed from $(hostname)"
  for host in "$@"; do
    say "Uninstalling from $host"
    ssh -t "$host" "curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/install.sh | bash -s -- --uninstall" </dev/tty
  done
}

case "${1:-}" in
  --receiver) install_receiver ;;
  --doctor) shift; doctor "$@" ;;
  --uninstall) shift; uninstall "$@" ;;
  -h|--help|"") sed -n '2,13p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//' ||
    true; [ -n "${1:-}" ] || die "usage: install.sh <ssh-host>..." ;;
  *) install_sender "$@" ;;
esac
