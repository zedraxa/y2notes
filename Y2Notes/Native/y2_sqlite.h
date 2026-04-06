/*
 *  y2_sqlite.h
 *  Y2Notes
 *
 *  Lightweight C wrapper around SQLite for note persistence.
 *  Designed to be called from Swift via the bridging header.
 *  Replaces Foundation JSONEncoder dependency with direct SQLite storage.
 */

#ifndef Y2_SQLITE_H
#define Y2_SQLITE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque database handle */
typedef struct y2_db y2_db;

/* ── Lifecycle ──────────────────────────────────────────────────────── */

/**
 * Open (or create) the SQLite database at `path`.
 * Creates tables and runs migrations automatically.
 * Returns NULL on failure.
 */
y2_db *y2_db_open(const char *path);

/**
 * Flush WAL and close the database.  Safe to call with NULL.
 */
void y2_db_close(y2_db *db);

/* ── Key-value persistence (PersistenceDriver interface) ───────────── */

/**
 * Write `length` bytes of `data` for the given `key`.
 * Replaces any existing value.  Returns 0 on success, -1 on error.
 */
int y2_db_write(y2_db *db, const char *key, const void *data, uint32_t length);

/**
 * Read data for `key`.  On success, `*out_data` is set to a malloc'd
 * buffer and `*out_length` to its size.  Caller must free `*out_data`.
 * Returns 0 on success, 1 if key not found, -1 on error.
 */
int y2_db_read(y2_db *db, const char *key, void **out_data, uint32_t *out_length);

/**
 * Delete the row for `key`.  Returns 0 on success, -1 on error.
 */
int y2_db_delete(y2_db *db, const char *key);

/**
 * Check whether `key` exists.
 */
bool y2_db_exists(y2_db *db, const char *key);

/* ── Maintenance ───────────────────────────────────────────────────── */

/**
 * Execute a WAL checkpoint to flush pending writes.
 */
void y2_db_checkpoint(y2_db *db);

/**
 * Return the SQLite version string (e.g. "3.42.0").
 */
const char *y2_sqlite_version(void);

#ifdef __cplusplus
}
#endif

#endif /* Y2_SQLITE_H */
