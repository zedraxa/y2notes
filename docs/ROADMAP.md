# Y2Notes — Roadmap & Improvement Plan

## Current State (v1.0)

The app is fully functional with:
- ✅ PencilKit drawing with full Apple Pencil support
- ✅ Multi-page notes with page navigation
- ✅ Ink effects (fire, sparkle, glitch, ripple) with device-tier budgeting
- ✅ Notebooks with sections, reordering, and management
- ✅ PDF import and per-page annotation
- ✅ SM-2 spaced-repetition flashcard study system
- ✅ Google Drive cloud sync with offline queue
- ✅ 6 themes, 7 paper materials, 12 notebook covers
- ✅ Page templates (blank, lined, grid, dotted, Cornell, music staff)
- ✅ Full-text search (title + typed text + handwriting OCR)
- ✅ Codemagic CI/CD → TestFlight distribution

---

## Known Issues

### Effects System

| Issue | Severity | Details |
|-------|----------|---------|
| Glitch layer frame drift | Low | On device rotation, the glitch layer frame may not update until the next `configure()` call. Could add `layoutSubviews` override. |
| Fire particles clip at overlay edge | Low | When drawing near the screen edge, particles that fly beyond the overlay bounds are clipped. Could extend overlay frame with padding. |
| No per-page FX persistence | Medium | If you set Fire on page 1 and switch to page 2, the effect is still active. FX should reset or persist per-page. |

### Multi-Page

| Issue | Severity | Details |
|-------|----------|---------|
| No page reordering | Medium | Pages can only be appended/removed, not reordered. Need drag-to-reorder. |
| No page deletion confirmation | Low | `removePage` is immediate. Should show confirmation alert for pages with content. |
| Canvas recreation on page switch | Medium | Changing pages destroys and recreates the entire `PKCanvasView`. This loses undo history and may flash briefly. A smoother transition (pre-render next page) would be better. |

### General

| Issue | Severity | Details |
|-------|----------|---------|
| No unit tests | High | Zero test coverage. JSON encoding/decoding, multi-page migration, and coordinate conversion should have tests. |
| No UI tests | Medium | Critical flows (create note, draw, switch page, select effect) should have XCUITest coverage. |
| Shallow clone only | Low | Git repo is a shallow clone — full history not available for blame/bisect. |
| No error UI | Medium | Persistence errors are only logged via `assertionFailure`. Users don't see save failures. |

---

## Short-Term Improvements (v1.1)

### 1. Testing Infrastructure

**Priority**: Critical

Add a test target to `Y2Notes.xcodeproj`:

- **Unit tests**:
  - Note encoding/decoding (single-page, multi-page, legacy format migration)
  - InkEffectStore (preset selection, resolvedFX computation, persistence round-trip)
  - NoteStore (updateDrawing, addPage, removePage, duplicateNote)
  - DeviceCapabilityTier detection edge cases
  - Coordinate conversion (viewportPoint calculation at various zoom/scroll states)

- **UI tests**:
  - Create a note and draw a stroke → verify it persists
  - Switch between pages → verify correct drawing loads
  - Select an ink effect → verify engine configures
  - Create a notebook with sections → verify note organization

### 2. Page Transition Animations

**Priority**: Medium

Currently, switching pages destroys the CanvasView and creates a new one (via `.id()` modifier).
This causes a brief flash and loses undo history.

Improvement: Pre-render the next page's `PKDrawing` as an image snapshot, cross-fade to it,
then swap the live canvas underneath. This gives a smooth page-turn feel:

```
                 ┌──────────────────┐
User taps Next → │ Snapshot current │ → Cross-fade → │ Swap canvas data │ → Remove snapshot
                 └──────────────────┘                 └──────────────────┘
```

### 3. Error Reporting UI

**Priority**: Medium

Replace `assertionFailure` in persistence errors with user-visible UI:
- Toast banner: "Unable to save — check storage"
- Retry button in the save state indicator
- Diagnostic info in Settings → Diagnostics

### 4. Undo History Across Pages

**Priority**: Low

PencilKit's undo manager is per-canvas instance. When destroying the canvas on page switch,
all undo history is lost. Options:
- Keep a fixed pool of PKCanvasView instances (e.g., 3: current, prev, next)
- Save/restore undo manager state (not possible with PKCanvasView's internal manager)
- Accept the limitation and document it as expected behavior

---

## Medium-Term Features (v1.2)

### 5. Page Thumbnail Strip

A horizontal strip of page thumbnails below the canvas for quick navigation:

```
┌─────────────────────────────────────────────────────────┐
│                    Canvas (Page 3)                        │
└─────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────┐
│ [◄] │ [P1] │ [P2] │ [■P3] │ [P4] │ [P5] │ [+] │ [►]  │
└──────────────────────────────────────────────────────────┘
```

Each thumbnail is a miniature rendering of the page's PKDrawing. The active page is
highlighted. Tap to jump, long-press to reorder, swipe to delete.

### 6. Page Gestures

| Gesture | Action |
|---------|--------|
| Swipe left (2 fingers) | Next page |
| Swipe right (2 fingers) | Previous page |
| Pinch-to-overview | Show all pages in a grid for reordering |

Two-finger swipes avoid conflict with Apple Pencil drawing (single-finger/pencil).

### 7. Export Improvements

| Format | Status | Description |
|--------|--------|-------------|
| PDF (single page) | Implemented | Via PDFStore |
| PDF (multi-page) | Not yet | Combine all note pages into one PDF |
| Image (PNG) | Not yet | Export current page as image |
| Notebook export | Not yet | Export entire notebook as multi-page PDF |

### 8. New Effects

| Effect | Description | Tier |
|--------|-------------|------|
| **Rainbow** | Hue-cycling stroke trail | Standard+ |
| **Snow** | Falling particle overlay | Standard+ |
| **Lightning** | Brief flash lines at stroke end | Pro+ |
| **Dissolve** | Particles scatter from old strokes | Pro+ |
| **Glow** | Bloom/blur around stroke path | Ultra |

Each new effect would follow the existing pattern:
1. Add a case to `WritingFXType`
2. Implement setup + event hooks in `InkEffectEngine`
3. Add presets to `InkFamilyRegistry`

### 9. Handwriting-to-Text Conversion

Use Apple's Vision framework to convert handwritten notes to typed text:
- On-device OCR running in background after each page edit
- Results stored in `note.ocrText` (field already exists)
- Searchable via `SearchService` (already wired)
- Optional: show converted text as a selectable overlay

---

## Long-Term Vision (v2.0)

### 10. Real-Time Collaboration

Multi-user editing via CloudKit sharing:
- Operational transform or CRDT for concurrent stroke editing
- Presence indicators (colored cursors for each collaborator)
- Share individual notes or entire notebooks

### 11. Template Marketplace

User-created and community templates:
- Template pack protocol already defined (`TemplatePackProviding`)
- Template browser with preview, download, and install
- Revenue share model for premium template packs

### 12. AI Features

| Feature | Description |
|---------|-------------|
| Smart summarization | AI summary of handwritten notes |
| Diagram recognition | Convert hand-drawn diagrams to vector shapes |
| Formula solving | Recognize and solve mathematical expressions |
| Voice-to-sketch | Describe a diagram and AI sketches it |

### 13. Widget & Live Activity

- Lock screen widget showing the latest note thumbnail
- Live Activity during a study session showing progress

### 14. Cross-Platform

- iPhone companion app (view + simple edits, no Pencil)
- macOS Catalyst or native app (trackpad drawing)
- Web viewer (read-only, via exported PDFs or a web renderer)

---

## Technical Debt

| Item | Effort | Description |
|------|--------|-------------|
| Type-checker timeouts | Low | `ManageSectionsSheet` body must be decomposed into subviews to avoid Swift type-checker timeout |
| `onChange` migration | Done | Already migrated to iOS 17 two-parameter form |
| `Color.primary` removal | Done | Already replaced with `Color(uiColor: .label)` |
| `UIGraphicsBeginImageContext` | Done | Already replaced with `UIGraphicsImageRenderer` |
| pbxproj UUID management | Medium | Manual UUID tracking is fragile; consider using `xcodegen` or `tuist` |
| Localization coverage | Medium | 141+ keys in en.lproj but no other languages yet |
| Accessibility audit | Medium | VoiceOver labels exist but not comprehensively tested |
| Memory profiling | Low | Multi-page notes with many pages may hold excessive Data in memory |

---

## Metrics to Track

| Metric | Target | How to Measure |
|--------|--------|----------------|
| App launch → first draw | < 500ms | Instruments Time Profiler |
| Page switch time | < 100ms | OSSignposter interval |
| Effect overlay frame rate | ≥ 60fps | Core Animation instruments |
| Save latency | < 50ms | OSSignposter "DrawingSaved" event |
| Memory (100-page note) | < 100 MB | Instruments Memory Graph |
| JSON file size (typical) | < 5 MB | File system measurement |
