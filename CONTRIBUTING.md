# Contributing to Y2Notes

Thank you for your interest in contributing to Y2Notes! This guide covers everything
you need to know to get started.

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Xcode** | 15.0+ | Mac App Store |
| **macOS** | Sonoma 14.0+ | Required for Xcode 15 |
| **SwiftLint** | 0.54+ | `brew install swiftlint` |
| **iPad Simulator** | iOS 17.0+ | Xcode → Settings → Platforms |

### Clone and Build

```bash
git clone https://github.com/zedraxa/y2notes.git
cd y2notes
open Y2Notes.xcodeproj
# Select "iPad Pro 13-inch (M4)" simulator → ⌘B to build
```

Or use the Makefile:

```bash
make build       # Build for iPad Simulator
make lint        # Run SwiftLint
make test        # Run tests (when test target exists)
make help        # See all available commands
```

---

## Project Structure

```
Y2Notes/
├── Models/           Data models (Note, Notebook, Section, StudySet)
├── Views/            SwiftUI views (editor, shelf, toolbar, study)
├── Ink/              Ink effects engine, models, presets, store
├── PencilKit/        Apple Pencil coordinator, hover, contextual palette
├── PDF/              PDF viewer, annotation, persistence
├── Persistence/      NoteStore — JSON file persistence layer
├── GoogleDrive/      Cloud sync (auth, client, engine, offline queue)
├── Search/           Full-text search service (title + OCR)
├── Theme/            Theme definitions and ThemeStore
├── Tools/            Drawing tool state and models
├── Settings/         App settings, diagnostics
├── Accessibility/    VoiceOver and accessibility helpers
├── en.lproj/         English localisation strings
└── es.lproj/         Spanish localisation strings (scaffolding)

docs/
├── ARCHITECTURE.md           System architecture overview
├── INK_EFFECTS_DEEP_DIVE.md  Ink effects engine deep dive
├── MULTI_PAGE_DESIGN.md      Multi-page note model design
├── DATA_MODEL_REFERENCE.md   Complete data model reference
├── TESTING_STRATEGY.md       Testing plan and conventions
└── ROADMAP.md                Feature roadmap and known issues
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full module map and data flow.

---

## Development Workflow

### Branch Naming

| Type | Format | Example |
|------|--------|---------|
| Feature | `feature/<short-name>` | `feature/page-thumbnails` |
| Bug fix | `fix/<short-name>` | `fix/glitch-frame-drift` |
| Docs | `docs/<short-name>` | `docs/testing-guide` |
| Chore | `chore/<short-name>` | `chore/update-deployment-target` |

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add page thumbnail strip
fix: prevent glitch layer frame drift on rotation
docs: add testing strategy document
chore: bump deployment target to iOS 17
refactor: extract ManageSectionsSheet subviews
```

### Pull Requests

1. Create a branch from `main`
2. Make your changes
3. Run `make validate` (lint + strings check + pbxproj validation)
4. Push and open a PR — the GitHub Actions workflow runs automatically
5. Fill out the PR template
6. Request review

---

## Coding Conventions

### Swift Style

- Follow the rules in [`.swiftlint.yml`](.swiftlint.yml)
- Max line length: 140 characters (warning), 200 (error)
- Use `Color(uiColor: .label)` instead of `Color.primary` (iOS 26 SDK removed it)
- Use `.foregroundStyle()` instead of `.foregroundColor()` (deprecated)
- Use `UIGraphicsImageRenderer` instead of `UIGraphicsBeginImageContextWithOptions`
- Decompose complex SwiftUI bodies into extracted computed properties to avoid
  type-checker timeouts

### Naming

- Types: `UpperCamelCase` (e.g., `NoteEditorView`, `InkEffectEngine`)
- Variables/functions: `lowerCamelCase` (e.g., `currentPageIndex`, `updateDrawing()`)
- Constants: `lowerCamelCase` (e.g., `unsectionedSentinel`)
- Abbreviations: keep short (e.g., `fx` for effects, `bg` for background)

### Localisation

- All user-facing strings must go through `Localizable.strings`
- Key format: `<Screen>.<Element>` or `<Feature>.<Action>` (e.g., `Editor.Undo`)
- When adding keys, add them to **both** `en.lproj` and `es.lproj` (scaffold)

### Environment Objects

The app uses 7 `@StateObject` stores injected as `.environmentObject`:

| Store | Responsibility |
|-------|---------------|
| `NoteStore` | Notes, notebooks, sections, persistence |
| `ThemeStore` | Global theme selection |
| `DrawingToolStore` | Active pen/pencil/eraser/lasso state |
| `InkEffectStore` | Ink presets, FX toggle, user presets |
| `PDFStore` | Imported PDFs and annotations |
| `AppSettingsStore` | User preferences |
| `GoogleDriveSyncEngine` | Cloud backup |

### Xcode Project File

- Manual UUID tracking in `project.pbxproj` — next available suffix: **C9**
- When adding new `.swift` files, assign the next UUID suffix and increment
- Validate with: `ruby -e 'require "xcodeproj"; Xcodeproj::Project.open("Y2Notes.xcodeproj")'`

---

## Testing

See [`docs/TESTING_STRATEGY.md`](docs/TESTING_STRATEGY.md) for the full testing plan.

Currently the project has a **unit test target** (`Y2NotesTests/`) as well as
tests inside each SPM package under `Packages/`. When contributing tests:

- Unit tests go in `Y2NotesTests/`
- Package-level tests go in `Packages/<PackageName>/Tests/`
- Test file naming: `<SourceFile>Tests.swift` (e.g., `NoteTests.swift`)
- Use `XCTAssert*` for assertions, `XCTSkip` for conditional skips

---

## Documentation

- Architecture docs live in `docs/`
- Update docs when changing data models, persistence format, or system architecture
- Use ASCII diagrams for visualisations (they render well everywhere)
- Documentation changes don't need a build/test — just linting

---

## Reporting Issues

Use the GitHub issue templates:

- **Bug Report**: For crashes, incorrect behaviour, or visual glitches
- **Feature Request**: For new capabilities or UX improvements

Include device model, iOS version, and app version when reporting bugs.

---

## Code of Conduct

Be respectful, constructive, and patient. We're building something great together.
