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

#include "zenoh-pico/protocol/ext.h"

#include <stdint.h>

#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/utils/logging.h"

_z_msg_ext_t _z_msg_ext_make_unit(uint8_t id) {
    _z_msg_ext_t ext;

    ext._header = id & _Z_EXT_ID_MASK;
    ext._header |= _Z_MSG_EXT_ENC_UNIT;

    return ext;
}

void _z_msg_ext_clear_unit(_z_msg_ext_unit_t *ext) { (void)(ext); }

void _z_msg_ext_copy_unit(_z_msg_ext_unit_t *clone, const _z_msg_ext_unit_t *ext) {
    (void)(clone);
    (void)(ext);
}

_z_msg_ext_t _z_msg_ext_make_zint(uint8_t id, _z_zint_t zid) {
    _z_msg_ext_t ext;

    ext._header = id & _Z_EXT_ID_MASK;
    ext._header |= _Z_MSG_EXT_ENC_ZINT;

    ext._body._zint._val = zid;

    return ext;
}

void _z_msg_ext_clear_zint(_z_msg_ext_zint_t *ext) { (void)(ext); }

void _z_msg_ext_copy_zint(_z_msg_ext_zint_t *clone, const _z_msg_ext_zint_t *ext) { clone->_val = ext->_val; }

_z_msg_ext_t _z_msg_ext_make_zbuf(uint8_t id, _z_slice_t zbuf) {
    _z_msg_ext_t ext;

    ext._header = id & _Z_EXT_ID_MASK;
    ext._header |= _Z_MSG_EXT_ENC_ZBUF;

    ext._body._zbuf._val = _z_slice_steal(&zbuf);

    return ext;
}

void _z_msg_ext_clear_zbuf(_z_msg_ext_zbuf_t *ext) { _z_slice_clear(&ext->_val); }

void _z_msg_ext_copy_zbuf(_z_msg_ext_zbuf_t *clone, const _z_msg_ext_zbuf_t *ext) {
    _z_slice_copy(&clone->_val, &ext->_val);
}

void _z_msg_ext_copy(_z_msg_ext_t *clone, const _z_msg_ext_t *ext) {
    clone->_header = ext->_header;

    uint8_t enc = _Z_EXT_ENC(clone->_header);
    switch (enc) {
        case _Z_MSG_EXT_ENC_UNIT: {
            _z_msg_ext_copy_unit(&clone->_body._unit, &ext->_body._unit);
        } break;

        case _Z_MSG_EXT_ENC_ZINT: {
            _z_msg_ext_copy_zint(&clone->_body._zint, &ext->_body._zint);
        } break;

        case _Z_MSG_EXT_ENC_ZBUF: {
            _z_msg_ext_copy_zbuf(&clone->_body._zbuf, &ext->_body._zbuf);
        } break;

        default: {
            _Z_INFO("WARNING: Trying to copy message extension with unknown encoding(%d)", enc);
        } break;
    }
}

void _z_msg_ext_clear(_z_msg_ext_t *ext) {
    uint8_t enc = _Z_EXT_ENC(ext->_header);
    switch (enc) {
        case _Z_MSG_EXT_ENC_UNIT: {
            _z_msg_ext_clear_unit(&ext->_body._unit);
        } break;

        case _Z_MSG_EXT_ENC_ZINT: {
            _z_msg_ext_clear_zint(&ext->_body._zint);
        } break;

        case _Z_MSG_EXT_ENC_ZBUF: {
            _z_msg_ext_clear_zbuf(&ext->_body._zbuf);
        } break;

        default: {
            _Z_INFO("WARNING: Trying to free message extension with unknown encoding(%d)", enc);
        } break;
    }
}
