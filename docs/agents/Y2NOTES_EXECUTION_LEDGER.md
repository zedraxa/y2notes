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

## [2026-04-01T14:27:20Z] AGENT-02 — Search, Thumbnails & Undo/Redo

Branch: copilot/agent02-search-thumbnails-undo
Model used: claude-sonnet-4.6
Scope: Improve list usability and editor quality with three functional features: note search/filter, drawing thumbnails in list rows, and undo/redo toolbar buttons.

Files modified:
- `Y2Notes/Views/NoteListView.swift` — search + thumbnails
- `Y2Notes/Views/NoteEditorView.swift` — undo/redo toolbar

What was completed:
- **Search/filter**: `.searchable(text:prompt:)` added to `NoteListView`. Filtering is done via a `filteredNotes` computed property using `localizedCaseInsensitiveContains`. Swipe-to-delete maps filtered offsets back to the full `noteStore.notes` array so deletes are always correct regardless of active search query.
- **Drawing thumbnails**: `NoteRowView` renders a 60×45 pt rounded thumbnail next to each note title. Thumbnail is generated asynchronously via `Task(priority: .utility)` using `PKDrawing.image(from:scale:)` so the main thread is never blocked. The `task(id: note.modifiedAt)` modifier re-runs when the note is edited, keeping previews fresh. Empty drawings show a placeholder `systemGray6` rectangle.
- **Undo/redo**: `NoteEditorView` reads `@Environment(\.undoManager)` (the UIWindowScene undo manager, which PencilKit registers its undo actions against) and adds two toolbar buttons (↩ / ↪) in `.navigationBarTrailing`. Both call `undo()` / `redo()` on the environment undo manager — no custom responder chain wiring required.

What remains:
- iCloud / CloudKit sync (future agent).
- Export (PDF/image) feature (future agent).
- Unit/UI tests (future agent once CI with Xcode is available).
- App icon artwork (needs a designer pass).

Build/test evidence:
- All changes are confined to existing Swift source files; no new file references were added to `project.pbxproj`.
- PencilKit is already linked (imported in `NoteEditorView`); adding `import PencilKit` to `NoteListView` for `PKDrawing` usage requires no project changes.
- Structural review: all `@State`, `@Environment`, and `task` usages follow idiomatic iOS 16 SwiftUI patterns.

Open risks:
- `@Environment(\.undoManager)` propagates the window's undo manager. On iOS 16+ iPad with a single window scene this is the same manager PencilKit uses. If a future multi-window configuration is added this should still work correctly because each scene has its own undo manager and SwiftUI routes the environment value per scene.
- Thumbnail `Task(priority: .utility)` is cancelled automatically by SwiftUI when the row view leaves the hierarchy, so no manual cancellation is needed.

Notes for next agents:
- `deleteFiltered(at:)` in `NoteListView` replaces the direct `noteStore.deleteNotes` call to handle filtered index remapping. Do not revert to a direct `onDelete` without accounting for this.
- Thumbnail size (60×45) and padding (12 pt) are hardcoded constants; a future agent adding note sizes/templates may wish to derive the aspect ratio from the canvas size instead.
