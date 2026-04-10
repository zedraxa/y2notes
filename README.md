# Y2Notes

A premium iPad note-taking app built with SwiftUI and PencilKit — designed for handwriting, ink effects, multi-page notebooks, and study workflows.

---

## Features

| Feature | Description |
|---------|-------------|
| **PencilKit Canvas** | Full Apple Pencil support: pressure, tilt, barrel-roll (Pencil Pro), hover preview (M2+ iPad Pro) |
| **Ink Effects** | Fire 🔥, sparkle ✨, glitch 🌀, ripple 💧 — real-time particle overlays with per-device performance budgets |
| **Multi-Page Notes** | Book-like experience: add/remove/navigate pages within a single note |
| **Notebooks & Sections** | Organise notes into notebooks with collapsible sections, reorder/rename/delete |
| **Study System** | SM-2 spaced repetition flashcards with mastery tracking, bulk import, and study stats |
| **PDF Annotation** | Import PDFs, annotate pages with PencilKit, save per-page drawings |
| **Cloud Sync** | Google Drive backup with offline queue and conflict resolution |
| **Themes** | System, Light, Dark, Sepia, Midnight, Ocean — per-note or per-notebook overrides |
| **Page Templates** | Blank, Lined, Grid, Dotted, Cornell, Music Staff — extensible via template packs |
| **Search** | Full-text search across note titles, typed text, and handwriting OCR |
| **Accessibility** | Reduced motion, high contrast, VoiceOver labels, autosave controls |

## Architecture

```
Y2NotesApp (@main)
│
├─ ContentView (NavigationSplitView — 3 columns on iPad)
│  ├─ Sidebar:  ShelfView (notebooks + sections)
│  ├─ Content:  NoteGridView / NoteListView (note cards)
│  └─ Detail:   NoteEditorView (PencilKit canvas + toolbar)
│
├─ Environment Objects
│  ├─ NoteStore          — notes, notebooks, sections persistence (JSON files)
│  ├─ ThemeStore         — global theme selection
│  ├─ DrawingToolStore   — active pen/pencil/eraser/lasso state
│  ├─ InkEffectStore     — premium ink presets + FX toggle
│  ├─ PDFStore           — imported PDFs and per-page annotations
│  ├─ AppSettingsStore   — user preferences
│  └─ GoogleDriveSyncEngine — cloud backup
│
├─ Ink Effect Pipeline
│  ├─ InkModels          — DeviceCapabilityTier, InkFamily, InkPreset, WritingFXType
│  ├─ InkFamilyRegistry  — 20 built-in presets across 7 families
│  ├─ InkEffectStore     — preset selection, user presets, persistence
│  └─ InkEffectEngine    — CAEmitterLayer / CAShapeLayer overlay rendering
│
└─ Persistence
   ├─ y2notes_notes.json      (Note array — multi-page drawing data)
   ├─ y2notes_notebooks.json  (Notebook array)
   ├─ y2notes_sections.json   (NotebookSection array)
   └─ y2notes_study.json      (StudyPayload — sets, cards, review history)
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full system design.

## Building

**Requirements**: Xcode 15+ on macOS, targeting iPad (iOS 17.0+)

```bash
# Open in Xcode
open Y2Notes.xcodeproj

# Or build from command line
xcodebuild -project Y2Notes.xcodeproj \
  -scheme Y2Notes \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

**CI/CD**: Codemagic pushes to TestFlight automatically on merge to `main`.
See [`codemagic.yaml`](codemagic.yaml) for the full pipeline.

## Project Structure

```
Y2Notes/
├── Models/           Note, Notebook, NotebookSection, PageTemplate, StudySet
├── Views/            All SwiftUI views (editor, shelf, toolbar, study, etc.)
├── Ink/              Ink effect engine, models, presets, store
├── PencilKit/        Apple Pencil coordinator, hover overlay, contextual palette
├── PDF/              PDF viewer, annotation, store
├── Persistence/      NoteStore (JSON-backed persistence)
├── GoogleDrive/      Auth, client, sync engine, offline queue
├── Search/           SearchService (title + typed text + OCR)
├── Theme/            AppTheme definitions + ThemeStore
├── Tools/            DrawingToolStore + ToolModels
├── Settings/         AppSettingsStore, SettingsView, DiagnosticsView
├── Accessibility/    AccessibilityHelpers
└── en.lproj/         Localizable.strings (335 keys)
```

## AI-Generated Multiple-Choice Test Import (JSON)

Study sets now support importing versioned multiple-choice test files (`.json`).

Schema (v1):

```json
{
  "version": 1,
  "set": {
    "title": "Biology Chapter 3",
    "description": "Cell structure and transport"
  },
  "questions": [
    {
      "prompt": "Which organelle is responsible for ATP production?",
      "options": ["Nucleus", "Mitochondrion", "Golgi apparatus", "Lysosome"],
      "correctOptionIndex": 1,
      "explanation": "Mitochondria generate ATP via cellular respiration.",
      "tags": ["biology", "cells"],
      "source": "chapter-3-notes"
    }
  ]
}
```

Validation requirements:
- `version` must be `1`
- each `prompt` must be non-empty
- each question must have at least 2 non-empty `options`
- `correctOptionIndex` must be a valid index in `options`

In-app path:
- Open a study set
- Tap `…` menu
- Choose **Import Test File**
- Preview and import

## Documentation

| Document | Description |
|----------|-------------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Full system architecture: modules, data flow, coordinate spaces |
| [`docs/INK_EFFECTS_DEEP_DIVE.md`](docs/INK_EFFECTS_DEEP_DIVE.md) | Ink effects engine: particles, device tiers, coordinate conversion |
| [`docs/MULTI_PAGE_DESIGN.md`](docs/MULTI_PAGE_DESIGN.md) | Multi-page note model, backward compatibility, page navigation |
| [`docs/DATA_MODEL_REFERENCE.md`](docs/DATA_MODEL_REFERENCE.md) | Complete data model reference for all entities |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Improvement roadmap, known issues, future plans |
| [`docs/agents/Y2NOTES_EXECUTION_LEDGER.md`](docs/agents/Y2NOTES_EXECUTION_LEDGER.md) | Agent coordination log |

## License

Private / proprietary. All rights reserved.
