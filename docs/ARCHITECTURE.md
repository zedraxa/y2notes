# Y2Notes — System Architecture

## Overview

Y2Notes is a native iPad note-taking application built on three Apple frameworks:
**SwiftUI** (UI layer), **PencilKit** (drawing engine), and **Core Animation** (ink effects).

The app follows a unidirectional data flow pattern where observable stores hold all state,
SwiftUI views react to published changes, and UIKit bridges (`UIViewRepresentable`) connect
PencilKit's `PKCanvasView` to the SwiftUI hierarchy.

The codebase is modularised into four local Swift packages under `Packages/`, with the
main `Y2Notes` app target acting as a thin shell that imports them all.

---

## SPM Package Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                      Y2Notes.app  (main target)                      │
│                                                                      │
│  Thin shell: Y2NotesApp, ContentView, app-specific SwiftUI views     │
│  Imports: Y2Core, Y2Engine, Y2Components, Y2GoogleDrive              │
└──────┬───────────┬───────────────┬──────────────────┬────────────────┘
       │           │               │                  │
       ▼           ▼               ▼                  ▼
┌────────────┐ ┌──────────┐ ┌──────────────┐ ┌───────────────┐
│  Y2Core    │ │ Y2Engine │ │ Y2Components │ │ Y2GoogleDrive │
│            │ │          │ │              │ │               │
│ Models     │ │ Ink FX   │ │ Reusable UI  │ │ Auth, Sync,   │
│ Persistence│ │ Tools    │ │ Components   │ │ Offline Queue │
│ StudySets  │ │ Search   │ │              │ │               │
│ PageTypes  │ │ Colors   │ │              │ │               │
└────────────┘ └────┬─────┘ └──────┬───────┘ └───────┬───────┘
                    │              │                  │
                    └──────────────┴──────────────────┘
                           depends on Y2Core
```

### Package Responsibilities

| Package | Contents | Dependencies |
|---------|----------|--------------|
| **Y2Core** | Data models (Note, Notebook, StudySet, PageTemplate, etc.), persistence types, SM-2 algorithm | None |
| **Y2Engine** | Ink effects engine, tool models, writing config, effects coordinator, color science, trie index | Y2Core |
| **Y2Components** | Reusable SwiftUI view components (future extraction) | Y2Core, Y2Engine |
| **Y2GoogleDrive** | Google Drive auth, sync engine, offline queue | Y2Core |

### NoteEditorView Split

The monolithic `NoteEditorView.swift` (4451 lines) has been split into focused files:

| File | Lines | Contents |
|------|-------|----------|
| `NoteEditorView.swift` | ~500 | Main struct, body chain, canvas section |
| `NoteEditorView+Toolbars.swift` | ~430 | Floating toolbar, selection bars, menus |
| `NoteEditorView+Actions.swift` | ~454 | Action handlers: placement, shapes, selection |
| `NoteEditorView+Export.swift` | ~157 | Export (PDF/image), find bar, text save |
| `NoteEditorView+SubViews.swift` | ~370 | Banners, overlays, title, find bar, page nav |
| `CanvasView.swift` | ~830 | UIViewRepresentable PencilKit bridge |
| `CanvasViewCoordinator.swift` | ~1170 | Coordinator + PencilActionDelegate |
| `ToolSnapshot.swift` | ~30 | PKTool identity snapshot |
| `ShapeOverlayView.swift` | ~190 | Shape gesture overlay |
| `NoteFlashcardSheet.swift` | ~160 | Flashcard creation sheet |
| `PageOverviewGrid.swift` | ~240 | Page thumbnail grid |

---

## State Architecture (ARCH-02)

State management uses a **protocol-oriented service container** pattern.
Core business logic lives in framework-agnostic protocols and implementations
(`Y2Notes/Core/`), while SwiftUI views consume thin adapter wrappers
(`Y2Notes/Adapters/`).

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SwiftUI Views                                    │
│         @EnvironmentObject var noteStore: NoteStore                  │
│         @EnvironmentObject var themeStore: ThemeStore                 │
│                          ...                                         │
└─────────┬───────────────────────────────────────────────────────────┘
          │  (ObservableObject / @Published)
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Y2Notes/Adapters/  (SwiftUI bridge layer)               │
│                                                                      │
│  ObservableNoteStore    ObservableThemeStore   ObservableToolStore    │
│  ObservableInkEffectStore   ObservableSettingsStore                   │
│                                                                      │
│  Each adapter is <50 lines — subscribes to Combine publishers and    │
│  mirrors state as @Published for SwiftUI consumption.                │
└─────────┬───────────────────────────────────────────────────────────┘
          │  (AnyPublisher / CurrentValueSubject)
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│          Y2Notes/Core/  (ZERO SwiftUI imports)                       │
│                                                                      │
│  Protocols/          Services/           Persistence/                 │
│  ├─NoteRepository    ├─CoreThemeService  ├─PersistenceDriver         │
│  ├─ThemeProvider     ├─CoreSettings…     └─JSONFilePersistence…      │
│  ├─ToolStateProvider └─CoreInkEffect…                                │
│  ├─InkEffectProvider                                                 │
│  ├─SettingsProvider  ServiceContainer.swift                          │
│  └─SyncProvider      (owns all service instances)                    │
└─────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Engine / UIKit code uses protocols directly:                        │
│    container.noteRepository.notes                                    │
│    container.toolStateProvider.activeWidth                            │
│    container.inkEffectProvider.resolvedFX                             │
└─────────────────────────────────────────────────────────────────────┘
```

### ServiceContainer

`ServiceContainer` is the single dependency injection container. Created once
in `Y2NotesApp.init()`, it owns every service instance:

| Protocol | Implementation | Persistence |
|----------|---------------|-------------|
| `NoteRepository` | `NoteStore` (existing) | JSON files in `~/Documents/` |
| `ThemeProvider` | `CoreThemeService` | UserDefaults |
| `ToolStateProvider` | `DrawingToolStore` (existing) | UserDefaults |
| `InkEffectProvider` | `CoreInkEffectService` | UserDefaults |
| `SettingsProvider` | `CoreSettingsService` | UserDefaults |
| `SyncProvider` | `GoogleDriveSyncEngine` (existing) | JSON + Google Drive API |

### PersistenceDriver

The `PersistenceDriver` protocol abstracts file-level I/O:

```swift
protocol PersistenceDriver {
    func write(_ data: Data, forKey key: String) throws
    func read(forKey key: String) throws -> Data?
    func delete(forKey key: String) throws
    func exists(forKey key: String) -> Bool
}
```

`JSONFilePersistenceDriver` is the default implementation, mapping each key
to a `<key>.json` file with single-generation `.bak` backup.

---

## Module Map

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Y2NotesApp  (@main)                             │
│                                                                         │
│  Creates ServiceContainer → injects stores as .environmentObject        │
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

## Canvas Rendering Engine (ARCH-01)

The `Y2Notes/Engine/` module provides a UIKit-native canvas controller that
decouples rendering from SwiftUI's view lifecycle.  The engine can be embedded
in SwiftUI via the thin `Y2CanvasHostingView` wrapper or used directly in UIKit.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                  SwiftUI Host                                        │
│  NoteEditorView → Y2CanvasHostingView (UIViewControllerRepresentable)│
│                   (<50 lines — pure bridge)                          │
└──────────┬──────────────────────────────────────────────────────────┘
           │  embeds
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│           Y2CanvasViewController  (pure UIKit, NO SwiftUI)           │
│                                                                      │
│  ┌──────────────────┐  ┌───────────────────────────┐                │
│  │  PKCanvasView    │  │  StrokeRenderingPipeline   │                │
│  │  (input capture) │  │  ├─EffectsCoordinator      │                │
│  │                  │  │  ├─Coordinate mapping       │                │
│  │                  │  │  └─Effect activation        │                │
│  └──────────────────┘  └───────────────────────────┘                │
│                                                                      │
│  ┌──────────────────┐  ┌───────────────────────────┐                │
│  │  EffectOverlay   │  │  PencilInteraction         │                │
│  │  Layer           │  │  Coordinator               │                │
│  │  (CAEmitter/     │  │  (hover, barrel-roll,      │                │
│  │   CAShapeLayer)  │  │   double-tap, squeeze)     │                │
│  └──────────────────┘  └───────────────────────────┘                │
│                                                                      │
│  Output → CanvasDelegate protocol                                    │
│    ├─ canvasDidUpdateDrawing(data:)                                  │
│    ├─ canvasDidChangeUndoState(canUndo:canRedo:)                     │
│    ├─ canvasRequestsPageChange(direction:)                           │
│    └─ canvasDidUpdateShapes/Attachments/Widgets/Stickers/TextObjects │
└─────────────────────────────────────────────────────────────────────┘
```

### Engine Files

| File | Lines | Purpose |
|------|-------|---------|
| `CanvasDelegate.swift` | ~80 | Protocol for canvas → host communication |
| `StrokeRenderingPipeline.swift` | ~160 | Stroke lifecycle dispatch + coordinate mapping |
| `EffectOverlayLayer.swift` | ~120 | Non-interactive overlay view for effect sublayers |
| `Y2CanvasViewController.swift` | ~290 | UIKit canvas controller (owns PKCanvasView) |
| `Y2CanvasHostingView.swift` | ~39 | UIViewControllerRepresentable bridge |

### Key Design Decisions

1. **PKCanvasView as input layer only**: PencilKit captures Apple Pencil input with
   full pressure/tilt fidelity. Custom rendering happens in the effect overlay layer.

2. **CanvasConfiguration value type**: All canvas state is expressed as a `CanvasConfiguration`
   struct. `apply(_:)` diffs old vs new to minimise UIKit mutations.

3. **Delegate-based output**: `CanvasDelegate` replaces closure-based callbacks.
   The host (SwiftUI or UIKit) implements the delegate to receive drawing changes.

4. **Tool-safe updates**: Tools are never set mid-stroke to preserve PencilKit's
   pressure/tilt pipeline.

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
