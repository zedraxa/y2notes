import UIKit
import AVFoundation

// MARK: - Y2AudioClipView

/// An inline canvas widget for playing embedded voice recordings.
///
/// Displays a waveform visualisation, play/pause button, and duration label.
/// Supports mini (pill) and expanded modes with playback speed control.
final class Y2AudioClipView: UIView {

    // MARK: - Modes

    enum DisplayMode { case mini, expanded }

    // MARK: - Layout constants

    private enum Metrics {
        static let cornerRadius: CGFloat = 12
        static let playButtonSize: CGFloat = 36
        static let padding: CGFloat = 10
        static let waveBarWidth: CGFloat = 2
        static let waveBarSpacing: CGFloat = 2
    }

    // MARK: - Subviews

    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let playPauseButton = UIButton(type: .system)
    private let waveformView = UIView()
    private let durationLabel = UILabel()
    private let titleLabel = UILabel()
    private let speedButton = UIButton(type: .system)
    private var waveBarLayers: [CALayer] = []

    // MARK: - State

    private let audioClip: AudioClipObject
    private(set) var displayMode: DisplayMode = .mini
    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var isPlaying = false
    private var playbackSpeed: Float = 1.0

    // MARK: - Init

    init(audioClip: AudioClipObject) {
        self.audioClip = audioClip
        super.init(frame: .zero)
        setupView()
        buildWaveform()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupView() {
        layer.cornerRadius = Metrics.cornerRadius
        clipsToBounds = true

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Play/pause button
        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playPauseButton.tintColor = .systemBlue
        playPauseButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.accessibilityLabel = "Play recording"
        addSubview(playPauseButton)

        // Waveform view
        waveformView.backgroundColor = .clear
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(waveformView)

        // Duration label
        durationLabel.text = formatDuration(audioClip.duration)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .secondaryLabel
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)

        // Title label
        titleLabel.text = audioClip.title.isEmpty
            ? DateFormatter.localizedString(from: audioClip.recordedAt, dateStyle: .short, timeStyle: .short)
            : audioClip.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Speed button
        speedButton.setTitle("1×", for: .normal)
        speedButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        speedButton.tintColor = .secondaryLabel
        speedButton.addTarget(self, action: #selector(cycleSpeed), for: .touchUpInside)
        speedButton.translatesAutoresizingMaskIntoConstraints = false
        speedButton.isHidden = true
        speedButton.accessibilityLabel = "Playback speed: 1×"
        speedButton.accessibilityHint = "Double-tap to change playback speed"
        addSubview(speedButton)

        NSLayoutConstraint.activate([
            playPauseButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.padding),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: Metrics.playButtonSize),
            playPauseButton.heightAnchor.constraint(equalToConstant: Metrics.playButtonSize),

            titleLabel.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.padding),
            titleLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),

            waveformView.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 8),
            waveformView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.padding),
            waveformView.trailingAnchor.constraint(equalTo: speedButton.leadingAnchor, constant: -8),
            waveformView.heightAnchor.constraint(equalToConstant: 24),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.padding),
            durationLabel.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.padding),

            speedButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.padding),
            speedButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.padding),
            speedButton.widthAnchor.constraint(equalToConstant: 28),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Voice recording: \(audioClip.title.isEmpty ? "" : audioClip.title), \(formatDuration(audioClip.duration))"
        accessibilityTraits = [.button]
        accessibilityHint = "Double-tap to play or pause"
    }

    private func buildWaveform() {
        waveformView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        waveBarLayers.removeAll()

        let samples = audioClip.waveformData.isEmpty
            ? Array(repeating: Float(0.3), count: 40)
            : audioClip.waveformData

        let count = min(samples.count, 60)
        for i in 0..<count {
            let bar = CALayer()
            bar.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7).cgColor
            bar.cornerRadius = 1
            waveformView.layer.addSublayer(bar)
            waveBarLayers.append(bar)
        }
        layoutWaveformBars(samples: samples, count: count)
    }

    private func layoutWaveformBars(samples: [Float], count: Int) {
        let totalWidth = CGFloat(count) * (Metrics.waveBarWidth + Metrics.waveBarSpacing)
        let availableHeight: CGFloat = 24
        for i in 0..<count {
            let amplitude = CGFloat(i < samples.count ? samples[i] : 0.2)
            let height = max(2, amplitude * availableHeight)
            let x = CGFloat(i) * (Metrics.waveBarWidth + Metrics.waveBarSpacing)
            waveBarLayers[i].frame = CGRect(
                x: x,
                y: (availableHeight - height) / 2,
                width: Metrics.waveBarWidth,
                height: height
            )
        }
        _ = totalWidth
    }

    // MARK: - Playback

    @objc private func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    private func play() {
        let url = MediaFileManager.shared.audioURL(objectID: extractObjectID())
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.currentTime = audioClip.playbackPosition
            player?.enableRate = true
            player?.rate = playbackSpeed
            player?.play()
            isPlaying = true
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            accessibilityLabel = "Pause recording"
            speedButton.isHidden = false
            startProgressTimer()
        } catch {
            // Silently fail — icon stays as play.
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        accessibilityLabel = "Play recording"
        playbackTimer?.invalidate()
    }

    private func startProgressTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func updateProgress() {
        guard let player else { return }
        if !player.isPlaying { pause() }
        let elapsed = player.currentTime
        durationLabel.text = formatDuration(max(0, audioClip.duration - elapsed))
    }

    @objc private func cycleSpeed() {
        let speeds: [Float] = [0.5, 1.0, 1.5, 2.0]
        let idx = (speeds.firstIndex(of: playbackSpeed) ?? 1)
        playbackSpeed = speeds[(idx + 1) % speeds.count]
        player?.rate = playbackSpeed
        let label = playbackSpeed == 1.0 ? "1×" : String(format: "%.1f×", playbackSpeed)
        speedButton.setTitle(label, for: .normal)
        speedButton.accessibilityLabel = "Playback speed: \(label)"
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func extractObjectID() -> UUID {
        // Derive UUID from filename stored in the audio clip.
        let name = (audioClip.audioFilename as NSString).deletingPathExtension
        return UUID(uuidString: name) ?? UUID()
    }
}
