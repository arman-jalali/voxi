// Voxi: local-model fork. The transcription pipeline, entirely on-device:
//
//   CAF → WAV → local Voxtral server (MLX) → ReplacementEngine → inserted text.
//
// Voxtral-Mini-4B-Realtime is transcription-only, so there is no cleanup /
// tone pass and no validation gate — the dictionary's wrong→right rules are
// the one hard guarantee and they apply on every path.
//
// Rules unchanged from the Gemini pipeline: one silent retry on transient
// failures; empty-transcript second chance on real audio; every failure is a
// typed TranscriptionError mapping to the failure matrix.

import Foundation

public struct LocalTranscriptionService: TranscriptionServicing {
    public static let modelID = "voxtral-mini-4b-realtime (local)"

    private let client: VoxtralClient

    public init(client: VoxtralClient = VoxtralClient()) {
        self.client = client
    }

    public func transcribe(audioURL: URL, durationSeconds: Double, context: DictationContext) async throws -> TranscriptionResult {
        let wavURL = audioURL.deletingLastPathComponent().appendingPathComponent("audio.wav")
        let encoded = try WAVEncoder.encode(cafURL: audioURL, wavURL: wavURL)
        Log.transcription.info("WAV \(encoded.byteCount) bytes in \(Int(encoded.encodeSeconds * 1000))ms")
        let wavData = try Data(contentsOf: encoded.url)
        // Derived data — the CAF is the only audio artifact that persists.
        try? FileManager.default.removeItem(at: encoded.url)

        let deadline = TimeoutPolicy.overallDeadline(audioDuration: durationSeconds)
        var raw = try await transcribeWithRetry(wavData: wavData, deadline: deadline)

        var trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRaw.isEmpty, durationSeconds >= 0.6 {
            // Empty result on real audio can be model nondeterminism — one
            // re-send before surfacing anything.
            Log.transcription.info("empty transcript on \(String(format: "%.1f", durationSeconds))s audio — one re-send")
            raw = (try? await client.transcribe(wavData: wavData, deadline: deadline)) ?? ""
            trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmedRaw.isEmpty else {
            // The coordinator classifies silence vs dropped-transcript by energy.
            throw TranscriptionError.emptyTranscript
        }

        // Dictionary rules are a HARD guarantee — they apply on every path.
        let rules = DictionaryStore().replacementRules()
        let text = ReplacementEngine.apply(rules, to: trimmedRaw)
        return TranscriptionResult(
            rawTranscript: trimmedRaw,
            cleanedTranscript: text,
            modelID: Self.modelID
        )
    }

    private func transcribeWithRetry(wavData: Data, deadline: TimeInterval) async throws -> String {
        do {
            return try await client.transcribe(wavData: wavData, deadline: deadline)
        } catch let error as TranscriptionError {
            switch error {
            case .network, .timeout:
                // One silent retry for transient classes (audio is safe on disk).
                Log.transcription.info("transcribe retrying after \(String(describing: error), privacy: .public)")
                try await Task.sleep(nanoseconds: 500_000_000)
                return try await client.transcribe(wavData: wavData, deadline: deadline)
            default:
                throw error
            }
        }
    }
}
