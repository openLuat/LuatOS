//
// Copyright (c) 2022 ZettaScale Technology
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

#ifndef ZENOH_PICO_UTILS_ENDIANNESS_H
#define ZENOH_PICO_UTILS_ENDIANNESS_H

#include <stdint.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

#if !defined(ZENOH_ENDIANNNESS_BIG) && !defined(ZENOH_ENDIANNNESS_LITTLE)
// Gcc/clang test
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define ZENOH_ENDIANNNESS_BIG
#else
#define ZENOH_ENDIANNNESS_LITTLE
#endif
#endif

// Load int from memory with specified endianness

// *** Little endian ***
#define _Z_LE_LOAD_IMPL(SIZE)                                           \
    static inline uint##SIZE##_t _z_le_load##SIZE(const uint8_t *src) { \
        uint##SIZE##_t val = 0;                                         \
        for (size_t i = sizeof(val); i != 0; --i) {                     \
            val = val << 8;                                             \
            val = (uint##SIZE##_t)(val | src[i - 1]);                   \
        }                                                               \
        return val;                                                     \
    }

#define _Z_LE_STORE_IMPL(SIZE)                                               \
    static inline void _z_le_store##SIZE(uint##SIZE##_t val, uint8_t *dst) { \
        for (size_t i = 0; i < sizeof(val); ++i) {                           \
            dst[i] = (uint8_t)val;                                           \
            val = val >> 8;                                                  \
        }                                                                    \
    }

_Z_LE_LOAD_IMPL(16)
_Z_LE_LOAD_IMPL(32)
_Z_LE_LOAD_IMPL(64)

_Z_LE_STORE_IMPL(16)
_Z_LE_STORE_IMPL(32)
_Z_LE_STORE_IMPL(64)

#undef _Z_LE_LOAD_IMPL
#undef _Z_LE_STORE_IMPL

// *** Big endian ***
#define _Z_BE_LOAD_IMPL(SIZE)                                           \
    static inline uint##SIZE##_t _z_be_load##SIZE(const uint8_t *src) { \
        uint##SIZE##_t val = 0;                                         \
        for (size_t i = 0; i < sizeof(val); ++i) {                      \
            val = val << 8;                                             \
            val = (uint##SIZE##_t)(val | src[i]);                       \
        }                                                               \
        return val;                                                     \
    }

#define _Z_BE_STORE_IMPL(SIZE)                                               \
    static inline void _z_be_store##SIZE(uint##SIZE##_t val, uint8_t *dst) { \
        for (size_t i = sizeof(val); i != 0; --i) {                          \
            dst[i - 1] = (uint8_t)val;                                       \
            val = val >> 8;                                                  \
        }                                                                    \
    }

_Z_BE_LOAD_IMPL(16)
_Z_BE_LOAD_IMPL(32)
_Z_BE_LOAD_IMPL(64)

_Z_BE_STORE_IMPL(16)
_Z_BE_STORE_IMPL(32)
_Z_BE_STORE_IMPL(64)

#undef _Z_BE_LOAD_IMPL
#undef _Z_BE_STORE_IMPL

// *** Host ***
static inline uint16_t _z_host_le_load8(const uint8_t *src) { return src[0]; }

static inline uint16_t _z_host_le_load16(const uint8_t *src) {
#if defined(ZENOH_ENDIANNNESS_BIG)
    return _z_be_load16(src);
#elif defined(ZENOH_ENDIANNNESS_LITTLE)
    return _z_le_load16(src);
#endif
}

static inline uint32_t _z_host_le_load32(const uint8_t *src) {
#if defined(ZENOH_ENDIANNNESS_BIG)
    return _z_be_load32(src);
#elif defined(ZENOH_ENDIANNNESS_LITTLE)
    return _z_le_load32(src);
#endif
}

static inline uint64_t _z_host_le_load64(const uint8_t *src) {
#if defined(ZENOH_ENDIANNNESS_BIG)
    return _z_be_load64(src);
#elif defined(ZENOH_ENDIANNNESS_LITTLE)
    return _z_le_load64(src);
#endif
}

static inline void _z_host_le_store8(const uint8_t val, uint8_t *dst) { dst[0] = val; }

static inline void _z_host_le_store16(const uint16_t val, uint8_t *dst) {
#if defined(ZENOH_ENDIANNNESS_BIG)
    _z_be_store16(val, dst);
#elif defined(ZENOH_ENDIANNNESS_LITTLE)
    _z_le_store16(val, dst);
#endif
}

static inline void _z_host_le_store32(const uint32_t val, uint8_t *dst) {
#if defined(ZENOH_ENDIANNNESS_BIG)
    _z_be_store32(val, dst);
#elif defined(ZENOH_ENDIANNNESS_LITTLE)
    _z_le_store32(val, dst);
#endif
}

static inline void _z_host_le_store64(const uint64_t val, uint8_t *dst) {
#if defined(ZENOH_ENDIANNNESS_BIG)
    _z_be_store64(val, dst);
#elif defined(ZENOH_ENDIANNNESS_LITTLE)
    _z_le_store64(val, dst);
#endif
}

static inline void _z_host_u16_from_le_u16(uint16_t *val) {
#if defined(ZENOH_ENDIANNNESS_BIG)
    uint16_t tmp = (uint16_t)((*val & 0x00FF) << 8) + (uint16_t)((*val & 0xFF00) >> 8);
    *val = tmp;
#elif defined(ZENOH_ENDIANNNESS_LITTLE)
    _ZP_UNUSED(val);
    return;
#endif
}

// Return u16 individual bytes
static inline uint8_t _z_get_u16_lsb(uint_fast16_t val) { return (uint8_t)(val >> 0); }
static inline uint8_t _z_get_u16_msb(uint_fast16_t val) { return (uint8_t)(val >> 8); }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_ENDIANNESS_H */
