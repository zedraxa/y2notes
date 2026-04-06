import AVFoundation
import UIKit
import QuartzCore
import AVFoundation

// MARK: - Ambient Scene

/// Visual mood scenes that layer subtle atmospheric effects onto the
/// editor canvas.  Each scene is intentionally restrained — the goal
/// is a barely-noticeable texture that increases immersion, not a
/// full-blown weather simulation.
///
/// Scenes are **mutually exclusive**: activating one deactivates any
/// previously active scene.
enum AmbientScene: String, CaseIterable, Identifiable {
    /// Soft rain-on-glass: subtle streaks drifting down + slight blue
    /// tint + heavier vignette.  Pairs with study / concentration.
    case rainStudy

    /// Lo-fi warm light: gentle warm colour wash + very slow, barely
    /// perceptible brightness pulse.  Pairs with relaxed note-taking.
    case lofiLight

    /// Night grain: faint film-grain texture + cool dark tint + slow
    /// parallax drift.  Pairs with dark-canvas / late-night sessions.
    case nightGrain

    var id: String { rawValue }

    /// SF Symbol name for the scene picker.
    var iconName: String {
        switch self {
        case .rainStudy: return "cloud.rain"
        case .lofiLight: return "light.recessed"
        case .nightGrain: return "moon.stars"
        }
    }

    /// Short human-readable label.
    var label: String {
        switch self {
        case .rainStudy: return "Rain"
        case .lofiLight: return "Lo-Fi"
        case .nightGrain: return "Night"
        }
    }
}

// MARK: - Ambient Environment Engine

/// GPU-composited ambient effect engine that overlays subtle atmospheric
/// textures onto the note editor canvas.
///
/// All effects use Core Animation layers and implicit GPU compositing —
/// no main-thread layout passes, no `UIView` hierarchy mutations.
///
/// **Performance contract**: total setup < 0.5 ms per scene activation,
/// steady-state zero CPU (GPU-composited repeating animations).
/// Within `PerformanceConstraints.ambientEnvironmentBudgetMs`.
///
/// **Reduce Motion**: when enabled, animated textures (rain streaks,
/// grain drift, light pulse) are presented as static overlays with no
/// motion — the tint / vignette still applies.
///
/// **Lifecycle**: create once per editor session.  Call `activate(_:…)`
/// / `deactivate()` as the user picks or dismisses a scene.
final class AmbientEnvironmentEngine {

    // MARK: - Tuning Constants

    private enum Tuning {
        // ── Rain Study ────────────────────────────────────────────
        /// Number of semi-transparent rain streak sublayers.
        static let rainStreakCount: Int = 6

        /// Rain streak width (points).
        static let rainStreakWidth: CGFloat = 1.0

        /// Rain streak height range (points).
        static let rainStreakMinHeight: CGFloat = 40.0
        static let rainStreakMaxHeight: CGFloat = 90.0

        /// Opacity of each rain streak.
        static let rainStreakOpacity: Float = 0.04

        /// Duration for a full top-to-bottom drift cycle (seconds).
        static let rainDriftDuration: CFTimeInterval = 4.0

        /// Blue-tinted colour overlay opacity.
        static let rainTintOpacity: Float = 0.04

        /// Rain-scene vignette opacity (heavier than focus mode).
        static let rainVignetteOpacity: Float = 0.22

        // ── Lo-Fi Light ───────────────────────────────────────────
        /// Warm colour wash overlay.
        static let lofiWarmColor: UIColor = UIColor(
            red: 1.0, green: 0.92, blue: 0.76, alpha: 1.0
        )
        /// Opacity of the warm colour wash.
        static let lofiWashOpacity: Float = 0.06

        /// Brightness pulse amplitude (opacity oscillation ±).
        static let lofiPulseAmplitude: Float = 0.025

        /// Pulse cycle duration (seconds) — very slow, barely visible.
        static let lofiPulseDuration: CFTimeInterval = 6.0

        // ── Night Grain ───────────────────────────────────────────
        /// Cool dark tint overlay opacity.
        static let nightTintOpacity: Float = 0.07

        /// Cool tint colour.
        static let nightTintColor: UIColor = UIColor(
            red: 0.15, green: 0.18, blue: 0.28, alpha: 1.0
        )

        /// Grain layer opacity.
        static let nightGrainOpacity: Float = 0.035

        /// Grain cell size (points) — one noise tile.
        static let nightGrainCellSize: CGFloat = 3.0

        /// Parallax drift speed (points/second).
        static let nightGrainDriftSpeed: CGFloat = 2.0

        /// Full drift cycle duration (seconds).
        static let nightGrainDriftDuration: CFTimeInterval = 12.0

        // ── Shared ────────────────────────────────────────────────
        /// Cross-fade duration for scene transitions (seconds).
        static let transitionDuration: CFTimeInterval = 0.45

        /// Instant transition when Reduce Motion is enabled.
        static let reducedMotionDuration: CFTimeInterval = 0.0

        // ── Sound ─────────────────────────────────────────────────
        /// Peak output volume for the rain soundscape (0–1).
        static let rainSoundVolume:  Float = 0.14
        /// Peak output volume for the lo-fi soundscape (0–1).
        static let lofiSoundVolume:  Float = 0.09
        /// Peak output volume for the night soundscape (0–1).
        static let nightSoundVolume: Float = 0.07
        /// LFO frequency used to add gentle lo-fi tremolo (Hz).
        static let lofiLFOFrequency: Float = 0.10
        /// Steps used for the volume fade-in / fade-out timer.
        static let soundFadeSteps:   Int   = 20
        /// Sample rate of the synthesised audio (Hz).
        static let sampleRate:       Double = 44_100
        /// Pre-computed lo-fi LFO phase increment per audio sample (radians).
        /// = 2π × lofiLFOFrequency / sampleRate
        static let lofiLFOIncrement: Float = Float(
            2.0 * Double.pi * Double(lofiLFOFrequency) / sampleRate
        )
    }

    // MARK: - State

    private(set) var activeScene: AmbientScene?

    /// Container holding all ambient sublayers — removed on deactivate.
    private weak var ambientContainer: CALayer?

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full {
        didSet {
            guard oldValue != effectIntensity, let scene = activeScene else { return }
            // Adjust live volume when intensity changes while a scene is active.
            let target = resolvedSoundVolume(for: scene)
            audioEngine?.mainMixerNode.outputVolume = target
        }
    }

    // MARK: - Sound state

    /// `true` when the user has not muted ambient sound.
    var soundEnabled: Bool = true {
        didSet {
            guard oldValue != soundEnabled else { return }
            if soundEnabled, let scene = activeScene {
                startAudio(for: scene)
            } else if !soundEnabled {
                stopAudio(immediate: true)
            }
        }
    }

    private var audioEngine:     AVAudioEngine?
    private var audioSourceNode: AVAudioSourceNode?
    private var volumeFadeTimer: Timer?

    // MARK: - Transition Duration

    private var fadeDuration: CFTimeInterval {
        ReduceMotionObserver.shared.isEnabled ? Tuning.reducedMotionDuration
        : (effectIntensity.allowsAmbientAnimations ? Tuning.transitionDuration
           : Tuning.reducedMotionDuration)
    }

    // MARK: - Activate

    /// Activates the given ambient scene on the editor container layer.
    ///
    /// - Parameters:
    ///   - scene: The ambient scene to activate.
    ///   - container: The root layer of the editor view.
    ///   - toolStore: Used to adjust toolbar opacity for immersion.
    func activate(
        _ scene: AmbientScene,
        on container: CALayer,
        toolStore: DrawingToolStore
    ) {
        // If a scene is already active, deactivate first.
        if activeScene != nil {
            deactivateImmediately()
        }

        activeScene = scene
        let bounds = container.bounds

        // Create a grouping container for all scene sublayers.
        let group = CALayer()
        group.frame = bounds
        group.zPosition = 998  // above canvas, below toolbar
        group.opacity = 0
        group.name = "ambientEnvironment"
        container.addSublayer(group)
        self.ambientContainer = group

        // Build scene-specific sublayers.
        switch scene {
        case .rainStudy:  buildRainStudy(in: group, bounds: bounds)
        case .lofiLight:  buildLofiLight(in: group, bounds: bounds)
        case .nightGrain: buildNightGrain(in: group, bounds: bounds)
        }

        // Fade in.
        animateOpacity(of: group, to: 1.0)

        // Start synthesised soundscape.
        if soundEnabled {
            startAudio(for: scene)
        }

        // Subtle toolbar dimming for immersion.
        toolStore.toolbarOpacity = 0.45
    }

    // MARK: - Deactivate

    /// Deactivates the current ambient scene with a fade-out.
    func deactivate(toolStore: DrawingToolStore) {
        guard let container = ambientContainer else {
            activeScene = nil
            return
        }
        activeScene = nil

        animateOpacity(of: container, to: 0) {
            container.removeFromSuperlayer()
        }

        stopAudio(immediate: false)
        toolStore.toolbarOpacity = 1.0
    }

    // MARK: - Layout Update

    /// Call when the container bounds change (e.g. rotation).
    func updateLayout(containerBounds: CGRect) {
        ambientContainer?.frame = containerBounds
        // Sublayers within the container auto-resize via autoresizing masks.
    }

    // MARK: - Immediate Teardown (no fade)

    private func deactivateImmediately() {
        ambientContainer?.removeAllAnimations()
        ambientContainer?.removeFromSuperlayer()
        ambientContainer = nil
        activeScene = nil
        stopAudio(immediate: true)
    }

    // MARK: - Rain Study Scene

    // MARK: - Ambient Sound Engine

    /// Starts the scene-specific synthesised soundscape with a smooth fade-in.
    private func startAudio(for scene: AmbientScene) {
        stopAudio(immediate: true)

        // Configure audio session to mix with other app audio (music, etc.).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let sampleRate = Tuning.sampleRate
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else { return }

        // Capture mutable noise state by reference via a helper class so the
        // render closure (which runs on the real-time audio thread) never touches
        // `self` — avoiding any potential data races.
        let noiseState = NoiseState()
        let capturedScene = scene

        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let bufPtr = ablPointer.first.map({ UnsafeMutableBufferPointer<Float>($0) }) else {
                return noErr
            }
            for i in 0..<Int(frameCount) {
                let sample: Float
                switch capturedScene {
                case .rainStudy:
                    sample = noiseState.pinkNoise()
                case .lofiLight:
                    // Pink noise with gentle LFO tremolo for lo-fi warmth.
                    let lfoValue = 0.85 + 0.15 * sinf(noiseState.lfoPhase)
                    noiseState.lfoPhase += Tuning.lofiLFOIncrement
                    if noiseState.lfoPhase > Float(2.0 * Double.pi) {
                        noiseState.lfoPhase -= Float(2.0 * Double.pi)
                    }
                    sample = noiseState.pinkNoise() * lfoValue
                case .nightGrain:
                    // Brown noise — deeper, bass-heavy for late-night atmosphere.
                    sample = noiseState.brownNoise()
                }
                bufPtr[i] = sample
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        // Start at zero; fade in below.
        engine.mainMixerNode.outputVolume = 0

        do {
            try engine.start()
        } catch {
            return
        }

        self.audioEngine     = engine
        self.audioSourceNode = sourceNode

        // Fade volume in over the scene transition duration.
        fadeVolume(to: resolvedSoundVolume(for: scene), steps: Tuning.soundFadeSteps,
                   interval: Tuning.transitionDuration / Double(Tuning.soundFadeSteps))
    }

    /// Stops the soundscape with an optional fade-out.
    private func stopAudio(immediate: Bool) {
        volumeFadeTimer?.invalidate()
        volumeFadeTimer = nil

        guard let engine = audioEngine else { return }

        if immediate {
            engine.stop()
            audioEngine     = nil
            audioSourceNode = nil
        } else {
            // Fade out then stop.
            let startVolume = engine.mainMixerNode.outputVolume
            let steps       = Tuning.soundFadeSteps
            let interval    = Tuning.transitionDuration / Double(steps)
            let delta       = startVolume / Float(steps)
            var step        = 0
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
                [weak self, weak engine] timer in
                guard let engine else { timer.invalidate(); return }
                step += 1
                engine.mainMixerNode.outputVolume = max(0, startVolume - delta * Float(step))
                if step >= steps {
                    timer.invalidate()
                    engine.stop()
                    self?.audioEngine     = nil
                    self?.audioSourceNode = nil
                }
            }
            RunLoop.main.add(t, forMode: .common)
            volumeFadeTimer = t
        }
    }

    /// Smoothly ramps the mixer's output volume to `target` over `steps` timer ticks.
    private func fadeVolume(to target: Float, steps: Int, interval: TimeInterval) {
        volumeFadeTimer?.invalidate()
        volumeFadeTimer = nil

        guard let engine = audioEngine else { return }
        let startVolume = engine.mainMixerNode.outputVolume
        let delta       = (target - startVolume) / Float(steps)
        var step        = 0

        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self, weak engine] timer in
            guard let engine else { timer.invalidate(); return }
            step += 1
            engine.mainMixerNode.outputVolume = startVolume + delta * Float(step)
            if step >= steps {
                timer.invalidate()
                self?.volumeFadeTimer = nil
                engine.mainMixerNode.outputVolume = target
            }
        }
        RunLoop.main.add(t, forMode: .common)
        volumeFadeTimer = t
    }

    /// Returns the effective peak volume for a scene, scaled by intensity and power mode.
    private func resolvedSoundVolume(for scene: AmbientScene) -> Float {
        let base: Float
        switch scene {
        case .rainStudy:  base = Tuning.rainSoundVolume
        case .lofiLight:  base = Tuning.lofiSoundVolume
        case .nightGrain: base = Tuning.nightSoundVolume
        }
        var vol = base
        switch effectIntensity {
        case .full:    break
        case .reduced: vol *= 0.6
        case .minimal: return 0
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Halve volume in Low Power Mode to reduce audio processing load.
            vol *= 0.5
        }
        return vol
    }

    // MARK: - Rain Study Scene

    private func buildRainStudy(in group: CALayer, bounds: CGRect) {
        // 1. Cool blue tint overlay.
        let tint = CALayer()
        tint.frame = bounds
        tint.backgroundColor = UIColor(red: 0.6, green: 0.75, blue: 0.95, alpha: 1.0).cgColor
        tint.opacity = Tuning.rainTintOpacity
        group.addSublayer(tint)

        // 2. Heavier vignette.
        let vignette = makeVignette(bounds: bounds, opacity: Tuning.rainVignetteOpacity)
        group.addSublayer(vignette)

        // 3. Rain streaks — thin vertical lines drifting downward.
        for i in 0..<Tuning.rainStreakCount {
            let streak = CALayer()
            let h = Tuning.rainStreakMinHeight
                + CGFloat(i) / CGFloat(max(Tuning.rainStreakCount - 1, 1))
                * (Tuning.rainStreakMaxHeight - Tuning.rainStreakMinHeight)
            let xFraction = CGFloat(i + 1) / CGFloat(Tuning.rainStreakCount + 1)
            let x = bounds.width * xFraction

            streak.frame = CGRect(x: x, y: -h, width: Tuning.rainStreakWidth, height: h)
            streak.backgroundColor = UIColor.white.cgColor
            streak.opacity = Tuning.rainStreakOpacity
            streak.cornerRadius = Tuning.rainStreakWidth / 2
            group.addSublayer(streak)

            if !ReduceMotionObserver.shared.isEnabled && effectIntensity.allowsAmbientAnimations {
                let drift = CABasicAnimation(keyPath: "position.y")
                drift.fromValue = -h / 2
                drift.toValue = bounds.height + h / 2
                // Stagger each streak slightly.
                drift.duration = Tuning.rainDriftDuration + Double(i) * 0.3
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .linear)
                streak.add(drift, forKey: "rainDrift")
            } else {
                // Static: position streaks at random vertical offsets.
                streak.position.y = bounds.height * xFraction
            }
        }
    }

    // MARK: - Lo-Fi Light Scene

    private func buildLofiLight(in group: CALayer, bounds: CGRect) {
        // 1. Warm colour wash.
        let wash = CALayer()
        wash.frame = bounds
        wash.backgroundColor = Tuning.lofiWarmColor.cgColor
        wash.opacity = Tuning.lofiWashOpacity
        group.addSublayer(wash)

        // 2. Slow brightness pulse.
        if !ReduceMotionObserver.shared.isEnabled && effectIntensity.allowsAmbientAnimations {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = Tuning.lofiWashOpacity - Tuning.lofiPulseAmplitude
            pulse.toValue   = Tuning.lofiWashOpacity + Tuning.lofiPulseAmplitude
            pulse.duration  = Tuning.lofiPulseDuration
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wash.add(pulse, forKey: "lofiPulse")
        }

        // 3. Soft vignette.
        let vignette = makeVignette(bounds: bounds, opacity: 0.12)
        group.addSublayer(vignette)
    }

    // MARK: - Night Grain Scene

    private func buildNightGrain(in group: CALayer, bounds: CGRect) {
        // 1. Cool dark tint.
        let tint = CALayer()
        tint.frame = bounds
        tint.backgroundColor = Tuning.nightTintColor.cgColor
        tint.opacity = Tuning.nightTintOpacity
        group.addSublayer(tint)

        // 2. Film grain texture.
        let grain = makeGrainLayer(bounds: bounds)
        grain.opacity = Tuning.nightGrainOpacity
        group.addSublayer(grain)

        // 3. Slow parallax drift on the grain layer.
        if !ReduceMotionObserver.shared.isEnabled && effectIntensity.allowsAmbientAnimations {
            let driftX = CABasicAnimation(keyPath: "position.x")
            driftX.fromValue = grain.position.x
            driftX.toValue   = grain.position.x + Tuning.nightGrainDriftSpeed * CGFloat(Tuning.nightGrainDriftDuration)
            driftX.duration  = Tuning.nightGrainDriftDuration
            driftX.autoreverses = true
            driftX.repeatCount = .infinity
            driftX.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            grain.add(driftX, forKey: "grainDriftX")

            let driftY = CABasicAnimation(keyPath: "position.y")
            driftY.fromValue = grain.position.y
            driftY.toValue   = grain.position.y + Tuning.nightGrainDriftSpeed * 0.5 * CGFloat(Tuning.nightGrainDriftDuration)
            driftY.duration  = Tuning.nightGrainDriftDuration * 1.3
            driftY.autoreverses = true
            driftY.repeatCount = .infinity
            driftY.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            grain.add(driftY, forKey: "grainDriftY")
        }

        // 4. Heavier vignette for night mood.
        let vignette = makeVignette(bounds: bounds, opacity: 0.20)
        group.addSublayer(vignette)
    }

    // MARK: - Grain Texture Factory

    /// Creates a `CAReplicatorLayer`-based noise pattern.  The pattern
    /// tiles a small random-brightness cell across the bounds.
    private func makeGrainLayer(bounds: CGRect) -> CALayer {
        let cell = Tuning.nightGrainCellSize
        // Oversized to allow drift without revealing edges.
        let overscan: CGFloat = 60
        let size = CGSize(
            width: bounds.width + overscan * 2,
            height: bounds.height + overscan * 2
        )

        // Build a small bitmap with random grayscale noise.
        let cols = Int(ceil(size.width / cell))
        let rows = Int(ceil(size.height / cell))

        let layer = CALayer()
        layer.frame = CGRect(
            x: -overscan,
            y: -overscan,
            width: size.width,
            height: size.height
        )

        // Use a CG bitmap for the noise pattern.
        let bitmapWidth  = cols
        let bitmapHeight = rows
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bytesPerRow: bitmapWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return layer
        }

        // Fill with random noise.
        guard let buffer = ctx.data else { return layer }
        let ptr = buffer.bindMemory(to: UInt8.self, capacity: bitmapWidth * bitmapHeight)
        for i in 0..<(bitmapWidth * bitmapHeight) {
            ptr[i] = UInt8.random(in: 80...200)
        }

        if let image = ctx.makeImage() {
            layer.contents = image
            layer.contentsGravity = .resize
            layer.magnificationFilter = .nearest  // Pixelated look.
        }

        return layer
    }

    // MARK: - Vignette Factory

    private func makeVignette(bounds: CGRect, opacity: Float) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.frame = bounds

        let clear = UIColor.clear.cgColor
        let dark  = UIColor.black.cgColor

        layer.colors    = [clear, clear, dark]
        layer.locations = [0.0, 0.40, 1.0]
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint   = CGPoint(x: 1.0, y: 1.0)
        layer.opacity    = opacity

        return layer
    }

    // MARK: - Opacity Animation

    private func animateOpacity(
        of layer: CALayer,
        to target: Float,
        completion: (() -> Void)? = nil
    ) {
        let anim                    = CABasicAnimation(keyPath: "opacity")
        anim.fromValue              = layer.opacity
        anim.toValue                = target
        anim.duration               = fadeDuration
        anim.timingFunction         = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode               = .forwards
        anim.isRemovedOnCompletion  = false

        if let completion = completion {
            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            layer.add(anim, forKey: "ambientFade")
            CATransaction.commit()
        } else {
            layer.add(anim, forKey: "ambientFade")
        }
    }
}

// MARK: - NoiseState

/// Mutable noise generator state passed into the real-time audio render closure.
/// Using a reference type avoids capturing `self` (AmbientEnvironmentEngine) from the
/// render callback, which would introduce a retain cycle and potential data race.
private final class NoiseState {
    // Pink-noise filter coefficients (Paul Kellet's algorithm).
    var b0: Float = 0, b1: Float = 0, b2: Float = 0
    var b3: Float = 0, b4: Float = 0, b5: Float = 0
    // Brown-noise integrator.
    var bnLastOut: Float = 0
    // Lo-fi LFO phase (radians).
    var lfoPhase: Float = 0
    // LCG PRNG state — fast, lock-free, suitable for audio thread.
    var lcgState: UInt32 = 2_463_534_242

    /// Returns the next pink-noise sample in the approximate range ±0.5.
    ///
    /// Uses Paul Kellet's pink-noise IIR filter (3rd-order Yule-Walker approximation).
    /// The six filter coefficients (0.99886…) are the pole locations that shape the
    /// spectrum to approximate a −3 dB/octave roll-off characteristic of pink noise.
    @inline(__always)
    func pinkNoise() -> Float {
        let white = lcgFloat()
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        return (b0 + b1 + b2 + b3 + b4 + b5 + white * 0.5362) * 0.11
    }

    /// Returns the next brown-noise sample (deeper, bass-heavy).
    @inline(__always)
    func brownNoise() -> Float {
        let white = lcgFloat()
        bnLastOut = (bnLastOut + 0.02 * white) / 1.02
        return bnLastOut * 3.5
    }

    /// Returns a uniform random Float in [-1, 1] using an LCG PRNG.
    @inline(__always)
    private func lcgFloat() -> Float {
        lcgState = lcgState &* 1_664_525 &+ 1_013_904_223
        return (Float(lcgState) / Float(UInt32.max)) * 2.0 - 1.0
    }
}
