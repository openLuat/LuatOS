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

#include <stddef.h>

#include "zenoh-pico/net/sample.h"
#include "zenoh-pico/protocol/core.h"

void _z_hello_clear(_z_hello_t *hello) { _z_string_svec_clear(&hello->_locators); }

void _z_hello_free(_z_hello_t **hello) {
    _z_hello_t *ptr = *hello;

    if (ptr != NULL) {
        _z_hello_clear(ptr);

        z_free(ptr);
        *hello = NULL;
    }
}

void _z_value_clear(_z_value_t *value) {
    _z_encoding_clear(&value->encoding);
    _z_bytes_drop(&value->payload);
}

void _z_value_free(_z_value_t **value) {
    _z_value_t *ptr = *value;

    if (ptr != NULL) {
        _z_value_clear(ptr);

        z_free(ptr);
        *value = NULL;
    }
}

bool _z_hello_check(const _z_hello_t *hello) { return _z_id_check(hello->_zid); }
