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

#include "zenoh-pico/utils/json_encoder.h"

#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "zenoh-pico/api/primitives.h"

#if Z_FEATURE_ADMIN_SPACE == 1

z_result_t _z_json_encoder_empty(_z_json_encoder_t *je) {
    if (je == NULL) {
        return _Z_ERR_INVALID;
    }
    *je = (_z_json_encoder_t){0};
    _Z_RETURN_IF_ERR(z_bytes_writer_empty(&je->_bw));
    return _Z_RES_OK;
}

static bool _z_json_encoder_value_allowed(_z_json_encoder_t *je) {
    if (je->_depth == 0) {
        return je->_done == false;
    }

    _z_json_frame_t *frame = &je->_stk[je->_depth - 1];
    if (frame->kind == _Z_JSON_CTX_OBJ && !frame->expect_value) {
        return false;
    }
    return true;
}

static inline z_result_t _z_json_encoder_putc(_z_json_encoder_t *je, char c) {
    const uint8_t b = (uint8_t)c;
    return z_bytes_writer_write_all(z_bytes_writer_loan_mut(&je->_bw), &b, 1);
}

static inline z_result_t _z_json_encoder_putsn(_z_json_encoder_t *je, const char *s, size_t len) {
    return z_bytes_writer_write_all(z_bytes_writer_loan_mut(&je->_bw), (const uint8_t *)s, len);
}

static z_result_t _z_json_encoder_push(_z_json_encoder_t *je, _z_json_ctx_kind_t kind) {
    if (je->_depth >= Z_JSON_MAX_DEPTH) {
        return _Z_ERR_OVERFLOW;
    }

    je->_stk[je->_depth].kind = kind;
    je->_stk[je->_depth].expect_value = false;
    je->_stk[je->_depth].first = true;
    je->_depth++;
    return _Z_RES_OK;
}

static z_result_t _z_json_encoder_pop(_z_json_encoder_t *je) {
    if (je->_depth == 0) {
        return _Z_ERR_UNDERFLOW;
    }

    je->_depth--;
    return _Z_RES_OK;
}

static z_result_t _z_json_encoder_finish_value(_z_json_encoder_t *je) {
    if (je->_depth == 0) {
        je->_done = true;
        return _Z_RES_OK;
    }

    _z_json_frame_t *parent = &je->_stk[je->_depth - 1];
    if (parent->kind == _Z_JSON_CTX_OBJ) {
        parent->expect_value = false;
    }
    return _Z_RES_OK;
}

static z_result_t _z_json_encoder_before_key(_z_json_encoder_t *je) {
    if (je->_depth == 0) {
        return _Z_ERR_INVALID;
    }

    _z_json_frame_t *frame = &je->_stk[je->_depth - 1];
    if (frame->kind != _Z_JSON_CTX_OBJ || frame->expect_value) {
        return _Z_ERR_INVALID;
    }

    if (!frame->first) {
        _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, ','));
    } else {
        frame->first = false;
    }
    return _Z_RES_OK;
}

static z_result_t _z_json_encoder_before_value(_z_json_encoder_t *je) {
    if (je->_depth == 0) {
        // root value: no separator
        return _Z_RES_OK;
    }

    _z_json_frame_t *frame = &je->_stk[je->_depth - 1];

    if (frame->kind == _Z_JSON_CTX_ARR) {
        if (!frame->first) {
            _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, ','));
        } else {
            frame->first = false;
        }
        return _Z_RES_OK;
    }

    // object: value separators are handled at key time, and we must be expecting a value now
    if (frame->kind == _Z_JSON_CTX_OBJ) {
        if (!frame->expect_value) {
            return _Z_ERR_INVALID;
        }
        return _Z_RES_OK;
    }

    return _Z_ERR_INVALID;
}

z_result_t _z_json_encoder_start_object(_z_json_encoder_t *je) {
    if (je == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_push(je, _Z_JSON_CTX_OBJ));

    z_result_t res = _z_json_encoder_putc(je, '{');
    if (res != _Z_RES_OK) {
        _z_json_encoder_pop(je);
    }
    return res;
}

z_result_t _z_json_encoder_end_object(_z_json_encoder_t *je) {
    if (je == NULL || je->_depth == 0) {
        return _Z_ERR_INVALID;
    }

    _z_json_frame_t *frame = &je->_stk[je->_depth - 1];
    if (frame->kind != _Z_JSON_CTX_OBJ || frame->expect_value) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, '}'));
    _Z_RETURN_IF_ERR(_z_json_encoder_pop(je));
    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_start_array(_z_json_encoder_t *je) {
    if (je == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_push(je, _Z_JSON_CTX_ARR));

    z_result_t res = _z_json_encoder_putc(je, '[');
    if (res != _Z_RES_OK) {
        _z_json_encoder_pop(je);
    }
    return res;
}

z_result_t _z_json_encoder_end_array(_z_json_encoder_t *je) {
    if (je == NULL || je->_depth == 0) {
        return _Z_ERR_INVALID;
    }

    _z_json_frame_t *frame = &je->_stk[je->_depth - 1];
    if (frame->kind != _Z_JSON_CTX_ARR) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, ']'));
    _Z_RETURN_IF_ERR(_z_json_encoder_pop(je));
    return _z_json_encoder_finish_value(je);
}

static z_result_t _z_json_encoder_write_escaped_string(_z_json_encoder_t *je, const char *str, size_t len) {
    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, '"'));

    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)str[i];

        switch (c) {
            case '"':
                _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "\\\"", 2));
                break;
            case '\\':
                _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "\\\\", 2));
                break;
            case '\b':
                _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "\\b", 2));
                break;
            case '\f':
                _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "\\f", 2));
                break;
            case '\n':
                _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "\\n", 2));
                break;
            case '\r':
                _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "\\r", 2));
                break;
            case '\t':
                _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "\\t", 2));
                break;
            default:
                if (c < 0x20) {
                    // Encode other control chars as \u00XX
                    char buf[7];
                    int n = snprintf(buf, sizeof(buf), "\\u%04x", (unsigned)c);
                    if (n != 6) {
                        return _Z_ERR_INVALID;
                    }
                    _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, buf, 6));
                } else {
                    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, (char)c));
                }
                break;
        }
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, '"'));
    return _Z_RES_OK;
}

z_result_t _z_json_encoder_write_key(_z_json_encoder_t *je, const char *key) {
    if (je == NULL || key == NULL || je->_depth == 0) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_key(je));

    // Flawfinder: ignore [CWE-126] - Intended to take a null terminated string
    _Z_RETURN_IF_ERR(_z_json_encoder_write_escaped_string(je, key, strlen(key)));
    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, ':'));

    _z_json_frame_t *frame = &je->_stk[je->_depth - 1];
    frame->expect_value = true;

    return _Z_RES_OK;
}

z_result_t _z_json_encoder_write_string(_z_json_encoder_t *je, const char *value) {
    if (je == NULL || value == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    // Flawfinder: ignore [CWE-126] - Intended to take a null terminated string
    _Z_RETURN_IF_ERR(_z_json_encoder_write_escaped_string(je, value, strlen(value)));
    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_write_z_string(_z_json_encoder_t *je, const _z_string_t *value) {
    if (je == NULL || value == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    _Z_RETURN_IF_ERR(_z_json_encoder_write_escaped_string(je, _z_string_data(value), _z_string_len(value)));
    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_write_z_slice(_z_json_encoder_t *je, const _z_slice_t *value) {
    static const char hex[] = "0123456789abcdef";

    if (je == NULL || value == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    const uint8_t *p = (const uint8_t *)value->start;
    size_t len = value->len;

    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, '"'));

    for (size_t i = 0; i < len; i++) {
        uint8_t b = p[i];
        char out[2] = {hex[b >> 4], hex[b & 0x0F]};
        _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, out, 2));
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_putc(je, '"'));
    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_write_double(_z_json_encoder_t *je, double value) {
    if (je == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }
    if (!isfinite(value)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%.17g", value);
    if (n <= 0 || (size_t)n >= sizeof(buf)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, buf, (size_t)n));
    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_write_i64(_z_json_encoder_t *je, int64_t value) {
    if (je == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    char buf[32];
    // Flawfinder: ignore (CWE-134) - format string is compile-time constant (C99 PRId64), not attacker-controlled.
    int n = snprintf(buf, sizeof(buf), "%" PRId64, value);
    if (n <= 0 || (size_t)n >= sizeof(buf)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, buf, (size_t)n));
    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_write_u64(_z_json_encoder_t *je, uint64_t value) {
    if (je == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    char buf[32];
    // Flawfinder: ignore (CWE-134) - format string is compile-time constant (C99 PRId64), not attacker-controlled.
    int n = snprintf(buf, sizeof(buf), "%" PRIu64, value);
    if (n <= 0 || (size_t)n >= sizeof(buf)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, buf, (size_t)n));
    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_write_boolean(_z_json_encoder_t *je, bool value) {
    if (je == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    if (value) {
        _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "true", 4));
    } else {
        _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "false", 5));
    }

    return _z_json_encoder_finish_value(je);
}

z_result_t _z_json_encoder_write_null(_z_json_encoder_t *je) {
    if (je == NULL || !_z_json_encoder_value_allowed(je)) {
        return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_before_value(je));

    _Z_RETURN_IF_ERR(_z_json_encoder_putsn(je, "null", 4));
    return _z_json_encoder_finish_value(je);
}

static z_result_t _z_json_encoder_validate(const _z_json_encoder_t *je) {
    if (je == NULL || je->_depth != 0 || !je->_done) {
        return _Z_ERR_INVALID;
    }
    return _Z_RES_OK;
}

z_result_t _z_json_encoder_finish(_z_json_encoder_t *je, z_owned_bytes_t *bytes) {
    if (je == NULL || bytes == NULL) {
        return _Z_ERR_INVALID;
    }
    _Z_RETURN_IF_ERR(_z_json_encoder_validate(je));
    z_bytes_writer_finish(z_bytes_writer_move(&je->_bw), bytes);

    je->_depth = 0;
    je->_done = false;

    return _Z_RES_OK;
}

void _z_json_encoder_clear(_z_json_encoder_t *je) {
    if (je == NULL) {
        return;
    }
    z_bytes_writer_drop(z_bytes_writer_move(&je->_bw));
    je->_depth = 0;
    je->_done = false;
}

#endif  // Z_FEATURE_ADMIN_SPACE == 1
