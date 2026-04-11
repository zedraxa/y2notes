/// Y2ParticleSystem.metal
/// GPU compute kernel (particle physics) and render shaders (point sprites)
/// for Metal-driven ink particle effects.
///
/// Data-layout contract: the `MetalParticle` struct below must stay byte-for-byte
/// identical to the particle struct used by the renderer.

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared data types

/// One particle in the pool.  48 bytes — must match renderer layout.
struct MetalParticle {
    float2 position;  //  8: UIKit screen-space (pts, top-left origin, y-down)
    float2 velocity;  //  8: points per second
    float4 color;     // 16: RGBA — .w is alpha (set by compute kernel each frame)
    float  life;      //  4: remaining lifetime (seconds); 0 = dead
    float  maxLife;   //  4: initial lifetime (seconds)
    float  size;      //  4: point-sprite diameter in points
    float  pad;       //  4: alignment padding
    // Total: 48 bytes
};

/// Uniforms for the physics compute pass.
struct PhysicsUniforms {
    float2 gravity;        //  8: acceleration (pts/s²); y+ = downward in UIKit
    float  wind;           //  4: x-axis acceleration (pts/s²)
    float  dt;             //  4: frame delta-time (seconds)
    uint   particleCount;  //  4: number of particles in the pool
    float  pad0;           //  4
    float  pad1;           //  4
    float  pad2;           //  4
    // Total: 32 bytes
};

/// Uniforms for the render pass.
struct RenderUniforms {
    float2 viewportSize;  //  8: overlay bounds in UIKit points
    float  contentScale;  //  4: UIScreen.main.scale (for crisp Retina sprites)
    float  pad;           //  4
    // Total: 16 bytes
};

// MARK: - Compute kernel: physics update

/// Updates every live particle's position, velocity, and alpha each frame.
///
/// Dead particles (life ≤ 0) are skipped so the GPU wastes no time on idle pool slots.
/// Alpha fades quadratically — full opacity at birth, rapid fade at end of life — which
/// avoids the harsh pop-out that a linear fade produces.
kernel void updateParticles(
    device MetalParticle*       particles [[ buffer(0) ]],
    constant PhysicsUniforms&   uniforms  [[ buffer(1) ]],
    uint id                               [[ thread_position_in_grid ]])
{
    if (id >= uniforms.particleCount) return;

    device MetalParticle& p = particles[id];
    if (p.life <= 0.0f) return;  // dead — CPU will recycle this slot

    // ── Integrate velocity ───────────────────────────────────────────────────
    p.velocity.x += (uniforms.gravity.x + uniforms.wind) * uniforms.dt;
    p.velocity.y +=  uniforms.gravity.y                  * uniforms.dt;
    p.position   +=  p.velocity * uniforms.dt;

    // ── Age ──────────────────────────────────────────────────────────────────
    p.life = max(0.0f, p.life - uniforms.dt);

    // ── Alpha fade: quadratic ease-out ───────────────────────────────────────
    // t = 1 at birth, 0 at death.  t² gives full opacity early and a quick
    // fade near end-of-life, matching the feel of a CAEmitterCell alphaSpeed.
    float t    = p.life / p.maxLife;
    p.color.w  = t * t;
}

// MARK: - Vertex shader

struct VertexOut {
    float4 clipPos    [[ position  ]];
    float4 color;
    float  pointSize  [[ point_size ]];
};

/// Transforms each particle from UIKit screen-space to Metal clip-space and outputs
/// a point sprite whose size scales down linearly with remaining lifetime.
vertex VertexOut particleVertex(
    uint                      vertexID  [[ vertex_id  ]],
    constant MetalParticle*   particles [[ buffer(0)  ]],
    constant RenderUniforms&  uniforms  [[ buffer(1)  ]])
{
    MetalParticle p = particles[vertexID];
    VertexOut out;

    if (p.life <= 0.0f) {
        // Park dead particles far off-screen; the rasteriser discards them cheaply.
        out.clipPos   = float4(-10.0f, -10.0f, 0.0f, 1.0f);
        out.color     = float4(0.0f);
        out.pointSize = 0.0f;
        return out;
    }

    // UIKit (top-left, y-down, pts) → Metal NDC (centre, y-up, −1..1)
    float nx =  (p.position.x / uniforms.viewportSize.x) * 2.0f - 1.0f;
    float ny = -((p.position.y / uniforms.viewportSize.y) * 2.0f - 1.0f);

    out.clipPos   = float4(nx, ny, 0.0f, 1.0f);
    out.color     = p.color;

    // Shrink the sprite as it ages: 100% at birth → 40% at death.
    float lifeRatio = p.life / p.maxLife;
    out.pointSize   = max(1.0f, p.size * uniforms.contentScale * (0.40f + 0.60f * lifeRatio));
    return out;
}

// MARK: - Fragment shader

/// Renders each point sprite as a soft-edged disc via a signed-distance field.
///
/// `point_coord` is the 2-D coordinate within the point sprite, in [0, 1].
/// Mapping it to [−1, 1] gives the SDF for a unit circle; fragments outside
/// radius 1 are discarded; those inside receive a smooth radial alpha falloff.
fragment float4 particleFragment(
    VertexOut in          [[ stage_in    ]],
    float2    pointCoord  [[ point_coord ]])
{
    // SDF: map sprite UV to [-1, 1], discard outside unit circle.
    float2 uv = pointCoord * 2.0f - 1.0f;
    float  d  = dot(uv, uv);
    if (d > 1.0f) discard_fragment();

    // Smooth alpha: full at centre, zero at edge.
    float softness = 1.0f - smoothstep(0.25f, 1.0f, d);
    return float4(in.color.rgb, in.color.w * softness);
}
