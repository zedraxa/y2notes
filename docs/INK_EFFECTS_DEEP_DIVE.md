# Ink Effects Engine — Deep Dive

## Overview

The ink effects system renders real-time visual overlays (fire, sparkle, glitch, ripple)
on top of the PencilKit canvas while the user draws. It is architected as a **completely
non-invasive layer** — effects never modify PKCanvasView stroke data; they are purely
visual decorations that live in a separate UIView overlay.

When no effect is active (`activeFX == .none`), the overlay is removed from the view
hierarchy entirely — **zero runtime cost** on the base note-taking path.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Container UIView                                             │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  InkEffectEngine.overlayView                            │   │
│  │  ├─ CAEmitterLayer (fire / sparkle particles)           │   │
│  │  ├─ CALayer (glitch — horizontal shift + tint pulse)    │   │
│  │  └─ CAShapeLayer × 3 (ripple rings — created per-stroke)│   │
│  │                                                          │   │
│  │  isUserInteractionEnabled = false (pass-through touch)   │   │
│  │  backgroundColor = .clear                                │   │
│  │  isOpaque = false                                        │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  PKCanvasView  (receives all touch events)              │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  PageBackgroundView  (ruling lines)                     │   │
│  └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

The overlay sits **above** the canvas in the z-order but has `isUserInteractionEnabled = false`,
so all touch events pass through to the PKCanvasView beneath.

---

---

## Effect Types

### 🔥 Fire (`.fire`)

A `CAEmitterLayer` with point emission that trails the Apple Pencil nib.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Birth rate | 48 particles/sec | Fixed rate for consistent performance |
| Lifetime | 0.45 ± 0.25 s | Short-lived for responsiveness |
| Velocity | 70 ± 35 pts/s | Upward emission (`−π/2`) |
| Emission range | π/5 | Narrow cone |
| Scale | 0.05 ± 0.02, decays at −0.015/s | Particles shrink as they age |
| Alpha | Decays at −2.2/s | Rapid fade-out |
| Render mode | Additive | Particles glow on top of strokes |
| Color | User color with fire-orange bias: R+30%, G+10%, B−20% | Preserves hue intent |
| Content | 12px white circle | CGImage rendered with UIGraphicsImageRenderer |

**Lifecycle**:
- `onStrokeBegan`: `birthRate = 1`, show emitter, set position
- `onStrokeUpdated`: update emitter position
- `onStrokeEnded`: `birthRate = 0` (particles die naturally)

### ✨ Sparkle (`.sparkle`)

A lighter CAEmitterLayer with omnidirectional emission.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Birth rate | 9 particles/sec | Lighter than fire |
| Lifetime | 0.35 ± 0.20 s | Brief twinkle |
| Velocity | 45 ± 40 pts/s | Omnidirectional (`2π` range) |
| Scale | 0.025 ± 0.012, decays at −0.020/s | Tiny sparks |
| Alpha | Decays at −2.8/s | Very rapid fade |
| Color | User color at 95% alpha | Slight RGB variance (0.12 range) |
| Content | 8px white circle | Smaller than fire particles |

**Lifecycle**: Same as fire — the emitter is shared between fire and sparkle modes.

---

## Coordinate Conversion

### The Problem

The `InkEffectEngine.overlayView` lives in the container's **viewport** coordinate space.
But stroke positions from `PKDrawing.strokes.last.path.last.location` are in the canvas's
**content** coordinate space. When the user is zoomed or scrolled, these don't match.

### The Solution

```
viewportPoint.x = contentPoint.x × zoomScale − contentOffset.x
viewportPoint.y = contentPoint.y × zoomScale − contentOffset.y
```

This conversion is performed in `Coordinator.viewportPoint(from:in:)` before passing
points to the effect engine.

### Stroke-Begin Edge Case

At stroke start (`canvasViewDidBeginUsingTool`), the new stroke hasn't been committed to
`PKDrawing.strokes` yet — `strokes.last` still points to the *previous* stroke. Instead of
using a stale position, the engine receives the viewport center as an initial point. The very
next `onStrokeUpdated` callback (triggered by `canvasViewDrawingDidChange`) snaps the emitter
to the real nib position.

---

## Configuration Flow

```
InkEffectPickerView
    │  user selects preset
    ▼
InkEffectStore.selectPreset(preset)
    │  @Published activePreset changes
    ▼
SwiftUI re-renders NoteEditorView
    │  extracts inkStore.resolvedFX + inkStore.activePreset?.uiColor
    ▼
CanvasView(activeFX: resolvedFX, fxColor: color)
    │  SwiftUI calls updateUIView
    ▼
Coordinator: engine.configure(fx: activeFX, color: fxColor)
    │  InkEffectEngine compares to current state
    │
    ├─ Same FX? → only recolour emitter cells (no setup)
    ├─ Different FX? → stopCurrentFX() → setup new FX
    └─ .none? → hide overlay entirely
```

### resolvedFX Logic

```
if !fxEnabled            → .none   (master toggle off)
if activePreset == nil   → .none   (no preset selected)
else                     → preset.writingFX
```

---

## Performance Guarantees

1. **Zero-cost when idle**: When `activeFX == .none`, the overlay is `isHidden = true` and
   removed from the render pipeline. No layers are allocated, no timers run.

2. **Fixed particle budget**: Particle counts are fixed at 48 for fire and 9 for sparkle,
   ensuring consistent performance across all devices.

3. **Emitter cell reuse**: The `CAEmitterLayer` is shared between fire and sparkle modes.
   Switching between them clears cells and reconfigures — no layer destruction/creation.

4. **Animation removal**: `deactivate()` calls `stopCurrentFX()` which removes all
   animations and clears all emitter cells.

5. **Main-thread only**: The entire engine assumes main-thread execution. No locks or
   dispatch queues — Core Animation manages its own thread-safe display link.

---

## Preset Registry

Built-in presets across multiple ink families:

| Family | Presets | Default FX | Traits |
|--------|---------|------------|--------|
| **Standard** | Classic Black, Fine Pencil, Fountain | None | Standard / Dry / Wet |
| **Metallic** | Gold, Silver, Copper | Sparkle | Metallic sheen |
| **Neon** | Green, Pink, Blue | Sparkle | Standard |
| **Watercolour** | Aqua Wash, Rose Blush, Moss Green | None | Watercolour |
| **Fire** | Ember, Inferno, Blue Flame | Fire | Standard |
| **Phantom** | Ghost Ink, UV Reveal | None / Sparkle | Dry (near-invisible) |

Users can also create unlimited custom presets stored in `UserDefaults`.

---

## Persistence

| Key | Storage | Content |
|-----|---------|---------|
| `y2notes.ink.fxEnabled` | UserDefaults (Bool) | Master FX toggle |
| `y2notes.ink.userPresets` | UserDefaults (JSON Data) | Array of user-created InkPreset |
| `y2notes.ink.activePresetID` | UserDefaults (String) | UUID of currently active preset |

Active preset is restored from the combined registry (built-in + user presets) on app launch.
If the stored UUID doesn't match any known preset, no preset is selected (base tool mode).
