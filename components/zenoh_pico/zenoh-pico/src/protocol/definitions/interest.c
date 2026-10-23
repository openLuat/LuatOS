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
//

#include "zenoh-pico/protocol/definitions/interest.h"

void _z_interest_clear(_z_interest_t *interest) { _z_wireexpr_clear(&interest->_keyexpr); }

_z_interest_t _z_make_interest(_Z_MOVE(_z_wireexpr_t) key, uint32_t id, uint8_t flags) {
    return (_z_interest_t){
        ._id = id,
        ._keyexpr = (key == NULL) ? _z_wireexpr_null() : _z_wireexpr_steal(key),
        .flags = flags,
    };
}

_z_interest_t _z_make_interest_final(uint32_t id) {
    return (_z_interest_t){
        ._id = id,
        ._keyexpr = _z_wireexpr_null(),
        .flags = 0,
    };
}
