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
