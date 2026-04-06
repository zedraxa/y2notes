/*
 *  y2_levenshtein.h
 *  Y2Notes
 *
 *  SIMD-optimized Levenshtein edit distance (Wagner-Fischer DP).
 *  Provides single-pair and batch-distance computation for the
 *  fuzzy search subsystem.
 *
 *  All functions are thread-safe (no mutable global state).
 */

#ifndef Y2_LEVENSHTEIN_H
#define Y2_LEVENSHTEIN_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Compute the Levenshtein edit distance between two UTF-8 strings
/// operating on Unicode scalar values.
/// Uses O(min(m,n)) space Wagner-Fischer DP with NEON-accelerated
/// min operations on Apple Silicon.
///
/// Returns the minimum number of single-character edits (insert,
/// delete, substitute) required to transform `src` into `tgt`.
int y2_levenshtein_distance(const uint32_t *src, int srcLen,
                            const uint32_t *tgt, int tgtLen);

/// Normalised similarity in [0, 1] where 1.0 = identical.
/// sim = 1 − distance / max(srcLen, tgtLen).
double y2_levenshtein_similarity(const uint32_t *src, int srcLen,
                                 const uint32_t *tgt, int tgtLen);

/// Batch: compute distances from one query to many targets.
/// Writes `count` distances into `outDistances` (pre-allocated).
///
/// Each target is given as a (pointer, length) pair:
///   targets[i]    → pointer to uint32_t scalar array
///   targetLens[i] → length of that array
void y2_levenshtein_batch(const uint32_t *query, int queryLen,
                          const uint32_t *const *targets,
                          const int *targetLens,
                          int count,
                          int *outDistances);

#ifdef __cplusplus
}
#endif

#endif /* Y2_LEVENSHTEIN_H */
