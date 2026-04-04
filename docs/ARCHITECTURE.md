# Y2Notes — System Architecture

## Overview

Y2Notes is a native iPad note-taking application built on three Apple frameworks:
**SwiftUI** (UI layer), **PencilKit** (drawing engine), and **Core Animation** (ink effects).

The app follows a unidirectional data flow pattern where observable stores hold all state,
SwiftUI views react to published changes, and UIKit bridges (`UIViewRepresentable`) connect
PencilKit's `PKCanvasView` to the SwiftUI hierarchy.

---

## Module Map

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Y2NotesApp  (@main)                             │
│                                                                         │
│  Creates 7 @StateObject stores → injects as .environmentObject          │
│                                                                         │
│  ┌─────────────┐ ┌─────────────┐ ┌───────────────┐ ┌───────────────┐  │
│  │  NoteStore   │ │ ThemeStore  │ │DrawingToolStore│ │InkEffectStore │  │
│  │ (persistence)│ │   (theme)   │ │   (pen/tool)   │ │  (ink FX)     │  │
│  └──────┬───────┘ └──────┬──────┘ └──────┬─────────┘ └──────┬────────┘  │
│         │                │               │                   │          │
│  ┌──────┴───────┐ ┌──────┴──────┐ ┌──────┴─────────┐                   │
│  │   PDFStore   │ │AppSettings  │ │GoogleDriveSync  │                   │
│  │  (pdf docs)  │ │   Store     │ │   Engine        │                   │
│  └──────────────┘ └─────────────┘ └─────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       ContentView                                       │
│                                                                         │
│              NavigationSplitView (3-column iPad layout)                  │
│                                                                         │
│  ┌──────────────┐  ┌─────────────────┐  ┌───────────────────────────┐  │
│  │   Sidebar    │  │    Content      │  │         Detail            │  │
│  │              │  │                 │  │                           │  │
│  │  ShelfView   │  │  NoteGridView   │  │    NoteEditorView        │  │
│  │  (notebooks, │  │  (note cards    │  │    (title + toolbar      │  │
│  │   sections)  │  │   sorted/       │  │     + CanvasView)        │  │
│  │              │  │   filtered)     │  │                           │  │
│  └──────────────┘  └─────────────────┘  └───────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Write Path (user draws a stroke)

```
Apple Pencil touch
    │
    ▼
PKCanvasView (UIKit)           ── PencilKit processes pressure/tilt/azimuth
    │
    ├─ canvasViewDidBeginUsingTool()
    │      │
    │      ├─ Coordinator.isDrawing = true
    │      ├─ Capture barrelRollBaseWidth (for fountain pen)
    │      └─ effectEngine.onStrokeBegan(at: viewportPoint)
    │
    ├─ canvasViewDrawingDidChange()
    │      │
    │      ├─ Export: drawing.dataRepresentation() → Data
    │      ├─ Forward: onDrawingChanged(data) → NoteStore.updateDrawing(for:pageIndex:data:)
    │      ├─ Convert: contentPoint → viewportPoint (zoom + scroll)
    │      ├─ Forward: effectEngine.onStrokeUpdated(at: viewportPoint)
    │      ├─ Report: (canUndo, canRedo) to toolbar
    │      └─ Debounce: schedule save in 0.8s
    │
    └─ canvasViewDidEndUsingTool()
           │
           ├─ Coordinator.isDrawing = false
           ├─ effectEngine.onStrokeEnded(at: viewportPoint)
           └─ Trigger debounced save timer
                 │
                 ▼
           NoteStore.save()
                 │
                 ▼
           flushToDisk() → atomic JSON write to Documents/
```

### Read Path (user opens a note)

```
ShelfView: user taps note card
    │
    ▼
selectedNoteID = note.id   (SwiftUI @State binding)
    │
    ▼
NoteEditorView(note: note)
    │
    ├─ Extract note.pages[currentPageIndex] → Data
    ├─ Pass to CanvasView(drawingData:)
    │
    ▼
CanvasView.makeUIView()
    │
    ├─ Create UIView container
    ├─ Create PageBackgroundView (frame-based, sized to pageSize)
    ├─ Create PKCanvasView (Auto Layout fills container)
    │     └─ canvas.drawing = PKDrawing(data: drawingData)
    ├─ Create ShapeOverlayView
    ├─ Create PencilHoverOverlayView
    ├─ Create PencilInteractionCoordinator → attach to canvas
    ├─ Create InkEffectEngine → configure(fx, color) → attach to container
    └─ Apply page shadow (book feel)
```

---

## Coordinate Spaces

Three coordinate spaces are relevant to the canvas:

```
┌────────────────────────────────────────────────────┐
│  Container UIView  (screen/viewport space)          │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  InkEffectEngine.overlayView                  │   │
│  │  (same frame as container, non-interactive)   │   │
│  │  Emitter positions, ripple centers are in     │   │
│  │  THIS coordinate space.                       │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  PKCanvasView  (UIScrollView subclass)        │   │
│  │                                               │   │
│  │  ┌─────────────────────────────────────────┐  │   │
│  │  │  Content space (pageSize)                │  │   │
│  │  │                                          │  │   │
│  │  │  PKDrawing stroke coordinates live here  │  │   │
│  │  │  drawing.strokes[i].path[j].location     │  │   │
│  │  │                                          │  │   │
│  │  │  Size: pageSize (landscape width × A4)   │  │   │
│  │  └─────────────────────────────────────────┘  │   │
│  │                                               │   │
│  │  Zoom: 0.25× to 5×                           │   │
│  │  Scroll: alwaysBounceVertical                 │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  PageBackgroundView  (frame-based)            │   │
│  │  CGAffineTransform tracks zoom + scroll       │   │
│  │  via KVO on contentOffset / zoomScale         │   │
│  └──────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

### Content → Viewport Conversion

When the user is zoomed/scrolled, stroke positions from `PKDrawing` (content space)
must be converted to the overlay's coordinate space (viewport space) for effects:

```
viewportPoint.x = contentPoint.x × zoomScale − contentOffset.x
viewportPoint.y = contentPoint.y × zoomScale − contentOffset.y
```

This conversion happens in `Coordinator.viewportPoint(from:in:)`.

### Page Background Transform

`PageBackgroundView` is positioned with a `CGAffineTransform` that combines:
1. **Scale** by `zoomScale` — ruling lines zoom with drawing strokes
2. **Translate** to compensate for `contentOffset` — background pans with content

```
tx = −contentOffset.x + pageWidth × (zoomScale − 1) / 2
ty = −contentOffset.y + pageHeight × (zoomScale − 1) / 2

transform = scale(z, z) ⊕ translate(tx, ty)
```

---

## Page Size Calculation

```
let screen = UIScreen.main.bounds
let w = max(screen.width, screen.height)     // landscape width
let h = ceil(w × 1.414)                      // A4 aspect ratio (1:√2)
pageSize = CGSize(width: w, height: h)
```

Why `max(screen.width, screen.height)`? This ensures the page fills the screen width
in any orientation. On an iPad Pro 12.9" (1366 pts wide), the page becomes
1366 × 1931 pts — a virtual A4 sheet that can be scrolled vertically.

---

## Persistence Layer

### File Format

All data is stored as JSON arrays in the app's Documents directory:

```
Documents/
├── y2notes_notes.json         [Note]
├── y2notes_notebooks.json     [Notebook]
├── y2notes_sections.json      [NotebookSection]
└── y2notes_study.json         StudyPayload { sets, cards, reviewHistory }
```

### Atomic Write Strategy

1. **Backup**: Copy current file → `file.bak` (one-generation rolling backup)
2. **Write**: `data.write(to: url, options: .atomic)` — writes to temp file, then renames
3. **Recovery**: On corrupt/missing primary, promotes `.bak` to primary on next load

### Save Triggers

| Trigger | Delay | Method |
|---------|-------|--------|
| Stroke completed | 0.8s debounce | `canvasViewDrawingDidChange` → `Timer` → `save()` |
| Autosave timer | 30s | `NoteStore` internal timer (when `isDirty`) |
| App backgrounding | Immediate | `willResignActive` notification → `flushToDisk()` |
| User action | Immediate | Delete, move, duplicate, etc. → `save()` |

---

## Environment Object Graph

```
Y2NotesApp
│
├─ @StateObject noteStore     = NoteStore()
├─ @StateObject themeStore    = ThemeStore()
├─ @StateObject toolStore     = DrawingToolStore()
├─ @StateObject inkStore      = InkEffectStore()
├─ @StateObject pdfStore      = PDFStore()
├─ @StateObject settingsStore = AppSettingsStore()
├─ @StateObject syncEngine    = GoogleDriveSyncEngine()
│
└─ .environmentObject(noteStore)
   .environmentObject(themeStore)
   .environmentObject(toolStore)
   .environmentObject(inkStore)
   .environmentObject(pdfStore)
   .environmentObject(settingsStore)
   .environmentObject(syncEngine)
```

Every view in the hierarchy can `@EnvironmentObject var store: XStore` to access any store.
Stores are `ObservableObject` with `@Published` properties — SwiftUI automatically re-renders
views when published values change.

---

## UIKit ↔ SwiftUI Bridge

`CanvasView` is a `UIViewRepresentable` with a `Coordinator` that:

1. **Creates UIKit views** in `makeUIView(context:)` — runs once per CanvasView identity
2. **Syncs SwiftUI state → UIKit** in `updateUIView(_:context:)` — runs on every SwiftUI re-render
3. **Forwards UIKit events → SwiftUI** via `PKCanvasViewDelegate` callbacks

### Tool Update Safety

Setting `canvas.tool` mid-stroke resets PencilKit's internal pressure/tilt pipeline,
destroying pressure sensitivity. The Coordinator uses a `ToolSnapshot` comparison:

```
if !isDrawing && (snapshot != lastToolSnapshot) {
    canvas.tool = currentTool
    lastToolSnapshot = snapshot
}
```

This ensures tools only update between strokes, never during.

---

## Module Dependency Graph

```
InkModels ◄──── InkFamilyRegistry
    ▲                 ▲
    │                 │
InkEffectStore ───────┘
    ▲
    │
InkEffectEngine
    ▲
    │
NoteEditorView.CanvasView.Coordinator
    ▲
    │
NoteEditorView
    ▲
    │
ContentView ──► ShelfView ──► NoteGridView
    │
    └──► StudySetListView ──► StudySessionView
    │
    └──► PDFViewerView
    │
    └──► SettingsView
```

No circular dependencies. All data flows down from `Y2NotesApp` via environment objects.
