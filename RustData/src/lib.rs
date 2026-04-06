//! # y2data — Y2Notes Rust Data Layer
//!
//! Pure-Rust implementation of the Y2Notes data model and JSON persistence.
//! Compiled as `libY2Data.a` (C-ABI static library) and called from Swift
//! through a thin C FFI bridge.
//!
//! ## Design goals
//! - **Zero Swift in the data layer** — all model definitions and persistence
//!   logic live here.
//! - **Language-agnostic** — the C FFI can be called from Swift, Kotlin, C++,
//!   or any language with a C FFI.
//! - **Wire-compatible** — JSON output matches the existing Swift `Codable`
//!   format so old and new builds can read each other's files.

pub mod models;
pub mod persistence;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::Mutex;

use models::{Note, Notebook, NotebookSection};
use persistence::DataStore;

// ---------------------------------------------------------------------------
// Global data store — accessed from Swift through opaque handle functions.
// ---------------------------------------------------------------------------

static DATA_STORE: Mutex<Option<DataStore>> = Mutex::new(None);

fn with_store<R>(f: impl FnOnce(&DataStore) -> R) -> Option<R> {
    DATA_STORE.lock().ok().and_then(|guard| guard.as_ref().map(f))
}

fn with_store_mut<R>(f: impl FnOnce(&mut DataStore) -> R) -> Option<R> {
    DATA_STORE
        .lock()
        .ok()
        .and_then(|mut guard| guard.as_mut().map(f))
}

// ---------------------------------------------------------------------------
// C FFI — Lifecycle
// ---------------------------------------------------------------------------

/// Initialise the data store, loading persisted data from the given directory.
///
/// # Safety
/// `documents_dir` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn y2data_init(documents_dir: *const c_char) -> bool {
    if documents_dir.is_null() {
        return false;
    }
    let path = match CStr::from_ptr(documents_dir).to_str() {
        Ok(s) => s.to_owned(),
        Err(_) => return false,
    };
    let store = match DataStore::load(&path) {
        Ok(s) => s,
        Err(_) => DataStore::new(&path),
    };
    if let Ok(mut guard) = DATA_STORE.lock() {
        *guard = Some(store);
        true
    } else {
        false
    }
}

/// Persist all in-memory data to disk.  Returns `true` on success.
#[no_mangle]
pub extern "C" fn y2data_save() -> bool {
    with_store(|s| s.save().is_ok()).unwrap_or(false)
}

/// Tear down the global data store and free all memory.
#[no_mangle]
pub extern "C" fn y2data_shutdown() {
    if let Ok(mut guard) = DATA_STORE.lock() {
        if let Some(store) = guard.take() {
            let _ = store.save();
        }
    }
}

// ---------------------------------------------------------------------------
// C FFI — Notes CRUD
// ---------------------------------------------------------------------------

/// Return all notes as a JSON array string.
///
/// Caller must free the returned pointer with `y2data_free_string`.
#[no_mangle]
pub extern "C" fn y2data_get_all_notes() -> *mut c_char {
    let json = with_store(|s| serde_json::to_string(&s.notes).unwrap_or_default());
    to_c_string(json.unwrap_or_default())
}

/// Get a single note by UUID string.  Returns a JSON object or null.
///
/// # Safety
/// `uuid_str` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn y2data_get_note(uuid_str: *const c_char) -> *mut c_char {
    let uuid = match parse_uuid(uuid_str) {
        Some(u) => u,
        None => return ptr::null_mut(),
    };
    let json = with_store(|s| {
        s.notes
            .iter()
            .find(|n| n.id == uuid)
            .and_then(|n| serde_json::to_string(n).ok())
    })
    .flatten();
    match json {
        Some(j) => to_c_string(j),
        None => ptr::null_mut(),
    }
}

/// Add a new note with the given title.  Returns the UUID string of the new
/// note, or null on failure.
///
/// # Safety
/// `title` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn y2data_add_note(title: *const c_char) -> *mut c_char {
    let title = match c_str_to_string(title) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let note = Note::new(title);
    let id_str = note.id.to_string();
    with_store_mut(|s| s.notes.push(note));
    to_c_string(id_str)
}

/// Delete the note with the given UUID.  Returns `true` on success.
///
/// # Safety
/// `uuid_str` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn y2data_delete_note(uuid_str: *const c_char) -> bool {
    let uuid = match parse_uuid(uuid_str) {
        Some(u) => u,
        None => return false,
    };
    with_store_mut(|s| {
        let before = s.notes.len();
        s.notes.retain(|n| n.id != uuid);
        s.notes.len() != before
    })
    .unwrap_or(false)
}

/// Update the title of an existing note.  Returns `true` on success.
///
/// # Safety
/// `uuid_str` and `new_title` must be valid null-terminated UTF-8 C strings.
#[no_mangle]
pub unsafe extern "C" fn y2data_update_note_title(
    uuid_str: *const c_char,
    new_title: *const c_char,
) -> bool {
    let uuid = match parse_uuid(uuid_str) {
        Some(u) => u,
        None => return false,
    };
    let title = match c_str_to_string(new_title) {
        Some(s) => s,
        None => return false,
    };
    with_store_mut(|s| {
        if let Some(note) = s.notes.iter_mut().find(|n| n.id == uuid) {
            note.title = title;
            note.modified_at = chrono::Utc::now();
            true
        } else {
            false
        }
    })
    .unwrap_or(false)
}

// ---------------------------------------------------------------------------
// C FFI — Notebooks CRUD
// ---------------------------------------------------------------------------

/// Return all notebooks as a JSON array string.
#[no_mangle]
pub extern "C" fn y2data_get_all_notebooks() -> *mut c_char {
    let json = with_store(|s| serde_json::to_string(&s.notebooks).unwrap_or_default());
    to_c_string(json.unwrap_or_default())
}

/// Add a new notebook.  Returns the UUID string or null.
///
/// # Safety
/// `name` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn y2data_add_notebook(name: *const c_char) -> *mut c_char {
    let name = match c_str_to_string(name) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let nb = Notebook::new(name);
    let id_str = nb.id.to_string();
    with_store_mut(|s| s.notebooks.push(nb));
    to_c_string(id_str)
}

/// Delete a notebook by UUID.
///
/// # Safety
/// `uuid_str` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn y2data_delete_notebook(uuid_str: *const c_char) -> bool {
    let uuid = match parse_uuid(uuid_str) {
        Some(u) => u,
        None => return false,
    };
    with_store_mut(|s| {
        let before = s.notebooks.len();
        s.notebooks.retain(|nb| nb.id != uuid);
        s.notebooks.len() != before
    })
    .unwrap_or(false)
}

// ---------------------------------------------------------------------------
// C FFI — Sections CRUD
// ---------------------------------------------------------------------------

/// Return all sections as a JSON array string.
#[no_mangle]
pub extern "C" fn y2data_get_all_sections() -> *mut c_char {
    let json = with_store(|s| serde_json::to_string(&s.sections).unwrap_or_default());
    to_c_string(json.unwrap_or_default())
}

/// Add a new section to a notebook.  Returns the UUID string or null.
///
/// # Safety
/// `name` and `notebook_uuid_str` must be valid null-terminated UTF-8 C strings.
#[no_mangle]
pub unsafe extern "C" fn y2data_add_section(
    name: *const c_char,
    notebook_uuid_str: *const c_char,
) -> *mut c_char {
    let name = match c_str_to_string(name) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let nb_id = match parse_uuid(notebook_uuid_str) {
        Some(u) => u,
        None => return ptr::null_mut(),
    };
    let sec = NotebookSection::new(name, nb_id);
    let id_str = sec.id.to_string();
    with_store_mut(|s| s.sections.push(sec));
    to_c_string(id_str)
}

// ---------------------------------------------------------------------------
// C FFI — Memory helpers
// ---------------------------------------------------------------------------

/// Free a string previously returned by a `y2data_*` function.
///
/// # Safety
/// `ptr` must have been allocated by this library via `CString::into_raw`.
#[no_mangle]
pub unsafe extern "C" fn y2data_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .map(|cs| cs.into_raw())
        .unwrap_or(ptr::null_mut())
}

unsafe fn c_str_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_owned())
}

unsafe fn parse_uuid(ptr: *const c_char) -> Option<uuid::Uuid> {
    c_str_to_string(ptr).and_then(|s| uuid::Uuid::parse_str(&s).ok())
}
