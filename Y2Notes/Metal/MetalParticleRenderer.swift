import UIKit
import Metal
import QuartzCore

// MARK: - Metal-layout types
// These structs must stay byte-for-byte identical to the structs in Y2ParticleSystem.metal.

/// One particle.  48 bytes — matches `MetalParticle` in Y2ParticleSystem.metal.
private struct MetalParticle {
    var position: SIMD2<Float>  //  8
    var velocity: SIMD2<Float>  //  8
    var color:    SIMD4<Float>  // 16
    var life:     Float         //  4
    var maxLife:  Float         //  4
    var size:     Float         //  4
    var pad:      Float = 0     //  4  (alignment)
    // Total: 48 bytes

    static let stride = 48

    static let dead = MetalParticle(
        position: .zero, velocity: .zero,
        color: .zero, life: 0, maxLife: 1, size: 0
    )
}

/// Physics uniforms — 32 bytes, matches `PhysicsUniforms` in Y2ParticleSystem.metal.
private struct PhysicsUniforms {
    var gravity:       SIMD2<Float>  //  8
    var wind:          Float         //  4
    var dt:            Float         //  4
    var particleCount: UInt32        //  4
    var pad0:          Float = 0     //  4
    var pad1:          Float = 0     //  4
    var pad2:          Float = 0     //  4
}

/// Render uniforms — 16 bytes, matches `RenderUniforms` in Y2ParticleSystem.metal.
private struct RenderUniforms {
    var viewportSize: SIMD2<Float>   //  8
    var contentScale: Float          //  4
    var pad:          Float = 0      //  4
}

// MARK: - Color mode

/// How a newly-spawned particle's color is determined.
enum MetalSpawnColorMode {
    /// Constant RGBA for every particle (sparkle, dissolve, snow, …).
    case solid(SIMD4<Float>)
    /// Fire warm palette: random interpolation between yellow-white core and orange-red mid-flame.
    case firePalette(inkTint: SIMD4<Float>)
    /// Random full-saturation hue per particle (rainbow, sheen, …).
    case cyclingHue(saturation: Float, brightness: Float, alpha: Float)
    /// Blood: fixed deep-crimson with slight red variance.
    case blood
    /// Shadow smoke: mid-grey with cool blue tint.
    case shadow
}

// MARK: - Preset configuration

/// Physics and visual parameters for one emitter-based ink effect.
/// These replace the CAEmitterCell parameter sets that were configured in InkEffectEngine.
struct MetalParticlePresetConfig {
    let gravity:             SIMD2<Float>  // pts/s² — UIKit y-down (positive y = down)
    let wind:                Float         // x-axis acceleration (pts/s²)
    let spawnRate:           Float         // particles per second at `birthRateMultiplier` = 1
    let initialSpeed:        Float         // mean launch speed (pts/s)
    let speedRange:          Float         // ± random deviation around `initialSpeed`
    let minLifetime:         Float         // seconds
    let maxLifetime:         Float
    let minSize:             Float         // point-sprite diameter (pts)
    let maxSize:             Float
    let emissionHalfCone:    Float         // half-angle spread in radians (π = omnidirectional)
    let emissionAngle:       Float         // base emission direction (0 = right, −π/2 = up)
    let useAdditiveBlending: Bool          // true = additive; false = source-over (shadow)
}

extension MetalParticlePresetConfig {
    // MARK: Named presets — one per emitter-based WritingFXType

    static let fire = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(0, -180),
        wind:                0,
        spawnRate:           48,
        initialSpeed:        95, speedRange: 45,
        minLifetime: 0.30, maxLifetime: 0.70,
        minSize:      6, maxSize: 16,
        emissionHalfCone: .pi / 4,
        emissionAngle:    -.pi / 2,         // upward
        useAdditiveBlending: true
    )
    static let sparkle = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(0, 50),
        wind:                0,
        spawnRate:           30,
        initialSpeed: 80, speedRange: 40,
        minLifetime: 0.35, maxLifetime: 0.80,
        minSize: 4, maxSize: 12,
        emissionHalfCone: .pi,
        emissionAngle:    0,
        useAdditiveBlending: true
    )
    static let snow = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(-8, 40),
        wind:                -10,
        spawnRate:           20,
        initialSpeed: 28, speedRange: 15,
        minLifetime: 1.0, maxLifetime: 2.5,
        minSize: 3, maxSize: 8,
        emissionHalfCone: .pi,
        emissionAngle:    0,
        useAdditiveBlending: true
    )
    static let dissolve = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(0, 80),
        wind:                0,
        spawnRate:           38,
        initialSpeed: 85, speedRange: 40,
        minLifetime: 0.35, maxLifetime: 1.0,
        minSize: 5, maxSize: 14,
        emissionHalfCone: .pi,
        emissionAngle:    0,
        useAdditiveBlending: true
    )
    static let rainbow = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(0, 30),
        wind:                0,
        spawnRate:           32,
        initialSpeed: 60, speedRange: 30,
        minLifetime: 0.50, maxLifetime: 1.30,
        minSize: 6, maxSize: 18,
        emissionHalfCone: .pi,
        emissionAngle:    0,
        useAdditiveBlending: true
    )
    static let sheen = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(0, 20),
        wind:                0,
        spawnRate:           55,
        initialSpeed: 80, speedRange: 30,
        minLifetime: 0.45, maxLifetime: 1.0,
        minSize: 5, maxSize: 14,
        emissionHalfCone: .pi,
        emissionAngle:    0,
        useAdditiveBlending: true
    )
    static let blood = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(0, 350),
        wind:                0,
        spawnRate:           22,
        initialSpeed: 45, speedRange: 20,
        minLifetime: 0.50, maxLifetime: 1.2,
        minSize: 8, maxSize: 18,
        emissionHalfCone: .pi / 6,
        emissionAngle:    .pi / 2,          // downward
        useAdditiveBlending: true
    )
    static let shadow = MetalParticlePresetConfig(
        gravity:             SIMD2<Float>(0, -30),
        wind:                8,
        spawnRate:           25,
        initialSpeed: 18, speedRange: 12,
        minLifetime: 0.90, maxLifetime: 1.80,
        minSize: 14, maxSize: 32,
        emissionHalfCone: .pi,
        emissionAngle:    0,
        useAdditiveBlending: false          // normal alpha so grey puffs are visible on white
    )
}

// MARK: - MetalParticleRenderer

/// GPU-accelerated particle renderer that replaces `CAEmitterLayer` for all
/// emitter-based ink effects (fire, sparkle, snow, dissolve, rainbow, sheen, blood, shadow).
///
/// **Architecture**
/// - Owns a `CAMetalLayer` that is inserted as a sublayer of the provided `overlayLayer`.
/// - A `CADisplayLink` drives frame updates at the display's native refresh rate.
/// - **Spawn logic** runs on the CPU: writes new particles directly into a shared
///   `MTLBuffer` before encoding the GPU command buffer.
/// - **Physics update** runs on the GPU via a Metal compute kernel (`updateParticles`).
/// - **Rendering** uses point sprites: each live particle becomes a single vertex;
///   the fragment shader draws a soft radial disc.
///
/// **Particle pool**
/// The pool is a fixed-size ring of `MetalParticle` records in shared CPU/GPU memory.
/// The CPU tracks each slot's expiry wall-clock time so it can recycle dead slots without
/// reading back GPU-side `life` values (which would require a costly completion-handler hop).
///
/// **Blending**
/// - Most effects use **additive** blending (src·α + dst) — particles glow on dark surfaces.
/// - Shadow uses **source-over** alpha blending so grey smoke is visible on white paper.
///
/// **Thread safety**: create and use exclusively on the **main thread**.
final class MetalParticleRenderer {

    // MARK: - Pool size

    private static let poolSize = 2048

    // MARK: - Metal resources

    private let device:           MTLDevice
    private let commandQueue:     MTLCommandQueue
    private let computePipeline:  MTLComputePipelineState
    private let additivePipeline: MTLRenderPipelineState
    private let normalPipeline:   MTLRenderPipelineState
    private let particleBuffer:   MTLBuffer
    private let metalLayer:       CAMetalLayer

    // Pointer to the shared CPU/GPU particle data (do not cache across frame boundaries).
    private let particlePtr: UnsafeMutablePointer<MetalParticle>

    // MARK: - CPU spawn state

    /// Wall-clock expiry timestamp for every pool slot (seconds since reference date).
    /// The CPU uses this to find dead slots without reading back GPU memory.
    private var expiryTime: [Double]
    private var spawnCursor:      Int    = 0
    private var spawnAccumulator: Double = 0

    // MARK: - Active preset

    private var preset:    MetalParticlePresetConfig = .sparkle
    private var colorMode: MetalSpawnColorMode       = .solid(SIMD4<Float>(1, 1, 1, 1))

    // MARK: - Public interface

    /// Current pen-tip position in the overlay view's coordinate space (UIKit points).
    var emitterPosition: CGPoint = .zero

    /// Emission rate multiplier.
    /// • 0.0 = no new particles (pen lifted / effect inactive).
    /// • 1.0 = normal rate defined by the preset.
    /// • 3.0 = burst mode (end-of-stroke scatter).
    var birthRateMultiplier: Float = 0

    // MARK: - Display link

    private var displayLink:   CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    // MARK: - Init

    /// Attaches a new `CAMetalLayer` to `overlayLayer` and builds all Metal pipelines.
    ///
    /// Returns `nil` if the device does not support Metal (unreachable on iOS 17+).
    init?(overlayLayer: CALayer) {
        guard
            let dev   = MTLCreateSystemDefaultDevice(),
            let queue = dev.makeCommandQueue(),
            let lib   = dev.makeDefaultLibrary()
        else { return nil }

        // ── Compute pipeline (physics) ────────────────────────────────────────
        guard
            let computeFn = lib.makeFunction(name: "updateParticles"),
            let cp        = try? dev.makeComputePipelineState(function: computeFn)
        else { return nil }

        // ── Additive render pipeline ──────────────────────────────────────────
        func buildRenderPipeline(additive: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction   = lib.makeFunction(name: "particleVertex")
            d.fragmentFunction = lib.makeFunction(name: "particleFragment")
            let att = d.colorAttachments[0]!
            att.pixelFormat              = .bgra8Unorm
            att.isBlendingEnabled        = true
            att.sourceRGBBlendFactor     = .sourceAlpha
            att.sourceAlphaBlendFactor   = .sourceAlpha
            att.destinationRGBBlendFactor  = additive ? .one : .oneMinusSourceAlpha
            att.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
            return try? dev.makeRenderPipelineState(descriptor: d)
        }
        guard
            let addRP  = buildRenderPipeline(additive: true),
            let normRP = buildRenderPipeline(additive: false)
        else { return nil }

        // ── Particle buffer (storageModeShared = accessible from both CPU and GPU) ──
        let bufLen = MetalParticleRenderer.poolSize * MetalParticle.stride
        guard let buf = dev.makeBuffer(length: bufLen, options: .storageModeShared) else { return nil }
        let ptr = buf.contents().bindMemory(to: MetalParticle.self,
                                            capacity: MetalParticleRenderer.poolSize)
        for i in 0..<MetalParticleRenderer.poolSize { ptr[i] = .dead }

        // ── CAMetalLayer ──────────────────────────────────────────────────────
        let ml = CAMetalLayer()
        ml.device          = dev
        ml.pixelFormat     = .bgra8Unorm
        ml.framebufferOnly = false
        ml.isOpaque        = false
        ml.backgroundColor = CGColor(gray: 0, alpha: 0)
        ml.contentsScale   = UIScreen.main.scale
        ml.frame           = overlayLayer.bounds
        ml.drawableSize    = CGSize(
            width:  overlayLayer.bounds.width  * UIScreen.main.scale,
            height: overlayLayer.bounds.height * UIScreen.main.scale
        )
        overlayLayer.insertSublayer(ml, at: 0)   // behind all CA layers (glows, lightning, etc.)

        self.device           = dev
        self.commandQueue     = queue
        self.computePipeline  = cp
        self.additivePipeline = addRP
        self.normalPipeline   = normRP
        self.particleBuffer   = buf
        self.metalLayer       = ml
        self.particlePtr      = ptr
        self.expiryTime       = Array(repeating: 0.0, count: MetalParticleRenderer.poolSize)
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Configuration

    /// Configures the particle system for a specific effect and colour.
    ///
    /// Call before `start()` or any time the effect/colour changes.
    /// Only newly spawned particles will use the updated configuration;
    /// particles already alive keep their birth colour.
    func configure(preset: MetalParticlePresetConfig, colorMode: MetalSpawnColorMode) {
        self.preset    = preset
        self.colorMode = colorMode
        spawnAccumulator = 0
    }

    /// Updates the colour mode without touching physics/preset.  Used when the ink
    /// colour changes mid-session for effects like sparkle, dissolve, snow, fire.
    func updateColorMode(_ mode: MetalSpawnColorMode) {
        colorMode = mode
    }

    // MARK: - Lifecycle

    /// Starts the `CADisplayLink` frame loop.  Safe to call multiple times.
    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = CACurrentMediaTime()
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    /// Stops the frame loop and immediately clears all live particles.
    func stop() {
        displayLink?.invalidate()
        displayLink    = nil
        birthRateMultiplier = 0
        clearAllParticles()
    }

    /// Keeps the `CAMetalLayer`'s frame and drawable size in sync with the overlay bounds.
    ///
    /// Call from `InkEffectEngine.syncLayerFrames()` whenever the overlay is laid out.
    func syncFrame(to bounds: CGRect) {
        guard metalLayer.frame != bounds else { return }
        metalLayer.frame       = bounds
        metalLayer.drawableSize = CGSize(
            width:  bounds.width  * UIScreen.main.scale,
            height: bounds.height * UIScreen.main.scale
        )
    }

    // MARK: - Frame update

    @objc private func tick() {
        guard let dl = displayLink else { return }
        let now = dl.timestamp
        let dt  = Float(min(now - lastTimestamp, 0.05))   // cap at 50 ms to absorb pauses
        lastTimestamp = now
        guard dt > 0 else { return }

        // 1. CPU spawn: write new particles into dead slots before GPU command encoding.
        if birthRateMultiplier > 0 {
            spawnParticles(dt: dt, wallTime: now)
        }

        // 2. Encode GPU work.
        guard
            let drawable = metalLayer.nextDrawable(),
            let cmdBuf   = commandQueue.makeCommandBuffer()
        else { return }

        // ── Compute pass: physics ─────────────────────────────────────────────
        var pu = PhysicsUniforms(
            gravity:       preset.gravity,
            wind:          preset.wind,
            dt:            dt,
            particleCount: UInt32(MetalParticleRenderer.poolSize)
        )
        guard let physBuf = device.makeBuffer(bytes: &pu,
                                              length: MemoryLayout<PhysicsUniforms>.stride,
                                              options: .storageModeShared) else { return }

        if let enc = cmdBuf.makeComputeCommandEncoder() {
            enc.setComputePipelineState(computePipeline)
            enc.setBuffer(particleBuffer, offset: 0, index: 0)
            enc.setBuffer(physBuf,        offset: 0, index: 1)
            let tgw    = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
            let count  = MetalParticleRenderer.poolSize
            let groups = (count + tgw - 1) / tgw
            enc.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: tgw, height: 1, depth: 1))
            enc.endEncoding()
        }

        // ── Render pass: point sprites ────────────────────────────────────────
        var ru = RenderUniforms(
            viewportSize: SIMD2<Float>(Float(metalLayer.frame.width),
                                       Float(metalLayer.frame.height)),
            contentScale: Float(UIScreen.main.scale)
        )
        guard let renderBuf = device.makeBuffer(bytes: &ru,
                                                length: MemoryLayout<RenderUniforms>.stride,
                                                options: .storageModeShared) else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = drawable.texture
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        if let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(
                preset.useAdditiveBlending ? additivePipeline : normalPipeline
            )
            enc.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            enc.setVertexBuffer(renderBuf,      offset: 0, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0,
                               vertexCount: MetalParticleRenderer.poolSize)
            enc.endEncoding()
        }

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - CPU spawn logic

    private func spawnParticles(dt: Float, wallTime: Double) {
        spawnAccumulator += Double(preset.spawnRate * birthRateMultiplier * dt)
        let n = Int(spawnAccumulator)
        spawnAccumulator -= Double(n)
        for _ in 0..<n { spawnOne(wallTime: wallTime) }
    }

    private func spawnOne(wallTime: Double) {
        // Round-robin search for an expired slot.
        // Using the CPU-side `expiryTime` avoids a GPU readback while staying
        // accurate: the lifetime matches what the compute kernel will decrement.
        var found = false
        for _ in 0..<MetalParticleRenderer.poolSize {
            if wallTime > expiryTime[spawnCursor] {
                found = true
                break
            }
            spawnCursor = (spawnCursor + 1) % MetalParticleRenderer.poolSize
        }
        guard found else { return }   // pool exhausted — drop this spawn

        let idx = spawnCursor
        spawnCursor = (spawnCursor + 1) % MetalParticleRenderer.poolSize

        let lifetime = Float.random(in: preset.minLifetime...preset.maxLifetime)
        expiryTime[idx] = wallTime + Double(lifetime)

        let spread = Float.random(in: -preset.emissionHalfCone...preset.emissionHalfCone)
        let angle  = preset.emissionAngle + spread
        let speed  = preset.initialSpeed + Float.random(in: -preset.speedRange...preset.speedRange)

        // Write directly into the shared MTLBuffer — visible to the GPU on the same frame.
        particlePtr[idx] = MetalParticle(
            position: SIMD2<Float>(Float(emitterPosition.x), Float(emitterPosition.y)),
            velocity: SIMD2<Float>(cos(angle) * speed, sin(angle) * speed),
            color:    spawnColor(),
            life:     lifetime,
            maxLife:  lifetime,
            size:     Float.random(in: preset.minSize...preset.maxSize)
        )
    }

    private func spawnColor() -> SIMD4<Float> {
        switch colorMode {
        case .solid(let c):
            return c

        case .firePalette(let tint):
            // Interpolate between yellow-white hot core and orange-red mid-flame.
            let t     = Float.random(in: 0...1)
            let core  = SIMD4<Float>(1.00, 0.96, 0.62, 0.95)
            let flame = SIMD4<Float>(
                min(1.0, tint.x * 0.35 + 0.72),
                min(1.0, tint.y * 0.25 + 0.22),
                max(0.0, tint.z * 0.08),
                0.90
            )
            return core * (1 - t) + flame * t

        case .cyclingHue(let sat, let bri, let alpha):
            let hue = Float.random(in: 0...1)
            return hsbToSIMD4(h: hue, s: sat, b: bri, a: alpha)

        case .blood:
            let r = Float.random(in: 0.45...0.65)
            return SIMD4<Float>(r, 0.01, 0.01, 0.90)

        case .shadow:
            let grey = Float.random(in: 0.28...0.45)
            return SIMD4<Float>(grey, grey, grey + 0.04, 0.35)
        }
    }

    private func clearAllParticles() {
        for i in 0..<MetalParticleRenderer.poolSize {
            particlePtr[i] = .dead
            expiryTime[i]  = 0
        }
        spawnAccumulator = 0
        spawnCursor      = 0
    }
}

// MARK: - UIColor convenience

extension UIColor {
    /// Returns the colour's RGBA components as a SIMD4<Float>.
    var simd4: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}

// MARK: - HSB → SIMD4 helper

private func hsbToSIMD4(h: Float, s: Float, b: Float, a: Float) -> SIMD4<Float> {
    let color = UIColor(hue: CGFloat(h), saturation: CGFloat(s),
                        brightness: CGFloat(b), alpha: CGFloat(a))
    return color.simd4
}
