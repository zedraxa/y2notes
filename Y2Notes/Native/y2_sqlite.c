/*
 *  y2_sqlite.c
 *  Y2Notes
 *
 *  Lightweight C SQLite persistence layer for Y2Notes.
 *  Implements a key-value store backed by a single SQLite table.
 *  WAL mode is enabled for concurrent read/write performance.
 *
 *  Uses the system SQLite (libsqlite3) that ships with iOS.
 */

#include "y2_sqlite.h"
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ── Opaque handle ──────────────────────────────────────────────────── */

struct y2_db {
    sqlite3 *handle;
    /* Prepared statements for hot path */
    sqlite3_stmt *stmt_write;
    sqlite3_stmt *stmt_read;
    sqlite3_stmt *stmt_delete;
    sqlite3_stmt *stmt_exists;
};

/* ── Schema ─────────────────────────────────────────────────────────── */

static const char *kCreateTable =
    "CREATE TABLE IF NOT EXISTS kv_store ("
    "  key   TEXT PRIMARY KEY NOT NULL,"
    "  value BLOB NOT NULL,"
    "  updated_at INTEGER NOT NULL DEFAULT (strftime('%%s','now'))"
    ");";

static const char *kCreateSchemaVersion =
    "CREATE TABLE IF NOT EXISTS schema_version ("
    "  version INTEGER NOT NULL"
    ");";

static const int kCurrentSchemaVersion = 1;

/* ── Forward declarations ───────────────────────────────────────────── */

static int prepare_statements(y2_db *db);
static int run_migrations(y2_db *db);
static int get_schema_version(y2_db *db);
static int set_schema_version(y2_db *db, int version);

/* ── Lifecycle ──────────────────────────────────────────────────────── */

y2_db *y2_db_open(const char *path) {
    if (!path) return NULL;

    y2_db *db = calloc(1, sizeof(y2_db));
    if (!db) return NULL;

    int rc = sqlite3_open_v2(path, &db->handle,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        NULL);
    if (rc != SQLITE_OK) {
        free(db);
        return NULL;
    }

    /* Enable WAL mode for concurrent readers + single writer. */
    sqlite3_exec(db->handle, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
    /* Busy timeout: 5 seconds. */
    sqlite3_busy_timeout(db->handle, 5000);
    /* Foreign keys (for future use). */
    sqlite3_exec(db->handle, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL);

    /* Create schema. */
    char *errmsg = NULL;
    rc = sqlite3_exec(db->handle, kCreateTable, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        sqlite3_free(errmsg);
        sqlite3_close(db->handle);
        free(db);
        return NULL;
    }

    rc = sqlite3_exec(db->handle, kCreateSchemaVersion, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        sqlite3_free(errmsg);
        sqlite3_close(db->handle);
        free(db);
        return NULL;
    }

    /* Run migrations. */
    if (run_migrations(db) != 0) {
        sqlite3_close(db->handle);
        free(db);
        return NULL;
    }

    /* Prepare statements. */
    if (prepare_statements(db) != 0) {
        sqlite3_close(db->handle);
        free(db);
        return NULL;
    }

    return db;
}

void y2_db_close(y2_db *db) {
    if (!db) return;

    if (db->stmt_write)  sqlite3_finalize(db->stmt_write);
    if (db->stmt_read)   sqlite3_finalize(db->stmt_read);
    if (db->stmt_delete) sqlite3_finalize(db->stmt_delete);
    if (db->stmt_exists) sqlite3_finalize(db->stmt_exists);

    /* Checkpoint WAL before closing. */
    sqlite3_wal_checkpoint_v2(db->handle, NULL, SQLITE_CHECKPOINT_TRUNCATE,
                               NULL, NULL);
    sqlite3_close(db->handle);
    free(db);
}

/* ── Key-value CRUD ─────────────────────────────────────────────────── */

int y2_db_write(y2_db *db, const char *key, const void *data, uint32_t length) {
    if (!db || !key || !data) return -1;

    sqlite3_stmt *s = db->stmt_write;
    sqlite3_reset(s);
    sqlite3_bind_text(s, 1, key, -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(s, 2, data, (int)length, SQLITE_TRANSIENT);

    int rc = sqlite3_step(s);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int y2_db_read(y2_db *db, const char *key, void **out_data, uint32_t *out_length) {
    if (!db || !key || !out_data || !out_length) return -1;

    *out_data = NULL;
    *out_length = 0;

    sqlite3_stmt *s = db->stmt_read;
    sqlite3_reset(s);
    sqlite3_bind_text(s, 1, key, -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(s);
    if (rc == SQLITE_ROW) {
        int len = sqlite3_column_bytes(s, 0);
        const void *blob = sqlite3_column_blob(s, 0);
        if (blob && len > 0) {
            *out_data = malloc((size_t)len);
            if (!*out_data) return -1;
            memcpy(*out_data, blob, (size_t)len);
            *out_length = (uint32_t)len;
        }
        return 0;
    } else if (rc == SQLITE_DONE) {
        return 1;  /* Key not found */
    }
    return -1;
}

int y2_db_delete(y2_db *db, const char *key) {
    if (!db || !key) return -1;

    sqlite3_stmt *s = db->stmt_delete;
    sqlite3_reset(s);
    sqlite3_bind_text(s, 1, key, -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(s);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

bool y2_db_exists(y2_db *db, const char *key) {
    if (!db || !key) return false;

    sqlite3_stmt *s = db->stmt_exists;
    sqlite3_reset(s);
    sqlite3_bind_text(s, 1, key, -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(s);
    if (rc == SQLITE_ROW) {
        int count = sqlite3_column_int(s, 0);
        return count > 0;
    }
    return false;
}

/* ── Maintenance ────────────────────────────────────────────────────── */

void y2_db_checkpoint(y2_db *db) {
    if (!db) return;
    sqlite3_wal_checkpoint_v2(db->handle, NULL, SQLITE_CHECKPOINT_PASSIVE,
                               NULL, NULL);
}

const char *y2_sqlite_version(void) {
    return sqlite3_libversion();
}

/* ── Internal helpers ───────────────────────────────────────────────── */

static int prepare_statements(y2_db *db) {
    int rc;

    rc = sqlite3_prepare_v2(db->handle,
        "INSERT OR REPLACE INTO kv_store (key, value, updated_at) "
        "VALUES (?1, ?2, strftime('%s','now'));",
        -1, &db->stmt_write, NULL);
    if (rc != SQLITE_OK) return -1;

    rc = sqlite3_prepare_v2(db->handle,
        "SELECT value FROM kv_store WHERE key = ?1;",
        -1, &db->stmt_read, NULL);
    if (rc != SQLITE_OK) return -1;

    rc = sqlite3_prepare_v2(db->handle,
        "DELETE FROM kv_store WHERE key = ?1;",
        -1, &db->stmt_delete, NULL);
    if (rc != SQLITE_OK) return -1;

    rc = sqlite3_prepare_v2(db->handle,
        "SELECT COUNT(*) FROM kv_store WHERE key = ?1;",
        -1, &db->stmt_exists, NULL);
    if (rc != SQLITE_OK) return -1;

    return 0;
}

static int get_schema_version(y2_db *db) {
    sqlite3_stmt *s = NULL;
    int rc = sqlite3_prepare_v2(db->handle,
        "SELECT version FROM schema_version LIMIT 1;",
        -1, &s, NULL);
    if (rc != SQLITE_OK) { sqlite3_finalize(s); return 0; }

    int version = 0;
    if (sqlite3_step(s) == SQLITE_ROW) {
        version = sqlite3_column_int(s, 0);
    }
    sqlite3_finalize(s);
    return version;
}

static int set_schema_version(y2_db *db, int version) {
    char sql[128];
    snprintf(sql, sizeof(sql),
        "DELETE FROM schema_version; INSERT INTO schema_version VALUES (%d);",
        version);
    return sqlite3_exec(db->handle, sql, NULL, NULL, NULL) == SQLITE_OK ? 0 : -1;
}

static int run_migrations(y2_db *db) {
    int current = get_schema_version(db);

    if (current < 1) {
        /* v0 → v1: initial schema (kv_store table already created above). */
        if (set_schema_version(db, 1) != 0) return -1;
    }

    /* Future migrations go here:
     * if (current < 2) { ... migrate v1→v2 ... set_schema_version(db, 2); }
     */

    return 0;
}
