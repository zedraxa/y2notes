import UIKit
import AVFoundation

// MARK: - Y2AudioRecorderDelegate

protocol Y2AudioRecorderDelegate: AnyObject {
    func audioRecorder(_ recorder: Y2AudioRecorder, didFinishWith clip: AudioClipObject)
    func audioRecorderDidCancel(_ recorder: Y2AudioRecorder)
    func audioRecorder(_ recorder: Y2AudioRecorder, didUpdateLevel level: Float)
}

// MARK: - Y2AudioRecorder

/// `AVAudioRecorder` wrapper for in-note voice recordings.
///
/// Records to `Documents/AudioClips/{objectID}.m4a` (AAC, 128 kbps).
/// Waveform data is generated asynchronously after recording ends via
/// ``Y2WaveformGenerator``.
///
/// ## Lifecycle
/// 1. Call `startRecording()` — requests microphone permission on first use.
/// 2. The floating record button shows a live level meter via `didUpdateLevel`.
/// 3. Call `stopRecording()` (or it auto-stops at 30 min) — triggers waveform
///    generation and calls `didFinishWith`.
final class Y2AudioRecorder: NSObject {

    // MARK: - Constants

    private enum Constants {
        static let maxDuration: TimeInterval = 30 * 60  // 30 minutes
        static let levelPollInterval: TimeInterval = 0.05
        static let sampleRate: Double = 44100
        static let bitRate: Int = 128_000
    }

    // MARK: - Public

    weak var delegate: Y2AudioRecorderDelegate?
    private(set) var isRecording = false
    private(set) var elapsedTime: TimeInterval = 0

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var levelTimer: Timer?
    private let objectID = UUID()

    // MARK: - Public API

    /// Requests microphone permission and starts recording.
    func startRecording() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.beginRecording()
                } else {
                    self?.delegate?.audioRecorderDidCancel(self!)
                }
            }
        }
    }

    /// Stops recording, finalises the file, generates waveform data, and delivers
    /// the completed `AudioClipObject` to the delegate.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        timer?.invalidate()
        levelTimer?.invalidate()
        audioRecorder?.stop()
        finalise()
    }

    /// Cancels the current recording and deletes the partial file.
    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        timer?.invalidate()
        levelTimer?.invalidate()
        audioRecorder?.stop()
        try? FileManager.default.removeItem(at: audioFileURL())
        delegate?.audioRecorderDidCancel(self)
    }

    // MARK: - Recording setup

    private func beginRecording() {
        let url = audioFileURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: Constants.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Constants.bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            elapsedTime = 0
            startTimers()
        } catch {
            delegate?.audioRecorderDidCancel(self)
        }
    }

    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.elapsedTime += 1
            if self.elapsedTime >= Constants.maxDuration { self.stopRecording() }
        }
        levelTimer = Timer.scheduledTimer(withTimeInterval: Constants.levelPollInterval, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.audioRecorder?.updateMeters()
            let db = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            let normalised = max(0, min(1, (db + 60) / 60))
            self.delegate?.audioRecorder(self, didUpdateLevel: normalised)
        }
    }

    // MARK: - Finalisation

    private func finalise() {
        let url = audioFileURL()
        let duration = elapsedTime
        let filename = url.lastPathComponent

        Y2WaveformGenerator.generate(from: url) { [weak self] samples in
            guard let self else { return }
            let clip = AudioClipObject(
                audioFilename: filename,
                duration: duration,
                waveformData: samples,
                recordedAt: Date()
            )
            DispatchQueue.main.async {
                self.delegate?.audioRecorder(self, didFinishWith: clip)
            }
        }
    }

    private func audioFileURL() -> URL {
        MediaFileManager.shared.audioURL(objectID: objectID)
    }
}

// MARK: - AVAudioRecorderDelegate

extension Y2AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag, isRecording { stopRecording() }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        stopRecording()
    }
}

// MARK: - AVAudioApplication compat

private extension AVAudioApplication {
    static func requestRecordPermission(completionHandler: @escaping (Bool) -> Void) {
        if #available(iOS 17, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completionHandler)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completionHandler)
        }
    }
}
