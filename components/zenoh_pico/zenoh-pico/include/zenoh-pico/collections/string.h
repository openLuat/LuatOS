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

#ifndef ZENOH_PICO_COLLECTIONS_STRING_H
#define ZENOH_PICO_COLLECTIONS_STRING_H

#include "zenoh-pico/collections/array.h"
#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/intmap.h"
#include "zenoh-pico/collections/list.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/collections/vec.h"

#ifdef __cplusplus
extern "C" {
#endif

/*-------- str --------*/
typedef char *_z_str_t;

char *_z_str_clone(const char *src);
char *_z_str_n_clone(const char *src, size_t len);
void _z_str_clear(char *src);
void _z_str_free(char **src);
bool _z_str_eq(const char *left, const char *right);
int _z_str_cmp(const char *left, const char *right);

size_t _z_str_size(const char *src);
void _z_str_copy(char *dst, const char *src);
void _z_str_n_copy(char *dst, const char *src, size_t size);
_Z_ELEM_DEFINE(_z_str, char, _z_str_size, _z_noop_clear, _z_str_copy, _z_noop_move, _z_str_eq, _z_str_cmp, _z_noop_hash)

_Z_VEC_DEFINE(_z_str, char)
_Z_LIST_DEFINE(_z_str, char)
_Z_INT_MAP_DEFINE(_z_str, char)

#define INT_STR_MAP_KEYVALUE_SEPARATOR '='
#define INT_STR_MAP_LIST_SEPARATOR ';'

typedef struct {
    char *_str;
    uint8_t _key;
} _z_str_intmapping_t;

size_t _z_str_intmap_strlen(const _z_str_intmap_t *s, uint8_t argc, _z_str_intmapping_t argv[]);

void _z_str_intmap_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s, uint8_t argc,
                            _z_str_intmapping_t argv[]);
char *_z_str_intmap_to_str(const _z_str_intmap_t *s, uint8_t argc, _z_str_intmapping_t argv[]);

z_result_t _z_str_intmap_from_str(_z_str_intmap_t *strint, const char *s, uint8_t argc, _z_str_intmapping_t argv[]);
z_result_t _z_str_intmap_from_strn(_z_str_intmap_t *strint, const char *s, uint8_t argc, _z_str_intmapping_t argv[],
                                   size_t n);

/*-------- string --------*/
/**
 * A string with no terminator.
 *
 */
typedef struct {
    _z_slice_t _slice;
} _z_string_t;

// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_string_t _z_string_null(void) { return (_z_string_t){0}; }
static inline bool _z_string_check(const _z_string_t *value) { return !_z_slice_is_empty(&value->_slice); }
static inline _z_string_t _z_string_alias(const _z_string_t str) {
    _z_string_t ret;
    ret._slice = _z_slice_alias(str._slice);
    return ret;
}
static inline size_t _z_string_len(const _z_string_t *s) { return s->_slice.len; }
static inline const char *_z_string_data(const _z_string_t *s) { return (const char *)s->_slice.start; }
static inline bool _z_string_is_empty(const _z_string_t *s) { return s->_slice.len == 0; }
static inline _z_string_t _z_string_alias_slice(const _z_slice_t *slice) {
    _z_string_t s;
    s._slice = _z_slice_alias(*slice);
    return s;
}
static inline _z_string_t _z_string_alias_str(const char *value) {
    _z_string_t s;
    s._slice = _z_slice_alias_buf((const uint8_t *)(value), strlen(value));
    return s;
}
static inline _z_string_t _z_string_alias_substr(const char *value, size_t len) {
    _z_string_t s;
    s._slice = _z_slice_alias_buf((const uint8_t *)(value), len);
    return s;
}
static inline _z_string_t _z_string_from_str_custom_deleter(char *value, _z_delete_context_t c) {
    _z_string_t s;
    s._slice = _z_slice_from_buf_custom_deleter((const uint8_t *)(value), strlen(value), c);
    return s;
}
static inline void _z_string_reset(_z_string_t *str) { _z_slice_reset(&str->_slice); }
static inline void _z_string_clear(_z_string_t *str) { _z_slice_clear(&str->_slice); }

_z_string_t _z_string_copy_from_str(const char *value);
_z_string_t _z_string_copy_from_substr(const char *value, size_t len);
_z_string_t *_z_string_copy_from_str_as_ptr(const char *value);
const char *_z_string_rchr(_z_string_t *str, char filter);
char *_z_string_pbrk(_z_string_t *str, const char *filter);

z_result_t _z_string_copy(_z_string_t *dst, const _z_string_t *src);
z_result_t _z_string_copy_substring(_z_string_t *dst, const _z_string_t *src, size_t offset, size_t len);
z_result_t _z_string_move(_z_string_t *dst, _z_string_t *src);
_z_string_t _z_string_steal(_z_string_t *str);
void _z_string_move_str(_z_string_t *dst, char *src);
void _z_string_free(_z_string_t **s);
int _z_string_compare(const _z_string_t *left, const _z_string_t *right);
int _z_substring_compare(const _z_string_t *left, size_t left_start, size_t left_len, const _z_string_t *right,
                         size_t right_start, size_t right_len);
bool _z_string_equals(const _z_string_t *left, const _z_string_t *right);
_z_string_t _z_string_convert_bytes_le(const _z_slice_t *bs);
_z_string_t _z_string_preallocate(const size_t len);
z_result_t _z_string_concat_substr(_z_string_t *s, const _z_string_t *left, const char *right, size_t len,
                                   const char *separator, size_t separator_len);
static inline z_result_t _z_string_concat(_z_string_t *s, const _z_string_t *left, const _z_string_t *right,
                                          const char *separator, size_t separator_len) {
    return _z_string_concat_substr(s, left, _z_string_data(right), _z_string_len(right), separator, separator_len);
}

char *_z_str_from_string_clone(const _z_string_t *str);

_Z_ELEM_DEFINE(_z_string, _z_string_t, _z_string_len, _z_string_clear, _z_string_copy, _z_string_move, _z_string_equals,
               _z_string_compare, _z_noop_hash)
_Z_SVEC_DEFINE(_z_string, _z_string_t)
_Z_LIST_DEFINE(_z_string, _z_string_t)
_Z_INT_MAP_DEFINE(_z_string, _z_string_t)

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_STRING_H */
