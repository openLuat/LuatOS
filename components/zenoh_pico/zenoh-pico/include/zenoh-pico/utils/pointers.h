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

#ifndef ZENOH_PICO_UTILS_POINTERS_H
#define ZENOH_PICO_UTILS_POINTERS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Computes the distance between two ``uint8_t`` pointers as an absolute value.
 * Note that ``l_ptr`` must be higher than ``r_ptr``.
 *
 * Parameters:
 *   l_ptr: The first pointer.
 *   r_ptr: The second pointer.
 *
 * Returns:
 *   Returns the distance between the pointers as an absolute value.
 */
static inline size_t _z_ptr_u8_diff(const uint8_t *l_ptr, const uint8_t *r_ptr) { return (size_t)(l_ptr - r_ptr); }

/**
 * Offsets a ``uint8_t`` pointer by a given distance. Offsets can be both positive and negative values.
 *
 * Parameters:
 *   ptr: The pointer to offset.
 *   off: The offset distance to be applied.
 *
 * Returns:
 *   Returns a ``const uint8_t`` pointer, pointing to the offset position.
 */
const uint8_t *_z_cptr_u8_offset(const uint8_t *ptr, ptrdiff_t off);

/**
 * Offsets a ``uint8_t`` pointer by a given distance. Offsets can be both positive and negative values.
 *
 * Parameters:
 *   ptr: The pointer to offset.
 *   off: The offset distance to be applied.
 *
 * Returns:
 *   Returns a ``uint8_t`` pointer, pointing to the offset position.
 */
static inline uint8_t *_z_ptr_u8_offset(uint8_t *ptr, const ptrdiff_t off) { return ptr + off; }

/**
 * Computes the distance between two ``char`` pointers as an absolute value.
 * Note that ``l_ptr`` must be higher than ``r_ptr``.
 *
 * Parameters:
 *   l_ptr: The first pointer.
 *   r_ptr: The second pointer.
 *
 * Returns:
 *   Returns the distance between the pointers as an absolute value.
 */
static inline size_t _z_ptr_char_diff(const char *l_ptr, const char *r_ptr) { return (size_t)(l_ptr - r_ptr); }

/**
 * Offsets a ``char`` pointer by a given distance. Offsets can be both positive and negative values.
 *
 * Parameters:
 *   ptr: The pointer to offset.
 *   off: The offset distance to be applied.
 *
 * Returns:
 *   Returns a ``const char`` pointer, pointing to the offset position.
 */
const char *_z_cptr_char_offset(const char *ptr, ptrdiff_t off);

/**
 * Offsets a ``char`` pointer by a given distance. Offsets can be both positive and negative values.
 *
 * Parameters:
 *   ptr: The pointer to offset.
 *   off: The offset distance to be applied.
 *
 * Returns:
 *   Returns a ``char`` pointer, pointing to the offset position.
 */
static inline char *_z_ptr_char_offset(char *ptr, const ptrdiff_t off) { return ptr + off; }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_POINTERS_H */
