# Y2Notes — Roadmap & Improvement Plan

## Current State (v1.0)

The app is fully functional with:
- ✅ PencilKit drawing with full Apple Pencil support
- ✅ Multi-page notes with page navigation
- ✅ Ink effects (fire, sparkle, glitch, ripple, rainbow, snow, lightning, dissolve, glow) with device-tier budgeting
- ✅ **New interactive inks**: Sheen (holographic shimmer), Shadow (dark smoke), Blood (crimson drips)
- ✅ Notebooks with sections, reordering, and management
- ✅ PDF import and per-page annotation
- ✅ Document import (DOCX, EPUB, PPTX, Keynote, ODP) with Quick Look viewer
- ✅ **Multi-page PDF export + PNG image export** with background, ruling and drawing composite
- ✅ **On-device handwriting OCR** via Vision framework — auto-runs after drawing, feeds search
- ✅ SM-2 spaced-repetition flashcard study system
- ✅ Google Drive cloud sync with offline queue
- ✅ 6 themes, 12 notebook covers
- ✅ Page templates (blank, lined, grid, dotted, Cornell, music staff)
- ✅ **Per-page ruling**: each page in a note can individually use blank/lined/grid/dotted
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

**Status**: ✅ Implemented

Page switches now use a cross-fade transition via SwiftUI's `.transition(.opacity)` on the
`CanvasView` combined with a `.animation(.easeInOut(duration: 0.22), value: safePageIndex)`
modifier. When the user swipes to a new page, the old canvas fades out and the new canvas
fades in simultaneously over 220 ms. This eliminates the jarring flash that occurred before
when the canvas was simply recreated without any transition.

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

**Status**: ✅ Implemented

| Gesture | Action | Status |
|---------|--------|--------|
| Swipe left (2 fingers) | Next page | ✅ Done |
| Swipe right (2 fingers) | Previous page | ✅ Done |
| Pinch-to-overview | Show all pages in a grid for selection | ✅ Done |

Two-finger swipes avoid conflict with Apple Pencil drawing (single-finger/pencil).
The pinch-to-overview uses a pinch-in gesture (scale < 0.7) to open a full-screen
page grid with thumbnails. The grid is also accessible via the page indicator button
in the navigation bar.

### 7. Export Improvements

| Format | Status | Description |
|--------|--------|-------------|
| PDF (single page) | ✅ Done | Via PDFStore for annotated PDFs; via NoteExporter for freehand notes |
| PDF (multi-page) | ✅ Done | `NoteExporter.exportAsPDF` combines all note pages into one PDF |
| Image (PNG) | ✅ Done | `NoteExporter.exportPageAsImage` exports current page as UIImage |
| Notebook export | Not yet | Export entire notebook (all its notes) as one large PDF |

### 8. New Effects

**Status**: ✅ Implemented (all five, plus three new interactive ink families)

| Effect | Description | Tier | Status |
|--------|-------------|------|--------|
| **Rainbow** | Hue-cycling stroke trail | Standard+ | ✅ Done |
| **Snow** | Falling particle overlay | Standard+ | ✅ Done |
| **Lightning** | Brief flash lines at stroke end | Pro+ | ✅ Done |
| **Dissolve** | Particles scatter from old strokes | Pro+ | ✅ Done |
| **Glow** | Bloom/blur around stroke path | Ultra | ✅ Done |
| **Sheen** | Iridescent holographic shimmer (hue cycles while you write) | Standard+ | ✅ Done |
| **Shadow** | Dark cinematic smoke trailing behind strokes | Standard+ | ✅ Done |
| **Blood** | Viscous crimson drips that fall from the nib | Pro+ | ✅ Done |

### 9. Handwriting-to-Text Conversion

**Status**: ✅ Implemented

Use Apple's Vision framework to convert handwritten notes to typed text:
- On-device OCR running in background 4 seconds after each page edit (debounced)
- Results stored in `note.ocrText` via `NoteStore.scheduleOCR(for:)` → `OCREngine`
- Searchable via `SearchService` (already wired — `SearchMatchType.handwritingOCR`)
- Find bar in the editor now searches OCR text for drawing-only notes

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
