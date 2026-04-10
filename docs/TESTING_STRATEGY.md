# Testing Strategy

This document outlines the testing plan for Y2Notes. The project currently has
**zero test coverage** — establishing a test infrastructure is the highest-priority
item on the roadmap.

---

## Test Targets

| Target | Type | Directory | Framework |
|--------|------|-----------|-----------|
| `Y2NotesTests` | Unit tests | `Y2NotesTests/` | XCTest |
| `Y2NotesUITests` | UI tests | `Y2NotesUITests/` | XCUITest |

---

## Unit Test Plan

### Priority 1: Data Model Encoding/Decoding

These are the most critical tests — data corruption is the worst possible bug.

| Test File | What to Test |
|-----------|-------------|
| `NoteTests.swift` | Single-page encode/decode round-trip |
| | Multi-page encode/decode round-trip |
| | Legacy single-page → multi-page migration |
| | Empty pages array safety (always ≥ 1 page) |
| | `drawingData` computed property maps to `pages[0]` |
| | Dual encoding: both `drawingData` and `pages` keys present |
| `NotebookTests.swift` | All `NotebookCover` cases encode/decode |
| | All `PageType` cases encode/decode |
| | Custom cover data round-trip |
| `StudySetTests.swift` | Flashcard SM-2 parameters persist |
| | `StudyReviewEntry` encode/decode |
| | `MasteryLevel` threshold logic (0→new, 1-5→learning, 6-20→reviewing, 21+→mastered) |
| | Backward-compatible `StudyPayload` decoder |

### Priority 2: Store Logic

| Test File | What to Test |
|-----------|-------------|
| `NoteStoreTests.swift` | `updateDrawing(for:data:)` updates `pages[0]` |
| | `updateDrawing(for:pageIndex:data:)` updates correct page |
| | `addPage(to:)` appends page and returns new index |
| | `removePage(from:at:)` removes page (min 1 page enforced) |
| | `removePage` no-op when only 1 page remains |
| | `duplicateNote(id:)` copies all pages |
| | `isDirty` flag set on mutations |
| | Page index out-of-bounds is a no-op |
| `InkEffectStoreTests.swift` | `resolvedFX` returns `.none` when toggle off |
| | `resolvedFX` returns `.none` when device tier too low |
| | `resolvedFX` returns correct FX when preset selected |
| | User preset persistence round-trip (UserDefaults) |
| | Active preset ID restoration on launch |
| `DrawingToolStoreTests.swift` | Tool snapshot equality comparison |
| | Tool selection state transitions |
| `ThemeStoreTests.swift` | Theme persistence in UserDefaults |
| | All 6 themes have valid canvas BG and ink colors |

### Priority 3: Utility Functions

| Test File | What to Test |
|-----------|-------------|
| `CoordinateTests.swift` | `viewportPoint(from:in:)` at zoom 1.0, offset (0,0) |
| | `viewportPoint` at zoom 2.0 with offset |
| | `viewportPoint` at fractional zoom |
| `DeviceTierTests.swift` | Tier detection: < 3 GB → `.basic` |
| | Tier detection: 3 GB → `.standard` |
| | Tier detection: 4 GB, 6 cores → `.pro` |
| | Tier detection: 8 GB, 8 cores → `.ultra` |
| | `isSupported(tier:)` for each WritingFXType |
| `SearchServiceTests.swift` | Title-only search matches |
| | OCR text search matches |
| | Case-insensitive search |
| | Empty query returns all |

### Priority 4: Ink Models

| Test File | What to Test |
|-----------|-------------|
| `InkFamilyRegistryTests.swift` | All 20 built-in presets are present |
| | Each family has at least 1 preset |
| | No duplicate preset IDs |
| | Default presets have valid FX for their minimum tier |
| `InkModelsTests.swift` | `InkPreset` encode/decode round-trip |
| | `InkFamily` raw values are stable (persisted) |
| | `WritingFXType` raw values are stable |

---

## UI Test Plan

| Test | Steps | Assertion |
|------|-------|-----------|
| Create Note | Tap "New Note" → note editor appears | Editor title is "New Note" |
| Draw Stroke | Touch canvas with simulated pencil | `PKDrawing.strokes.count > 0` |
| Page Navigation | Create note → Add page → Next → Previous | Page indicator shows correct count |
| Ink Effect | Select "Ember" preset → draw | Effect overlay is visible |
| Notebook Creation | New Notebook wizard → name + cover → Create | Notebook appears in sidebar |
| Study Session | Open study set → Start → flip card → rate | Card interval updated |
| Search | Type query in search bar | Matching notes appear in results |
| Theme Switch | Settings → Theme → Dark | Canvas background changes |

---

## Test Conventions

### File Naming

```
Y2NotesTests/
├── Models/
│   ├── NoteTests.swift
│   ├── NotebookTests.swift
│   └── StudySetTests.swift
├── Stores/
│   ├── NoteStoreTests.swift
│   ├── InkEffectStoreTests.swift
│   └── ThemeStoreTests.swift
├── Utilities/
│   ├── CoordinateTests.swift
│   └── DeviceTierTests.swift
└── Ink/
    ├── InkFamilyRegistryTests.swift
    └── InkModelsTests.swift
```

### Patterns

- **Given/When/Then**: Structure tests as setup → action → assertion
- **One assertion per concept**: A test should verify one logical thing
- **Descriptive names**: `test_addPage_appendsNewPage_andReturnsIndex()`
- **Factory methods**: Create `Note.fixture()`, `Notebook.fixture()` helpers
  to reduce boilerplate
- **No network**: All tests run offline — mock Google Drive client if needed

### Test Data

Use dedicated fixture/factory extensions:

```
extension Note {
    static func fixture(
        title: String = "Test Note",
        pages: [Data] = [Data()],
        ...
    ) -> Note { ... }
}
```

---

## Coverage Targets

| Phase | Target | Timeline |
|-------|--------|----------|
| Phase 1 | 40% (models + encoding) | v1.1 |
| Phase 2 | 60% (+ stores + utilities) | v1.2 |
| Phase 3 | 75% (+ UI tests) | v1.3 |

---

## Running Tests

### Command Line

```bash
make test           # Run all tests
make test-verbose   # Verbose output
```

### Xcode

⌘U to run all tests, or click the diamond next to individual test methods.

### CI

Tests run automatically on every PR via the GitHub Actions `build.yml` workflow
and on every merge to `main` via the Codemagic pipeline.
