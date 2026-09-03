// Voxi: local-model fork. Live transcript preview while you talk.
//
// Voxtral is a streaming model, so the words can be shown in the pill as they
// are recognised. This path is DECORATION ONLY: the text that actually gets
// inserted still comes from the batch transcribe at key-up. A preview that
// stalls, errors, or drifts must never cost the user their dictation, so every
// failure here is swallowed and simply stops updating the pill.

import Foundation

/// Feeds recorded PCM to the server's streaming session and publishes the
/// growing transcript. One dictation at a time.
public final class LivePreview: @unchecked Sendable {
    public static let shared = LivePreview()

    /// Called on the main queue whenever the preview text grows.
    public var onText: ((String) -> Void)?

    /// Audio is coalesced into ~400ms posts: one HTTP round trip per capture
    /// buffer (~100ms) would spend more time in the socket than the model does
    /// decoding, and the pill cannot render faster than this anyway.
    private static let flushInterval: TimeInterval = 0.4

    private let queue = DispatchQueue(label: "com.voxi.app.livepreview")
    private let client = VoxtralClient()
    private var buffer = Data()
    private var active = false
    private var inFlight = false
    private var lastFlush = Date.distantPast
    /// The stream's final transcript for the session that just ended, produced
    /// by end(). Consumed exactly once by takeFinalText() so a later retry from
    /// History can never pick up a stale session's words.
    private var finalTask: Task<String?, Never>?

    private init() {}

    /// Opens a session. Cheap and fire-and-forget — recording never waits on it.
    public func begin() {
        queue.async {
            self.finalTask = nil
            self.buffer.removeAll(keepingCapacity: true)
            self.active = false
            self.inFlight = false
            self.lastFlush = Date()
            Task { [weak self] in
                let ok = await self?.client.streamStart() ?? false
                self?.queue.async { self?.active = ok }
                if !ok { Log.transcription.info("live preview unavailable — pill stays on the waveform") }
            }
        }
    }

    /// Appends captured PCM. Safe to call from the audio write queue.
    public func feed(_ pcm: Data) {
        queue.async {
            guard self.active else { return }
            self.buffer.append(pcm)
            guard !self.inFlight, Date().timeIntervalSince(self.lastFlush) >= Self.flushInterval else { return }
            self.flushLocked()
        }
    }

    /// Closes the session and flushes the tail. The finished transcript is
    /// parked for takeFinalText(); the batch path decides whether to use it.
    public func end() {
        queue.async {
            guard self.active else { return }
            self.active = false
            let tail = self.buffer
            self.buffer.removeAll(keepingCapacity: true)
            let client = self.client
            self.finalTask = Task {
                if !tail.isEmpty { _ = await client.streamFeed(tail) }
                return await client.streamFinish()
            }
        }
    }

    /// The stream's final transcript for the session that just ended, or nil if
    /// there was no live session, it failed, or it isn't done within `timeout`.
    /// Take-once: a second call returns nil.
    public func takeFinalText(timeout: TimeInterval) async -> String? {
        let task: Task<String?, Never>? = await withCheckedContinuation { cont in
            queue.async {
                let t = self.finalTask
                self.finalTask = nil
                cont.resume(returning: t)
            }
        }
        guard let task else { return nil }
        let deadline = Task<String?, Never> {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return nil
        }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { await task.value }
            group.addTask { await deadline.value }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Must be called on `queue`.
    private func flushLocked() {
        let chunk = buffer
        buffer.removeAll(keepingCapacity: true)
        guard !chunk.isEmpty else { return }
        inFlight = true
        lastFlush = Date()
        Task { [weak self] in
            guard let self else { return }
            let text = await self.client.streamFeed(chunk)
            self.queue.async { self.inFlight = false }
            if let text, !text.isEmpty {
                DispatchQueue.main.async { self.onText?(text) }
            }
        }
    }
}
