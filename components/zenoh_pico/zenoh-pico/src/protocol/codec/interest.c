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

#include "zenoh-pico/protocol/codec/interest.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "zenoh-pico/protocol/codec.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/protocol/codec/ext.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/core.h"
#include "zenoh-pico/protocol/definitions/interest.h"
#include "zenoh-pico/protocol/definitions/message.h"
#include "zenoh-pico/protocol/ext.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/system/platform.h"

#define _Z_INTEREST_CODEC_FLAG_N 0x20
#define _Z_INTEREST_CODEC_FLAG_M 0x40
#define _Z_INTEREST_FLAG_COPY_MASK 0x9f  // N & M flags occupy the place of C & F

#define _Z_INTEREST_TRACE_ID 0x13

z_result_t _z_interest_encode(_z_wbuf_t *wbf, const _z_interest_t *interest, bool is_final) {
    // Set id
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, interest->_id));
    if (is_final) {
        return _Z_RES_OK;
    }
    // Copy flags but clear current and future that are already processed.
    uint8_t flags = interest->flags;
    _Z_CLEAR_FLAG(flags, _Z_INTEREST_FLAG_CURRENT);
    _Z_CLEAR_FLAG(flags, _Z_INTEREST_FLAG_FUTURE);
    // Process restricted flag
    if (_Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_RESTRICTED)) {
        // Set Named & Mapping flags
        bool has_kesuffix = _z_wireexpr_has_suffix(&interest->_keyexpr);
        if (has_kesuffix) {
            _Z_SET_FLAG(flags, _Z_INTEREST_CODEC_FLAG_N);
        }
        if (_z_wireexpr_is_local(&interest->_keyexpr)) {
            _Z_SET_FLAG(flags, _Z_INTEREST_CODEC_FLAG_M);
        }
        // Set decl flags & keyexpr
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, flags));
        _Z_RETURN_IF_ERR(_z_wireexpr_encode(wbf, has_kesuffix, &interest->_keyexpr));
    } else {
        // Set decl flags
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, flags));
    }
    return _Z_RES_OK;
}

z_result_t _z_interest_decode(_z_interest_t *interest, _z_zbuf_t *zbf, bool is_final, bool has_ext, uintptr_t mapping) {
    // Decode id
    _Z_RETURN_IF_ERR(_z_zint32_decode(&interest->_id, zbf));
    if (!is_final) {
        uint8_t flags = 0;
        // Decode interest flags
        _Z_RETURN_IF_ERR(_z_uint8_decode(&flags, zbf));
        // Process restricted flag
        if (_Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_RESTRICTED)) {
            // Decode ke
            _Z_RETURN_IF_ERR(_z_wireexpr_decode(&interest->_keyexpr, zbf, _Z_HAS_FLAG(flags, _Z_INTEREST_CODEC_FLAG_N),
                                                _Z_HAS_FLAG(flags, _Z_INTEREST_CODEC_FLAG_M), mapping));
        }
        // Store interest flags (current and future already processed)
        interest->flags = (uint8_t)(interest->flags | (flags & _Z_INTEREST_FLAG_COPY_MASK));
    }
    if (has_ext) {
        _Z_RETURN_IF_ERR(_z_msg_ext_skip_non_mandatories(zbf, _Z_INTEREST_TRACE_ID));
    }
    return _Z_RES_OK;
}
