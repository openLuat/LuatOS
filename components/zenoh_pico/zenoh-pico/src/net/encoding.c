//
// Copyright (c) 2024 ZettaScale Technology
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

#include "zenoh-pico/net/encoding.h"

#include <string.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/result.h"

_z_encoding_t _z_encoding_wrap(uint16_t id, const char *schema) {
    return (_z_encoding_t){.id = id,
                           .schema = (schema == NULL) ? _z_string_null() : _z_string_alias_str((char *)schema)};
}

z_result_t _z_encoding_make(_z_encoding_t *encoding, uint16_t id, const char *schema, size_t len) {
    encoding->id = id;
    // Clone schema
    if (schema != NULL) {
        encoding->schema = _z_string_copy_from_substr(schema, len);
        if (_z_string_len(&encoding->schema) != len) {
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
    } else {
        encoding->schema = _z_string_null();
    }
    return _Z_RES_OK;
}

z_result_t _z_encoding_copy(_z_encoding_t *dst, const _z_encoding_t *src) {
    dst->id = src->id;
    if (_z_string_check(&src->schema)) {
        _Z_RETURN_IF_ERR(_z_string_copy(&dst->schema, &src->schema));
    } else {
        dst->schema = _z_string_null();
    }
    return _Z_RES_OK;
}

z_result_t _z_encoding_move(_z_encoding_t *dst, _z_encoding_t *src) {
    dst->id = src->id;
    src->id = _Z_ENCODING_ID_DEFAULT;
    dst->schema = _z_string_null();
    if (_z_string_check(&src->schema)) {
        _Z_RETURN_IF_ERR(_z_string_move(&dst->schema, &src->schema));
    }
    return _Z_RES_OK;
}
