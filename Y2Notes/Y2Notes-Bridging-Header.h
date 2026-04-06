/*
 *  Y2Notes-Bridging-Header.h
 *  Y2Notes
 *
 *  Objective-C / C bridging header for Swift interop.
 *  Exposes SIMD-optimized C implementations of performance-critical
 *  algorithms to Swift: Perlin noise, SPH fluid, OKLAB color science,
 *  and Levenshtein edit distance.
 */

#ifndef Y2Notes_Bridging_Header_h
#define Y2Notes_Bridging_Header_h

#include "Native/y2_perlin.h"
#include "Native/y2_sph.h"
#include "Native/y2_color.h"
#include "Native/y2_levenshtein.h"
#include "Native/y2_sqlite.h"

/* Rust data layer FFI (libY2Data) */
#include "../RustData/include/y2data.h"

#endif /* Y2Notes_Bridging_Header_h */
