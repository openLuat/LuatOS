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

#include "zenoh-pico/utils/encoding.h"

#include "zenoh-pico/utils/pointers.h"

size_t _z_cobs_encode(const uint8_t *input, size_t input_len, uint8_t *output) {
    size_t len = input_len;
    uint8_t *pos = output;
    uint8_t *codep = output;
    uint8_t code = 1;

    pos = _z_ptr_u8_offset(pos, 1);
    for (const uint8_t *byte = input; len != (size_t)0; byte++) {
        if (*byte != 0x00) {
            *pos = *byte;
            pos = _z_ptr_u8_offset(pos, 1);
            code = code + (uint8_t)1;
        }

        if (!*byte || (code == (uint8_t)0xFF)) {
            *codep = code;
            code = 1;
            codep = pos;
            if (!*byte || len) {
                pos = _z_ptr_u8_offset(pos, 1);
            }
        }

        len = len - (size_t)1;
    }
    *codep = code;

    return _z_ptr_u8_diff(pos, output);
}

size_t _z_cobs_decode(const uint8_t *input, size_t input_len, uint8_t *output) {
    const uint8_t *byte = input;
    uint8_t *pos = output;

    uint8_t code = (uint8_t)0xFF;
    const uint8_t *input_end_ptr = _z_cptr_u8_offset(input, (ptrdiff_t)input_len);
    for (uint8_t block = (uint8_t)0x00; byte < input_end_ptr; block--) {
        if (block != (uint8_t)0x00) {
            *pos = *byte;
            pos = _z_ptr_u8_offset(pos, 1);
            byte = _z_cptr_u8_offset(byte, 1);
        } else {
            if (code != (uint8_t)0xFF) {
                *pos = (uint8_t)0x00;
                pos = _z_ptr_u8_offset(pos, 1);
            }
            code = *byte;
            block = *byte;
            byte = _z_cptr_u8_offset(byte, 1);
            if (code == (uint8_t)0x00) {
                pos = _z_ptr_u8_offset(pos, -1);
                break;
            }
        }
    }

    return _z_ptr_u8_diff(pos, output);
}
