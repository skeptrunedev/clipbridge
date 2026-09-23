# clipbridge

Paste images into Claude Code and Codex running on a remote Linux box over SSH.

A terminal paste only carries text. Both apps grab images with Ctrl+V by
reading the X clipboard of the machine they run on, and a headless SSH box has
no clipboard. clipbridge gives it one that mirrors your Mac:

```
Mac: copy image ──► clipbridge (LaunchAgent) ══ one persistent ssh stream ══►
Linux: clipbridge-recv owns CLIPBOARD on Xvfb :99 ◄── Ctrl+V in claude / codex
```

- Only images cross the wire. Copying anything else clears the remote image, so
  a stale screenshot is never pasted.
- Screenshots (TIFF) and Finder-copied image files are converted to PNG.
- One long-lived SSH stream per host. Remote shell startup is paid once, and a
  copy lands in well under a second.
- Images are served as one X property, never INCR. Codex's clipboard library
  (arboard) abandons INCR transfers after 10ms between chunks, which wedges
  xclip-style owners.

## Install

On the Linux host (needs sudo once for `xvfb xclip python3-xcffib`):

```bash
linux/install.sh
```

This starts `clipbridge-xvfb.service` (user unit, lingering enabled) and adds a
line to `~/.bashrc` that sets `DISPLAY=:99` for shells without a display. Start
`claude`/`codex` from a new shell so they inherit it.

On the Mac, with the Linux host reachable by key-based ssh:

```bash
mac/install.sh <ssh-host>...
```

Logs: `~/Library/Logs/clipbridge.log`.

## Use

Copy or screenshot an image on the Mac (Cmd+Ctrl+Shift+4), then press
**Ctrl+V** (not Cmd+V) in Claude Code or Codex.
