import Foundation
import CoreGraphics

// MARK: - AudioClipObject

/// Metadata for a voice recording embedded as a playable widget on the canvas.
///
/// Audio data is stored externally in `Documents/AudioClips/{objectID}.m4a`
/// and managed by ``MediaFileManager``.
struct AudioClipObject: Codable, Equatable {
    /// Path relative to Documents/AudioClips/ (filename only, no leading path).
    var audioFilename: String
    /// Total recording duration in seconds.
    var duration: TimeInterval
    /// Pre-computed waveform samples for visual display (~200 points, normalised 0…1).
    var waveformData: [Float]
    /// Speech-to-text result; populated lazily on first playback when available.
    var transcription: String?
    /// Last known playback position for resume-on-tap behaviour.
    var playbackPosition: TimeInterval
    /// Display title shown on the widget (defaults to recording date/time).
    var title: String
    /// ISO8601 timestamp when recording was captured.
    var recordedAt: Date

    init(
        audioFilename: String,
        duration: TimeInterval,
        waveformData: [Float] = [],
        transcription: String? = nil,
        playbackPosition: TimeInterval = 0,
        title: String = "",
        recordedAt: Date = Date()
    ) {
        self.audioFilename = audioFilename
        self.duration = duration
        self.waveformData = waveformData
        self.transcription = transcription
        self.playbackPosition = playbackPosition
        self.title = title
        self.recordedAt = recordedAt
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case audioFilename, duration, waveformData, transcription
        case playbackPosition, title, recordedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audioFilename = try c.decode(String.self, forKey: .audioFilename)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        waveformData = try c.decodeIfPresent([Float].self, forKey: .waveformData) ?? []
        transcription = try c.decodeIfPresent(String.self, forKey: .transcription)
        playbackPosition = try c.decodeIfPresent(TimeInterval.self, forKey: .playbackPosition) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt) ?? Date()
    }
}
