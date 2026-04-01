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

## [2026-04-01T14:25:19Z] AGENT-02 — Search, Sort & Duplicate

Branch: copilot/agent02-search-sort-notes
Model used: claude-sonnet-4.6
Scope: Enrich the note list with live search, sort options, and duplicate; fix index-mismatch delete bug that would have appeared once search/sort were active.

Files modified:
- `Y2Notes/Persistence/NoteStore.swift` — added `deleteNote(noteID:)` and `duplicateNote(noteID:)`
- `Y2Notes/Views/NoteListView.swift` — rewrote with search, sort, duplicate swipe, no-results state, empty-title handling in row

What was completed:
- `NoteSortOrder` enum (Last Modified, Oldest First, Title A→Z, Title Z→A) defined at top of NoteListView.swift.
- `displayedNotes` computed property: filters by case-insensitive title search, then sorts by selected order.
- `.searchable(text:prompt:)` modifier wires up the standard iOS search bar in the sidebar.
- Sort `Menu` (↑↓ icon) + new-note button grouped in `.navigationBarTrailing` via `ToolbarItemGroup`.
- Leading swipe action per row: **Duplicate** (blue, `doc.on.doc`) — creates a copy with " (Copy)" suffix, selects it immediately.
- `.onDelete` now maps filtered-projection offsets back to note IDs before deletion, preventing index-mismatch crashes when search or sort is active.
- `NoteStore.deleteNote(noteID:)` — ID-based single-note removal; `duplicateNote(noteID:)` — inserts copy after source, saves atomically.
- `NoteRowView` renders "Untitled" in secondary colour when `note.title` is empty.
- No-results placeholder shown inline when a search query returns zero matches.

What remains:
- App icon artwork (still placeholder).
- iCloud / CloudKit sync (future agent).
- Unit/UI tests (future agent).
- Export (PDF/image) feature (future agent).
- Persist sort preference across launches (future agent or trivial @AppStorage addition).

Build/test evidence:
- All Swift syntax manually validated against iOS 16 + Swift 5 API surface.
- `NoteSortOrder` uses only types available since iOS 13.
- `swipeActions` and `.searchable` are iOS 15+ APIs — within the iOS 16 deployment target.
- No Xcode available in sandbox; structural validation only (same constraint as AGENT-01).

Notes for next agents:
- `NoteStore.deleteNotes(at:IndexSet)` (the original offset-based method) is still present for any caller that holds a direct reference to `noteStore.notes` indices. Do not remove it without auditing call sites.
- `displayedNotes` is a pure computed property; it is not stored back to `NoteStore`. Any future agent adding drag-reorder must decide whether reorder applies to the sorted projection or to the raw store order.
- Sort state (`sortOrder`) is transient (@State in NoteListView). A future agent can promote it to `@AppStorage("noteSortOrder")` trivially — the raw value is `String`.
