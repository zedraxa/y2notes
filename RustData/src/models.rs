//! Data models that mirror the Swift `Note`, `Notebook`, and `NotebookSection`
//! structs.  The `serde` attributes ensure that the JSON output is
//! wire-compatible with the existing Swift `Codable` encoding so that old and
//! new builds can share the same persistence files.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// NoteColorLabel
// ---------------------------------------------------------------------------

/// Optional colour label for visual organisation (matches Swift `NoteColorLabel`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum NoteColorLabel {
    Red,
    Orange,
    Yellow,
    Green,
    Teal,
    Blue,
    Purple,
}

// ---------------------------------------------------------------------------
// PageType
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PageType {
    Blank,
    Lined,
    Grid,
    Dotted,
    Cornell,
}

impl Default for PageType {
    fn default() -> Self {
        Self::Blank
    }
}

// ---------------------------------------------------------------------------
// Note
// ---------------------------------------------------------------------------

/// Core note model — mirrors the Swift `Note` struct field-for-field.
///
/// Drawing data is stored as opaque `Vec<u8>` (PencilKit `PKDrawing` bytes).
/// All parallel-array layers (stickers, shapes, attachments, etc.) are kept
/// as raw JSON `Value`s so that the Rust layer can round-trip them without
/// understanding every Swift-specific type.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub id: Uuid,
    pub title: String,
    pub created_at: DateTime<Utc>,
    pub modified_at: DateTime<Utc>,

    /// Multi-page drawing data.  Each element is a base64-encoded
    /// `PKDrawing` blob; `null` entries represent blank pages.
    #[serde(default)]
    pub pages: Vec<Option<String>>,

    // Organisation
    #[serde(default)]
    pub is_favorited: bool,
    #[serde(default)]
    pub notebook_id: Option<Uuid>,
    #[serde(default)]
    pub section_id: Option<Uuid>,
    #[serde(default)]
    pub sort_order: i64,
    #[serde(default)]
    pub template_id: Option<String>,

    // Theming
    #[serde(default)]
    pub theme_override: Option<String>,
    #[serde(default)]
    pub page_type: PageType,
    #[serde(default)]
    pub page_types: Vec<Option<PageType>>,
    #[serde(default)]
    pub page_colors: Vec<Option<String>>,

    // Content layers (parallel arrays — one entry per page)
    #[serde(default)]
    pub sticker_layers: Vec<Option<serde_json::Value>>,
    #[serde(default)]
    pub shape_layers: Vec<Option<serde_json::Value>>,
    #[serde(default)]
    pub attachment_layers: Vec<Option<serde_json::Value>>,
    #[serde(default)]
    pub widget_layers: Vec<Option<serde_json::Value>>,
    #[serde(default)]
    pub text_layers: Vec<Option<serde_json::Value>>,
    #[serde(default)]
    pub embedded_object_layers: Vec<Option<serde_json::Value>>,
    #[serde(default)]
    pub expansion_regions: Vec<Option<serde_json::Value>>,

    // PDF support
    #[serde(default)]
    pub pdf_filename: Option<String>,
    #[serde(default)]
    pub linked_pdf_id: Option<Uuid>,
    #[serde(default)]
    pub linked_document_id: Option<Uuid>,

    // Search / metadata
    #[serde(default)]
    pub typed_text: Option<String>,
    #[serde(default)]
    pub ocr_text: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub color_label: Option<NoteColorLabel>,
}

impl Note {
    /// Create a new, empty note with the given title and one blank page.
    pub fn new(title: String) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title,
            created_at: now,
            modified_at: now,
            pages: vec![None], // one blank page
            is_favorited: false,
            notebook_id: None,
            section_id: None,
            sort_order: 0,
            template_id: None,
            theme_override: None,
            page_type: PageType::default(),
            page_types: Vec::new(),
            page_colors: Vec::new(),
            sticker_layers: Vec::new(),
            shape_layers: Vec::new(),
            attachment_layers: Vec::new(),
            widget_layers: Vec::new(),
            text_layers: Vec::new(),
            embedded_object_layers: Vec::new(),
            expansion_regions: Vec::new(),
            pdf_filename: None,
            linked_pdf_id: None,
            linked_document_id: None,
            typed_text: None,
            ocr_text: None,
            tags: Vec::new(),
            color_label: None,
        }
    }
}

// ---------------------------------------------------------------------------
// Notebook
// ---------------------------------------------------------------------------

/// Notebook container — matches the Swift `Notebook` struct.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Notebook {
    pub id: Uuid,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub modified_at: DateTime<Utc>,
    #[serde(default)]
    pub color_hex: Option<String>,
    #[serde(default)]
    pub icon_name: Option<String>,
    #[serde(default)]
    pub sort_order: i64,
    #[serde(default)]
    pub is_archived: bool,
}

impl Notebook {
    pub fn new(name: String) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            name,
            created_at: now,
            modified_at: now,
            color_hex: None,
            icon_name: None,
            sort_order: 0,
            is_archived: false,
        }
    }
}

// ---------------------------------------------------------------------------
// NotebookSection
// ---------------------------------------------------------------------------

/// Section within a notebook — matches the Swift `NotebookSection` struct.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NotebookSection {
    pub id: Uuid,
    pub notebook_id: Uuid,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub modified_at: DateTime<Utc>,
    #[serde(default)]
    pub sort_order: i64,
    #[serde(default)]
    pub color_hex: Option<String>,
}

impl NotebookSection {
    pub fn new(name: String, notebook_id: Uuid) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            notebook_id,
            name,
            created_at: now,
            modified_at: now,
            sort_order: 0,
            color_hex: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn note_round_trip() {
        let note = Note::new("Test Note".into());
        let json = serde_json::to_string(&note).unwrap();
        let decoded: Note = serde_json::from_str(&json).unwrap();
        assert_eq!(note.id, decoded.id);
        assert_eq!(note.title, decoded.title);
    }

    #[test]
    fn notebook_round_trip() {
        let nb = Notebook::new("Physics".into());
        let json = serde_json::to_string(&nb).unwrap();
        let decoded: Notebook = serde_json::from_str(&json).unwrap();
        assert_eq!(nb.id, decoded.id);
        assert_eq!(nb.name, decoded.name);
    }

    #[test]
    fn section_round_trip() {
        let sec = NotebookSection::new("Chapter 1".into(), Uuid::new_v4());
        let json = serde_json::to_string(&sec).unwrap();
        let decoded: NotebookSection = serde_json::from_str(&json).unwrap();
        assert_eq!(sec.id, decoded.id);
        assert_eq!(sec.name, decoded.name);
    }
}
