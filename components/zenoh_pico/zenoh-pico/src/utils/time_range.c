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

#include "zenoh-pico/utils/time_range.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"
#include "zenoh-pico/utils/string.h"

/**
 * Parses a _z_str_se_t as a duration.
 * Expected format is a double in seconds, or "<double><unit>" where <unit> is:
 *  - 'u'  => microseconds
 *  - "ms" => milliseconds
 *  - 's' => seconds
 *  - 'm' => minutes
 *  - 'h' => hours
 *  - 'd' => days
 *  - 'w' => weeks
 *
 * Returns true if the duration is successfully parsed, false otherwise.
 * If true, duration will contain the parsed duration on return.
 */
static bool _z_time_range_parse_duration(const _z_str_se_t *bound, double *duration) {
    size_t len = _z_ptr_char_diff(bound->end, bound->start);
    if (len == 0) {
        return false;
    }

    double multiplier = 1.0;
    switch (*_z_cptr_char_offset(bound->end, -1)) {
        case 'u':
            multiplier = _Z_TIME_RANGE_U_TO_SECS;
            len--;
            break;
        case 's':
            if (len > 1 && *_z_cptr_char_offset(bound->end, -2) == 'm') {
                multiplier = _Z_TIME_RANGE_MS_TO_SECS;
                len--;
            }
            len--;
            break;
        case 'm':
            multiplier = _Z_TIME_RANGE_M_TO_SECS;
            len--;
            break;
        case 'h':
            multiplier = _Z_TIME_RANGE_H_TO_SECS;
            len--;
            break;
        case 'd':
            multiplier = _Z_TIME_RANGE_D_TO_SECS;
            len--;
            break;
        case 'w':
            multiplier = _Z_TIME_RANGE_W_TO_SECS;
            len--;
            break;
    }

    // String contains unit only
    if (len == 0) {
        return false;
    }

    char *buf = z_malloc(len + 1);
    if (buf == NULL) {
        _Z_ERROR("Failed to allocate buffer.");
        return false;
    }
    size_t offset = 0;
    if (!_z_memcpy_checked(buf, len + 1, &offset, bound->start, len)) {
        z_free(buf);
        return false;
    }
    buf[len] = '\0';
    char *err;
    double value = strtod(bound->start, &err);
    z_free(buf);
    if (value == 0 && *err != '\0') {
        return false;
    }
    value *= multiplier;

    // Check for overflow
    if (isinf(value)) {
        return false;
    }

    *duration = value;
    return true;
}

static bool _z_time_range_parse_time_bound(_z_str_se_t *str, bool inclusive, _z_time_bound_t *bound) {
    size_t len = _z_ptr_char_diff(str->end, str->start);
    if (len == 0) {
        bound->bound = _Z_TIME_BOUND_UNBOUNDED;
        return true;
    } else if (len >= 5) {
        bound->bound = inclusive ? _Z_TIME_BOUND_INCLUSIVE : _Z_TIME_BOUND_EXCLUSIVE;

        if (*str->start == 'n' && *_z_cptr_char_offset(str->start, 1) == 'o' &&
            *_z_cptr_char_offset(str->start, 2) == 'w' && *_z_cptr_char_offset(str->start, 3) == '(' &&
            *_z_cptr_char_offset(str->end, -1) == ')') {
            if (len == 5) {
                bound->now_offset = 0;
            } else {
                _z_str_se_t duration = {.start = _z_cptr_char_offset(str->start, 4),
                                        .end = _z_cptr_char_offset(str->end, -1)};

                if (!_z_time_range_parse_duration(&duration, &bound->now_offset)) {
                    return false;
                }
            }
            return true;
        }
        // TODO: Add support for RFC3339 timestamps
    }
    return false;
}

bool _z_time_range_from_str(const char *str, size_t len, _z_time_range_t *range) {
    // Minimum length is 4 "[..]"
    if (len < 4) {
        return false;
    }

    bool inclusive_start;
    switch (str[0]) {
        case '[':
            inclusive_start = true;
            break;
        case ']':
            inclusive_start = false;
            break;
        default:
            return false;
    }

    bool inclusive_end;
    switch (str[len - 1]) {
        case '[':
            inclusive_end = false;
            break;
        case ']':
            inclusive_end = true;
            break;
        default:
            return false;
    }

    // Search for '..'
    const char *separator =
        _z_strstr(_z_cptr_char_offset(str, 1), _z_cptr_char_offset(str, (ptrdiff_t)(len - 1)), "..");
    if (separator != NULL) {
        _z_str_se_t start_str = {.start = _z_cptr_char_offset(str, 1), .end = separator};
        _z_str_se_t end_str = {.start = _z_cptr_char_offset(separator, 2),
                               .end = _z_cptr_char_offset(str, (ptrdiff_t)(len - 1))};

        if (!_z_time_range_parse_time_bound(&start_str, inclusive_start, &range->start) ||
            !_z_time_range_parse_time_bound(&end_str, inclusive_end, &range->end)) {
            return false;
        }
    } else {
        // Search for ';'
        separator = _z_strstr(_z_cptr_char_offset(str, 1), _z_cptr_char_offset(str, (ptrdiff_t)(len - 1)), ";");
        if (separator == NULL) {
            return false;
        }

        _z_str_se_t start_str = {.start = _z_cptr_char_offset(str, 1), .end = separator};
        _z_str_se_t end_str = {.start = _z_cptr_char_offset(separator, 1),
                               .end = _z_cptr_char_offset(str, (ptrdiff_t)(len - 1))};

        if (!_z_time_range_parse_time_bound(&start_str, inclusive_start, &range->start) ||
            range->start.bound == _Z_TIME_BOUND_UNBOUNDED) {
            return false;
        }

        double duration;
        if (!_z_time_range_parse_duration(&end_str, &duration)) {
            return false;
        }
        range->end.bound = inclusive_end ? _Z_TIME_BOUND_INCLUSIVE : _Z_TIME_BOUND_EXCLUSIVE;
        range->end.now_offset = range->start.now_offset + duration;
    }

    return true;
}

static bool _z_time_bound_delim_to_char(const _z_time_bound_t *bound, bool is_start, char *delim) {
    if (bound == NULL || delim == NULL) {
        return false;
    }
    switch (bound->bound) {
        case _Z_TIME_BOUND_INCLUSIVE:
            *delim = is_start ? '[' : ']';
            break;
        case _Z_TIME_BOUND_EXCLUSIVE:
            *delim = is_start ? ']' : '[';
            break;
        case _Z_TIME_BOUND_UNBOUNDED:
            *delim = is_start ? '[' : ']';
            break;
        default:
            return false;
    }
    return true;
}

bool _z_time_bound_to_str(const _z_time_bound_t *bound, char *buf, size_t buf_len) {
    if (bound == NULL || buf == NULL || buf_len < 1) {
        return false;  // Not enough space for at least '\0'
    }

    if (bound->bound == _Z_TIME_BOUND_UNBOUNDED) {
        buf[0] = '\0';
        return true;
    }

    size_t pos = 0;

    // Ensure enough space for "now("
    if (buf_len < 4) {
        return false;
    }
    buf[pos++] = 'n';
    buf[pos++] = 'o';
    buf[pos++] = 'w';
    buf[pos++] = '(';

    if (bound->now_offset != 0.0) {
        int len = snprintf(&buf[pos], buf_len - pos, "%.17f", bound->now_offset);
        if (len < 0 || (size_t)len >= buf_len - pos) {
            return false;  // Not enough space for the formatted string
        }

        // Trim trailing zeros and decimal point if no fractions remain
        char *start = &buf[pos];
        char *dot = strchr(start, '.');
        if (dot != NULL) {
            size_t remaining = buf_len - pos;
            size_t str_len = strnlen(start, remaining);
            if (str_len == remaining) {
                // Null terminator not found within bounds
                return false;
            }
            char *end = start + str_len - 1;
            while (end > dot && *end == '0') {
                *end-- = '\0';
            }
            if (end == dot) {
                *end = '\0';  // remove trailing '.'
            }
        }

        size_t remaining = buf_len - pos;
        size_t str_len = strnlen(start, remaining);
        if (str_len == remaining) {
            // Null terminator not found within bounds
            return false;
        }
        pos += str_len;

        if (buf_len - pos < 1) {
            return false;  // Not enough space for 's'
        }
        buf[pos++] = 's';
    }

    if (buf_len - pos < 2) {
        return false;  // Not enough space for ")\0"
    }

    buf[pos++] = ')';
    buf[pos++] = '\0';
    return true;
}

bool _z_time_range_to_str(const _z_time_range_t *range, char *buf, size_t buf_len) {
    size_t pos = 0;

    if (range == NULL || buf == NULL || buf_len < 3) {
        return false;  // Not enough space for at least "[]"
    }

    if (!_z_time_bound_delim_to_char(&range->start, true, &buf[pos++])) {
        return false;  // Invalid bound delimiter
    }

    if (range->start.bound == _Z_TIME_BOUND_INCLUSIVE || range->start.bound == _Z_TIME_BOUND_EXCLUSIVE) {
        if (!_z_time_bound_to_str(&range->start, &buf[pos], buf_len - pos)) {
            return false;
        }
        size_t remaining = buf_len - pos;
        size_t str_len = strnlen(&buf[pos], remaining);
        if (str_len == remaining) {
            // Null terminator not found within bounds
            return false;
        }
        pos += str_len;
    }

    if (buf_len - pos < 2) {
        return false;  // Not enough space for ".."
    }
    buf[pos++] = '.';
    buf[pos++] = '.';

    if (range->end.bound == _Z_TIME_BOUND_INCLUSIVE || range->end.bound == _Z_TIME_BOUND_EXCLUSIVE) {
        if (!_z_time_bound_to_str(&range->end, &buf[pos], buf_len - pos)) {
            return false;
        }
        size_t remaining = buf_len - pos;
        size_t str_len = strnlen(&buf[pos], remaining);
        if (str_len == remaining) {
            // Null terminator not found within bounds
            return false;
        }
        pos += str_len;
    }

    if (buf_len - pos < 2) {
        return false;  // Not enough space for end delimiter and '\0'
    }
    if (!_z_time_bound_delim_to_char(&range->end, false, &buf[pos++])) {
        return false;  // Invalid bound delimiter
    }
    buf[pos] = '\0';

    return true;
}

_z_ntp64_t _z_time_range_resolve_offset(_z_ntp64_t base, double offset) {
    const double FRAC_PER_SEC = 4294967296.0;  // 2^32

    if (offset == 0.0) {
        return base;
    }

    double abs_offset = fabs(offset);
    uint32_t offset_seconds = (uint32_t)abs_offset;
    double fractions = abs_offset - (double)offset_seconds;
    uint32_t offset_fractions = (uint32_t)(fractions * FRAC_PER_SEC + 0.5);
    _z_ntp64_t offset_ntp = ((uint64_t)offset_seconds << 32) | offset_fractions;

    if (offset < 0.0) {
        return base - offset_ntp;
    } else {
        return base + offset_ntp;
    }
}

bool _z_time_range_contains_at_time(const _z_time_range_t *range, const _z_ntp64_t timestamp, const _z_ntp64_t time) {
    if (range == NULL) {
        return false;
    }

    if (range->start.bound != _Z_TIME_BOUND_UNBOUNDED) {
        _z_ntp64_t start = _z_time_range_resolve_offset(time, range->start.now_offset);
        if (range->start.bound == _Z_TIME_BOUND_INCLUSIVE) {
            if (start > timestamp) {
                return false;
            }
        } else {  // EXCLUSIVE
            if (start >= timestamp) {
                return false;
            }
        }
    }

    if (range->end.bound != _Z_TIME_BOUND_UNBOUNDED) {
        _z_ntp64_t end = _z_time_range_resolve_offset(time, range->end.now_offset);
        if (range->end.bound == _Z_TIME_BOUND_INCLUSIVE) {
            if (end < timestamp) {
                return false;
            }
        } else {  // EXCLUSIVE
            if (end <= timestamp) {
                return false;
            }
        }
    }

    return true;
}
