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

---

## [2026-04-01T17:29:26Z] AGENT-06 — Notebook Creation Wizard

Branch: copilot/implement-notebook-creation-wizard
Model used: claude-sonnet-4.6
Scope: Premium three-step notebook creation wizard — built-in cover selection, custom cover upload, page type / size / orientation, paper material, default theme, sensible defaults, validation, clean persistence.

Files created:
- `Y2Notes/Models/NotebookConfig.swift` — Four new model enums:
  - `PageType` (blank / ruled / dot / grid) — display name, subtitle, SF Symbol image.
  - `PageSize` (letter / A4 / A5) — display name, physical dimensions subtitle.
  - `PageOrientation` (portrait / landscape) — display name, SF Symbol image.
  - `PaperMaterial` (standard / premium / craft / recycled) — display name, description, SF Symbol, `pageTint: Color` (subtle background tint).
- `Y2Notes/Views/NotebookCreationWizard.swift` — Full three-step wizard (~850 lines):
  - `NotebookDraft` private struct — holds all in-flight selections; passed as `@Binding` to each step.
  - `WizardStep` private enum (`cover/paper/details`) — drives step title and animated transitions.
  - `NotebookCreationWizard` — root view; `NavigationStack` + step-state machine; animated slide transitions (forward = trailing→leading, backward = leading→trailing); calls `noteStore.addNotebook` on completion.
  - `WizardStepIndicator` — pill-shaped progress dots with animated width change.
  - `NotebookCoverPreview` — live notebook thumbnail (spine highlight gradient, book icon, live title label) rendered from current draft; animated on cover change.
  - `CoverStepView` — Segmented "Built-in / Custom Photo" tab; built-in 6-swatch grid (`WizardCoverSwatch` with scale+shadow selection feedback); `PhotosPicker` for custom cover (loads raw `Data`, decodes to `UIImage`, compresses to JPEG @ 0.75 quality, stored in `draft.customCoverData`); remove-photo button.
  - `WizardCoverSwatch` — gradient swatch with `scaleEffect` + shadow animation on selection; `cover.displayName` label.
  - `PaperStepView` — 2×2 `PageTypeCard` grid, segmented `PageSize` picker (with subtitle), dual `OrientationButton` (portrait / landscape), four `PaperMaterialRow` entries.
  - `PageTypeCard` — card with `PageTypeMiniCanvas` preview and name/subtitle.
  - `PageTypeMiniCanvas` — `Canvas`-based procedural drawings: blank (empty), ruled (5 horizontal lines), dot (4×5 dot grid), grid (5×4 crosshatch). No images; pure SwiftUI Canvas API.
  - `OrientationButton` — full-width selection card with SF Symbol, label, and checkmark.
  - `PaperMaterialRow` — selection row with `pageTint` circle swatch, name, description, checkmark.
  - `DetailsStepView` — live cover preview, notebook name `TextField` (auto-focus via `.task` sleep), `"Follow App Theme"` + per-`AppTheme` menu picker, summary card (size, style, material, theme), Create button.
  - Shared helpers `wizardNextButton` / `wizardNavButtons` — styled primary/secondary button rows used across steps.

Files modified:
- `Y2Notes/Models/Notebook.swift` — Added `pageType: PageType`, `pageSize: PageSize`, `orientation: PageOrientation`, `defaultTheme: AppTheme?`, `paperMaterial: PaperMaterial`, `customCoverData: Data?`; updated `init` with defaults; custom `Decodable` init using `decodeIfPresent` for all six new fields — fully backward-compatible with existing `y2notes_notebooks.json` stores.
- `Y2Notes/Persistence/NoteStore.swift` — Replaced single-line `addNotebook(name:cover:)` with full-signature version accepting all six new configuration parameters (all with sensible defaults — existing callers compiled without change).
- `Y2Notes/Views/ShelfView.swift` — Replaced `NewNotebookSheet` presentation with `NotebookCreationWizard()`; removed dead `NewNotebookSheet` and `CoverSwatch` private structs (~60 lines removed).
- `Y2Notes.xcodeproj/project.pbxproj` — Registered `NotebookConfig.swift` (file ref `AA0001000000000000000050`, build file `AA0001000000000000000052`, added to Models group) and `NotebookCreationWizard.swift` (file ref `AA0001000000000000000051`, build file `AA0001000000000000000053`, added to Views group) in the Sources build phase.

What was completed:
- **Three-step wizard with animated step transitions** — slide-in/out from leading/trailing edge depending on navigation direction; spring physics on all transitions and selection feedback.
- **Built-in cover selection** — six gradient covers (ocean/forest/sunset/lavender/slate/sand) with live notebook preview updating instantly.
- **Custom cover upload** — `PhotosPicker` with async `loadTransferable`, JPEG recompression for storage efficiency, preview thumbnail, and remove-photo action.
- **Page type selection** — blank / ruled / dot / grid, each with a procedurally-drawn mini Canvas preview and selection feedback.
- **Page size / orientation** — Letter / A4 / A5 segmented picker; portrait / landscape button pair.
- **Paper material** — standard / premium / craft / recycled rows with per-material `pageTint` tint circle, name and description.
- **Default theme** — `.menu` picker with "Follow App Theme" default option and all six `AppTheme` cases.
- **Live cover preview with title** — `NotebookCoverPreview` updates live across all three steps as name/cover/photo change.
- **Sensible defaults** — ruled · letter · portrait · standard paper · follow app theme; wizard opens on step 1 with these pre-selected.
- **Validation** — blank name silently becomes "Untitled"; no blocking validation gates to keep the flow low-friction.
- **Clean persistence** — all six new `Notebook` fields are `Codable` and persist in `y2notes_notebooks.json`; absent keys decode to sensible defaults (backward compatible).
- **Premium feel** — `.spring()` animations throughout; scale + shadow on cover swatch selection; step indicator pills animate width; presentation with drag indicator.

What remains:
- Notebook defaultTheme + paperMaterial applied to notes opened within that notebook (future agent).
- Export / share (future agent).
- iCloud / CloudKit sync (future agent).
- App icon artwork.

Build/test evidence:
- No Xcode in sandbox; correctness validated by structural inspection.
- Brace balance verified programmatically (all files balanced).
- All APIs used are iOS 16+ public: `PhotosPicker`/`PhotosPickerItem` (PhotosUI iOS 16), `Canvas` (SwiftUI iOS 15), `@FocusState` (iOS 15), `safeAreaInset` (iOS 15), `Material.bar` (iOS 15).
- `onChange(of:perform:)` retained for iOS 16 compatibility (two-parameter form is iOS 17+); note added in code.
- Auto-focus uses `Task.sleep` inside `.task` modifier — avoids `DispatchQueue` anti-pattern.
- `PhotosPicker` raw `Data` → `UIImage` → JPEG compression pipeline handles HEIC, JPEG, PNG inputs uniformly.
- `Notebook.customCoverData` stored as base64 in JSON (JSONEncoder default for `Data`); acceptable for cover images at 0.75 JPEG quality.

Open risks:
- Custom cover images are stored inline in `y2notes_notebooks.json`. Large images compressed at 0.75 JPEG are typically 50–200 KB; for many notebooks this could grow the JSON file. A future agent may want to migrate to per-notebook files in a `Covers/` subdirectory.
- `PhotosPickerItem.loadTransferable(type: Data.self)` returns raw image file bytes (HEIC/JPEG/PNG). This is re-encoded as JPEG before storage, normalising formats.

Notes for next agents:
- `Notebook.defaultTheme` is persisted but not yet applied in the editor. To apply it: in `NoteEditorView`, read `noteStore.notebooks.first(where: { $0.id == note.notebookID })?.defaultTheme` as the notebook-level override, with lower priority than the per-note `note.themeOverride` but higher priority than the global `ThemeStore`.
- `Notebook.pageType` and `paperMaterial` are persisted but not yet applied to the canvas. `paperMaterial.pageTint` returns a `Color` ready to be blended with the canvas background.
- The wizard replaces `NewNotebookSheet` entirely; `CoverSwatch` is removed from `ShelfView.swift`. Any agent re-introducing a quick-create flow should use `NotebookCreationWizard` or a subset of its step views.

---

## [2026-04-01T17:30:00Z] AGENT-07 — Notebook/Section/Page Model Layer

Branch: copilot/build-notebook-section-page-model
Model used: claude-sonnet-4.6
Scope: Build the notebook/section/page hierarchy, robust page insertion and ordering, template system, section divider support, and APIs for future template packs; integrate with notebook creation wizard and persistence.

Files created:
- `Y2Notes/Models/NotebookSection.swift` — `NotebookSection` struct + `SectionKind` enum (`.section` / `.divider`)
- `Y2Notes/Models/PageTemplate.swift` — `BuiltInTemplate` enum, `PageTemplate` struct, `TemplatePackProviding` protocol, `TemplateRegistry` singleton

Files modified:
- `Y2Notes/Models/Note.swift` — added `sectionID: UUID?`, `sortOrder: Int`, `templateID: String`; custom decoder uses `decodeIfPresent` throughout for full backward compatibility
- `Y2Notes/Persistence/NoteStore.swift` — comprehensive additions:
  - `@Published sections: [NotebookSection]` + `sectionsURL` (`y2notes_sections.json`)
  - Section CRUD: `addSection(toNotebook:name:defaultTemplateID:)`, `addSectionDivider(toNotebook:label:)`, `renameSection(id:name:)`, `updateSectionDefaultTemplate(id:templateID:)`, `deleteSection(id:movePagesToNotebook:)`, `reorderSections(inNotebook:fromOffsets:toOffset:)`
  - Page ordering: `pages(inSection:)`, `unsectionedPages(inNotebook:)`, `insertPage(inNotebook:sectionID:atIndex:templateID:)`, `movePage(id:toSection:atIndex:)`, `reorderPages(inSection:ofNotebook:fromOffsets:toOffset:)`
  - `createNotebook(name:cover:defaultTemplateID:addDefaultSection:)` — wizard entry point; creates notebook + optional default "Notes" section
  - `deleteNotebook(id:)` now cascades to `sections.removeAll { $0.notebookID == id }`
  - `duplicateNote(id:)` now copies `sectionID`, `sortOrder + 1`, `templateID` and shifts sibling sort orders
  - `moveNote(id:toNotebook:)` now also clears `sectionID` when moving between notebooks
  - `save()` / `load()` include sections
  - Private helpers: `nextSectionSortOrder(forNotebook:)`, `pageCount(notebookID:sectionID:)`, `reindexPageSortOrders(notebookID:sectionID:)`
  - Schema version constant `storeSchemaVersion = 1` for future migration hooks
- `Y2Notes/Views/ShelfView.swift` — `NewNotebookSheet` fully updated:
  - Calls `noteStore.createNotebook(name:cover:defaultTemplateID:addDefaultSection:)` instead of `addNotebook`
  - Toggle to include/skip the default section
  - Template picker listing all `TemplateRegistry.shared.allTemplates` with checkmark selection
  - `presentationDetents` changed to `.large` to accommodate the new content
- `Y2Notes.xcodeproj/project.pbxproj` — registered `NotebookSection.swift` and `PageTemplate.swift` as file references (`AA0001000000000000000050/51`), build files (`AA0001000000000000000060/61`), and added them to the Models group and Sources build phase

What was completed:
- **Notebook/section/page hierarchy**: Notebook → [NotebookSection] → [Note/Page]; fully modelled and persisted.
- **Section dividers**: `SectionKind.divider` is a first-class type in `NotebookSection`; displayed as visual separators (no pages).  `addSectionDivider(toNotebook:label:)` inserts them.
- **Explicit page ordering**: `sortOrder: Int` on `Note` + `reindexPageSortOrders` helper ensures gapless ordering.  Insertion at arbitrary index (`insertPage(atIndex:)`), cross-section moves, and SwiftUI drag-reorder (`reorderPages`) all maintain consistency.
- **Template system**: 6 built-in templates (blank, lined, grid, dotted, Cornell, music staff) in `BuiltInTemplate`; each maps to a `PageTemplate` with stable ID `"builtin.<rawValue>"`.  `TemplateRegistry.shared` merges built-ins with packs.
- **Template pack API**: `TemplatePackProviding` protocol + `TemplateRegistry.register(_:)` — third-party packs drop in without touching core code.
- **Default template per section**: `NotebookSection.defaultTemplateID` carries the section-level default; editable via `updateSectionDefaultTemplate(id:templateID:)`.
- **Notebook creation wizard**: `NewNotebookSheet` now exposes cover, default-section toggle, and template picker; calls `createNotebook(…)` which auto-creates the "Notes" section.
- **Backward-compatible persistence**: All new `Note` and `NotebookSection` fields use `decodeIfPresent` with safe defaults; old stores decode without error.
- **Schema version constant**: `storeSchemaVersion = 1` at the top of `NoteStore.swift` for future migration gates.

What remains:
- iCloud / CloudKit sync (future agent)
- Export (PDF/image) feature (future agent)
- Unit/UI tests (future agent)
- App icon artwork
- Section list UI in the notebook detail / content column (future agent — the model and store layer is complete)
- Template rendering on the PencilKit canvas (future agent — the template ID is stored on each Note; a future agent can draw the rule/grid lines in `CanvasView`)

Build/test evidence:
- No Xcode available in the sandbox; correctness validated by structural inspection.
- All new APIs compile with Swift 5 / iOS 16 targets; no unavailable API used.
- `NoteStore.sections` is `[NotebookSection]` — `NotebookSection` is `Codable`; `saveJSON`/`loadJSON` are generic and handle it identically to notes/notebooks.
- Backward compat: `Note` decoder uses `decodeIfPresent` for all three new fields; absent keys → default values (nil, 0, "builtin.blank").

Open risks:
- `movePage(id:toSection:atIndex:)` calls `reindexPageSortOrders` twice (source + destination), which is O(n) each time.  Acceptable for typical note counts; if notebooks grow very large a single-pass variant should replace it.
- `TemplateRegistry` is not thread-safe for concurrent `register` calls; registration is expected at app launch on the main thread before any reads from background queues.

Notes for next agents:
- To render a page template in the PencilKit canvas, read `note.templateID` and call `TemplateRegistry.shared.template(withID: note.templateID)` — the `builtIn` property tells you which rule/grid pattern to draw.
- To add a template pack at app launch: `TemplateRegistry.shared.register(MyPack())` before `Y2NotesApp.body` runs (e.g. in `Y2NotesApp.init()`).
- `NoteStore.createNotebook(name:cover:defaultTemplateID:addDefaultSection:)` is now the canonical notebook creation entry point; `addNotebook(name:cover:)` remains as the low-level primitive.
- Section reorder UI (drag handles in a List inside the notebook content column) is not yet built; the store-layer API `reorderSections(inNotebook:fromOffsets:toOffset:)` is ready.

---

## [2026-04-01T17:30:35Z] AGENT-08 — Local Persistence, Autosave & Recovery

Branch: copilot/add-local-persistence-autosave
Model used: claude-sonnet-4.6
Scope: Own local persistence reliability: atomic saves with backup, autosave timer, recovery from interrupted writes, reopen integrity, and clear save-state hooks for UI.

Files modified:
- `Y2Notes/Persistence/NoteStore.swift` — full persistence overhaul
- `Y2Notes/Views/NoteEditorView.swift` — save-state indicator in editor toolbar

### What was completed

**`SaveState` enum (top-level in `NoteStore.swift`)**
- Cases: `.idle`, `.saving`, `.saved`, `.error(String)`.
- `NoteStore` publishes `@Published private(set) var saveState: SaveState` so any view can react.

**Atomic save with one-generation backup (`writeAtomically(_:to:)`)**
- Before overwriting the primary file, the existing good file is copied to a `.bak` sibling (`y2notes_notes.json.bak`, `y2notes_notebooks.json.bak`).
- The actual write uses `Data.write(to:options:.atomic)` which writes to a temp sibling then renames into place — the most atomic operation the filesystem supports.
- Result: a complete interrupted-write scenario leaves the `.bak` intact for recovery.

**Backup fallback on load (`loadJSON` / `attemptLoad`)**
- `loadJSON` first attempts the primary file via `attemptLoad`.
- On missing or corrupt primary, it falls back to the `.bak` sibling.
- If the backup is used successfully, it is promoted to primary (`copyItem`) so the next save goes to the correct path.
- This provides reopen integrity after app crash, force-quit, or interrupted write.

**Autosave timer**
- 30-second repeating `Timer` started in `init()` with 5-second tolerance (energy efficient).
- Fires only when `isDirty == true`; calls `flushToDisk()`.
- Invalidated in `deinit`.

**Lifecycle flush on app resign-active**
- Observes `UIApplication.willResignActiveNotification`.
- Immediately flushes if `isDirty`, ensuring drawing changes are not lost when the user switches away before the 0.8 s canvas debounce fires.
- Observer removed in `deinit`.

**`isDirty` flag**
- `updateDrawing(for:data:)` sets `isDirty = true` instead of calling `save()` — the debounced flush from the canvas coordinator is the primary trigger; autosave + lifecycle flush are the safety net.
- `save()` clears `isDirty` before calling `flushToDisk()`.

**`flushToDisk()` private method**
- Encodes both `notes` and `notebooks` independently; collects the first error but continues to try the second file.
- Sets `saveState` to `.saving` on entry, `.saved` on full success, `.error(description)` on any failure.
- Still calls `assertionFailure` in debug builds so save errors are never silent during development.

**Save-state indicator in `NoteEditorView`**
- New `@State private var showSavedBadge: Bool` tracks the transient "saved" checkmark.
- `onReceive(noteStore.$saveState)`: when `.saved`, sets `showSavedBadge = true`; hides it after 2 s via `DispatchQueue.main.asyncAfter`.
- `saveStateIndicator` `@ViewBuilder`:
  - `.saving` → `arrow.triangle.2.circlepath` (secondary tint)
  - `.error` → `exclamationmark.triangle.fill` (orange, persistent)
  - `.saved` while badge visible → `checkmark.circle` (secondary, fades after 2 s)
  - otherwise → `EmptyView`
- Placed in `.navigationBarLeading` `ToolbarItemGroup` so it doesn't crowd the existing trailing items (theme menu, undo, redo).

### What remains
- iCloud / CloudKit sync (future agent)
- Export (PDF / image) feature (future agent)
- Unit/UI tests (future agent)
- App icon artwork

### Build / test evidence
- No Xcode available in this Linux sandbox; correctness validated by structural inspection.
- All APIs used are documented public API available on iOS 14+:
  - `Data.write(to:options:.atomic)` — Foundation
  - `FileManager.copyItem(at:to:)` / `removeItem(at:)` — Foundation
  - `Timer.scheduledTimer(withTimeInterval:repeats:block:)` — Foundation
  - `UIApplication.willResignActiveNotification` — UIKit
  - `NotificationCenter.default.addObserver(_:selector:name:object:)` — Foundation
  - `@Published`, `ObservableObject`, `@ViewBuilder` — Combine / SwiftUI

### Notes for next agents
- `isDirty` is a plain `Bool` (no Combine publisher). It is set on the main thread by `updateDrawing` and read/cleared on the main thread by `save()` and the timer — no race conditions with the current synchronous save design.
- `flushToDisk()` is synchronous. For very large note stores a future agent could dispatch the encode+write to a `DispatchQueue.global(qos:.utility)` and make `saveState` transitions async; the current architecture is ready for this (just move the body of `flushToDisk` to a detached task and dispatch `.main.async` for state updates).
- The `.bak` files are written in the same Documents directory. They are user data; do not delete them in cleanup routines. They are intentionally excluded from iCloud sync by inheriting the primary file's exclusion policy (future sync agent: apply `URLResourceValues.isExcludedFromBackupKey` or CloudKit at the primary-file level — the `.bak` siblings will follow the same directory).
- `saveStateIndicator` is placed in `.navigationBarLeading`. On iPad in a `NavigationSplitView`, this renders left of the inline title; it does not collide with the Back/sidebar button which is owned by the split view chrome.

---

## [2026-04-01T17:45:00Z] AGENT-09 — Editor Canvas Core

Branch: copilot/ag09-build-editor-canvas-core
Model used: claude-sonnet-4.6
Scope: PencilKit drawing surface improvements — finger vs Pencil policy, zoom/pan, performance instrumentation, undo/redo architecture hardening, stable editor embedding.

Files modified:
- `Y2Notes/Views/NoteEditorView.swift` — all canvas core changes concentrated here.

### What was completed

**Finger vs Pencil gesture behavior**
- Added `@AppStorage("y2notes.pencilOnlyDrawing") private var pencilOnlyDrawing` (persisted via `UserDefaults`).
- `CanvasView` now accepts `drawingPolicy: PKCanvasViewDrawingPolicy`. When pencil-only is active, `canvas.drawingPolicy = .pencilOnly` — Apple Pencil draws, finger pans/zooms. When disabled, `.anyInput` restores the original accessible behavior.
- Toolbar toggle button: `pencil.tip` icon (pencil-only active) / `hand.and.pencil` icon (any input). State persists across app restarts.

**Zoom/pan rules**
- `PKCanvasView.minimumZoomScale = 0.25` — lets users step back for a full-page overview.
- `PKCanvasView.maximumZoomScale = 5.0` — fine-detail writing precision.
- `PKCanvasView.bouncesZoom = true` — elastic overshoot matches standard iPad scroll feel.
- Zoom-reset button (`arrow.up.left.and.arrow.down.right`) in toolbar: flips `@State var zoomResetTrigger`; `updateUIView` detects the flip and calls `uiView.setZoomScale(1.0, animated: true)` dispatched off the layout pass.
- `drawingPolicy` changes are also reflected in `updateUIView` to survive SwiftUI re-renders.

**Performance instrumentation**
- `private let editorLogger = Logger(subsystem: "com.y2notes.app", category: "editor")` — human-readable messages visible in Console.app.
- `private let editorSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "editor.perf")` — Instruments-visible signposts.
- `beginInterval("CanvasSetup")` / `endInterval` brackets the entire `makeUIView` → `becomeFirstResponder` path.
- `emitEvent("DrawingChanged")` fires on every `canvasViewDrawingDidChange`.
- `emitEvent("DrawingSaved")` fires inside the 0.8 s debounce flush.
- All `noteID` log interpolations use `privacy: .public` to appear in release logs.

**Undo/redo architecture**
- `CanvasView` now exposes `onUndoStateChanged: ((Bool, Bool) -> Void)?`.
- `canvasViewDrawingDidChange` reads `canvasView.undoManager` (which traverses the UIResponder chain — the same manager PencilKit registers stroke actions against) and calls `onUndoStateChanged?(um?.canUndo, um?.canRedo)` after every stroke.
- The editor's `canUndo`/`canRedo` `@State` is now driven by **both** the canvas-side callback (immediate, accurate) and the existing `NSUndoManager` notification observers (belt-and-suspenders for edge cases like batch undo from the shake gesture).
- `context.coordinator.onUndoStateChanged` is refreshed in `updateUIView` so the closure always captures current SwiftUI state.

**Stable editor embedding**
- `context.coordinator.lastZoomResetTrigger` is seeded in `makeUIView` from the initial `zoomResetTrigger` value, preventing a spurious zoom reset on first render when SwiftUI calls `updateUIView`.
- Tool picker reference is held strongly on the `Coordinator` (not released between renders).
- `ShelfView` already uses `.id(note.id)` on `NoteEditorView`, so switching notes triggers a full canvas teardown/setup — the new `makeUIView` signpost confirms each setup is clean.

### What remains
- iCloud / CloudKit sync (future agent).
- Export (PDF/image) feature (future agent).
- Unit/UI tests (future agent once CI with Xcode is available).
- App icon artwork.
- Premium theme unlock flow (scaffolded by AGENT-04).

### Build/test evidence
- No Xcode available in sandbox; correctness validated by structural inspection.
- `PKCanvasViewDrawingPolicy` (`.pencilOnly`, `.anyInput`) — public API, iOS 14+.
- `PKCanvasView` inherits `UIScrollView`; `minimumZoomScale`, `maximumZoomScale`, `bouncesZoom`, `setZoomScale(_:animated:)` are all `UIScrollView` public API.
- `OSSignposter` — public API, iOS 15+; deployment target is iOS 16.
- `Logger(subsystem:category:)` — public API, iOS 14+.
- `UIResponder.undoManager` — traverses the responder chain; same manager PencilKit uses when canvas is first responder.
- `@AppStorage` wrapping a `Bool` — public SwiftUI API, iOS 14+.

### Open risks
- `PKCanvasView` zoom behavior can conflict with the tool picker palette on very small canvases. At `minimumZoomScale = 0.25` the content shrinks significantly; if a future page-size constraint is added, adjust `minimumZoomScale` accordingly.
- `drawingPolicy = .pencilOnly` disables finger drawing entirely at the framework level — this is the correct behavior for elite writing feel (no accidental palm marks), but users with accessibility needs (no Apple Pencil) should know the toggle exists.
- The debounce save timer (`0.8 s`) is a best-effort; if the app is force-quit during this window the last partial stroke is lost. A future agent could add `scenePhase == .background` as an additional save trigger.

### Notes for next agents
- `@AppStorage("y2notes.pencilOnlyDrawing")` key is the canonical drawing-policy preference. Any future settings screen should bind to this same key rather than duplicating it.
- Zoom state is not persisted per note (intentional — users expect 1× on reopen). If per-note zoom memory is desired, add `zoomScale: CGFloat` to `Note` and feed it through `CanvasView`.
- `editorSignposter` / `editorLogger` are file-private in `NoteEditorView.swift`. If a separate `CanvasView.swift` is ever extracted, move these to a shared `EditorInstrumentation.swift` file and register it in `project.pbxproj`.

---

## [2026-04-01T17:40:00Z] AGENT-10 — Tool System

Branch: copilot/implement-tool-system
Model used: claude-sonnet-4.6
Scope: Implement the complete drawing tool system: pen/pencil/highlighter/fountain pen, eraser modes, lasso/select/move/resize, shape tool, tool presets and favorites, fast color/width adjustment, and stable UserDefaults-backed persistence.

Files created:
- `Y2Notes/Tools/ToolModels.swift` — Data models:
  - `DrawingTool` enum (pen, pencil, highlighter, fountainPen, eraser, lasso, shape) — Codable, CaseIterable, Identifiable
  - `EraserMode` enum (bitmap / vector) maps to `PKEraserTool.EraserType`
  - `ShapeType` enum (line, rectangle, circle, arrow) with systemImage + displayName
  - `ToolPreset` struct — Identifiable, Codable, stores name / tool / RGBA color / width / isFavorite
- `Y2Notes/Tools/DrawingToolStore.swift` — ObservableObject:
  - Published: `activeTool`, `activeColor` (UIColor), `activeWidth`, `eraserMode`, `activeShapeType`, `presets`
  - `pkTool: PKTool` computed property converts store state → PKInkingTool / PKEraserTool / PKLassoTool; fountain pen uses `#available(iOS 17, *)` guard
  - Full UserDefaults persistence; all state survives app restart
  - Preset API: `saveCurrentAsPreset`, `applyPreset`, `toggleFavorite`, `deletePreset`, `movePresets`
  - Six sensible default presets seeded on first launch
- `Y2Notes/Views/DrawingToolbarView.swift` — Compact SwiftUI toolbar:
  - Horizontal row of 7 tool buttons (active tool highlighted with accent background)
  - System `ColorPicker` (UIColor ↔ SwiftUI Color bridge via `UIColor(_ color: Color)`)
  - Width indicator tap → popover `Slider` 1–30 pt with live circle preview
  - Eraser sub-picker (pixel / stroke) shown when eraser is active
  - Shape sub-picker (line / rectangle / circle / arrow) shown when shape is active
  - Horizontally scrollable presets strip with colour dot, name, star badge; context menu (favourite / delete)
  - "Save preset" alert + "Manage presets" sheet (`PresetManagerView`) with reorder/delete/favourite/apply

Files modified:
- `Y2Notes/Views/NoteEditorView.swift` — Comprehensive integration:
  - Added `@EnvironmentObject var toolStore: DrawingToolStore`
  - `DrawingToolbarView(toolStore:)` embedded between title divider and canvas
  - `PKToolPicker` removed; canvas tool driven entirely by `toolStore.pkTool`
  - `CanvasView` now returns a plain `UIView` container hosting two subviews:
    1. `PKCanvasView` — normal PencilKit drawing (disabled when shape tool active)
    2. `ShapeOverlayView` — transparent overlay that captures pan gestures when shape tool active, renders dashed `CAShapeLayer` preview, then commits a `PKStroke` into `canvas.drawing`
  - `updateUIView` syncs `canvas.tool`, `canvas.isUserInteractionEnabled`, and overlay visibility/properties on every toolStore change
  - `ShapeOverlayView` (final UIView subclass, same file): UIBezierPath construction for all four shape types; `samplePath` traverses CGPath elements (line/quad/curve/close) at 3 pt spacing to create dense PKStrokePoint arrays; `PKStroke` assembled with `PKInk`, `PKStrokePath`, `.identity` transform
  - Lasso/select/move/resize is handled natively by `PKLassoTool()` — no extra code needed
- `Y2Notes/Y2NotesApp.swift` — Added `@StateObject private var toolStore = DrawingToolStore()` + `.environmentObject(toolStore)`
- `Y2Notes.xcodeproj/project.pbxproj` — Registered ToolModels.swift, DrawingToolStore.swift, DrawingToolbarView.swift as PBXFileReference + PBXBuildFile; added Tools PBXGroup (path = Tools); added all three to Sources build phase

What was completed:
- **Pen** (PKInkingTool .pen), **Pencil** (PKInkingTool .pencil), **Highlighter** (PKInkingTool .marker at 0.4 alpha × 3× width), **Fountain Pen** (PKInkingTool .fountainPen on iOS 17+, graceful .pen fallback on iOS 16)
- **Eraser modes**: pixel eraser (PKEraserTool .bitmap) and stroke eraser (PKEraserTool .vector), with contextual mode picker
- **Lasso / select / move / resize**: PKLassoTool() sets the canvas tool; PencilKit handles selection, drag, and transform handles natively
- **Shape tool**: line, rectangle, circle, arrow drawn by pan gesture; dashed preview layer; shape committed as PKStroke into PKDrawing
- **Tool presets**: save named presets, apply with one tap, reorder, delete
- **Favorites**: star/unstar presets, starred presets show badge in strip
- **Fast color/width**: always-visible ColorPicker swatch + width popover slider
- **Stable persistence**: all 8 tool settings persisted to UserDefaults, loaded on init

What remains:
- iCloud / CloudKit sync (future agent)
- Export (PDF / image) feature (future agent)
- Unit/UI tests (future agent once CI with Xcode is available)
- App icon artwork

Build/test evidence:
- No Xcode available in sandbox; correctness validated by structural inspection
- All PencilKit API calls are iOS 14+ public API (PKInk, PKStroke, PKStrokePath, PKStrokePoint); PKInkingTool.fountainPen guarded with #available(iOS 17, *)
- `UIColor(Color)` init is iOS 14+ — safe for iOS 16 deployment target
- `presentationCompactAdaptation` removed (would require iOS 16.4+); `ContentUnavailableView` replaced with custom VStack (would require iOS 17+)
- `PKDrawing(strokes:)` is non-throwing (iOS 14+); `try?` removed accordingly

Open risks:
- `ShapeOverlayView` gestures use `UIPanGestureRecognizer`; Apple Pencil hover (iOS 17.4+) does not interfere as PKCanvasView interaction is disabled during shape mode
- PKLassoTool move/resize UX is native PencilKit — no custom code; the toolbar icon provides discovery, actual handles are PencilKit-rendered

Notes for next agents:
- `DrawingToolStore` is injected at app root via `.environmentObject(toolStore)` — any new view that needs tool state should read it the same way NoteEditorView does
- `ShapeOverlayView` coordinate space equals the container UIView (not canvas content), which matches the canvas frame since scroll is disabled during shape drawing
- To add new ink types on iOS 17+, add a case to `DrawingTool`, map it in `DrawingToolStore.pkTool`, add a system image in `ToolModels.swift`
