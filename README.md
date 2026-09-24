# clipbridge

Paste images into Claude Code and Codex running on a remote Linux box over SSH,
from a Mac or an X11 Linux desktop.

A terminal paste only carries text. Both apps grab images with Ctrl+V by
reading the X clipboard of the machine they run on, and a headless SSH box has
no clipboard. clipbridge gives it one that mirrors your desktops:

```
Mac: copy image ──► clipbridge (LaunchAgent) ═══╗
                                                 ╠═ one persistent ssh stream each ═►
X11: copy image ──► clipbridge-send (user unit) ═╝
SSH host: clipbridge-recv owns CLIPBOARD on Xvfb :99 ◄── Ctrl+V in claude / codex
```

- `receiver/`: the SSH host. `sender-mac/`, `sender-x11/`: your desktops.
- Last copy wins across desktops. A sender only pushes copies made while it
  runs, and clearing never touches another desktop's image.

- Only images cross the wire. Copying anything else clears the remote image, so
  a stale screenshot is never pasted.
- Screenshots (TIFF) and Finder-copied image files are converted to PNG.
- One long-lived SSH stream per host. Remote shell startup is paid once, and a
  copy lands in well under a second.
- Images are served as one X property, never INCR. Codex's clipboard library
  (arboard) abandons INCR transfers after 10ms between chunks, which wedges
  xclip-style owners.

## Install

On the SSH host (needs sudo once for `xvfb xclip python3-xcffib`):

```bash
receiver/install.sh
```

This starts `clipbridge-xvfb.service` (user unit, lingering enabled) and adds a
line to `~/.bashrc` that sets `DISPLAY=:99` for shells without a display. Start
`claude`/`codex` from a new shell so they inherit it.

On each desktop, with the SSH host reachable by key-based ssh:

```bash
sender-mac/install.sh <ssh-host>...   # logs: ~/Library/Logs/clipbridge.log
sender-x11/install.sh <ssh-host>...   # logs: journalctl --user -u clipbridge-send
```

## Use

Copy or screenshot an image to the clipboard (Mac: Cmd+Ctrl+Shift+4), then
press **Ctrl+V** in Claude Code or Codex running on the SSH host.

If your terminal binds Ctrl+V to its own text paste (VS Code on Linux with a
`workbench.action.terminal.paste` binding), the keypress never reaches the app.
Bind another key to send a raw Ctrl+V, e.g. in VS Code `keybindings.json`:

```json
{ "key": "ctrl+alt+v", "command": "workbench.action.terminal.sendSequence",
  "args": { "text": "\u0016" }, "when": "terminalFocus" }
```

## License

MIT
