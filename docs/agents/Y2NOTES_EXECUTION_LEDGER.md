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
