# Data Model Reference

Complete reference for all persistent data types in Y2Notes.

---

## Core Entities

### Note

The fundamental unit of content. Each note contains multi-page drawing data and metadata.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `UUID` | auto-generated | Immutable identity |
| `title` | `String` | `"New Note"` | User-editable title |
| `createdAt` | `Date` | now | Creation timestamp |
| `modifiedAt` | `Date` | now | Last modification timestamp |
| `pages` | `[Data]` | `[Data()]` | Array of serialized PKDrawing data (1 element per page) |
| `isFavorited` | `Bool` | `false` | Star/favourite flag |
| `notebookID` | `UUID?` | `nil` | Parent notebook (nil = unfiled) |
| `sectionID` | `UUID?` | `nil` | Parent section within notebook |
| `sortOrder` | `Int` | `0` | Position within section/notebook |
| `templateID` | `String` | `"builtin.blank"` | Page template applied at creation |
| `themeOverride` | `AppTheme?` | `nil` | Per-note theme (nil = inherit) |
| `pageType` | `PageType?` | `nil` | Per-note ruling (nil = inherit from notebook, or .blank) |
| `paperMaterial` | `PaperMaterial?` | `nil` | Per-note paper (nil = inherit from notebook, or .standard) |
| `typedText` | `String` | `""` | Keyboard-typed text content |
| `ocrText` | `String` | `""` | Handwriting OCR result |

**Computed properties**:
- `drawingData: Data` — Maps to `pages[0]` for backward compatibility
- `pageCount: Int` — `pages.count`

**Equality**: Identity-based (`id` only) — list selection stays stable while content changes.

---

### Notebook

Organises notes into named containers with default page configuration.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `UUID` | auto-generated | Immutable identity |
| `name` | `String` | required | Notebook title |
| `createdAt` | `Date` | now | Creation timestamp |
| `modifiedAt` | `Date` | now | Last modification timestamp |
| `cover` | `NotebookCover` | `.ocean` | Cover gradient theme |
| `pageType` | `PageType` | `.ruled` | Default ruling for new notes |
| `pageSize` | `PageSize` | `.letter` | Default page size |
| `orientation` | `PageOrientation` | `.portrait` | Default orientation |
| `defaultTheme` | `AppTheme?` | `nil` | Theme override for notes |
| `paperMaterial` | `PaperMaterial` | `.standard` | Default paper texture |
| `customCoverData` | `Data?` | `nil` | JPEG cover image from photo library |

---

### NotebookSection

Subdivisions within a notebook for grouping notes.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `UUID` | auto-generated | Immutable identity |
| `notebookID` | `UUID` | required | Parent notebook |
| `name` | `String` | required | Section title |
| `sortOrder` | `Int` | `0` | Position within notebook |

---

### StudySet

A collection of flashcards for spaced-repetition study.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `UUID` | auto-generated | Immutable identity |
| `name` | `String` | required | Set title |
| `createdAt` | `Date` | now | Creation timestamp |
| `modifiedAt` | `Date` | now | Last modification timestamp |
| `notebookID` | `UUID?` | `nil` | Associated notebook |

### Flashcard

A single question/answer card within a study set.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `UUID` | auto-generated | Immutable identity |
| `studySetID` | `UUID` | required | Parent study set |
| `front` | `String` | `""` | Question/prompt text |
| `back` | `String` | `""` | Answer text |
| `tags` | `[String]` | `[]` | User-defined tags |
| `easeFactor` | `Double` | `2.5` | SM-2 ease factor |
| `interval` | `Int` | `0` | Days until next review |
| `repetitions` | `Int` | `0` | Consecutive correct reviews |
| `nextReviewDate` | `Date?` | `nil` | Scheduled review date |

### StudyReviewEntry

Historical record of a study review event.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cardID` | `UUID` | required | Card reviewed |
| `date` | `Date` | required | When the review occurred |
| `quality` | `Int` | required | SM-2 quality rating (0–5) |
| `interval` | `Int` | required | Resulting interval |

### MasteryLevel

Derived from `interval` field:

| Level | Interval Threshold | Description |
|-------|-------------------|-------------|
| `.new` | 0 | Never studied |
| `.learning` | 1–5 days | Initial learning phase |
| `.reviewing` | 6–20 days | Active review cycle |
| `.mastered` | 21+ days | Long-term retention |

---

## Enumerations

### NotebookCover (12 cases)

| Case | Display Name | Description |
|------|-------------|-------------|
| `.ocean` | Ocean | Blue gradient |
| `.forest` | Forest | Green gradient |
| `.sunset` | Sunset | Orange/red gradient |
| `.lavender` | Lavender | Purple gradient |
| `.slate` | Slate | Gray gradient |
| `.sand` | Sand | Warm tan gradient |
| `.ruby` | Ruby | Deep red gradient |
| `.midnight` | Midnight | Dark blue gradient |
| `.jade` | Jade | Teal gradient |
| `.coral` | Coral | Pink/orange gradient |
| `.copper` | Copper | Bronze gradient |
| `.nebula` | Nebula | Multi-colour space gradient |

---

### PageType (4 cases)

| Case | Display | Description |
|------|---------|-------------|
| `.blank` | Blank | No ruling |
| `.ruled` | Ruled | Horizontal lines |
| `.dot` | Dot | Dot grid |
| `.grid` | Grid | Square grid |

---

### PageSize (3 cases)

| Case | Display | Dimensions |
|------|---------|-----------|
| `.letter` | Letter | 8.5 × 11" |
| `.a4` | A4 | 210 × 297 mm |
| `.a5` | A5 | 148 × 210 mm |

---

### PageOrientation (2 cases)

| Case | Display |
|------|---------|
| `.portrait` | Portrait |
| `.landscape` | Landscape |

---

### PaperMaterial (7 cases)

| Case | Display | Ink Alpha | Grain Texture | Page Tint |
|------|---------|-----------|---------------|-----------|
| `.standard` | Standard | 1.00 | No | White |
| `.premium` | Premium | 1.00 | No | Slight purple |
| `.craft` | Craft | 0.88 | Yes | Warm kraft |
| `.recycled` | Recycled | 0.90 | Yes | Light gray |
| `.matte` | Matte | 0.92 | No | Near-white |
| `.glossy` | Glossy | 1.00 | No | Pure white |
| `.textured` | Textured | 0.84 | Yes | Warm cream |

---

### AppTheme (6 cases)

| Case | Canvas BG | Ink Color | Description |
|------|-----------|-----------|-------------|
| `.system` | System | Adaptive | Follows system dark/light |
| `.light` | White | Black | Always light |
| `.dark` | Dark gray | White | Always dark |
| `.sepia` | Warm cream | Dark brown | Classic paper |
| `.midnight` | Near-black | Cyan/white | Deep dark |
| `.ocean` | Deep blue | Light text | Blue theme |

---

### InkFamily (7 cases)

| Case | Display | System Image | Description |
|------|---------|-------------|-------------|
| `.standard` | Standard | pencil | Everyday pen/pencil |
| `.metallic` | Metallic | sparkles | Gold/silver shimmer |
| `.neon` | Neon | light.max | Bright emissive colours |
| `.watercolor` | Watercolour | paintpalette | Soft, wet washes |
| `.fire` | Fire | flame.fill | Flame trail effect |
| `.glitch` | Glitch | waveform.path.ecg | Digital artefacts |
| `.phantom` | Phantom | eye.slash | Near-invisible ink |

---

### WritingFXType (5 cases)

| Case | Display | Min Tier | Description |
|------|---------|----------|-------------|
| `.none` | None | basic | No effect (zero cost) |
| `.sparkle` | Sparkle | standard | Brief bright sparks |
| `.fire` | Fire | pro | Flame particles trailing nib |
| `.glitch` | Glitch | pro | Digital scan-line artefacts |
| `.ripple` | Ripple | standard | Expanding ring at stroke end |

---

### DeviceCapabilityTier (4 cases)

| Case | Raw | Max Particles | Supports Any FX | Supports Realtime FX |
|------|-----|---------------|-----------------|---------------------|
| `.basic` | 0 | 0 | No | No |
| `.standard` | 1 | 15 | Yes | No |
| `.pro` | 2 | 40 | Yes | Yes |
| `.ultra` | 3 | 80 | Yes | Yes |

---

### BuiltInTemplate (6 cases)

| Case | Display | Description |
|------|---------|-------------|
| `.blank` | Blank | Empty page |
| `.lined` | Lined | Horizontal lines |
| `.grid` | Grid | Square grid |
| `.dotted` | Dotted | Dot grid |
| `.cornell` | Cornell | Cornell note-taking layout |
| `.staved` | Music Staff | Five-line staff groups |

---

## Persistence Format

All data is stored as JSON files in the app's Documents directory:

| File | Content | Format |
|------|---------|--------|
| `y2notes_notes.json` | All notes | `[Note]` JSON array |
| `y2notes_notebooks.json` | All notebooks | `[Notebook]` JSON array |
| `y2notes_sections.json` | All sections | `[NotebookSection]` JSON array |
| `y2notes_study.json` | Study data | `StudyPayload` JSON object |

### Backup Strategy

Each file has a `.bak` sibling:
- Written before every save (copy of previous good version)
- If primary is corrupt on load, `.bak` is promoted
- One-generation rolling backup (only the most recent backup is kept)

### Drawing Data Encoding

`PKDrawing` data is stored as `Data` which encodes as base64 in JSON. A typical single-page
handwritten note is 5–50 KB of base64 data. Multi-page notes store an array of these.

### Note JSON Example

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Physics Lecture 3",
  "createdAt": 704037600.0,
  "modifiedAt": 704123999.0,
  "drawingData": "<base64 of page 0>",
  "pages": [
    "<base64 of page 0>",
    "<base64 of page 1>"
  ],
  "isFavorited": true,
  "notebookID": "660e8400-e29b-41d4-a716-446655440001",
  "sectionID": null,
  "sortOrder": 2,
  "templateID": "builtin.lined",
  "themeOverride": null,
  "pageType": "ruled",
  "paperMaterial": "premium",
  "typedText": "",
  "ocrText": ""
}
```

---

## Embedded Canvas Objects (ARCH-06)

### CanvasObjectWrapper

Type-erased `Codable` container stored per-page in `Note.embeddedObjectLayers`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `UUID` | auto-generated | Stable identity |
| `frame` | `CGRect` | required | Position + size in page content coordinates |
| `rotation` | `CGFloat` | `0` | Rotation in degrees (clockwise positive) |
| `zIndex` | `Int` | `0` | Z-ordering within the object layer |
| `isLocked` | `Bool` | `false` | Prevents move/resize |
| `objectType` | `CanvasObjectType` | required | Typed payload (image / scannedDocument / audioClip / sticker / link / textBlock) |

**JSON discriminator**: `objectType.type` + `objectType.payload`.

### ImageObject (payload for `.image`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `relativePath` | `String` | required | `NoteMedia/{noteID}/{objectID}.jpg` relative to Documents/ |
| `originalFilename` | `String?` | `nil` | Source filename from photo library or file picker |
| `cropRect` | `CGRect?` | `nil` | Normalised crop rectangle (0…1) |
| `borderStyle` | `BorderStyle` | `.none` | `none` / `thin` / `rounded` / `shadow` |
| `opacity` | `CGFloat` | `1.0` | Overall opacity |
| `thumbnailData` | `Data?` | `nil` | Inline JPEG thumbnail ≤ 200×200 px for fast display |

### AudioClipObject (payload for `.audioClip`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `audioFilename` | `String` | required | `{objectID}.m4a` filename (no path) in Documents/AudioClips/ |
| `duration` | `TimeInterval` | required | Recording duration in seconds |
| `waveformData` | `[Float]` | `[]` | ~200 normalised (0…1) amplitude samples for visualisation |
| `transcription` | `String?` | `nil` | Speech-to-text result (populated lazily) |
| `playbackPosition` | `TimeInterval` | `0` | Last resume position in seconds |
| `title` | `String` | `""` | Display title on the widget |
| `recordedAt` | `Date` | `Date()` | Recording timestamp |

### StickerObject (payload for `.sticker`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `stickerID` | `String` | required | Pack-namespaced identifier, e.g. `"academic.star.filled"` |
| `stickerData` | `Data?` | `nil` | Inline PNG for third-party stickers (nil for built-in) |
| `category` | `String` | `""` | Display category (e.g. `"Academic"`) |
| `tintColor` | `StickerTintColor?` | `nil` | Optional RGBA recolour |
| `isBuiltIn` | `Bool` | `true` | Whether the sticker can be regenerated without inline data |

### LinkObject (payload for `.link`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `urlString` | `String` | required | Destination URL string |
| `title` | `String?` | `nil` | Open Graph or HTML page title |
| `faviconData` | `Data?` | `nil` | Site favicon PNG ≤ 32×32 px |
| `previewImageData` | `Data?` | `nil` | og:image JPEG ≤ 480 px wide |
| `displayDomain` | `String?` | `nil` | Root domain for display (e.g. `"github.com"`) |
| `displayStyle` | `LinkDisplayStyle` | `.chip` | `chip` / `card` / `inline` |

### Note.embeddedObjectLayers

A parallel array to `Note.pages`:

```swift
var embeddedObjectLayers: [[CanvasObjectWrapper]?]
```

- Index `i` contains the embedded objects for `pages[i]`.
- A `nil` element means no objects have been placed on that page (saves storage).
- An empty outer array (`[]`) means the note predates ARCH-06 (all pages have no objects).
- Missing key on decode defaults to `[]` (fully backward compatible).

### Media File Storage

| Content | Location | Naming |
|---------|----------|--------|
| Image files | `Documents/NoteMedia/{noteID}/{objectID}.jpg` | JPEG 0.8 quality, ≤ 2048 px long edge |
| Audio recordings | `Documents/AudioClips/{objectID}.m4a` | AAC 128 kbps mono |
| Scan thumbnails | `Documents/Scans/{objectID}_scan.jpg` | JPEG 0.7 quality, ≤ 240 px |

JSON stores only relative paths and metadata — never inline binary blobs — to keep note JSON files small.
