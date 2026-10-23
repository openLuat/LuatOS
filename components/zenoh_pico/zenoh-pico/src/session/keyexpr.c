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

#include "zenoh-pico/session/keyexpr.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#include "zenoh-pico/net/primitives.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"
#include "zenoh-pico/utils/string.h"

z_result_t _z_keyexpr_wire_declaration_new(_z_keyexpr_wire_declaration_t *declaration, const _z_string_t *keyexpr,
                                           const _z_session_rc_t *session) {
    *declaration = _z_keyexpr_wire_declaration_null();
    z_result_t ret = _z_declare_resource(_Z_RC_IN_VAL(session), keyexpr, &declaration->_id);
    if (ret == _Z_RES_OK) {
        declaration->_prefix_len = (uint16_t)_z_string_len(keyexpr);
        declaration->_session = _z_session_rc_clone_as_weak(session);
    }
    return ret;
}

z_result_t _z_keyexpr_wire_declaration_undeclare(_z_keyexpr_wire_declaration_t *declaration) {
    z_result_t ret = _Z_RES_OK;
    if (_Z_RC_IS_NULL(&declaration->_session)) {
        return ret;
    }

    _z_session_rc_t session_rc = _z_session_weak_upgrade_if_open(&declaration->_session);

    if (!_Z_RC_IS_NULL(&session_rc)) {
        ret = _z_undeclare_resource(_Z_RC_IN_VAL(&session_rc), declaration->_id);
        _z_session_rc_drop(&session_rc);
    }
    declaration->_id = Z_RESOURCE_ID_NONE;
    declaration->_prefix_len = 0;
    _z_session_weak_drop(&declaration->_session);
    return ret;
}

void _z_keyexpr_wire_declaration_clear(_z_keyexpr_wire_declaration_t *declaration) {
    _z_keyexpr_wire_declaration_undeclare(declaration);
}

_z_keyexpr_t _z_keyexpr_alias_from_string(const _z_string_t *str) {
    _z_keyexpr_t ke = _z_keyexpr_null();
    ke._keyexpr = _z_string_alias(*str);
    return ke;
}

_z_keyexpr_t _z_keyexpr_alias_from_substr(const char *str, size_t len) {
    _z_keyexpr_t ke = _z_keyexpr_null();
    ke._keyexpr = _z_string_alias_substr(str, len);
    return ke;
}

_z_declared_keyexpr_t _z_declared_keyexpr_alias_from_string(const _z_string_t *str) {
    _z_declared_keyexpr_t ke = _z_declared_keyexpr_null();
    ke._inner = _z_keyexpr_alias_from_string(str);
    return ke;
}

_z_declared_keyexpr_t _z_declared_keyexpr_alias_from_substr(const char *str, size_t len) {
    _z_declared_keyexpr_t ke = _z_declared_keyexpr_null();
    ke._inner = _z_keyexpr_alias_from_substr(str, len);
    return ke;
}

z_result_t _z_keyexpr_from_string(_z_keyexpr_t *dst, const _z_string_t *str) {
    return _z_keyexpr_from_substr(dst, _z_string_data(str), _z_string_len(str));
}

z_result_t _z_keyexpr_from_substr(_z_keyexpr_t *dst, const char *str, size_t len) {
    *dst = _z_keyexpr_null();
    dst->_keyexpr = _z_string_copy_from_substr(str, len);
    return _z_string_check(&dst->_keyexpr) ? _Z_RES_OK : _Z_ERR_SYSTEM_OUT_OF_MEMORY;
}

z_result_t _z_declared_keyexpr_copy(_z_declared_keyexpr_t *dst, const _z_declared_keyexpr_t *src) {
    *dst = _z_declared_keyexpr_null();
    _Z_RETURN_IF_ERR(_z_keyexpr_copy(&dst->_inner, &src->_inner));
    if (!_Z_RC_IS_NULL(&src->_declaration)) {
        dst->_declaration = _z_keyexpr_wire_declaration_rc_clone(&src->_declaration);
    }
    return _Z_RES_OK;
}

z_result_t _z_declared_keyexpr_move(_z_declared_keyexpr_t *dst, _z_declared_keyexpr_t *src) {
    *dst = _z_declared_keyexpr_null();
    _Z_RETURN_IF_ERR(_z_keyexpr_move(&dst->_inner, &src->_inner));
    dst->_declaration = src->_declaration;
    src->_declaration = _z_keyexpr_wire_declaration_rc_null();
    return _Z_RES_OK;
}

/*------------------ Canonize helpers ------------------*/
zp_keyexpr_canon_status_t __zp_canon_prefix(const char *start, size_t *len) {
    zp_keyexpr_canon_status_t ret = Z_KEYEXPR_CANON_SUCCESS;

    bool in_big_wild = false;
    char const *chunk_start = start;
    const char *end = _z_cptr_char_offset(start, (ptrdiff_t)(*len));
    char const *next_slash;

    do {
        next_slash = memchr(chunk_start, '/', _z_ptr_char_diff(end, chunk_start));
        const char *chunk_end = next_slash ? next_slash : end;
        size_t chunk_len = _z_ptr_char_diff(chunk_end, chunk_start);
        switch (chunk_len) {
            case 0: {
                ret = Z_KEYEXPR_CANON_EMPTY_CHUNK;
            } break;

            case 1: {
                if (in_big_wild && (chunk_start[0] == '*')) {
                    *len = _z_ptr_char_diff(chunk_start, start) - (size_t)3;
                    ret = Z_KEYEXPR_CANON_SINGLE_STAR_AFTER_DOUBLE_STAR;
                } else {
                    chunk_start = _z_cptr_char_offset(chunk_end, 1);
                    continue;
                }
            } break;

            case 2:
                if (chunk_start[1] == '*') {
                    if (chunk_start[0] == '$') {
                        *len = _z_ptr_char_diff(chunk_start, start);
                        ret = Z_KEYEXPR_CANON_LONE_DOLLAR_STAR;
                    } else if (chunk_start[0] == '*') {
                        if (in_big_wild) {
                            *len = _z_ptr_char_diff(chunk_start, start) - (size_t)3;
                            ret = Z_KEYEXPR_CANON_DOUBLE_STAR_AFTER_DOUBLE_STAR;
                        } else {
                            chunk_start = _z_cptr_char_offset(chunk_end, 1);
                            in_big_wild = true;
                            continue;
                        }
                    } else {
                        // Do nothing. Required to be compliant with MISRA 15.7 rule
                    }
                } else {
                    // Do nothing. Required to be compliant with MISRA 15.7 rule
                }
                break;

            default:
                break;
        }

        unsigned char in_dollar = 0;
        for (char const *c = chunk_start; (c < chunk_end) && (ret == Z_KEYEXPR_CANON_SUCCESS);
             c = _z_cptr_char_offset(c, 1)) {
            switch (c[0]) {
                case '#':
                case '?': {
                    ret = Z_KEYEXPR_CANON_CONTAINS_SHARP_OR_QMARK;
                } break;

                case '$': {
                    if (in_dollar != (unsigned char)0) {
                        ret = Z_KEYEXPR_CANON_DOLLAR_AFTER_DOLLAR_OR_STAR;
                    } else {
                        in_dollar = in_dollar + (unsigned char)1;
                    }
                } break;

                case '*': {
                    if (in_dollar != (unsigned char)1) {
                        ret = Z_KEYEXPR_CANON_STARS_IN_CHUNK;
                    } else {
                        in_dollar = in_dollar + (unsigned char)2;
                    }
                } break;

                default: {
                    if (in_dollar == (unsigned char)1) {
                        ret = Z_KEYEXPR_CANON_CONTAINS_UNBOUND_DOLLAR;
                    } else {
                        in_dollar = 0;
                    }
                } break;
            }
        }

        if (ret == Z_KEYEXPR_CANON_SUCCESS) {
            if (in_dollar == (unsigned char)1) {
                ret = Z_KEYEXPR_CANON_CONTAINS_UNBOUND_DOLLAR;
            } else {
                chunk_start = _z_cptr_char_offset(chunk_end, 1);
                in_big_wild = false;
            }
        }
    } while ((chunk_start < end) && (ret == Z_KEYEXPR_CANON_SUCCESS));

    if (ret == Z_KEYEXPR_CANON_SUCCESS) {
        if (chunk_start <= end) {
            ret = Z_KEYEXPR_CANON_EMPTY_CHUNK;
        }
    }

    return ret;
}

void __zp_singleify(char *start, size_t *len, const char *needle) {
    const char *end = _z_cptr_char_offset(start, (ptrdiff_t)(*len));
    bool right_after_needle = false;
    char *reader = start;

    while (reader < end) {
        size_t pos = _z_str_startswith(reader, needle);
        if (pos != (size_t)0) {
            if (right_after_needle == true) {
                break;
            }
            right_after_needle = true;
            reader = _z_ptr_char_offset(reader, (ptrdiff_t)pos);
        } else {
            right_after_needle = false;
            reader = _z_ptr_char_offset(reader, 1);
        }
    }

    char *writer = reader;
    while (reader < end) {
        size_t pos = _z_str_startswith(reader, needle);
        if (pos != (size_t)0) {
            if (right_after_needle == false) {
                for (size_t i = 0; i < pos; i++) {
                    writer[i] = reader[i];
                }
                writer = _z_ptr_char_offset(writer, (ptrdiff_t)pos);
            }
            right_after_needle = true;
            reader = _z_ptr_char_offset(reader, (ptrdiff_t)pos);
        } else {
            right_after_needle = false;
            *writer = *reader;
            writer = _z_ptr_char_offset(writer, 1);
            reader = _z_ptr_char_offset(reader, 1);
        }
    }
    *len = _z_ptr_char_diff(writer, start);
}

void __zp_ke_write_chunk(char **writer, const char *chunk, size_t len, const char *write_start) {
    if (writer[0] != write_start) {
        writer[0][0] = '/';
        writer[0] = _z_ptr_char_offset(writer[0], 1);
    }

    (void)memmove(writer[0], chunk, len);
    writer[0] = _z_ptr_char_offset(writer[0], (ptrdiff_t)len);
}

/*------------------ Common helpers ------------------*/
typedef bool (*_z_ke_chunk_matcher)(_z_str_se_t l, _z_str_se_t r);

enum _zp_wildness_t { _ZP_WILDNESS_ANY = 1, _ZP_WILDNESS_SUPERCHUNKS = 2, _ZP_WILDNESS_SUBCHUNK_DSL = 4 };
int8_t _zp_ke_wildness(_z_str_se_t ke, size_t *n_segments, size_t *n_verbatims) {
    const char *start = ke.start;
    const char *end = ke.end;
    int8_t result = 0;
    char prev_char = 0;
    for (char const *c = start; c < end; c = _z_cptr_char_offset(c, 1)) {
        switch (c[0]) {
            case '*': {
                result = result | (int8_t)_ZP_WILDNESS_ANY;
                if (prev_char == '*') {
                    result = result | (int8_t)_ZP_WILDNESS_SUPERCHUNKS;
                }
            } break;

            case '$': {
                result = result | (int8_t)_ZP_WILDNESS_SUBCHUNK_DSL;
            } break;

            case '/': {
                *n_segments = *n_segments + (size_t)1;
            } break;
            case '@': {
                *n_verbatims = *n_verbatims + (size_t)1;
            }
            default: {
                // Do nothing
            } break;
        }

        prev_char = *c;
    }

    return result;
}

const char *_Z_DOUBLE_STAR = "**";
const char *_Z_DOLLAR_STAR = "$*";

zp_keyexpr_canon_status_t _z_keyexpr_canonize(char *start, size_t *len) {
    __zp_singleify(start, len, "$*");
    size_t canon_len = *len;
    zp_keyexpr_canon_status_t ret = __zp_canon_prefix(start, &canon_len);

    if ((ret == Z_KEYEXPR_CANON_LONE_DOLLAR_STAR) || (ret == Z_KEYEXPR_CANON_SINGLE_STAR_AFTER_DOUBLE_STAR) ||
        (ret == Z_KEYEXPR_CANON_DOUBLE_STAR_AFTER_DOUBLE_STAR)) {
        ret = Z_KEYEXPR_CANON_SUCCESS;

        const char *end = _z_cptr_char_offset(start, (ptrdiff_t)(*len));
        char *reader = _z_ptr_char_offset(start, (ptrdiff_t)canon_len);
        const char *write_start = reader;
        char *writer = reader;
        char *next_slash = strchr(reader, '/');
        char const *chunk_end = (next_slash != NULL) ? next_slash : end;

        bool in_big_wild = false;
        if ((_z_ptr_char_diff(chunk_end, reader) == 2) && (reader[1] == '*')) {
            if (reader[0] == '*') {
                in_big_wild = true;
            } else if (reader[0] == '$') {
                writer[0] = '*';
                writer = _z_ptr_char_offset(writer, 1);
            } else {
                assert(false);  // anything before "$*" or "**" must be part of the canon prefix
            }
        } else {
            assert(false);  // anything before "$*" or "**" must be part of the canon prefix
        }
        while (next_slash != NULL) {
            reader = _z_ptr_char_offset(next_slash, 1);
            next_slash = memchr(reader, '/', _z_ptr_char_diff(end, reader));
            chunk_end = next_slash ? next_slash : end;
            switch (_z_ptr_char_diff(chunk_end, reader)) {
                case 0: {
                    ret = Z_KEYEXPR_CANON_EMPTY_CHUNK;
                } break;

                case 1: {
                    if (reader[0] == '*') {
                        __zp_ke_write_chunk(&writer, "*", 1, write_start);
                        continue;
                    }
                } break;

                case 2: {
                    if (reader[1] == '*') {
                        if (reader[0] == '$') {
                            __zp_ke_write_chunk(&writer, "*", 1, write_start);
                            continue;
                        } else if (reader[0] == '*') {
                            in_big_wild = true;
                            continue;
                        } else {
                            // Do nothing. Required to be compliant with MISRA 15.7 rule
                        }
                    }
                } break;

                default:
                    break;
            }

            unsigned char in_dollar = 0;
            for (char const *c = reader; (c < end) && (ret == Z_KEYEXPR_CANON_SUCCESS); c = _z_cptr_char_offset(c, 1)) {
                switch (*c) {
                    case '#':
                    case '?': {
                        ret = Z_KEYEXPR_CANON_CONTAINS_SHARP_OR_QMARK;
                    } break;

                    case '$': {
                        if (in_dollar != (unsigned char)0) {
                            ret = Z_KEYEXPR_CANON_DOLLAR_AFTER_DOLLAR_OR_STAR;
                        } else {
                            in_dollar = in_dollar + (unsigned char)1;
                        }
                    } break;

                    case '*': {
                        if (in_dollar != (unsigned char)1) {
                            ret = Z_KEYEXPR_CANON_STARS_IN_CHUNK;
                        } else {
                            in_dollar = in_dollar + (unsigned char)2;
                        }
                    } break;

                    default: {
                        if (in_dollar == (unsigned char)1) {
                            ret = Z_KEYEXPR_CANON_CONTAINS_UNBOUND_DOLLAR;
                        } else {
                            in_dollar = 0;
                        }
                    } break;
                }
            }

            if ((ret == Z_KEYEXPR_CANON_SUCCESS) && (in_dollar == (unsigned char)1)) {
                ret = Z_KEYEXPR_CANON_CONTAINS_UNBOUND_DOLLAR;
            }

            if (ret == Z_KEYEXPR_CANON_SUCCESS) {
                if (in_big_wild) {
                    __zp_ke_write_chunk(&writer, _Z_DOUBLE_STAR, 2, write_start);
                }

                __zp_ke_write_chunk(&writer, reader, _z_ptr_char_diff(chunk_end, reader), write_start);
                in_big_wild = false;
            }
        }

        if (ret == Z_KEYEXPR_CANON_SUCCESS) {
            if (in_big_wild) {
                __zp_ke_write_chunk(&writer, _Z_DOUBLE_STAR, 2, write_start);
            }
            *len = _z_ptr_char_diff(writer, start);
        }
    }

    return ret;
}

zp_keyexpr_canon_status_t _z_keyexpr_is_canon(const char *start, size_t len) { return __zp_canon_prefix(start, &len); }

z_result_t _z_keyexpr_concat(_z_keyexpr_t *key, const _z_keyexpr_t *left, const char *right, size_t len) {
    *key = _z_keyexpr_null();
    size_t left_len = _z_string_len(&left->_keyexpr);
    if (left_len == 0) {
        return _z_keyexpr_from_substr(key, right, len);
    }
    const char *left_data = _z_string_data(&left->_keyexpr);

    if (left_data[left_len - 1] == '*' && len > 0 && right[0] == '*') {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }
    _Z_RETURN_IF_ERR(_z_string_concat_substr(&key->_keyexpr, &left->_keyexpr, right, len, NULL, 0));

    return _Z_RES_OK;
}

z_result_t _z_declared_keyexpr_concat(_z_declared_keyexpr_t *key, const _z_declared_keyexpr_t *left, const char *right,
                                      size_t len) {
    *key = _z_declared_keyexpr_null();
    _Z_RETURN_IF_ERR(_z_keyexpr_concat(&key->_inner, &left->_inner, right, len));
    if (!_Z_RC_IS_NULL(&left->_declaration)) {
        key->_declaration = _z_keyexpr_wire_declaration_rc_clone(&left->_declaration);
    }
    return _Z_RES_OK;
}

z_result_t _z_keyexpr_join(_z_keyexpr_t *key, const _z_keyexpr_t *left, const _z_keyexpr_t *right) {
    *key = _z_keyexpr_null();

    _Z_RETURN_IF_ERR(_z_string_concat_substr(&key->_keyexpr, &left->_keyexpr, _z_string_data(&right->_keyexpr),
                                             _z_string_len(&right->_keyexpr), "/", 1));
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_canonize((char *)key->_keyexpr._slice.start, &key->_keyexpr._slice.len),
                           _z_keyexpr_clear(key));
    return _Z_RES_OK;
}

z_result_t _z_declared_keyexpr_join(_z_declared_keyexpr_t *key, const _z_declared_keyexpr_t *left,
                                    const _z_declared_keyexpr_t *right) {
    *key = _z_declared_keyexpr_null();
    _Z_RETURN_IF_ERR(_z_keyexpr_join(&key->_inner, &left->_inner, &right->_inner));
    if (!_Z_RC_IS_NULL(&left->_declaration)) {
        key->_declaration = _z_keyexpr_wire_declaration_rc_clone(&left->_declaration);
    }
    return _Z_RES_OK;
}

_z_wireexpr_t _z_declared_keyexpr_alias_to_wire(const _z_declared_keyexpr_t *key, const _z_session_t *session) {
    _z_wireexpr_t expr = _z_wireexpr_null();
    const char *suffix_str = _z_string_data(&key->_inner._keyexpr);
    size_t suffix_len = _z_string_len(&key->_inner._keyexpr);
    if (!_Z_RC_IS_NULL(&key->_declaration) &&
        _z_keyexpr_wire_declaration_is_declared_on_session(_Z_RC_IN_VAL(&key->_declaration), session)) {
        expr._id = _Z_RC_IN_VAL(&key->_declaration)->_id;
        expr._mapping = _Z_KEYEXPR_MAPPING_LOCAL;
        suffix_str = suffix_str + _Z_RC_IN_VAL(&key->_declaration)->_prefix_len;
        suffix_len -= _Z_RC_IN_VAL(&key->_declaration)->_prefix_len;
    }
    if (suffix_len > 0) {
        expr._suffix = _z_string_alias_substr(suffix_str, suffix_len);
    }
    return expr;
}

_z_wireexpr_t _z_keyexpr_alias_to_wire(const _z_keyexpr_t *key) {
    _z_wireexpr_t expr = _z_wireexpr_null();
    expr._suffix = _z_string_alias(key->_keyexpr);
    return expr;
}

z_result_t _z_keyexpr_declare_prefix(const _z_session_rc_t *zs, _z_declared_keyexpr_t *out, const _z_keyexpr_t *keyexpr,
                                     size_t prefix_len) {
    assert(prefix_len <= _z_string_len(&keyexpr->_keyexpr));
    *out = _z_declared_keyexpr_null();
    _Z_RETURN_IF_ERR(_z_string_copy(&out->_inner._keyexpr, &keyexpr->_keyexpr));
    if (prefix_len == 0) {
        return _Z_RES_OK;
    }
#if Z_FEATURE_MULTICAST_DECLARATIONS == 0
    if (_Z_RC_IN_VAL(zs)->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE) {
        // Skip declaration since declaring a keyexpr without Z_FEATURE_MULTICAST_DECLARATIONS might generate unknown
        // key expression errors.
        return _Z_RES_OK;
    }
#endif
    _z_keyexpr_wire_declaration_t declaration = _z_keyexpr_wire_declaration_null();
    out->_declaration = _z_keyexpr_wire_declaration_rc_new_from_val(&declaration);
    if (_Z_RC_IS_NULL(&out->_declaration)) {
        _z_declared_keyexpr_clear(out);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    _z_string_t prefix = _z_string_alias_substr(_z_string_data(&out->_inner._keyexpr), prefix_len);
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_wire_declaration_new(_Z_RC_IN_VAL(&out->_declaration), &prefix, zs),
                           _z_declared_keyexpr_clear(out));
    return _Z_RES_OK;
}

z_result_t _z_declared_keyexpr_declare(const _z_session_rc_t *zs, _z_declared_keyexpr_t *out,
                                       const _z_declared_keyexpr_t *keyexpr) {
    if (_z_declared_keyexpr_is_fully_optimized(keyexpr, _Z_RC_IN_VAL(zs))) {
        return _z_declared_keyexpr_copy(out, keyexpr);
    } else {
        return _z_keyexpr_declare_prefix(zs, out, &keyexpr->_inner, _z_string_len(&keyexpr->_inner._keyexpr));
    }
}

size_t _z_keyexpr_non_wild_prefix_len(const _z_keyexpr_t *key) {
    const char *data = _z_string_data(&key->_keyexpr);
    size_t len = _z_string_len(&key->_keyexpr);
    char *pos = (char *)memchr(data, '*', len);
    if (pos == NULL) {
        return len;
    }
    while (pos != data && *pos != '/') {
        pos--;
    }

    return _z_ptr_char_diff(pos, data);
}

z_result_t _z_declared_keyexpr_declare_non_wild_prefix(const _z_session_rc_t *zs, _z_declared_keyexpr_t *out,
                                                       const _z_declared_keyexpr_t *keyexpr) {
    if (_z_declared_keyexpr_is_non_wild_prefix_optimized(keyexpr, _Z_RC_IN_VAL(zs))) {
        return _z_declared_keyexpr_copy(out, keyexpr);
    } else {
        return _z_keyexpr_declare_prefix(zs, out, &keyexpr->_inner, _z_keyexpr_non_wild_prefix_len(&keyexpr->_inner));
    }
}

#define _ZP_KE_MATCH_TEMPLATE_INTERSECTS true
#include "zenoh-pico/session/keyexpr_match_template.h"
#define _ZP_KE_MATCH_TEMPLATE_INTERSECTS false
#include "zenoh-pico/session/keyexpr_match_template.h"

bool _z_keyexpr_intersects(const _z_keyexpr_t *left, const _z_keyexpr_t *right) {
    size_t left_len = _z_string_len(&left->_keyexpr);
    size_t right_len = _z_string_len(&right->_keyexpr);
    const char *left_start = _z_string_data(&left->_keyexpr);
    const char *right_start = _z_string_data(&right->_keyexpr);

    // fast path for identical key expressions, do we really need it ?
    if ((left_len == right_len) && (strncmp(left_start, right_start, left_len) == 0)) {
        return true;
    }

    return _z_keyexpr_forward_intersects(left_start, left_start + left_len, right_start, right_start + right_len, true);
}

bool _z_keyexpr_includes(const _z_keyexpr_t *left, const _z_keyexpr_t *right) {
    size_t left_len = _z_string_len(&left->_keyexpr);
    size_t right_len = _z_string_len(&right->_keyexpr);
    const char *left_start = _z_string_data(&left->_keyexpr);
    const char *right_start = _z_string_data(&right->_keyexpr);

    // fast path for identical key expressions, do we really need it ?
    if ((left_len == right_len) && (strncmp(left_start, right_start, left_len) == 0)) {
        return true;
    }

    return _z_keyexpr_forward_includes(left_start, left_start + left_len, right_start, right_start + right_len, true);
}
