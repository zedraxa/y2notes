/*
 *  y2_levenshtein.c
 *  Y2Notes
 *
 *  SIMD-optimized Wagner-Fischer Levenshtein edit distance.
 *  Uses Arm NEON intrinsics for min operations in the DP inner loop.
 *  Falls back to scalar on other architectures.
 */

#include "y2_levenshtein.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define Y2_HAS_NEON 1
#else
#define Y2_HAS_NEON 0
#endif

// ─── Helpers ───────────────────────────────────────────────────────

static inline int min2(int a, int b) { return a < b ? a : b; }
static inline int min3(int a, int b, int c) {
    int m = a < b ? a : b;
    return m < c ? m : c;
}

// ─── Core Wagner-Fischer ───────────────────────────────────────────

int y2_levenshtein_distance(const uint32_t *src, int srcLen,
                            const uint32_t *tgt, int tgtLen) {
    /* Make the shorter string the column dimension for O(min(m,n)) space. */
    if (srcLen < tgtLen) {
        const uint32_t *tmp = src; src = tgt; tgt = tmp;
        int tl = srcLen; srcLen = tgtLen; tgtLen = tl;
    }
    if (tgtLen == 0) return srcLen;

    const int n = tgtLen;

    /* Allocate two rows. Using stack for small strings, heap for large. */
    int stackBuf[512];
    int *prevRow, *currRow, *allocPtr = NULL;
    bool usedHeap = false;

    if ((n + 1) * 2 <= 512) {
        prevRow = stackBuf;
        currRow = stackBuf + (n + 1);
    } else {
        allocPtr = (int *)malloc((size_t)(n + 1) * 2 * sizeof(int));
        if (!allocPtr) return -1;
        prevRow = allocPtr;
        currRow = allocPtr + (n + 1);
        usedHeap = true;
    }

    /* Initialise prevRow = [0, 1, 2, …, n] */
    for (int j = 0; j <= n; j++) {
        prevRow[j] = j;
    }

    /* Fill DP table row by row. */
    for (int i = 1; i <= srcLen; i++) {
        currRow[0] = i;
        const uint32_t sc = src[i - 1];

#if Y2_HAS_NEON
        /*
         * NEON-accelerated inner loop: process 4 columns at a time.
         * For each column j, we compute:
         *   cost = (src[i-1] == tgt[j-1]) ? 0 : 1
         *   currRow[j] = min(currRow[j-1]+1, prevRow[j]+1, prevRow[j-1]+cost)
         *
         * The min of deletion (prevRow[j]+1) values can be done in
         * SIMD batches, then combined with scalar insert/substitute.
         * However, the dependency on currRow[j-1] makes full vectorisation
         * of the recurrence non-trivial.  We instead vectorise the
         * prevRow[j]+1 and prevRow[j-1]+cost computations, then do
         * the serial min with currRow[j-1]+1.
         */
        int j = 1;

        /* Process blocks of 4 using NEON for the two independent terms. */
        for (; j + 3 <= n; j += 4) {
            /* Load prevRow[j..j+3] (deletion source) */
            int32x4_t del = vld1q_s32(&prevRow[j]);
            int32x4_t del1 = vaddq_s32(del, vdupq_n_s32(1));

            /* Load prevRow[j-1..j+2] (substitution source) */
            int32x4_t sub = vld1q_s32(&prevRow[j - 1]);

            /* Build cost vector: 0 if match, 1 if mismatch */
            uint32_t tgtChars[4] = {
                tgt[j - 1], tgt[j], tgt[j + 1], tgt[j + 2]
            };
            uint32x4_t tc = vld1q_u32(tgtChars);
            uint32x4_t sc4 = vdupq_n_u32(sc);
            uint32x4_t eq = vceqq_u32(tc, sc4);
            int32x4_t cost = vbicq_s32(vdupq_n_s32(1),
                                       vreinterpretq_s32_u32(eq));

            /* sub + cost = prevRow[j-1] + (match ? 0 : 1) */
            int32x4_t sub_cost = vaddq_s32(sub, cost);

            /* candidate = min(del1, sub_cost) */
            int32x4_t candidate = vminq_s32(del1, sub_cost);

            /* Now we must include the serial dependency: ins = currRow[j-1]+1
             * We extract lanes and do the serial chain. */
            int cand[4];
            vst1q_s32(cand, candidate);

            currRow[j]     = min2(currRow[j - 1] + 1, cand[0]);
            currRow[j + 1] = min2(currRow[j]     + 1, cand[1]);
            currRow[j + 2] = min2(currRow[j + 1] + 1, cand[2]);
            currRow[j + 3] = min2(currRow[j + 2] + 1, cand[3]);
        }

        /* Scalar tail for remaining columns. */
        for (; j <= n; j++) {
            int cost = (sc == tgt[j - 1]) ? 0 : 1;
            currRow[j] = min3(
                currRow[j - 1] + 1,
                prevRow[j] + 1,
                prevRow[j - 1] + cost
            );
        }
#else
        for (int j = 1; j <= n; j++) {
            int cost = (sc == tgt[j - 1]) ? 0 : 1;
            currRow[j] = min3(
                currRow[j - 1] + 1,
                prevRow[j] + 1,
                prevRow[j - 1] + cost
            );
        }
#endif

        /* Swap rows. */
        int *tmp = prevRow;
        prevRow = currRow;
        currRow = tmp;
    }

    int result = prevRow[n];
    if (usedHeap) free(allocPtr);
    return result;
}

double y2_levenshtein_similarity(const uint32_t *src, int srcLen,
                                 const uint32_t *tgt, int tgtLen) {
    int maxLen = srcLen > tgtLen ? srcLen : tgtLen;
    if (maxLen == 0) return 1.0;
    int dist = y2_levenshtein_distance(src, srcLen, tgt, tgtLen);
    return 1.0 - (double)dist / (double)maxLen;
}

void y2_levenshtein_batch(const uint32_t *query, int queryLen,
                          const uint32_t *const *targets,
                          const int *targetLens,
                          int count,
                          int *outDistances) {
    for (int i = 0; i < count; i++) {
        outDistances[i] = y2_levenshtein_distance(
            query, queryLen, targets[i], targetLens[i]);
    }
}
