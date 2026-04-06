//! JSON-file persistence that matches the existing Swift `NoteStore` format.
//!
//! ## File layout
//! ```text
//! <documents_dir>/
//!   y2notes_notes.json        ← Note[]
//!   y2notes_notebooks.json    ← Notebook[]
//!   y2notes_sections.json     ← NotebookSection[]
//! ```
//!
//! ## Atomic writes
//! Writes go to a `.tmp` file first, then an atomic rename replaces the target.
//! On success the previous version is moved to `.bak` for one-generation
//! rollback (matching the Swift side's rolling-backup strategy).

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::models::{Note, Notebook, NotebookSection};

/// In-memory data store backed by JSON files.
pub struct DataStore {
    dir: PathBuf,
    pub notes: Vec<Note>,
    pub notebooks: Vec<Notebook>,
    pub sections: Vec<NotebookSection>,
}

// File names — must match the Swift `NoteStore` constants.
const NOTES_FILE: &str = "y2notes_notes.json";
const NOTEBOOKS_FILE: &str = "y2notes_notebooks.json";
const SECTIONS_FILE: &str = "y2notes_sections.json";

impl DataStore {
    /// Create an empty store that will persist to `dir`.
    pub fn new(dir: &str) -> Self {
        Self {
            dir: PathBuf::from(dir),
            notes: Vec::new(),
            notebooks: Vec::new(),
            sections: Vec::new(),
        }
    }

    /// Load a store from the given directory.  Missing files are silently
    /// treated as empty arrays so the first launch works without seeding.
    pub fn load(dir: &str) -> Result<Self, io::Error> {
        let dir_path = PathBuf::from(dir);
        let notes = load_json::<Vec<Note>>(&dir_path.join(NOTES_FILE));
        let notebooks = load_json::<Vec<Notebook>>(&dir_path.join(NOTEBOOKS_FILE));
        let sections = load_json::<Vec<NotebookSection>>(&dir_path.join(SECTIONS_FILE));
        Ok(Self {
            dir: dir_path,
            notes,
            notebooks,
            sections,
        })
    }

    /// Persist all collections to disk (atomic writes).
    pub fn save(&self) -> Result<(), io::Error> {
        fs::create_dir_all(&self.dir)?;
        atomic_write(&self.dir.join(NOTES_FILE), &self.notes)?;
        atomic_write(&self.dir.join(NOTEBOOKS_FILE), &self.notebooks)?;
        atomic_write(&self.dir.join(SECTIONS_FILE), &self.sections)?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Deserialise a JSON file to `T`, returning `T::default()` if the file does
/// not exist or contains invalid JSON.
fn load_json<T: serde::de::DeserializeOwned + Default>(path: &Path) -> T {
    match fs::read_to_string(path) {
        Ok(contents) => serde_json::from_str(&contents).unwrap_or_default(),
        Err(_) => T::default(),
    }
}

/// Write `data` as pretty-printed JSON to `path` atomically:
/// 1. Write to `path.tmp`
/// 2. Move existing `path` → `path.bak` (if present)
/// 3. Rename `path.tmp` → `path`
fn atomic_write<T: serde::Serialize>(path: &Path, data: &T) -> Result<(), io::Error> {
    let tmp = path.with_extension("json.tmp");
    let bak = path.with_extension("json.bak");

    let json = serde_json::to_string_pretty(data)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;

    fs::write(&tmp, json.as_bytes())?;

    // Rotate backup
    if path.exists() {
        let _ = fs::rename(path, &bak);
    }

    fs::rename(&tmp, path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn temp_store() -> (TempDir, DataStore) {
        let dir = TempDir::new().unwrap();
        let store = DataStore::new(dir.path().to_str().unwrap());
        (dir, store)
    }

    #[test]
    fn round_trip_empty() {
        let (dir, store) = temp_store();
        store.save().unwrap();
        let loaded = DataStore::load(dir.path().to_str().unwrap()).unwrap();
        assert!(loaded.notes.is_empty());
        assert!(loaded.notebooks.is_empty());
        assert!(loaded.sections.is_empty());
    }

    #[test]
    fn round_trip_with_data() {
        let (dir, mut store) = temp_store();
        let note = crate::models::Note::new("Hello".into());
        let id = note.id;
        store.notes.push(note);
        store.save().unwrap();

        let loaded = DataStore::load(dir.path().to_str().unwrap()).unwrap();
        assert_eq!(loaded.notes.len(), 1);
        assert_eq!(loaded.notes[0].id, id);
        assert_eq!(loaded.notes[0].title, "Hello");
    }

    #[test]
    fn backup_created() {
        let (dir, mut store) = temp_store();
        store.notes.push(crate::models::Note::new("v1".into()));
        store.save().unwrap();

        store.notes[0].title = "v2".to_string();
        store.save().unwrap();

        let bak = dir.path().join("y2notes_notes.json.bak");
        assert!(bak.exists(), "backup file should exist after second save");
    }
}
