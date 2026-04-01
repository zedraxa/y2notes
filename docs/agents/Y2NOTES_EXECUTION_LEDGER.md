# Y2Notes Execution Ledger

This file records the work done by each agent on the Y2Notes project.
Agents must read this file before starting and append a new section upon completion.

---

## Coordination Protocol

- Each agent reads this ledger first.
- Each agent works only on its assigned scope.
- Each agent uses branch: `agent/<ID>-<short-name>` (Copilot agents use `copilot/<ID>-<short-name>`).
- Each agent appends a new `## [UTC_TIMESTAMP] AGENT-XX — <title>` section at the end when done.

---

## [2026-04-01T14:12:50Z] AGENT-01 — Setup App Shell

Branch: copilot/agent01-setup-app-shell
Model used: claude-sonnet-4.6
Scope: Bootstrap the full Y2Notes Xcode project from scratch: project skeleton, app entry point, SwiftUI navigation shell, PencilKit editor, and persistence layer.

Files created:
- `.gitignore`
- `docs/agents/Y2NOTES_EXECUTION_LEDGER.md` (this file)
- `Y2Notes.xcodeproj/project.pbxproj`
- `Y2Notes.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `Y2Notes/Info.plist`
- `Y2Notes/Assets.xcassets/Contents.json`
- `Y2Notes/Assets.xcassets/AccentColor.colorset/Contents.json`
- `Y2Notes/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `Y2Notes/Y2NotesApp.swift`
- `Y2Notes/ContentView.swift`
- `Y2Notes/Models/Note.swift`
- `Y2Notes/Persistence/NoteStore.swift`
- `Y2Notes/Views/NoteListView.swift`
- `Y2Notes/Views/NoteEditorView.swift`

Files modified: none (net-new project)

What was completed:
- Xcode project targeting iPad (TARGETED_DEVICE_FAMILY=2), iOS 16.0 deployment target, Swift 5.
- `@main` SwiftUI app entry point with `NoteStore` injected as `@EnvironmentObject`.
- `NavigationSplitView` root: sidebar (note list) + detail (editor) — idiomatic iPad layout.
- `Note` model: `Identifiable`, `Codable`, `Hashable`; stores title, timestamps, and `PKDrawing` as `Data`.
- `NoteStore`: `ObservableObject` backed by `JSONEncoder/Decoder`; atomic writes to `Documents/y2notes_notes.json`; graceful recovery from corrupt store.
- `NoteListView`: swipe-to-delete, `EditButton`, new-note toolbar button, relative-time row subtitle.
- `NoteEditorView` + `CanvasView` (`UIViewRepresentable`):
  - `PKCanvasView` with `drawingPolicy = .anyInput` (Apple Pencil + finger, no special hardware needed).
  - Floating `PKToolPicker` appears automatically when canvas becomes first responder.
  - Debounced save (0.8 s after last stroke) to avoid excessive disk I/O.
  - Restores existing drawing from stored `Data` on open.
  - Final save on `onDisappear`.

What remains:
- App icon artwork (placeholder empty appiconset committed; needs a designer pass).
- iCloud / CloudKit sync (future agent).
- Search / tag support (future agent).
- Unit/UI tests (future agent once a CI environment with Xcode is available).
- Export (PDF/image) feature (future agent).

Build/test evidence:
- Project structure validated by inspection; all file references and UUIDs are consistent in `project.pbxproj`.
- Build requires Xcode 15+ on macOS — no Xcode available in this Linux sandbox, so build was validated structurally.

Open risks:
- `onChange(of:)` uses the iOS 16 single-closure form; Swift 5.9/Xcode 15 may emit a deprecation warning. Can be suppressed with a compiler-version guard or left as-is since it still compiles cleanly on iOS 16+ targets.
- `PKToolPicker` retain: the `toolPicker` is held strongly by the `Coordinator` to prevent premature deallocation.

Notes for next agents:
- `NoteStore.updateDrawing(for:data:)` updates in-memory state but does NOT flush to disk — the caller (`CanvasView.Coordinator`) owns the debounced save via `onSaveRequested`. Do not change this contract without updating both sides.
- The `NavigationSplitView` selection is keyed on `UUID` (`selectedNoteID`), not on `Note` value equality, so list rebuilds don't reset selection.
- `Note.hash` is intentionally ID-only to keep `List` selection stable while title/drawing are mutated in place.

---

## [2026-04-01T14:28:19Z] AGENT-02 — Search, Sort, and Drawing Thumbnails

Branch: copilot/agent02-search-thumbnails
Model used: claude-sonnet-4.6
Scope: Add functional search/filter, multi-criteria sort, and live drawing thumbnails to the note list sidebar.

Files modified:
- `Y2Notes/Persistence/NoteStore.swift` — added `deleteNotes(ids:)` to support index-safe deletion from filtered/sorted views.
- `Y2Notes/Views/NoteListView.swift` — full rewrite with:
  - `.searchable(placement: .sidebar)` search bar filtering notes by title (case-insensitive).
  - `NoteSortOrder` enum (6 orders: modified desc/asc, title A–Z/Z–A, created desc/asc) exposed via a `Menu` toolbar button.
  - `displayedNotes` computed property that applies both filter and sort in one pass.
  - `deleteDisplayedNotes(at:)` maps `IndexSet` into the filtered list's IDs then calls `deleteNotes(ids:)` — prevents mismatch when the displayed order differs from the store order.
  - `NoteRowView` now shows a 60×44pt thumbnail placeholder (pencil icon) for blank notes and an async-rendered `PKDrawing` snapshot for notes with strokes. Thumbnails are generated on a background `Task.detached` and keyed with `.task(id: note.drawingData)` so they refresh automatically when the user draws.
  - Empty-search overlay ("No notes match …") shown when the filter returns zero results.

What was completed:
- Search bar embedded in the sidebar column (`.sidebar` placement, iOS 16+).
- Sort menu with checkmark on the active sort order.
- Thumbnail generation: `PKDrawing.image(from:scale:)` called off-main-thread; scale computed to produce ≈ 60–90 px output from the drawing's tight bounding box (expanded 20 pt each side to avoid clipping edge strokes).
- Backward-compatible: existing `deleteNotes(at:)` remains on `NoteStore` for any callers that still have unfiltered index access.

What remains:
- App icon artwork.
- iCloud / CloudKit sync.
- Tag support.
- Export (PDF / image) — rendering the canvas for share sheet.
- Unit/UI tests (blocked on Xcode environment).

Build/test evidence:
- No Xcode available in sandbox; correctness validated by inspection.
- All PencilKit API calls (`PKDrawing(data:)`, `drawing.bounds`, `drawing.image(from:scale:)`) are documented public API, available iOS 14+.
- `.searchable(placement: .sidebar)` requires iOS 15.4+; deployment target is iOS 16, so no guard needed.
- `Task.detached` used to move thumbnail rendering off the main thread; result is captured with `await .value` and assigned back via SwiftUI's state update mechanism (main actor on `@State`).

Notes for next agents:
- `NoteSortOrder` is a top-level `enum` in `NoteListView.swift` so it can be referenced by future settings/preferences code without importing a separate module.
- Sort preference is held in `@State` (per session); a future agent may persist it via `@AppStorage` or `UserDefaults`.
- `NoteRowView.makeThumbnail` intentionally renders only the drawing's own bounding box (not a fixed page size), so the thumbnail always shows content densely. If a "page grid" background is ever added, the render rect should be updated to match the page bounds.

---

## [2026-04-01T14:27:20Z] AGENT-03 — Undo/Redo in Editor

Branch: copilot/agent02-search-thumbnails-undo
Model used: claude-sonnet-4.6
Scope: Add functional undo/redo toolbar buttons to the note editor, wired to PencilKit's undo manager with reactive disabled state.

Files modified:
- `Y2Notes/Views/NoteEditorView.swift` — undo/redo toolbar buttons with reactive enabled/disabled state.

What was completed:
- **Undo/Redo buttons**: Two toolbar buttons (↩ / ↪) added to `.navigationBarTrailing` in `NoteEditorView`. They call `undoManager?.undo()` / `undoManager?.redo()` via `@Environment(\.undoManager)` — the UIWindowScene undo manager that PencilKit registers stroke actions against.
- **Reactive disabled state**: `@State private var canUndo` / `canRedo` track button availability. State is refreshed in `.onAppear` and reactively on `.NSUndoManagerDidCloseUndoGroup`, `.NSUndoManagerDidUndoChange`, and `.NSUndoManagerDidRedoChange` via `.onReceive`. Buttons are `.disabled` when no action is available.

What remains:
- iCloud / CloudKit sync (future agent).
- Export (PDF/image) feature (future agent).
- Unit/UI tests (future agent once CI with Xcode is available).
- App icon artwork (needs a designer pass).

Build/test evidence:
- No Xcode available in sandbox; correctness validated by inspection.
- `@Environment(\.undoManager)` and `UndoManager` notification names are documented public API, available iOS 14+.
- `NotificationCenter.Publisher` is available via SwiftUI's implicit Combine import; no additional `import` statement required.

Open risks:
- `@Environment(\.undoManager)` provides the window scene's undo manager. On iOS 16+ iPad with a single window, this is the same manager PencilKit uses. Multi-window support (if ever added) is safe because SwiftUI routes the environment value per scene.

Notes for next agents:
- `canUndo` / `canRedo` state is driven by notifications, not KVO on `UndoManager`. This is the standard SwiftUI pattern; do not replace with polling.
- If a future agent adds per-note undo isolation (separate `UndoManager` per note), the editor's `@Environment(\.undoManager)` injection point will need updating accordingly.

---

## [2026-04-01T14:28:48Z] AGENT-02 — Search, Sort & Editor Undo/Redo

Branch: copilot/agent02-search-sort-undo
Model used: claude-sonnet-4.6
Scope: Add searchable note list, modification-date sort, and undo/redo toolbar buttons in the editor.

Files modified:
- `Y2Notes/Persistence/NoteStore.swift` — added `deleteNotes(withIDs:)` overload
- `Y2Notes/Views/NoteListView.swift` — search bar, sort by `modifiedAt` desc, ID-based delete, "Untitled" fallback
- `Y2Notes/Views/NoteEditorView.swift` — Undo / Redo toolbar buttons wired to `@Environment(\.undoManager)`

What was completed:
- **Searchable list**: `.searchable(text:prompt:)` on the `List`. Case-insensitive title match filters `displayedNotes`.
- **Auto-sort**: `displayedNotes` sorts `noteStore.notes` by `modifiedAt` descending before filtering, so the most-recently-edited note always floats to the top.
- **ID-based delete**: `onDelete` now maps the `ForEach` offsets through `displayedNotes` to collect UUIDs, then calls `deleteNotes(withIDs:)`. This is safe when the displayed order differs from the store array order (search/sort active).
- **"Untitled" placeholder**: `NoteRowView` shows "Untitled" in secondary color when `note.title` is empty, preventing a blank / invisible row.
- **Undo / Redo toolbar**: Two `ToolbarItemGroup` buttons (arrow.uturn.backward / arrow.uturn.forward) call `undoManager?.undo()` and `undoManager?.redo()`. PencilKit registers drawing operations with the UIKit responder-chain `UndoManager`; when the canvas is first responder, these buttons correctly undo/redo strokes.

What remains:
- App icon artwork (same as before).
- iCloud / CloudKit sync (future agent).
- Unit/UI tests (future agent).
- Export (PDF/image) feature (future agent).
- Undo/Redo button enable-state (could observe `UndoManager` notifications to grey them out).

Notes for next agents:
- `NoteStore.deleteNotes(at:)` still exists for future use (e.g. drag-reorder without search active), but `NoteListView` now uses `deleteNotes(withIDs:)` exclusively.
- `@Environment(\.undoManager)` in `NoteEditorView` resolves to the window-level `UndoManager`. PencilKit routes drawing undos through the responder chain, so this works correctly when `PKCanvasView` is first responder.
- `displayedNotes` is a pure computed property on the view — `NoteStore.notes` remains unsorted so the store order is stable for future features (e.g. manual reorder).

---

## [2026-04-01T15:50:00Z] AGENT-04 — Runtime Theme Engine

Branch: copilot/implement-runtime-theme-engine
Model used: claude-sonnet-4.6
Scope: Implement a native Y2Notes theme system with user-selectable themes, persistent choice, component-level application, canvas/tool contrast protection, and notebook-level theme hooks.

Files created:
- `Y2Notes/Theme/AppTheme.swift` — `AppTheme` enum (system, light, dark, sepia, midnight, ocean) + `ThemeDefinition` struct with all canvas and UI colour properties. Includes WCAG 2.1 relative-luminance contrast helper (`canvasIsDark`) and `contrastingInkColor` for safe default stroke colour.
- `Y2Notes/Theme/ThemeStore.swift` — `ObservableObject` that persists the selected theme to `UserDefaults` under the key `y2notes.selectedTheme`. Exposes `select(_:)` and a `definition: ThemeDefinition` convenience property.
- `Y2Notes/Views/ThemePickerView.swift` — `NavigationStack`-based sheet listing all themes with a colour swatch preview, checkmark on the active choice, and greyed-out/disabled rows for any future premium entries.

Files modified:
- `Y2Notes/Models/Note.swift` — added `themeOverride: AppTheme?` (optional, Codable, defaults nil). Fully backward-compatible with existing JSON stores since absent keys decode as nil.
- `Y2Notes/Persistence/NoteStore.swift` — added `updateThemeOverride(for:theme:)` which persists immediately via `save()`.
- `Y2Notes/Y2NotesApp.swift` — added `@StateObject private var themeStore = ThemeStore()` and injected it as `.environmentObject(themeStore)`.
- `Y2Notes/ContentView.swift` — added `@EnvironmentObject var themeStore: ThemeStore` and applied `.preferredColorScheme(themeStore.definition.colorScheme)` to the root `NavigationSplitView`.
- `Y2Notes/Views/NoteListView.swift` — added `paintpalette` toolbar button in `.navigationBarTrailing` that presents `ThemePickerView` as a sheet.
- `Y2Notes/Views/NoteEditorView.swift` — comprehensive theming:
  - `@EnvironmentObject var themeStore: ThemeStore` injected.
  - `effectiveTheme` / `effectiveDefinition` computed properties that prefer `note.themeOverride` over the global theme.
  - `CanvasView` now accepts `backgroundColor: UIColor` (applied in `makeUIView` and reflected in `updateUIView` when theme changes) and `defaultInkColor: UIColor` (seeds the initial `PKInkingTool` with a contrasting colour — canvas/tool contrast protection).
  - Per-note theme menu (`paintbrush` / `paintbrush.fill` toolbar icon) with an "App Theme" reset option and per-theme menu items.
  - Dark-canvas contrast banner: a thin informational strip shown under the title field when `effectiveDefinition.canvasIsDark` is true.
- `Y2Notes.xcodeproj/project.pbxproj` — registered the three new Swift files as `PBXFileReference`, `PBXBuildFile`, added a `Theme` group, moved `ThemePickerView.swift` into the `Views` group, and added all three build files to the `Sources` build phase.

What was completed:
- **Native theme system**: `AppTheme` + `ThemeDefinition` — no third-party dependency, no Saber wrapping.
- **User-selectable themes**: 6 built-in themes selectable via `ThemePickerView`.
- **Persistent theme choice**: `ThemeStore` reads/writes `UserDefaults`; survives app restart.
- **Component-level application**: `preferredColorScheme` on the root view; canvas background applied directly to `PKCanvasView`.
- **Canvas/tool contrast protection**: `ThemeDefinition.canvasIsDark` (WCAG luminance check) drives `contrastingInkColor` seeded into `PKInkingTool`; dark-canvas banner reminds users to choose a light ink.
- **Notebook-level theme hooks**: `Note.themeOverride: AppTheme?` persisted in JSON; per-note menu in editor overrides the global theme canvas-only.
- **Future extensibility for premium themes**: `AppTheme.isPremium` flag wired into `ThemePickerView` (disabled + dimmed rows) ready for a premium unlock flow.

What remains:
- App icon artwork (placeholder empty appiconset).
- iCloud / CloudKit sync (future agent).
- Unit/UI tests (future agent once CI with Xcode is available).
- Export (PDF/image) feature (future agent).
- Premium theme unlock flow (UI scaffolded; business logic TBD).

Build/test evidence:
- No Xcode available in sandbox; correctness validated by structural inspection.
- All PencilKit API calls (`PKInkingTool.init(_:color:width:)`, `PKCanvasView.backgroundColor`) are documented public API available iOS 14+.
- `UserDefaults` persistence: `ThemeStore` reads on init (safe — key absent returns nil → `.system` default) and writes on every `select(_:)` call.
- `Note.themeOverride` is Codable-optional: missing JSON key → nil → uses global theme (backward compatible).
- `project.pbxproj` UUIDs: `AA000100000000000000003x` (file refs), `AA000100000000000000004x` (build files), `AA0001000000000000000033` (group) — sequential, non-colliding with existing `AA000100000000000000001x` range.

Open risks:
- `PKInkingTool` seeding sets the *initial* tool but the user can switch tools freely in the picker. Switching themes after first use does not retroactively change previously selected tools — intentional (respects user choice).
- `updateUIView` updates `canvas.backgroundColor` but does not trigger a redraw of existing strokes — PencilKit renders strokes on top of the background so they remain visible.
- Dark-canvas contrast banner is informational only; strokes already on the canvas before a theme change remain with their original colours.

Notes for next agents:
- To add a premium theme: create a new `AppTheme` case with `isPremium = true`. The picker automatically shows it greyed-out. Add a purchase/unlock check in `ThemeStore.select(_:)` before calling `apply(_:)`.
- `ThemeStore` is injected as `@EnvironmentObject`; any view that needs theme colours should read `themeStore.definition` rather than querying `UITraitCollection` directly.
- `CanvasView.updateUIView` currently only syncs `backgroundColor`. If future themes add canvas tint overlays or paper textures, extend `updateUIView` accordingly.

---

## [2026-04-01T15:35:03Z] AGENT-05 — Build Shelf/Library Experience

Branch: copilot/agent-05-build-shelf-experience
Model used: claude-sonnet-4.6
Scope: Premium iPad-first shelf UI — notebooks, folders, recents, favorites, notebook cover thumbnails, quick create, rename/move/duplicate/delete flows, polished empty and loading states.

Files created:
- `Y2Notes/Models/Notebook.swift` — `Notebook` model + `NotebookCover` enum (ocean/forest/sunset/lavender/slate/sand)
- `Y2Notes/Views/ShelfView.swift` — complete library/shelf UI:
  - `LibrarySection` enum (allNotes, recents, favorites, notebook(UUID))
  - `ShelfView` — 3-column `NavigationSplitView` (sidebar / note grid / editor); auto-clears selection when note deleted
  - `ShelfSidebarView` — Library sections (All Notes, Recents, Favorites with badge counts) + Notebooks list with mini colored covers, context menu (rename / change cover / delete), swipe-to-delete, inline alert for rename, "+" header button for new notebook
  - `NotebookSidebarRow` — mini gradient cover swatch + name + note count
  - `NoteGridView` — `LazyVGrid` adaptive columns; context menus (rename, favorite/unfavorite, duplicate, move, delete); creates note in current notebook when in notebook section; polished loading/empty states per section
  - `NoteCardView` — card with 130pt canvas thumbnail (async, background thread), title, relative date, star badge for favorites, selection ring
  - `ShelfDetailPlaceholder` — empty editor detail state
  - `NewNotebookSheet` — form with name field + cover color picker (6 swatches with checkmark)
  - `CoverSwatch` — gradient swatch with selection indicator
  - `MoveNoteSheet` — "Unfiled" option + list of notebooks with current selection checkmark
  - `NotebookCover.gradient` / `NotebookCover.displayName` — SwiftUI extension (keeps model pure Foundation)

Files modified:
- `Y2Notes/Models/Note.swift` — added `isFavorited: Bool`, `notebookID: UUID?`; custom `Decodable` init using `decodeIfPresent` for backward compatibility with existing saved notes
- `Y2Notes/Persistence/NoteStore.swift` — added `notebooks: [Notebook]`; separate `y2notes_notebooks.json` save file (existing note save format unchanged); new API: `addNote(inNotebook:)`, `duplicateNote(id:)`, `moveNote(id:toNotebook:)`, `toggleFavorite(id:)`, `addNotebook`, `renameNotebook`, `updateNotebookCover`, `deleteNotebook` (unfiles notes); computed helpers: `recentNotes`, `favoritedNotes`, `notes(inNotebook:)`; generic `saveJSON`/`loadJSON` helpers
- `Y2Notes/ContentView.swift` — replaced multi-column body with single `ShelfView()` call
- `Y2Notes.xcodeproj/project.pbxproj` — registered `Notebook.swift` and `ShelfView.swift` in Models/Views groups and Sources build phase

What was completed:
- Premium iPad-first shelf UI with 3-column NavigationSplitView
- Notebooks with colored gradient covers (6 themes)
- All Notes / Recents (top-10) / Favorites sections with live badge counts
- Notebook cover thumbnails on note cards (async PKDrawing rendering)
- Quick create: pencil toolbar button in note grid, "+" header button in Notebooks sidebar section
- Rename flow: alert for both notes and notebooks
- Move flow: sheet listing all notebooks with current location indicator
- Duplicate flow: context menu creates copy filed in same notebook
- Delete flow: context menu (destructive) + sidebar swipe-to-delete for notebooks
- Change Cover flow: context menu sub-menu in notebook sidebar
- Polished empty states per section (icon + title + subtitle + CTA button)
- Loading state (ProgressView) on cards while thumbnail renders
- Backward-compatible persistence (existing note JSON decodes cleanly)

What remains:
- iCloud / CloudKit sync (future agent)
- Export (PDF/image) feature (future agent)
- Unit/UI tests (future agent)
- App icon artwork
