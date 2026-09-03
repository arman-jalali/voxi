// Voxi: local-model fork. HTTP client for the local Voxtral MLX server.
// Audio never leaves the machine: the only endpoint is 127.0.0.1.

import Foundation

/// Talks to the local voxi_server.py (Voxtral-Mini-4B-Realtime in MLX).
public struct VoxtralClient: Sendable {
    public static let defaultPort = 48765

    public let baseURL: URL

    public init(port: Int = VoxtralClient.defaultPort) {
        baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600 // per-request deadline is set per call
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// True when the server is up with the model loaded and warm.
    public func isHealthy() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await Self.session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Live preview session
    //
    // Best-effort by design: these return nil/false rather than throwing, so a
    // preview hiccup can never surface as a dictation failure.

    private func streamPost(_ path: String, body: Data, timeout: TimeInterval) async -> [String: Any]? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public func streamStart() async -> Bool {
        await streamPost("stream/start", body: Data(), timeout: 5) != nil
    }

    /// Returns the transcript so far, or nil if this chunk didn't land.
    public func streamFeed(_ pcm: Data) async -> String? {
        await streamPost("stream/audio", body: pcm, timeout: 15)?["text"] as? String
    }

    @discardableResult
    public func streamFinish() async -> String? {
        await streamPost("stream/finish", body: Data(), timeout: 20)?["text"] as? String
    }

    /// Sends WAV bytes, returns the raw transcript. Maps every failure onto the
    /// existing TranscriptionError matrix so the HUD/retry behaviour is unchanged.
    public func transcribe(wavData: Data, deadline: TimeInterval) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("transcribe"))
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData
        request.timeoutInterval = deadline

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TranscriptionError.timeout
        } catch {
            // Connection refused ⇒ the model server isn't running (or still loading).
            throw TranscriptionError.network("Local model not running — start it with scripts/server.sh")
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.network("no HTTP response")
        }
        guard http.statusCode == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { ($0 as? [String: Any])?["error"] as? String } ?? "HTTP \(http.statusCode)"
            throw TranscriptionError.network(detail)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            throw TranscriptionError.network("malformed server response")
        }
        return text
    }
}
