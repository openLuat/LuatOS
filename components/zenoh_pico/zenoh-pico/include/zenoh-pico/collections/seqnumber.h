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

#ifndef ZENOH_PICO_COLLECTIONS_SEQNUMBER_H
#define ZENOH_PICO_COLLECTIONS_SEQNUMBER_H

#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Compute the next sequence number after `last` in 32-bit serial number space.
 * Wraps from UINT32_MAX back to 0.
 */
static inline uint32_t _z_seqnumber_next(uint32_t last) { return (last == UINT32_MAX) ? 0u : (last + 1u); }

/*
 * Test whether `current` is the immediate successor of `last` in
 * 32-bit serial number space (wrap-safe).
 */
static inline bool _z_seqnumber_is_next(uint32_t last, uint32_t current) {
    return (current == _z_seqnumber_next(last));
}

/*
 * Compute the previous sequence number before `current` in 32-bit serial number space.
 * Wraps from 0 back to UINT32_MAX.
 */
static inline uint32_t _z_seqnumber_prev(uint32_t current) { return (current == 0u) ? UINT32_MAX : (current - 1u); }

/*
 * Test whether `current` is the immediate predecessor of `last` in
 * 32-bit serial number space (wrap-safe).
 */
static inline bool _z_seqnumber_is_prev(uint32_t last, uint32_t current) {
    return (current == _z_seqnumber_prev(last));
}

/*
 * Compute signed wrap-safe difference between two 32-bit sequence numbers.
 * Positive if 'a' is newer than 'b', negative if older, zero if equal.
 * Follows RFC 1982 serial number arithmetic.
 *
 * Range: [-2^31+1, 2^31-1]
 */
static inline int64_t _z_seqnumber_diff(uint32_t a, uint32_t b) { return (int64_t)((int32_t)(a - b)); }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_SEQNUMBER_H */
