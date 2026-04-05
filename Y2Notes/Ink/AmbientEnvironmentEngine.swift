import AVFoundation
import UIKit
import QuartzCore

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
        /// Master volume for ambient soundscapes (0–1).
        /// Intentionally low so audio stays in the background.
        static let soundVolume: Float = 0.30

        /// Volume multiplier applied when `effectIntensity` is `.reduced`.
        static let soundReducedMultiplier: Float = 0.55

        /// Volume fade-out duration when a scene is deactivated (seconds).
        static let soundFadeDuration: TimeInterval = 0.8

        /// Timer tick interval used when fading audio volume out (seconds).
        static let soundFadeStepInterval: TimeInterval = 0.05

        /// Bundle audio file names — one per scene.  Files may be absent
        /// (e.g. in a build that ships without audio assets); the engine
        /// gracefully skips playback when a resource cannot be found.
        static let rainSoundName:  String = "ambient_rain"
        static let lofiSoundName:  String = "ambient_lofi"
        static let nightSoundName: String = "ambient_night"
    }

    // MARK: - State

    private let reduceMotion: Bool
    private(set) var activeScene: AmbientScene?

    /// Container holding all ambient sublayers — removed on deactivate.
    private weak var ambientContainer: CALayer?

    /// Looping audio player for the active scene's soundscape.
    /// `nil` when no scene is active or when the audio asset is absent from
    /// the bundle (the engine degrades gracefully to visuals-only).
    private var audioPlayer: AVAudioPlayer?

    /// A repeating timer used to smoothly fade the audio volume to zero on
    /// deactivation, then stop the player once silence is reached.
    private var fadeTimer: Timer?

    init() {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
    }

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    // MARK: - Transition Duration

    private var fadeDuration: CFTimeInterval {
        reduceMotion ? Tuning.reducedMotionDuration
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

        // Start looping soundscape for this scene.
        startAudio(for: scene)

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

        // Fade audio out smoothly before stopping.
        stopAudio(fade: true)

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
        stopAudio(fade: false)
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

            if !reduceMotion && effectIntensity.allowsAmbientAnimations {
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
        if !reduceMotion && effectIntensity.allowsAmbientAnimations {
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
        if !reduceMotion && effectIntensity.allowsAmbientAnimations {
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

    // MARK: - Sound Playback

    /// Starts looping audio for the given scene.
    ///
    /// Uses `AVAudioSession.Category.ambient` so the soundscape mixes with
    /// the user's own music / podcasts and does not interrupt other apps.
    /// Audio is silenced entirely when `effectIntensity` is `.minimal` (e.g.
    /// very high writing velocity or low-power mode override) and reduced in
    /// volume at `.reduced` intensity.
    private func startAudio(for scene: AmbientScene) {
        // Determine the target volume; skip playback at minimal intensity.
        let targetVolume = resolvedSoundVolume
        guard targetVolume > 0 else { return }

        // Resolve bundle resource name for the scene.
        let resourceName: String
        switch scene {
        case .rainStudy:  resourceName = Tuning.rainSoundName
        case .lofiLight:  resourceName = Tuning.lofiSoundName
        case .nightGrain: resourceName = Tuning.nightSoundName
        }

        // Look up the audio file in the main bundle.  Supported extensions
        // are tried in order; the first match wins.
        let supportedExtensions = ["m4a", "mp3", "wav", "caf", "aiff"]
        var audioURL: URL?
        for ext in supportedExtensions {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: ext) {
                audioURL = url
                break
            }
        }
        guard let url = audioURL else {
            // Audio asset not present in bundle — degrade gracefully to
            // visuals-only.  This is expected in builds without audio assets.
            return
        }

        do {
            // Configure AVAudioSession to use the ambient category so that:
            // • the soundscape mixes with background music / media apps, and
            // • playback respects the hardware ringer/silent switch.
            try AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1  // Negative value = loop indefinitely (AVAudioPlayer API contract).
            player.volume = targetVolume
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            // Failed to initialise — proceed without audio.
            audioPlayer = nil
        }
    }

    /// Stops the active audio player, optionally fading the volume to zero
    /// first so the cut-off isn't abrupt.
    private func stopAudio(fade: Bool) {
        // Cancel any in-flight fade.
        fadeTimer?.invalidate()
        fadeTimer = nil

        guard let player = audioPlayer else { return }

        if fade && player.isPlaying {
            // Gradually reduce volume in small steps over `soundFadeDuration`.
            let stepInterval = Tuning.soundFadeStepInterval
            let steps = max(1, Int(Tuning.soundFadeDuration / stepInterval))
            let volumeStep = player.volume / Float(steps)

            // Explicitly schedule on RunLoop.main so the timer fires reliably
            // regardless of which thread this method is called from.
            let timer = Timer(
                timeInterval: stepInterval,
                repeats: true
            ) { [weak self, weak player] timer in
                guard let player else {
                    timer.invalidate()
                    self?.fadeTimer = nil
                    return
                }
                player.volume = max(0, player.volume - volumeStep)
                if player.volume <= 0 {
                    timer.invalidate()
                    self?.fadeTimer = nil
                    self?.finaliseStop(player: player)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            fadeTimer = timer
        } else {
            finaliseStop(player: player)
        }
    }

    /// Stops `player` and clears the `audioPlayer` reference.
    private func finaliseStop(player: AVAudioPlayer) {
        player.stop()
        audioPlayer = nil
    }

    /// Volume for the current effect intensity, also considering low power
    /// mode — halves the master volume when the device is in low-power mode.
    private var resolvedSoundVolume: Float {
        let lowPowerMultiplier: Float = ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.5 : 1.0
        switch effectIntensity {
        case .minimal:
            return 0
        case .reduced:
            return Tuning.soundVolume * Tuning.soundReducedMultiplier * lowPowerMultiplier
        case .full:
            return Tuning.soundVolume * lowPowerMultiplier
        }
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
