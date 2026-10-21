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

#ifndef ZENOH_PICO_UTILS_TIME_RANGE_H
#define ZENOH_PICO_UTILS_TIME_RANGE_H

#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/string.h"

#ifdef __cplusplus
extern "C" {
#endif

static const double _Z_TIME_RANGE_U_TO_SECS = 0.000001;
static const double _Z_TIME_RANGE_MS_TO_SECS = 0.001;
static const double _Z_TIME_RANGE_M_TO_SECS = 60.0;
static const double _Z_TIME_RANGE_H_TO_SECS = 3600.0;
static const double _Z_TIME_RANGE_D_TO_SECS = 86400.0;
static const double _Z_TIME_RANGE_W_TO_SECS = 604800.0;

typedef struct {
    enum { _Z_TIME_BOUND_INCLUSIVE, _Z_TIME_BOUND_EXCLUSIVE, _Z_TIME_BOUND_UNBOUNDED } bound;
    double now_offset;
} _z_time_bound_t;

typedef struct {
    _z_time_bound_t start;
    _z_time_bound_t end;
} _z_time_range_t;

/**
 * Parse a time range from a string.
 *
 * Returns true if the string contained a valid time range, false otherwise.
 * If valid range will contain the result.
 */
bool _z_time_range_from_str(const char *str, size_t len, _z_time_range_t *range);

/**
 * Converts a time bound into a string.
 *
 * Returns true if the time bound was successfully converted, false otherwise.
 * If valid buf will contain the result.
 */
bool _z_time_bound_to_str(const _z_time_bound_t *bound, char *buf, size_t buf_len);

/**
 * Converts a time range into a string.
 *
 * Returns true if the time range was successfully converted, false otherwise.
 * If valid buf will contain the result.
 */
bool _z_time_range_to_str(const _z_time_range_t *range, char *buf, size_t buf_len);

/**
 * Resolves an offset to a base time.
 *
 * Returns the offset time.
 */
_z_ntp64_t _z_time_range_resolve_offset(_z_ntp64_t base, double offset);

/**
 * Checks if a timestamp is contained within a time range at the specified time.
 *
 * Returns true if the timestamp is containend in the time range, false otherwise.
 */
bool _z_time_range_contains_at_time(const _z_time_range_t *range, const _z_ntp64_t timestamp, const _z_ntp64_t time);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_TIME_RANGE_H */
