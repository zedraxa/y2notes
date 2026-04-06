/*
 *  Y2Notes-Bridging-Header.h
 *  Y2Notes
 *
 *  Objective-C / C bridging header for Swift interop.
 *  Exposes SIMD-optimized C implementations of performance-critical
 *  algorithms (Perlin noise, SPH fluid simulation) to Swift.
 */

#ifndef Y2Notes_Bridging_Header_h
#define Y2Notes_Bridging_Header_h

#include "Native/y2_perlin.h"
#include "Native/y2_sph.h"

#endif /* Y2Notes_Bridging_Header_h */
