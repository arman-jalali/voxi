// Voxi: local-model fork. CAF → WAV passthrough — the capture format is already
// 16kHz/mono/Int16, exactly what Voxtral expects, so this is a container change,
// not a transcode.

import AVFoundation
import Foundation

public enum WAVEncoder {
    public struct Output: Sendable {
        public let url: URL
        public let byteCount: Int
        public let encodeSeconds: Double
    }

    public enum EncodeError: Error {
        case readFailed(String)
        case writeFailed(String)
    }

    public static func encode(cafURL: URL, wavURL: URL) throws -> Output {
        let started = Date()
        try? FileManager.default.removeItem(at: wavURL)

        let reader: AVAudioFile
        do {
            reader = try AVAudioFile(forReading: cafURL, commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            throw EncodeError.readFailed(String(describing: error))
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: reader.processingFormat.sampleRate,
            AVNumberOfChannelsKey: reader.processingFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let writer = try AVAudioFile(
                forWriting: wavURL, settings: settings,
                commonFormat: .pcmFormatInt16, interleaved: true
            )
            let chunk = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 65_536)!
            // read(into:) can throw a spurious nilError at EOF with an Int16 client
            // format — guard on framePosition instead (probed on macOS 26).
            while reader.framePosition < reader.length {
                try reader.read(into: chunk)
                if chunk.frameLength == 0 { break }
                try writer.write(from: chunk)
            }
        } catch {
            throw EncodeError.writeFailed(String(describing: error))
        }

        let bytes = ((try? FileManager.default.attributesOfItem(atPath: wavURL.path))?[.size] as? Int) ?? 0
        return Output(url: wavURL, byteCount: bytes, encodeSeconds: Date().timeIntervalSince(started))
    }
}
