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

---

## Custom UI Component System

The `Y2Notes/Components/` directory contains a reusable UIKit-native component library
that provides premium, app-specific UI elements with thin SwiftUI hosting wrappers.

### Design Principles

1. **UIKit internally** — all components are `UIView`/`UIViewController` subclasses for
   maximum layout and animation control at 60 fps.
2. **SwiftUI wrapper externally** — every component has a `UIViewRepresentable` or
   `UIViewControllerRepresentable` wrapper for seamless SwiftUI integration.
3. **Theme-aware** — components accept `ThemeColors` / `ThemeDefinition` for styling.
4. **Fully accessible** — VoiceOver labels, Dynamic Type support, and
   `UIAccessibility.isReduceMotionEnabled` checks on all animations.
5. **Self-contained** — no dependency on specific Y2Notes models; components are
   parameterised via configuration structs and callbacks.
6. **Each file < 400 lines** — keeping type-checker happy and code reviewable.

### Component Map

```
Components/
├── Toolbar/
│   ├── Y2FloatingToolbar.swift     — Draggable edge-snapping toolbar (UIKit + pan gesture)
│   ├── Y2ToolPalette.swift         — Radial/grid tool picker (Procreate-style)
│   └── Y2ColorWheel.swift          — HSB colour wheel with brightness slider
├── Navigation/
│   ├── Y2SplitController.swift     — UISplitViewController wrapper (pixel-level column control)
│   └── Y2ShelfPanel.swift          — Drag-to-resize sidebar panel
└── Cards/
    ├── Y2NoteCard.swift            — UIKit note card with thumbnail + haptic long-press
    └── Y2MasonryGrid.swift         — UICollectionView Pinterest-style masonry layout

Transitions/
├── PageFlipTransition.swift        — 3D page-flip with CATransform3D (+ SwiftUI .pageFlip)
└── ZoomOpenTransition.swift        — Zoom-in/out for opening notes (+ SwiftUI .zoomOpen)
```

### Toolbar System

| Component | Internal | Wrapper | Key Feature |
|-----------|----------|---------|-------------|
| `Y2FloatingToolbar` | `UIView` + `UIPanGestureRecognizer` | `Y2FloatingToolbarView` | Drag to any edge, spring snap, collapse/expand |
| `Y2ToolPalette` | `UIView` + radial layout | `Y2ToolPaletteView` | Radial arc (reduce-motion: grid fallback) |
| `Y2ColorWheel` | `UIView` + Core Graphics | `Y2ColorWheelView` | HSB wheel + brightness slider |

### Navigation System

| Component | Internal | Wrapper | Key Feature |
|-----------|----------|---------|-------------|
| `Y2SplitController` | `UISplitViewController` (triple-column) | `Y2SplitControllerView` | Pixel-level column widths, custom collapse |
| `Y2ShelfPanel` | `UIView` + drag handle | `Y2ShelfPanelView` | Fluid drag-to-resize with snap presets |

### Card & Grid System

| Component | Internal | Wrapper | Key Feature |
|-----------|----------|---------|-------------|
| `Y2NoteCard` | `UIView` + gestures | `Y2NoteCardView` | Thumbnail + title + haptic long-press + scale animation |
| `Y2MasonryGrid` | `UICollectionView` + custom layout | `Y2MasonryGridView` | Pinterest masonry, variable heights, cell reuse |

### Transition System

| Transition | UIKit API | SwiftUI API | Reduce-Motion Fallback |
|------------|-----------|-------------|------------------------|
| `PageFlipTransition` | `.flip(from:to:in:direction:)` | `.transition(.pageFlip)` | Cross-dissolve |
| `ZoomOpenTransition` | `.open(from:to:in:)` / `.close(from:to:in:)` | `.transition(.zoomOpen)` | Scale + opacity |

---

## Library Shelf & Page Navigation System

The `Y2Notes/Library/` and `Y2Notes/Engine/{Pages,Tabs}/` directories provide the
GoodNotes-quality home screen, page management panel, and multi-note tab system.

### Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│  Y2LibraryHostingView (UIViewControllerRepresentable)│
│  ┌─────────────────────────────────────────────────┐│
│  │ Y2LibraryViewController (UISplitViewController) ││
│  │ ┌───────────┐  ┌──────────────────────────────┐ ││
│  │ │Y2Sidebar  │  │  UICollectionView (grid)     │ ││
│  │ │  View     │  │  ┌────────────────────────┐  │ ││
│  │ │           │  │  │ Y2NotebookCardCell     │  │ ││
│  │ │ Documents │  │  │ (cover + star + fold)  │  │ ││
│  │ │ Favorites │  │  ├────────────────────────┤  │ ││
│  │ │ Shared    │  │  │ Y2NewButtonCell        │  │ ││
│  │ │ Study     │  │  │ (dashed "+" border)    │  │ ││
│  │ │ Market    │  │  └────────────────────────┘  │ ││
│  │ └───────────┘  └──────────────────────────────┘ ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

### Library Components

| File | Lines | Description |
|------|-------|-------------|
| `Library/Y2LibraryViewController.swift` | ~300 | `UISplitViewController` with sidebar + notebook grid |
| `Library/Y2SidebarView.swift` | ~250 | `UITableView`-based sidebar with selection pill |
| `Library/Y2NotebookCardCell.swift` | ~265 | `UICollectionViewCell` with cover, star, fold corner |
| `Library/Y2NewButtonView.swift` | ~100 | Dashed-border "+" cell |
| `Library/Y2LibraryHostingView.swift` | ~50 | `UIViewControllerRepresentable` bridge |

### Page Panel

```
┌────────────────────────────────────────────────┐
│ Y2PagePanelController (slide-in from left)     │
│ ┌──────────────────────────────────────────┐   │
│ │ ···    "Pages"    ✕                      │   │
│ │ [Grid] [List] [Outline]                  │   │
│ ├──────────────────────────────────────────┤   │
│ │ ┌──────────┐ ┌──────────┐               │   │
│ │ │ Page 1   │ │ Page 2   │  ← Y2PageCell │   │
│ │ │ (thumb)  │ │ (thumb)  │    2-col grid  │   │
│ │ │  📎 1 ▼  │ │ 🔖 2 ▼  │               │   │
│ │ ├──────────┤ ├──────────┤               │   │
│ │ │ Page 3   │ │┄┄┄┄┄┄┄┄┄┄│  ← AddPage  │   │
│ │ │ [BLUE]   │ │   +      │    dashed     │   │
│ │ └──────────┘ └──────────┘               │   │
│ └──────────────────────────────────────────┘   │
└────────────────────────────────────────────────┘
```

| File | Lines | Description |
|------|-------|-------------|
| `Engine/Pages/Y2PagePanelController.swift` | ~310 | Slide-in panel with 2-column page grid |
| `Engine/Pages/Y2PageCell.swift` | ~190 | Page thumbnail cell with blue selection border |
| `Engine/Pages/Y2PageThumbnailRenderer.swift` | ~160 | Async PKDrawing→UIImage + LRU cache (50 entries) |
| `Engine/Pages/Y2PageIndicator.swift` | ~130 | "3 / 4" bottom-left pill (UIKit + SwiftUI wrapper) |

### Tab Bar

```
┌──────────────────────────────────────────────────────────┐
│ 🟢 Untitled (5) ▼  ✕ │ 🔵 Untitled (6) ✕ │  +         │
│ ═══════════════════   │                    │             │
│ (active underline)    │ (inactive)         │ (add tab)   │
└──────────────────────────────────────────────────────────┘
```

| File | Lines | Description |
|------|-------|-------------|
| `Engine/Tabs/Y2NoteTabBar.swift` | ~195 | Horizontal `UICollectionView` tab strip |
| `Engine/Tabs/Y2NoteTabCell.swift` | ~175 | Tab cell: color dot + title + chevron + close |
| `Engine/Tabs/Y2TabStateManager.swift` | ~175 | Tab lifecycle + UserDefaults persistence (max 10) |

### Data Flow

```
NotebookDisplayItem (value type)
    ↓ setNotebooks(_:)
Y2LibraryViewController
    ↓ Y2LibraryDelegate callbacks
Y2LibraryHostingView (SwiftUI)
    ↓ closures
ShelfView / ContentView (existing SwiftUI layer)
    ↓ @EnvironmentObject
NoteStore (persistence)
```

### Design Principles

1. **UIKit internally** — `UICollectionView` for library grid, page panel, and tab bar.
2. **Thin SwiftUI bridge** — `Y2LibraryHostingView` is 50 lines.
3. **Model-agnostic** — Components accept `NotebookDisplayItem` / `PageDisplayItem` / `TabDisplayItem`
   value types, not domain models.
4. **Accessible** — VoiceOver labels, Dynamic Type, context menus on every interactive element.
5. **Async thumbnails** — `Y2PageThumbnailRenderer` renders on background queue with LRU cache.

---

## Content Embedding & Media Pipeline (ARCH-06)

### Overview

Y2Notes supports rich embedded objects placed directly on the canvas alongside ink strokes and typed text. Objects are rendered in a transparent overlay view inserted between `PKCanvasView` and the ink-effects layer.

### Object Z-Order

```
Bottom (furthest back)
├── Page background (ruling lines, paper texture)
├── Embedded objects (sorted by zIndex) ← Y2ObjectOverlayController
│   ├── Images (Y2ImageObjectView)
│   ├── Audio clips (Y2AudioClipView)
│   ├── Stickers (Y2StickerObjectView)
│   └── Links (Y2LinkObjectView)
├── PKCanvasView (drawing strokes — always above objects)
└── EffectOverlayLayer (particles, sparkles — topmost)
Top (nearest to user)
```

### Coordinate Space

All embedded objects use the **same page content coordinate space** as `PKDrawing` strokes. `Y2ObjectOverlayController.applyTransform(zoomScale:contentOffset:)` ensures objects pan and zoom identically to ink.

### Core Object Model (`Y2Notes/Core/EmbeddedObjects/`)

| File | Purpose |
|------|---------|
| `CanvasObject.swift` | `CanvasObject` protocol + `CanvasObjectType` enum (image / scannedDocument / audioClip / sticker / link / textBlock) |
| `ImageObject.swift` | Image metadata + `BorderStyle` enum; pixel data stored externally |
| `AudioClipObject.swift` | Audio clip metadata; `.m4a` file stored in `Documents/AudioClips/` |
| `StickerObject.swift` | Sticker metadata + `StickerTintColor`; built-in stickers rendered on demand |
| `LinkObject.swift` | Link URL + Open Graph metadata + `LinkDisplayStyle` enum |
| `CanvasObjectWrapper.swift` | Type-erased `Codable` container; stored per-page in `Note.embeddedObjectLayers` |

### Engine — Object Overlay (`Y2Notes/Engine/Objects/`)

| File | Purpose |
|------|---------|
| `Y2ObjectOverlayController.swift` | `UIViewController` that hosts all object views; handles gesture routing (finger-only), context menus, z-order management |
| `Y2ObjectSelectionHandler.swift` | Selection state, undo registration, copy/paste via `UIPasteboard` |
| `Views/Y2ImageObjectView.swift` | Lazy full-res loading from `MediaFileManager`; border styles; VoiceOver |
| `Views/Y2AudioClipView.swift` | Live waveform bars; AVAudioPlayer; speed control (0.5×–2×) |
| `Views/Y2StickerObjectView.swift` | Built-in CG rendering or inline PNG; tint support |
| `Views/Y2LinkObjectView.swift` | Chip / Card / Inline styles; opens URL in `SFSafariViewController` |

### Engine — Media Pipeline (`Y2Notes/Engine/Media/`)

| File | Purpose |
|------|---------|
| `Y2ImageInsertionController.swift` | `PHPickerViewController` + camera + file import; JPEG compression (0.8 quality, ≤ 2048 px) |
| `Y2ImageCropController.swift` | In-canvas crop overlay with draggable handles; normalised crop rect |
| `Y2DocumentScannerBridge.swift` | `VNDocumentCameraViewController` wrapper; processes scans into image objects |

### Engine — Audio (`Y2Notes/Engine/Audio/`)

| File | Purpose |
|------|---------|
| `Y2AudioRecorder.swift` | `AVAudioRecorder` wrapper; M4A/AAC 128 kbps; max 30 min; live level metering |
| `Y2AudioPlayerWidget.swift` | Floating record-button + timer + scrolling waveform animation |
| `Y2WaveformGenerator.swift` | Async `AVAudioFile` reader; downsamples to ~200 points; normalised 0…1 |

### Engine — Stickers (`Y2Notes/Engine/Stickers/`)

| File | Purpose |
|------|---------|
| `StickerPackProviding.swift` | Protocol + `StickerRegistry` (singleton); extensible pack system |
| `BuiltInStickerPack.swift` | 19 CG-rendered stickers in 4 categories (Academic, Shapes, Icons, Decorative) |
| `Y2StickerPanelController.swift` | UICollectionView panel with search; tapping inserts sticker at canvas centre |

### Engine — Links (`Y2Notes/Engine/Links/`)

| File | Purpose |
|------|---------|
| `Y2LinkInsertionController.swift` | URL entry form; fetches metadata preview; chip/card/inline style picker |
| `Y2LinkMetadataFetcher.swift` | Headless `WKWebView` + JS extraction for og:title, og:image, og:description, favicon; URLSession fallback |

### Persistence (`Y2Notes/Core/Persistence/`)

| File | Purpose |
|------|---------|
| `PersistenceDriver.swift` | Protocol abstracting key-value storage |
| `JSONFilePersistenceDriver.swift` | Legacy per-file JSON persistence with .bak backups |
| `SQLitePersistenceDriver.swift` | C SQLite persistence via `y2_sqlite.c`; WAL mode, prepared statements |
| `MediaFileManager.swift` | Binary media file manager (images, audio, scans) |
| `RustDataBridge.swift` | Swift bridge to Rust data layer (libY2Data) |

**Storage paths**:
- **Images**: `Documents/NoteMedia/{noteID}/{objectID}.jpg`
- **Audio**: `Documents/AudioClips/{objectID}.m4a`
- **Scans**: `Documents/Scans/{objectID}_scan.jpg`
- **SQLite DB**: `Documents/y2notes.db` (WAL mode)
- JSON stores only metadata (relative paths, frames, settings) — **never binary blobs**
- `deleteMediaForNote(noteID:)` called automatically from `NoteStore.deleteNotes` (cascade delete)
- `cleanup(referencedPaths:)` removes orphaned files not referenced by any live note
- `diskUsage()` returns total managed storage in bytes

### Gesture Separation

Apple Pencil always routes to `PKCanvasView` (drawing). Embedded object gestures use `UIGestureRecognizer` with `allowedTouchTypes = [UITouch.TouchType.direct]` to respond to fingers only.

### Undo Integration

Every object operation (insert, move, resize, delete) registers with `UndoManager` via `Y2ObjectSelectionHandler`. Undo of a delete restores the captured `CanvasObjectWrapper`; undo of a move restores the previous `frame`.

### Document Scanner Integration (ARCH-11)

`Y2CanvasViewController.insertScannedDocument(mode:)` presents the VisionKit document camera via `Y2DocumentScannerBridge`. Scanned pages are processed on a background queue, saved via `MediaFileManager`, and inserted as `.scannedDocument()` embedded objects. The bridge is retained on the controller during the scan session and released on completion/cancellation.

### SQLite Persistence (ARCH-13)

`NoteStore.persistenceDriver` accepts a `PersistenceDriver` (default: `SQLitePersistenceDriver`). When set, `flushToDisk()` and `load()` route through the driver instead of per-file JSON. On first launch with SQLite, existing JSON data is automatically migrated. The C implementation (`y2_sqlite.c`) uses WAL mode and prepared statements for O(1) reads/writes. `ServiceContainer` creates and injects the driver.

### Accessibility (ARCH-14)

All six embedded object views (`Y2ImageObjectView`, `Y2AudioClipView`, `Y2StickerObjectView`, `Y2LinkObjectView`, `Y2ScannedDocObjectView`, `Y2TextBlockView`) declare `isAccessibilityElement`, `accessibilityLabel`, `accessibilityTraits`, and `accessibilityHint`. `Y2LinkObjectView` overrides `accessibilityActivate()` to open the URL. `Y2TextBlockView` posts `UIAccessibility.Notification.announcement` on edit-mode transitions.

`Y2ObjectOverlayController` sets `accessibilityContainerType = .semanticGroup` so VoiceOver discovers objects individually. Each object view receives four `UIAccessibilityCustomAction` entries: Delete, Toggle Lock, Bring to Front, Send to Back — making all object operations reachable without gesture interaction.

### Multi-Window / Stage Manager (ARCH-15)

`UIApplicationSupportsMultipleScenes = true` in `Info.plist`. `WindowGroup` uses `.handlesExternalEvents(matching:)` for multi-window routing. Each window advertises the current note via `.userActivity()` with `NSUserActivity.editNoteActivityType`. On continuation (`.onContinueUserActivity`), the pending note ID is routed through `NavigationStore.navigateToNote(id:)`. `NavigationStore.pendingNoteID` is an observable property that the UI can consume to open the requested note in the active window.
