// Voxi: local-model fork. Keeps the local Voxtral MLX server alive.
//
// The server is a Python process (server/voxi_server.py inside the Voxi
// project folder) that loads the model once and answers on 127.0.0.1. The app
// starts it at launch if it isn't already running, and leaves it running on
// quit so the next launch is instant. Idempotent: scripts/server.sh exits
// immediately when a healthy server already owns the port.

import AppKit
import Foundation
import JotCore

@MainActor
final class VoxtralServerManager {
    static let shared = VoxtralServerManager()

    private var process: Process?
    private let client = VoxtralClient()

    /// The server runtime lives in Application Support (installed by
    /// scripts/install-server.sh) — deliberately OUTSIDE Documents/Desktop so
    /// launching it never trips a TCC files prompt. Overridable with
    /// `defaults write com.voxi.app serverRoot <path>` (expects server.sh there).
    private var serverRoot: URL {
        if let override = UserDefaults.standard.string(forKey: "serverRoot"), !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voxi")
    }

    /// Starts the server if it isn't already answering. Safe to call repeatedly.
    func ensureRunning() {
        Task {
            if await client.isHealthy() { return }
            launchIfNeeded()
        }
    }

    private func launchIfNeeded() {
        if let process, process.isRunning { return }
        let script = serverRoot.appendingPathComponent("server.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            Log.session.error("voxi-server script not found at \(script.path, privacy: .public) — run scripts/install-server.sh")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            Log.session.info("voxi-server process exited (status \(proc.terminationStatus))")
        }
        do {
            try p.run()
            process = p
            Log.session.info("voxi-server launched (pid \(p.processIdentifier))")
        } catch {
            Log.session.error("voxi-server failed to launch: \(String(describing: error), privacy: .public)")
        }
    }
}
