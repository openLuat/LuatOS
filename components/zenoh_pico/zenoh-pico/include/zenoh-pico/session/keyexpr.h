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

#ifndef INCLUDE_ZENOH_PICO_SESSION_KEYEXPR_H
#define INCLUDE_ZENOH_PICO_SESSION_KEYEXPR_H

#include <stdbool.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/collections/refcount.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/weak_session.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint16_t _id;
    uint16_t _prefix_len;
    _z_session_weak_t _session;
} _z_keyexpr_wire_declaration_t;

static inline _z_keyexpr_wire_declaration_t _z_keyexpr_wire_declaration_null(void) {
    _z_keyexpr_wire_declaration_t d = {0};
    return d;
}

static inline bool _z_keyexpr_wire_declaration_equals(const _z_keyexpr_wire_declaration_t *left,
                                                      const _z_keyexpr_wire_declaration_t *right) {
    return left->_id == right->_id && left->_session._val == right->_session._val;
}

z_result_t _z_keyexpr_wire_declaration_new(_z_keyexpr_wire_declaration_t *declaration, const _z_string_t *keyexpr,
                                           const _z_session_rc_t *session);

z_result_t _z_keyexpr_wire_declaration_undeclare(_z_keyexpr_wire_declaration_t *declaration);
void _z_keyexpr_wire_declaration_clear(_z_keyexpr_wire_declaration_t *declaration);
static inline bool _z_keyexpr_wire_declaration_is_declared_on_session(const _z_keyexpr_wire_declaration_t *declaration,
                                                                      const _z_session_t *s) {
    return !_Z_RC_IS_NULL(&declaration->_session) && declaration->_session._val == s;
}

_Z_REFCOUNT_DEFINE(_z_keyexpr_wire_declaration, _z_keyexpr_wire_declaration)

typedef struct {
    _z_string_t _keyexpr;
} _z_keyexpr_t;

static inline _z_keyexpr_t _z_keyexpr_null(void) {
    _z_keyexpr_t ke = {0};
    return ke;
}

bool _z_keyexpr_includes(const _z_keyexpr_t *left, const _z_keyexpr_t *right);
bool _z_keyexpr_intersects(const _z_keyexpr_t *left, const _z_keyexpr_t *right);

zp_keyexpr_canon_status_t _z_keyexpr_is_canon(const char *start, size_t len);
zp_keyexpr_canon_status_t _z_keyexpr_canonize(char *start, size_t *len);
z_result_t _z_keyexpr_concat(_z_keyexpr_t *key, const _z_keyexpr_t *left, const char *right, size_t len);
z_result_t _z_keyexpr_join(_z_keyexpr_t *key, const _z_keyexpr_t *left, const _z_keyexpr_t *right);
static inline _z_keyexpr_t _z_keyexpr_alias(const _z_keyexpr_t *src) {
    _z_keyexpr_t ret;
    ret._keyexpr = _z_string_alias(src->_keyexpr);
    return ret;
}

_z_keyexpr_t _z_keyexpr_alias_from_string(const _z_string_t *str);
_z_keyexpr_t _z_keyexpr_alias_from_substr(const char *str, size_t len);
static inline _z_keyexpr_t _z_keyexpr_alias_from_str(const char *str) {
    // SAFETY: By convention in pico code-base passing const char* without len implies that it is null-terminated.
    // Flawfinder: ignore [CWE-126]
    return _z_keyexpr_alias_from_substr(str, strlen(str));
}

z_result_t _z_keyexpr_from_string(_z_keyexpr_t *dst, const _z_string_t *str);
z_result_t _z_keyexpr_from_substr(_z_keyexpr_t *dst, const char *str, size_t len);

static inline void _z_keyexpr_clear(_z_keyexpr_t *key) { _z_string_clear(&key->_keyexpr); }

static inline bool _z_keyexpr_check(const _z_keyexpr_t *key) { return _z_string_check(&key->_keyexpr); }
static inline z_result_t _z_keyexpr_copy(_z_keyexpr_t *dst, const _z_keyexpr_t *src) {
    *dst = _z_keyexpr_null();
    return _z_string_copy(&dst->_keyexpr, &src->_keyexpr);
}

static inline z_result_t _z_keyexpr_move(_z_keyexpr_t *dst, _z_keyexpr_t *src) {
    *dst = _z_keyexpr_null();
    _Z_CLEAN_RETURN_IF_ERR(_z_string_move(&dst->_keyexpr, &src->_keyexpr), _z_keyexpr_clear(src));
    return _Z_RES_OK;
}

static inline _z_keyexpr_t _z_keyexpr_steal(_Z_MOVE(_z_keyexpr_t) src) {
    _z_keyexpr_t stolen = *src;
    *src = _z_keyexpr_null();
    return stolen;
}

size_t _z_keyexpr_non_wild_prefix_len(const _z_keyexpr_t *key);

static inline int _z_keyexpr_compare(const _z_keyexpr_t *first, const _z_keyexpr_t *second) {
    return _z_string_compare(&first->_keyexpr, &second->_keyexpr);
}
static inline bool _z_keyexpr_equals(const _z_keyexpr_t *first, const _z_keyexpr_t *second) {
    return _z_keyexpr_compare(first, second) == 0;
}
static inline size_t _z_keyexpr_size(_z_keyexpr_t *p) {
    _ZP_UNUSED(p);
    return sizeof(_z_keyexpr_t);
}

_z_wireexpr_t _z_keyexpr_alias_to_wire(const _z_keyexpr_t *key);

typedef struct {
    _z_keyexpr_wire_declaration_rc_t _declaration;
    _z_keyexpr_t _inner;
} _z_declared_keyexpr_t;

static inline bool _z_declared_keyexpr_includes(const _z_declared_keyexpr_t *left, const _z_declared_keyexpr_t *right) {
    return _z_keyexpr_includes(&left->_inner, &right->_inner);
}
static inline bool _z_declared_keyexpr_intersects(const _z_declared_keyexpr_t *left,
                                                  const _z_declared_keyexpr_t *right) {
    return _z_keyexpr_intersects(&left->_inner, &right->_inner);
}

z_result_t _z_declared_keyexpr_concat(_z_declared_keyexpr_t *key, const _z_declared_keyexpr_t *left, const char *right,
                                      size_t len);
z_result_t _z_declared_keyexpr_join(_z_declared_keyexpr_t *key, const _z_declared_keyexpr_t *left,
                                    const _z_declared_keyexpr_t *right);

static inline _z_declared_keyexpr_t _z_declared_keyexpr_null(void) {
    _z_declared_keyexpr_t ke = {0};
    return ke;
}

_z_declared_keyexpr_t _z_declared_keyexpr_alias_from_string(const _z_string_t *str);
_z_declared_keyexpr_t _z_declared_keyexpr_alias_from_substr(const char *str, size_t len);
static inline _z_declared_keyexpr_t _z_declared_keyexpr_alias_from_str(const char *str) {
    // SAFETY: By convention in pico code-base passing const char* without len implies that it is null-terminated.
    // Flawfinder: ignore [CWE-126]
    return _z_declared_keyexpr_alias_from_substr(str, strlen(str));
}
static inline z_result_t _z_declared_keyexpr_from_string(_z_declared_keyexpr_t *dst, const _z_string_t *str) {
    *dst = _z_declared_keyexpr_null();
    return _z_keyexpr_from_string(&dst->_inner, str);
}

static inline z_result_t _z_declared_keyexpr_from_substr(_z_declared_keyexpr_t *dst, const char *str, size_t len) {
    *dst = _z_declared_keyexpr_null();
    return _z_keyexpr_from_substr(&dst->_inner, str, len);
}

z_result_t _z_declared_keyexpr_copy(_z_declared_keyexpr_t *dst, const _z_declared_keyexpr_t *src);

static inline _z_declared_keyexpr_t _z_declared_keyexpr_steal(_Z_MOVE(_z_declared_keyexpr_t) src) {
    _z_declared_keyexpr_t stolen = *src;
    *src = _z_declared_keyexpr_null();
    return stolen;
}

static inline void _z_declared_keyexpr_clear(_z_declared_keyexpr_t *key) {
    _z_keyexpr_wire_declaration_rc_drop(&key->_declaration);
    _z_keyexpr_clear(&key->_inner);
}

static inline bool _z_declared_keyexpr_check(const _z_declared_keyexpr_t *key) {
    return _z_keyexpr_check(&key->_inner);
}

static inline bool _z_declared_keyexpr_is_fully_optimized(const _z_declared_keyexpr_t *key,
                                                          const _z_session_t *session) {
    return !_Z_RC_IS_NULL(&key->_declaration) &&
           _z_keyexpr_wire_declaration_is_declared_on_session(_Z_RC_IN_VAL(&key->_declaration), session) &&
           _Z_RC_IN_VAL(&key->_declaration)->_prefix_len == _z_string_len(&key->_inner._keyexpr);
}

static inline bool _z_declared_keyexpr_is_non_wild_prefix_optimized(const _z_declared_keyexpr_t *key,
                                                                    const _z_session_t *session) {
    return !_Z_RC_IS_NULL(&key->_declaration) &&
           _z_keyexpr_wire_declaration_is_declared_on_session(_Z_RC_IN_VAL(&key->_declaration), session) &&
           _Z_RC_IN_VAL(&key->_declaration)->_prefix_len == _z_keyexpr_non_wild_prefix_len(&key->_inner);
}

static inline bool _z_declared_keyexpr_equals(const _z_declared_keyexpr_t *left, const _z_declared_keyexpr_t *right) {
    return _z_keyexpr_equals(&left->_inner, &right->_inner);
}
z_result_t _z_declared_keyexpr_move(_z_declared_keyexpr_t *dst, _z_declared_keyexpr_t *src);

_z_wireexpr_t _z_declared_keyexpr_alias_to_wire(const _z_declared_keyexpr_t *key, const _z_session_t *session);
z_result_t _z_declared_keyexpr_declare(const _z_session_rc_t *zs, _z_declared_keyexpr_t *out,
                                       const _z_declared_keyexpr_t *keyexpr);
z_result_t _z_declared_keyexpr_declare_non_wild_prefix(const _z_session_rc_t *zs, _z_declared_keyexpr_t *out,
                                                       const _z_declared_keyexpr_t *keyexpr);

static inline size_t _z_declared_keyexpr_size(_z_declared_keyexpr_t *p) {
    _ZP_UNUSED(p);
    return sizeof(_z_declared_keyexpr_t);
}

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_SESSION_KEYEXPR_H */
