//
// Copyright (c) 2026 ZettaScale Technology
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

#ifndef ZENOH_PICO_UTILS_JSON_ENCODER_H
#define ZENOH_PICO_UTILS_JSON_ENCODER_H

#include "zenoh-pico/api/types.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_ADMIN_SPACE == 1

typedef enum {
    _Z_JSON_CTX_OBJ = 1,
    _Z_JSON_CTX_ARR = 2,
} _z_json_ctx_kind_t;

typedef struct {
    _z_json_ctx_kind_t kind;
    bool expect_value;
    bool first;
} _z_json_frame_t;

// Maximum nesting depth supported by the JSON encoder
#ifndef Z_JSON_MAX_DEPTH
#define Z_JSON_MAX_DEPTH 16
#endif

typedef struct {
    z_owned_bytes_writer_t _bw;

    uint8_t _depth;
    _z_json_frame_t _stk[Z_JSON_MAX_DEPTH];
    bool _done;
} _z_json_encoder_t;

z_result_t _z_json_encoder_empty(_z_json_encoder_t *je);

z_result_t _z_json_encoder_start_object(_z_json_encoder_t *je);
z_result_t _z_json_encoder_end_object(_z_json_encoder_t *je);
z_result_t _z_json_encoder_start_array(_z_json_encoder_t *je);
z_result_t _z_json_encoder_end_array(_z_json_encoder_t *je);

z_result_t _z_json_encoder_write_key(_z_json_encoder_t *je, const char *key);
z_result_t _z_json_encoder_write_string(_z_json_encoder_t *je, const char *value);
z_result_t _z_json_encoder_write_z_string(_z_json_encoder_t *je, const _z_string_t *value);
z_result_t _z_json_encoder_write_z_slice(_z_json_encoder_t *je, const _z_slice_t *value);
z_result_t _z_json_encoder_write_double(_z_json_encoder_t *je, double value);
z_result_t _z_json_encoder_write_i64(_z_json_encoder_t *je, int64_t value);
z_result_t _z_json_encoder_write_u64(_z_json_encoder_t *je, uint64_t value);
z_result_t _z_json_encoder_write_boolean(_z_json_encoder_t *je, bool value);
z_result_t _z_json_encoder_write_null(_z_json_encoder_t *je);

z_result_t _z_json_encoder_finish(_z_json_encoder_t *je, z_owned_bytes_t *bytes);
void _z_json_encoder_clear(_z_json_encoder_t *je);

#endif  // Z_FEATURE_ADMIN_SPACE == 1
#endif  // Z_FEATURE_UNSTABLE_API

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_JSON_ENCODER_H */
