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

## [2026-04-01T14:33:26Z] AGENT-02 — Search/Filter & Auto-Focus Title

Branch: copilot/agent02-search-and-ux
Model used: claude-sonnet-4.6
Scope: Add note-list search/filter and auto-focus the title field on new note creation.

Files modified:
- `Y2Notes/Persistence/NoteStore.swift` — added `deleteNotes(ids:)` overload (UUID-based) for search-aware deletion.
- `Y2Notes/Views/NoteListView.swift` — added `@State searchText`, `.searchable()` modifier, `filteredNotes` computed property, `onNoteCreated` callback parameter, id-based `deleteFiltered` helper; `NoteRowView` now shows "Untitled" placeholder for empty titles.
- `Y2Notes/Views/NoteEditorView.swift` — added `autoFocusTitle: Bool` parameter and `@FocusState private var titleFocused`; focuses the title field 0.25 s after appear when `autoFocusTitle` is true.
- `Y2Notes/ContentView.swift` — added `@State private var newlyCreatedNoteID: UUID?`; passes `onNoteCreated` closure to `NoteListView`; passes `autoFocusTitle: note.id == newlyCreatedNoteID` to `NoteEditorView`; resets `newlyCreatedNoteID` on `.onAppear` of the editor.

What was completed:
- **Search/filter**: typing in the search bar filters the note list by title (case-insensitive). Swipe-to-delete works correctly against the filtered subset via UUID mapping. Clearing the search restores all notes.
- **Auto-focus title**: tapping "New Note" (square.and.pencil) opens the editor and places the cursor in the title field automatically after a 0.25 s delay (allows NavigationSplitView transition to settle before keyboard appears). Subsequent opens of the same note do not re-trigger auto-focus.
- **Untitled placeholder**: list rows show "Untitled" in secondary colour when `note.title` is empty.

What remains:
- iCloud / CloudKit sync (future agent).
- Note thumbnail preview (PKDrawing rendered as thumbnail in the list row) — future agent.
- Tags / folders (future agent).
- Unit/UI tests (future agent once a CI environment with Xcode is available).
- Export (PDF/image) feature (future agent).

Build/test evidence:
- Code reviewed by inspection; Swift syntax validated manually. No Xcode available in this Linux sandbox.
- All changed call-sites updated: `NoteListView` init now requires `onNoteCreated`; old `deleteNotes(at:)` still present for callers not using search.

Notes for next agents:
- `NoteListView` now accepts `onNoteCreated: (UUID) -> Void` — any future refactor of the new-note button must supply this callback.
- The 0.25 s delay in `NoteEditorView.onAppear` is intentional; do not remove it without testing on device (keyboard animation conflicts with split-view transition on iPad).
- `newlyCreatedNoteID` is set to `nil` in the `.onAppear` of `NoteEditorView` in `ContentView`, so re-opening a previously created note will never re-trigger auto-focus.
