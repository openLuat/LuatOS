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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_DECLARATIONS_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_DECLARATIONS_H

#include <stdint.h>

#include "zenoh-pico/protocol/core.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint16_t _id;
    _z_wireexpr_t _keyexpr;
} _z_decl_kexpr_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_decl_kexpr_t _z_decl_kexpr_null(void) { return (_z_decl_kexpr_t){0}; }
typedef struct {
    uint16_t _id;
} _z_undecl_kexpr_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_undecl_kexpr_t _z_undecl_kexpr_null(void) { return (_z_undecl_kexpr_t){0}; }

typedef struct {
    _z_wireexpr_t _keyexpr;
    uint32_t _id;
} _z_decl_subscriber_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_decl_subscriber_t _z_decl_subscriber_null(void) { return (_z_decl_subscriber_t){0}; }
typedef struct {
    uint32_t _id;
    _z_wireexpr_t _ext_keyexpr;
} _z_undecl_subscriber_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_undecl_subscriber_t _z_undecl_subscriber_null(void) { return (_z_undecl_subscriber_t){0}; }

typedef struct {
    _z_wireexpr_t _keyexpr;
    uint32_t _id;
    struct {
        bool _complete;
        uint16_t _distance;
    } _ext_queryable_info;
} _z_decl_queryable_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_decl_queryable_t _z_decl_queryable_null(void) { return (_z_decl_queryable_t){0}; }
typedef struct {
    uint32_t _id;
    _z_wireexpr_t _ext_keyexpr;
} _z_undecl_queryable_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_undecl_queryable_t _z_undecl_queryable_null(void) { return (_z_undecl_queryable_t){0}; }

typedef struct {
    _z_wireexpr_t _keyexpr;
    uint32_t _id;
} _z_decl_token_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_decl_token_t _z_decl_token_null(void) { return (_z_decl_token_t){0}; }
typedef struct {
    uint32_t _id;
    _z_wireexpr_t _ext_keyexpr;
} _z_undecl_token_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_undecl_token_t _z_undecl_token_null(void) { return (_z_undecl_token_t){0}; }

typedef struct {
    bool _placeholder;  // In case we add extensions
} _z_decl_final_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_decl_final_t _z_decl_final_null(void) { return (_z_decl_final_t){0}; }

typedef struct {
    enum {
        _Z_DECL_KEXPR,
        _Z_UNDECL_KEXPR,
        _Z_DECL_SUBSCRIBER,
        _Z_UNDECL_SUBSCRIBER,
        _Z_DECL_QUERYABLE,
        _Z_UNDECL_QUERYABLE,
        _Z_DECL_TOKEN,
        _Z_UNDECL_TOKEN,
        _Z_DECL_FINAL,
    } _tag;
    union {
        _z_decl_kexpr_t _decl_kexpr;
        _z_undecl_kexpr_t _undecl_kexpr;
        _z_decl_subscriber_t _decl_subscriber;
        _z_undecl_subscriber_t _undecl_subscriber;
        _z_decl_queryable_t _decl_queryable;
        _z_undecl_queryable_t _undecl_queryable;
        _z_decl_token_t _decl_token;
        _z_undecl_token_t _undecl_token;
        _z_decl_final_t _decl_final;
    } _body;
} _z_declaration_t;
void _z_declaration_clear(_z_declaration_t* decl);

_z_declaration_t _z_make_decl_keyexpr(uint16_t id, _Z_MOVE(_z_wireexpr_t) key);
_z_declaration_t _z_make_undecl_keyexpr(uint16_t id);

_z_declaration_t _z_make_decl_subscriber(_Z_MOVE(_z_wireexpr_t) key, uint32_t id);
_z_declaration_t _z_make_undecl_subscriber(uint32_t id, _Z_OPTIONAL _Z_MOVE(_z_wireexpr_t) key);

_z_declaration_t _z_make_decl_queryable(_Z_MOVE(_z_wireexpr_t) key, uint32_t id, bool complete, uint16_t distance);
_z_declaration_t _z_make_undecl_queryable(uint32_t id, _Z_OPTIONAL _Z_MOVE(_z_wireexpr_t) key);

_z_declaration_t _z_make_decl_token(_Z_MOVE(_z_wireexpr_t) key, uint32_t id);
_z_declaration_t _z_make_undecl_token(uint32_t id, _Z_OPTIONAL _Z_MOVE(_z_wireexpr_t) key);

_z_declaration_t _z_make_decl_final(void);

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_DECLARATIONS_H */
