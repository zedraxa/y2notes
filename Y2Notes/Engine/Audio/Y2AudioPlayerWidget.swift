import UIKit
import AVFoundation

// MARK: - Y2AudioPlayerWidget

/// A floating record-button + timer panel presented during active recording.
///
/// Shows:
/// - A pulsing red microphone button (tap to stop)
/// - Elapsed time counter
/// - Live waveform bar chart driven by audio level callbacks from ``Y2AudioRecorder``
final class Y2AudioPlayerWidget: UIView {

    // MARK: - Layout constants

    private enum Metrics {
        static let cornerRadius: CGFloat = 24
        static let padding: CGFloat = 12
        static let micButtonSize: CGFloat = 48
        static let waveBarWidth: CGFloat = 2.5
        static let waveBarSpacing: CGFloat = 2
        static let waveBarCount = 30
    }

    // MARK: - Subviews

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let micButton = UIButton(type: .custom)
    private let timerLabel = UILabel()
    private var waveBars: [UIView] = []
    private var waveBarHeights: [CGFloat] = Array(repeating: 4, count: Metrics.waveBarCount)

    // MARK: - State

    private var displayLink: CADisplayLink?
    private var currentLevel: Float = 0
    private var isRecordingActive = false

    // MARK: - Callbacks

    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: - Setup

    private func setupView() {
        layer.cornerRadius = Metrics.cornerRadius
        clipsToBounds = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 12

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Mic button
        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = .systemRed
        micButton.layer.cornerRadius = Metrics.micButtonSize / 2
        micButton.clipsToBounds = true
        micButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.accessibilityLabel = "Stop recording"
        addSubview(micButton)

        // Timer label
        timerLabel.text = "0:00"
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        timerLabel.textColor = .label
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timerLabel)

        NSLayoutConstraint.activate([
            micButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.padding),
            micButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: Metrics.micButtonSize),
            micButton.heightAnchor.constraint(equalToConstant: Metrics.micButtonSize),

            timerLabel.leadingAnchor.constraint(equalTo: micButton.trailingAnchor, constant: 10),
            timerLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        buildWaveBars()
        isAccessibilityElement = false
    }

    private func buildWaveBars() {
        waveBars.forEach { $0.removeFromSuperview() }
        waveBars.removeAll()

        var lastBar: UIView?
        for _ in 0..<Metrics.waveBarCount {
            let bar = UIView()
            bar.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
            bar.layer.cornerRadius = 1.25
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)

            NSLayoutConstraint.activate([
                bar.centerYAnchor.constraint(equalTo: centerYAnchor),
                bar.widthAnchor.constraint(equalToConstant: Metrics.waveBarWidth),
            ])

            if let prev = lastBar {
                bar.leadingAnchor.constraint(
                    equalTo: prev.trailingAnchor, constant: Metrics.waveBarSpacing
                ).isActive = true
            } else {
                bar.leadingAnchor.constraint(
                    equalTo: timerLabel.trailingAnchor, constant: 12
                ).isActive = true
            }

            waveBars.append(bar)
            lastBar = bar
        }
    }

    // MARK: - Public API

    func startAnimating() {
        isRecordingActive = true
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
        pulseMicButton()
    }

    func stopAnimating() {
        isRecordingActive = false
        displayLink?.invalidate()
        displayLink = nil
        micButton.layer.removeAllAnimations()
    }

    func updateLevel(_ level: Float) {
        currentLevel = level
    }

    func updateElapsed(_ elapsed: TimeInterval) {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        timerLabel.text = String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Animation

    @objc private func tick() {
        guard isRecordingActive else { return }
        // Shift wave bars left and append new level at right end.
        for i in 0..<(Metrics.waveBarCount - 1) {
            waveBarHeights[i] = waveBarHeights[i + 1]
        }
        let newHeight = max(4, CGFloat(currentLevel) * 36)
        waveBarHeights[Metrics.waveBarCount - 1] = newHeight

        for (i, bar) in waveBars.enumerated() {
            UIView.animate(withDuration: 0.04) {
                bar.frame.size.height = self.waveBarHeights[i]
            }
        }
    }

    private func pulseMicButton() {
        UIView.animate(
            withDuration: 0.8,
            delay: 0,
            options: [.repeat, .autoreverse, .curveEaseInOut]
        ) {
            self.micButton.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        }
    }

    // MARK: - Button action

    @objc private func stopTapped() {
        stopAnimating()
        onStop?()
    }
}
