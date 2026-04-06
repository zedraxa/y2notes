/*  y2data.h — C FFI header for libY2Data (Rust data layer)
 *
 *  Include this header in the Swift bridging header to call the Rust
 *  data layer from Swift.  All strings use null-terminated UTF-8.
 *  Returned string pointers MUST be freed with y2data_free_string().
 */

#ifndef Y2DATA_H
#define Y2DATA_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Lifecycle ───────────────────────────────────────────────────────────── */

/// Initialise the data store, loading persisted data from `documents_dir`.
/// Returns `true` on success.
bool y2data_init(const char *documents_dir);

/// Persist all in-memory data to disk.  Returns `true` on success.
bool y2data_save(void);

/// Tear down the global data store and free all memory.
void y2data_shutdown(void);

/* ── Notes ───────────────────────────────────────────────────────────────── */

/// Get all notes as a JSON array string.  Caller must free with
/// y2data_free_string.
char *y2data_get_all_notes(void);

/// Get a single note by UUID string.  Returns a JSON object or NULL.
/// Caller must free with y2data_free_string.
char *y2data_get_note(const char *uuid_str);

/// Add a new note with the given title.  Returns the UUID string of the
/// new note, or NULL on failure.  Caller must free with y2data_free_string.
char *y2data_add_note(const char *title);

/// Delete the note with the given UUID.  Returns `true` on success.
bool y2data_delete_note(const char *uuid_str);

/// Update the title of an existing note.  Returns `true` on success.
bool y2data_update_note_title(const char *uuid_str, const char *new_title);

/* ── Notebooks ──────────────────────────────────────────────────────────── */

/// Get all notebooks as a JSON array string.  Caller must free with
/// y2data_free_string.
char *y2data_get_all_notebooks(void);

/// Add a new notebook.  Returns the UUID string or NULL.
/// Caller must free with y2data_free_string.
char *y2data_add_notebook(const char *name);

/// Delete a notebook by UUID.  Returns `true` on success.
bool y2data_delete_notebook(const char *uuid_str);

/* ── Sections ───────────────────────────────────────────────────────────── */

/// Get all sections as a JSON array string.  Caller must free with
/// y2data_free_string.
char *y2data_get_all_sections(void);

/// Add a new section to a notebook.  Returns the UUID string or NULL.
/// Caller must free with y2data_free_string.
char *y2data_add_section(const char *name, const char *notebook_uuid_str);

/* ── Memory ─────────────────────────────────────────────────────────────── */

/// Free a string previously returned by a y2data_* function.
void y2data_free_string(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* Y2DATA_H */
