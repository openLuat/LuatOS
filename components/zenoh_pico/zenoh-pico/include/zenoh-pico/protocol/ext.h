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

#ifndef ZENOH_PICO_PROTOCOL_EXTENSION_H
#define ZENOH_PICO_PROTOCOL_EXTENSION_H

#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/protocol/core.h"

#ifdef __cplusplus
extern "C" {
#endif

/*=============================*/
/*       Message header        */
/*=============================*/
#define _Z_EXT_FULL_ID_MASK 0x7F
#define _Z_EXT_ID_MASK 0x0F
#define _Z_EXT_ENC_MASK 0x60

/*=============================*/
/*       Message helpers       */
/*=============================*/
#define _Z_EXT_FULL_ID(h) (_Z_EXT_FULL_ID_MASK & h)
#define _Z_EXT_ID(h) (_Z_EXT_ID_MASK & h)
#define _Z_EXT_ENC(h) (_Z_EXT_ENC_MASK & h)
#define _Z_EXT_HAS_FLAG(h, f) ((h & f) != 0)
#define _Z_EXT_SET_FLAG(h, f) (h |= f)

/*=============================*/
/*        Extension IDs        */
/*=============================*/
#define _Z_MSG_EXT_ID_JOIN_QOS (0x01 | _Z_MSG_EXT_FLAG_M | _Z_MSG_EXT_ENC_ZBUF)
#define _Z_MSG_EXT_ID_JOIN_PATCH (0x07 | _Z_MSG_EXT_ENC_ZINT)
#define _Z_MSG_EXT_ID_INIT_PATCH (0x07 | _Z_MSG_EXT_ENC_ZINT)
#define _Z_MSG_EXT_ID_FRAGMENT_FIRST (0x02 | _Z_MSG_EXT_ENC_UNIT)
#define _Z_MSG_EXT_ID_FRAGMENT_DROP (0x03 | _Z_MSG_EXT_ENC_UNIT)

/*=============================*/
/*     Extension Encodings     */
/*=============================*/
#define _Z_MSG_EXT_ENC_UNIT 0x00  // 0x00 << 5
#define _Z_MSG_EXT_ENC_ZINT 0x20  // 0x01 << 5
#define _Z_MSG_EXT_ENC_ZBUF 0x40  // 0x10 << 5

/*=============================*/
/*       Extension flags       */
/*=============================*/
#define _Z_MSG_EXT_FLAG_M 0x10
#define _Z_MSG_EXT_IS_MANDATORY(h) ((h & _Z_MSG_EXT_FLAG_M) != 0)
#define _Z_MSG_EXT_FLAG_Z 0x80
#define _Z_MSG_EXT_MORE(more) (more ? _Z_MSG_EXT_FLAG_Z : 0)

typedef struct {
    uint8_t __dummy;  // Just to avoid empty structures that might cause undefined behavior
} _z_msg_ext_unit_t;
void _z_msg_ext_clear_unit(_z_msg_ext_unit_t *ext);

/*------------------ ZID Extension ------------------*/
typedef struct {
    uint64_t _val;
} _z_msg_ext_zint_t;
void _z_msg_ext_clear_zint(_z_msg_ext_zint_t *ext);

/*------------------ Unknown Extension ------------------*/
typedef struct {
    _z_slice_t _val;
} _z_msg_ext_zbuf_t;
void _z_msg_ext_clear_zbuf(_z_msg_ext_zbuf_t *ext);

/*------------------ Message Extensions ------------------*/
typedef union {
    _z_msg_ext_unit_t _unit;
    _z_msg_ext_zint_t _zint;
    _z_msg_ext_zbuf_t _zbuf;
} _z_msg_ext_body_t;

typedef struct {
    _z_msg_ext_body_t _body;
    uint8_t _header;
} _z_msg_ext_t;
void _z_msg_ext_clear(_z_msg_ext_t *ext);

/*------------------ Builders ------------------*/
_z_msg_ext_t _z_msg_ext_make_unit(uint8_t id);
_z_msg_ext_t _z_msg_ext_make_zint(uint8_t id, _z_zint_t zid);
_z_msg_ext_t _z_msg_ext_make_zbuf(uint8_t id, _z_slice_t zbuf);

/*------------------ Copy ------------------*/
void _z_msg_ext_copy(_z_msg_ext_t *clone, const _z_msg_ext_t *ext);
void _z_msg_ext_copy_unit(_z_msg_ext_unit_t *clone, const _z_msg_ext_unit_t *ext);
void _z_msg_ext_copy_zint(_z_msg_ext_zint_t *clone, const _z_msg_ext_zint_t *ext);
void _z_msg_ext_copy_zbuf(_z_msg_ext_zbuf_t *clone, const _z_msg_ext_zbuf_t *ext);

_Z_ELEM_DEFINE(_z_msg_ext, _z_msg_ext_t, _z_noop_size, _z_msg_ext_clear, _z_msg_ext_copy, _z_noop_move, _z_noop_eq,
               _z_noop_cmp, _z_noop_hash)
_Z_VEC_DEFINE(_z_msg_ext, _z_msg_ext_t)

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_PROTOCOL_EXTENSION_H */
