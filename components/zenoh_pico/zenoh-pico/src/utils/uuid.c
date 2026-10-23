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

#include "zenoh-pico/utils/uuid.h"

#include <ctype.h>
#include <stdint.h>
#include <stdlib.h>

#include "zenoh-pico/api/types.h"
#include "zenoh-pico/utils/pointers.h"

#define UUID_SIZE 16

void _z_uuid_to_bytes(uint8_t *bytes, const char *uuid_str) {
    uint8_t n_dash = 0;
    for (uint8_t i = 0; i < 32; i += 2) {
        if (i == 8 || i == 12 || i == 16 || i == 18) {
            n_dash += 1;
        }
        char val[5] = {'0', 'x', uuid_str[i + n_dash], uuid_str[i + 1 + n_dash], '\0'};
        *bytes = (uint8_t)strtoul(val, NULL, 0);
        bytes = _z_ptr_u8_offset(bytes, 1);
    }
}

_z_string_t _z_id_to_string(const _z_id_t *id) {
    _z_slice_t buf = _z_slice_alias_buf(id->id, sizeof(id->id));
    return _z_string_convert_bytes_le(&buf);
}

_z_id_t _z_id_from_string(const _z_string_t *str) {
    if (str == NULL) {
        return _z_id_empty();
    }

    const char *s = _z_string_data(str);
    size_t len = _z_string_len(str);

    // Expect exactly ZENOH_ID_SIZE * 2 lowercase hex characters
    if (s == NULL || len != ZENOH_ID_SIZE * 2) {
        return _z_id_empty();
    }

    z_id_t id;
    for (size_t i = 0; i < ZENOH_ID_SIZE; i++) {
        size_t offset = (ZENOH_ID_SIZE - 1 - i) * 2;
        char high = s[offset];
        char low = s[offset + 1];

        if (!isxdigit(high) || !isxdigit(low) || isupper((unsigned char)high) || isupper((unsigned char)low)) {
            return _z_id_empty();
        }

        char byte_str[3] = {high, low, '\0'};
        unsigned long byte_val = strtoul(byte_str, NULL, 16);
        id.id[i] = (uint8_t)byte_val;
    }
    return id;
}
