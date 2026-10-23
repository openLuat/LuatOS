//
// Copyright (c) 2025 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//

#ifndef ZENOH_PICO_UTILS_HASH_H
#define ZENOH_PICO_UTILS_HASH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Define FNV1a parameters for 32 and 64-bit platforms
#if SIZE_MAX == UINT64_MAX
#define _Z_FNV_OFFSET_BASIS 14695981039346656037ULL
#define _Z_FNV_PRIME 1099511628211ULL
#elif SIZE_MAX == UINT32_MAX
#define _Z_FNV_OFFSET_BASIS 2166136261U
#define _Z_FNV_PRIME 16777619U
#else
#error "Unsupported size_t size"
#endif

static inline size_t _z_hash_combine(size_t h1, size_t h2) {
    h1 ^= h2;
    h1 *= _Z_FNV_PRIME;
    return h1;
}

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_HASH_H */
