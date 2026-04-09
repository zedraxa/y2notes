import Foundation
import AVFoundation

// MARK: - Y2WaveformGenerator

/// Reads an M4A audio file and produces a normalised `[Float]` waveform array
/// suitable for display in ``Y2AudioClipView``.
///
/// Processing runs entirely on a background serial queue so the main thread is
/// never blocked.
enum Y2WaveformGenerator {

    // MARK: - Constants

    private enum Constants {
        /// Target number of data points in the output waveform.
        static let targetSampleCount = 200
        /// Reading buffer size in frames.
        static let readBufferSize: AVAudioFrameCount = 4096
    }

    // MARK: - Public API

    /// Reads `url` asynchronously and calls `completion` on a background thread
    /// with the waveform samples.  On failure an empty array is returned.
    static func generate(from url: URL, completion: @escaping ([Float]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(generateSync(from: url))
        }
    }

    /// Synchronous variant — call only from a background thread.
    static func generateSync(from url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return [] }

        var rawSamples: [Float] = []
        rawSamples.reserveCapacity(Int(frameCount))

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: Constants.readBufferSize
        ) else { return [] }
        file.framePosition = 0

        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            let toRead = min(remaining, Constants.readBufferSize)
            do {
                buffer.frameLength = toRead
                try file.read(into: buffer, frameCount: toRead)
            } catch { break }

            if let channel0 = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) {
                    rawSamples.append(abs(channel0[i]))
                }
            }
        }

        return downsample(rawSamples, to: Constants.targetSampleCount)
    }

    // MARK: - Downsampling

    private static func downsample(_ samples: [Float], to count: Int) -> [Float] {
        guard !samples.isEmpty, count > 0 else { return [] }
        let step = max(1, samples.count / count)
        var result = [Float]()
        result.reserveCapacity(count)

        var i = 0
        while i < samples.count && result.count < count {
            let slice = samples[i..<min(i + step, samples.count)]
            let peak = slice.max() ?? 0
            result.append(peak)
            i += step
        }

        // Normalise to 0…1.
        let maxVal = result.max() ?? 1
        if maxVal > 0 {
            result = result.map { $0 / maxVal }
        }
        return result
    }
}
