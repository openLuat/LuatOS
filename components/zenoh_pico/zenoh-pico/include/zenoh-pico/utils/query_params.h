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

#ifndef ZENOH_PICO_UTILS_QUERY_PARAMS_H
#define ZENOH_PICO_UTILS_QUERY_PARAMS_H

#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/utils/string.h"

#ifdef __cplusplus
extern "C" {
#endif

#define _Z_QUERY_PARAMS_KEY_TIME "_time"
#define _Z_QUERY_PARAMS_KEY_TIME_LEN (sizeof(_Z_QUERY_PARAMS_KEY_TIME) - 1)
#define _Z_QUERY_PARAMS_KEY_RANGE "_sn"
#define _Z_QUERY_PARAMS_KEY_RANGE_LEN (sizeof(_Z_QUERY_PARAMS_KEY_RANGE) - 1)
#define _Z_QUERY_PARAMS_KEY_MAX "_max"
#define _Z_QUERY_PARAMS_KEY_MAX_LEN (sizeof(_Z_QUERY_PARAMS_KEY_MAX) - 1)
#define _Z_QUERY_PARAMS_KEY_ANYKE "_anyke"
#define _Z_QUERY_PARAMS_KEY_ANYKE_LEN (sizeof(_Z_QUERY_PARAMS_KEY_ANYKE) - 1)

#define _Z_QUERY_PARAMS_LIST_SEPARATOR ";"
#define _Z_QUERY_PARAMS_LIST_SEPARATOR_LEN (sizeof(_Z_QUERY_PARAMS_LIST_SEPARATOR) - 1)
#define _Z_QUERY_PARAMS_FIELD_SEPARATOR "="
#define _Z_QUERY_PARAMS_FIELD_SEPARATOR_LEN (sizeof(_Z_QUERY_PARAMS_FIELD_SEPARATOR) - 1)

typedef struct {
    _z_str_se_t key;
    _z_str_se_t value;
} _z_query_param_t;

typedef struct {
    bool _has_start;
    uint32_t _start;
    bool _has_end;
    uint32_t _end;
} _z_query_param_range_t;

/**
 * Extracts the next query parameter from a `_z_str_se_t` string.
 *
 * Returns a `_z_query_param_t` with positions of the next key/value in the string if present.
 * After invocation `str` will point to the remainder of the string.
 */
_z_query_param_t _z_query_params_next(_z_str_se_t *str);

bool _z_parameters_has_anyke(const char *parameters, size_t parameters_len);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_QUERY_PARAMS_H */
