// clipbridge: mirrors images copied on this Mac into the X clipboard of SSH
// hosts, so Ctrl+V image paste works in Claude Code and Codex running there.
//
// Only images cross the wire. When the clipboard changes to anything else, the
// hosts are cleared so a stale image is never pasted. Each host gets one
// long-lived SSH stream, so remote shell startup is paid once, not per copy.

import AppKit

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

/// A persistent `ssh <host> clipbridge-recv` stream, reopened when it dies.
final class Link {
    let host: String
    private var ssh: Process?
    private var input: FileHandle?

    init(host: String) { self.host = host }

    /// Connect ahead of the first copy so it doesn't wait on SSH.
    func warm() {
        do { _ = try openIfNeeded() } catch { log("\(host): connect failed: \(error)") }
    }

    func send(_ frame: Data) {
        // One retry covers a stream that died since the last copy (sleep,
        // network change, remote restart).
        for attempt in 1...2 {
            do {
                try openIfNeeded().write(contentsOf: frame)
                return
            } catch {
                log("\(host): send failed (attempt \(attempt)): \(error)")
                close()
            }
        }
    }

    private func openIfNeeded() throws -> FileHandle {
        if let input, ssh?.isRunning == true { return input }
        close()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
            host, "~/.local/bin/clipbridge-recv",
        ]
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        ssh = process
        input = pipe.fileHandleForWriting
        log("\(host): connected")
        return pipe.fileHandleForWriting
    }

    private func close() {
        try? input?.close()
        ssh?.terminate()
        ssh = nil
        input = nil
    }
}

let hostNames = Array(CommandLine.arguments.dropFirst())
if hostNames.isEmpty {
    FileHandle.standardError.write(Data("usage: clipbridge <ssh-host>...\n".utf8))
    exit(2)
}
signal(SIGPIPE, SIG_IGN)  // a dead stream surfaces as a write error instead

let links = hostNames.map(Link.init)
let pasteboard = NSPasteboard.general
let sendQueue = DispatchQueue(label: "clipbridge.send")
// Only copies made while running are pushed. Re-pushing whatever was already on
// the clipboard at startup would steal the remote clipboard from another
// sender's newer copy ("last copy wins").
var lastChangeCount = pasteboard.changeCount
var hostsHoldImage = false

/// The clipboard as PNG: native PNG, else anything NSImage can read
/// (screenshots arrive as TIFF, Finder copies as an image file URL).
func clipboardPNG() -> Data? {
    if let png = pasteboard.data(forType: .png) { return png }
    guard NSImage.canInit(with: pasteboard),
          let image = NSImage(pasteboard: pasteboard),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

func broadcast(_ frame: Data) {
    sendQueue.async { links.forEach { $0.send(frame) } }
}

func poll() {
    let changeCount = pasteboard.changeCount
    guard changeCount != lastChangeCount else { return }
    lastChangeCount = changeCount

    if let png = clipboardPNG() {
        broadcast(Data("image \(png.count)\n".utf8) + png)
        hostsHoldImage = true
        log("pushed image (\(png.count) bytes)")
    } else if hostsHoldImage {
        broadcast(Data("clear\n".utf8))
        hostsHoldImage = false
    }
}

sendQueue.async { links.forEach { $0.warm() } }
Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in poll() }
RunLoop.main.run()
