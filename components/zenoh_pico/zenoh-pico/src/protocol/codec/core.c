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

#include "zenoh-pico/protocol/codec/core.h"

#include "zenoh-pico/protocol/iobuf.h"

z_result_t _z_zbuf_read_exact(_z_zbuf_t *zbf, uint8_t *dest, size_t length) {
    if (length > _z_zbuf_len(zbf)) {
        _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
    }
    _z_zbuf_read_bytes(zbf, dest, 0, length);
    return _Z_RES_OK;
}
