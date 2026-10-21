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

#include "zenoh-pico/transport/utils.h"

#include "zenoh-pico/protocol/core.h"

#define U8_MAX 0xFF
#define U16_MAX 0xFFFF
#define U32_MAX 0xFFFFFFFF
#define U64_MAX 0xFFFFFFFFFFFFFFFF

_z_zint_t _z_sn_max(uint8_t bits) {
    _z_zint_t ret = 0;
    switch (bits) {
        case 0x00: {
            ret = U8_MAX >> 1;
        } break;

        case 0x01: {
            ret = U16_MAX >> 2;
        } break;

        case 0x02: {
            ret = U32_MAX >> 4;
        } break;

        case 0x03: {
            ret = (_z_zint_t)(U64_MAX >> 1);
        } break;

        default: {
            // Do nothing
        } break;
    }

    return ret;
}

_z_zint_t _z_sn_half(_z_zint_t sn) { return sn >> 1; }

_z_zint_t _z_sn_modulo_mask(uint8_t bits) {
    _z_zint_t ret = 0;
    switch (bits) {
        case 0x00: {
            ret = U8_MAX >> 1;
        } break;

        case 0x01: {
            ret = U16_MAX >> 2;
        } break;

        case 0x02: {
            ret = U32_MAX >> 4;
        } break;

        case 0x03: {
            ret = (_z_zint_t)(U64_MAX >> 1);
        } break;

        default: {
            // Do nothing
        } break;
    }

    return ret;
}

bool _z_sn_precedes(const _z_zint_t sn_resolution, const _z_zint_t sn_left, const _z_zint_t sn_right) {
    _z_zint_t distance = (sn_right - sn_left) & sn_resolution;
    return ((distance <= _z_sn_half(sn_resolution)) && (distance != 0));
}

bool _z_sn_consecutive(const _z_zint_t sn_resolution, const _z_zint_t sn_left, const _z_zint_t sn_right) {
    _z_zint_t distance = (sn_right - sn_left) & sn_resolution;
    return distance == 1;
}

_z_zint_t _z_sn_increment(const _z_zint_t sn_resolution, const _z_zint_t sn) {
    _z_zint_t ret = sn + 1;
    return (ret &= sn_resolution);
}

_z_zint_t _z_sn_decrement(const _z_zint_t sn_resolution, const _z_zint_t sn) {
    _z_zint_t ret = sn - 1;
    return (ret &= sn_resolution);
}

void _z_conduit_sn_list_copy(_z_conduit_sn_list_t *dst, const _z_conduit_sn_list_t *src) {
    dst->_is_qos = src->_is_qos;
    if (dst->_is_qos == false) {
        dst->_val._plain._best_effort = src->_val._plain._best_effort;
        dst->_val._plain._reliable = src->_val._plain._reliable;
    } else {
        for (uint8_t i = 0; i < Z_PRIORITIES_NUM; i++) {
            dst->_val._qos[i]._best_effort = src->_val._qos[i]._best_effort;
            dst->_val._qos[i]._reliable = src->_val._qos[i]._reliable;
        }
    }
}

void _z_conduit_sn_list_decrement(const _z_zint_t sn_resolution, _z_conduit_sn_list_t *sns) {
    if (sns->_is_qos == false) {
        sns->_val._plain._best_effort = _z_sn_decrement(sn_resolution, sns->_val._plain._best_effort);
        sns->_val._plain._reliable = _z_sn_decrement(sn_resolution, sns->_val._plain._reliable);
    } else {
        for (uint8_t i = 0; i < Z_PRIORITIES_NUM; i++) {
            sns->_val._qos[i]._best_effort = _z_sn_decrement(sn_resolution, sns->_val._qos[i]._best_effort);
            sns->_val._qos[i]._best_effort = _z_sn_decrement(sn_resolution, sns->_val._qos[i]._reliable);
        }
    }
}
