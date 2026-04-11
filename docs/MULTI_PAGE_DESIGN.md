# Multi-Page Note Design

## Overview

Y2Notes supports multi-page notes — a single note can contain an ordered array of pages,
each with its own `PKDrawing` data. This creates a book-like experience where users can
flip between pages, add new blank pages, and remove pages (minimum 1 page per note).

---

## Data Model

### Note.pages

```
struct Note: Identifiable, Codable, Hashable {
    var pages: [Data]       // Each element is a serialized PKDrawing
    var pageCount: Int      // pages.count

    var drawingData: Data   // Computed: maps to pages[0]
        get → pages.first ?? Data()
        set → pages[0] = newValue  (or pages = [newValue] if empty)
}
```

**Key design decisions**:
- `pages` is the source of truth — the array holds all page data
- `drawingData` is a computed property for backward compatibility — it always maps to the first page
- A note always has at least one page (decoder ensures `pages` is never empty)

### Why Not Separate Page Entities?

We considered a `Page` struct linked to `Note` via a foreign key, but chose the embedded
array approach for several reasons:

1. **Atomicity**: All pages save together as part of the note JSON. No orphan pages.
2. **Simplicity**: No join logic, no separate store, no ID management per page.
3. **Size**: Drawing data for a typical handwritten page is 5–50 KB. Even a 100-page
   note fits comfortably in a single JSON file.
4. **Backward compatibility**: Existing single-page notes just have `pages.count == 1`.

---

## Backward Compatibility

### Encoding (dual-write)

The encoder always writes **both** keys for maximum backward compatibility:

```json
{
  "drawingData": "<base64 of page 0>",
  "pages": ["<base64 of page 0>", "<base64 of page 1>", "..."]
}
```

Older app versions that don't understand `pages` will still read `drawingData` correctly
and see the first page of any multi-page note.

### Decoding (prefer pages, fallback to drawingData)

```
if "pages" key exists and is non-empty:
    use pages array directly
    (if empty, default to [Data()] — one blank page)
else:
    read legacy "drawingData" key
    wrap in single-element array: [drawingData]
```

This handles three cases:
1. **New saves** with multi-page data → `pages` array used directly
2. **Old saves** with only `drawingData` → migrated to `pages[0]`
3. **Corrupt saves** with empty `pages` → one blank page (safety fallback)

---

## NoteStore API

### Writing

```
updateDrawing(for noteID: UUID, data: Data)
    → Updates pages[0] via the drawingData setter (legacy compatibility)
    → Marks isDirty = true

updateDrawing(for noteID: UUID, pageIndex: Int, data: Data)
    → Updates pages[pageIndex] directly
    → Marks isDirty = true
    → Bounds-checked: no-op if pageIndex out of range

addPage(to noteID: UUID) → Int?
    → Appends Data() to pages array
    → Returns new page index (pages.count - 1)
    → Marks isDirty = true

removePage(from noteID: UUID, at pageIndex: Int)
    → Removes pages[pageIndex]
    → No-op if pages.count ≤ 1 (always keep at least one page)
    → No-op if pageIndex out of bounds
    → Marks isDirty = true
```

### Duplicating

`duplicateNote(id:)` copies all pages:
```
let copy = Note(pages: original.pages, ...)
```

---

## Page Navigation UI

### NoteEditorView State

```
@State private var currentPageIndex = 0
```

### Canvas Identity

Each page gets its own canvas instance via SwiftUI's `.id()` modifier:

```
CanvasView(drawingData: note.pages[safePageIndex], ...)
    .id("\(note.id)-\(safePageIndex)")
```

When the page index changes, SwiftUI destroys the old CanvasView and creates a new one.
This triggers `makeUIView()` which loads the correct `PKDrawing` data for the new page.

### Safe Page Index

```
let safePageIndex: Int = {
    guard !note.pages.isEmpty else { return 0 }
    return min(currentPageIndex, note.pages.count - 1)
}()
```

This guards against:
- Empty pages array (shouldn't happen, but defensive)
- `currentPageIndex` exceeding page count after a page deletion

### Navigation Bar Layout

```
┌────────────────────────────────────────────────────────────────┐
│  [◄ Prev]    [▦ Page 1 of 3]    [+ Add]   [Next ►]           │
└────────────────────────────────────────────────────────────────┘
```

| Control | Action | Disabled When |
|---------|--------|---------------|
| ◄ Prev | `currentPageIndex -= 1` | `currentPageIndex <= 0` |
| Next ► | `currentPageIndex += 1` | `currentPageIndex >= pageCount - 1` |
| + Add | `noteStore.addPage(to:)` → navigate to new page | Never |
| ▦ Page X of Y | Opens page overview grid | Never |

All transitions are animated with `easeInOut(duration: 0.25)`.

### Page Gestures

| Gesture | Touch Count | Action | Conflict Avoidance |
|---------|-------------|--------|-------------------|
| Swipe left | 2 fingers | Next page | Single-finger/Pencil reserved for drawing |
| Swipe right | 2 fingers | Previous page | Single-finger/Pencil reserved for drawing |
| Pinch in (scale < 0.7) | 2+ fingers | Open page overview grid | Normal zoom uses pinch-out; pinch-in below threshold triggers overview |

Gesture recognizers are attached to the container UIView (not the PKCanvasView) to avoid
interfering with PencilKit's internal gesture handling. The swipe handlers check `isDrawing`
and are no-ops mid-stroke.

### Page Overview Grid

The page overview is a full-screen sheet (`PageOverviewGrid`) showing all pages as thumbnails
in an adaptive `LazyVGrid` (160–240pt columns):

```
┌────────────────────────────────────────────────────────────┐
│  Pages                                           [+] Done  │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌══════════┐  ┌──────────┐  │
│  │          │  │          │  ║          ║  │          │  │
│  │  Page 1  │  │  Page 2  │  ║  Page 3  ║  │  Page 4  │  │
│  │          │  │          │  ║ (active) ║  │          │  │
│  └──────────┘  └──────────┘  └══════════┘  └──────────┘  │
│                                                             │
│  ┌──────────┐  ┌──────────┐                                │
│  │          │  │          │                                │
│  │  Page 5  │  │  Page 6  │                                │
│  │          │  │          │                                │
│  └──────────┘  └──────────┘                                │
└────────────────────────────────────────────────────────────┘
```

Features:
- Async thumbnail rendering (off main thread, `PKDrawing.image(from:scale:)`)
- Current page highlighted with accent colour border
- Tap to jump to any page (dismisses overview)
- Add page button in toolbar
- Auto-scrolls to current page on appear
- VoiceOver: `.isSelected` trait on current page

Three entry points to the overview:
1. Tap the page indicator button in the navigation bar
2. Pinch-to-overview gesture (pinch in with 2+ fingers)
3. Future: keyboard shortcut (not yet implemented)

---

## Drawing Data Flow (Per-Page)

```
User draws on page 2 (index 1)
    │
    ▼
CanvasView.onDrawingChanged(data)
    │
    ▼
NoteEditorView closure:
    noteStore.updateDrawing(for: note.id, pageIndex: 1, data: data)
    │
    ▼
NoteStore:
    notes[idx].pages[1] = data
    notes[idx].modifiedAt = Date()
    isDirty = true
    │
    ▼
Debounced save (0.8s) → flushToDisk() → JSON write
```

---

## Thumbnail Generation

Thumbnails always use the **first page** (`drawingData` computed property):

```
.task(id: note.drawingData) {
    thumbnail = await makeThumbnail(from: note.drawingData)
}
```

This means the grid/list preview always shows page 1 of a multi-page note.

---

## Future Considerations

### Page Reordering
Currently pages are ordered by their position in the array. A future drag-to-reorder
gesture could be added to the page navigation bar.

### Page Thumbnails Strip
A horizontal thumbnail strip below the canvas showing all pages at once (like a PDF
page navigator) would improve the multi-page UX for notes with many pages.

### Per-Page Metadata
Currently all pages share the note's `pageType`. A future enhancement
could allow per-page overrides (e.g., one page ruled, the next blank).

### Page Break Auto-Detection
When drawing approaches the bottom of a page, the app could offer to auto-create a new
page — similar to how word processors add page breaks.

### Infinite Canvas Alternative
An alternative to fixed-size pages would be an infinite vertical canvas that the user
scrolls continuously. This would eliminate page breaks entirely but wouldn't match the
"book-like" metaphor the current design targets.
