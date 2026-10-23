//
// Copyright (c) 2025 ZettaScale Technology
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

#ifndef ZENOH_PICO_COLLECTIONS_HASHMAP_H
#define ZENOH_PICO_COLLECTIONS_HASHMAP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/list.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

#define _Z_DEFAULT_HASHMAP_CAPACITY 16

/**
 * A hashmap entry with generic keys.
 *
 * Members:
 *   void *_key: the key of the entry
 *   void *_val: the value of the entry
 */
typedef struct {
    void *_key;
    void *_val;
} _z_hashmap_entry_t;

/**
 * A hashmap with generic keys.
 *
 * Members:
 *    size_t _capacity: the number of buckets available in the hashmap
 *   _z_list_t **_vals: the linked list containing the values
 *   z_element_hash_f _f_hash: the hash function used to hash keys
 *   z_element_eq_f _f_equals: the function used to compare keys for equality
 */
typedef struct {
    size_t _capacity;
    _z_list_t **_vals;
    z_element_hash_f _f_hash;
    z_element_eq_f _f_equals;
} _z_hashmap_t;

/**
 * Iterator for a generic key-value hashmap.
 */
typedef struct {
    _z_hashmap_entry_t *_entry;
    const _z_hashmap_t *_map;
    size_t _idx;
    _z_list_t *_list_ptr;
} _z_hashmap_iterator_t;

void _z_hashmap_init(_z_hashmap_t *map, size_t capacity, z_element_hash_f f_hash, z_element_eq_f f_equals);
_z_hashmap_t _z_hashmap_make(size_t capacity, z_element_hash_f f_hash, z_element_eq_f f_equals);

void *_z_hashmap_insert(_z_hashmap_t *map, void *key, void *val, z_element_free_f f, bool replace);
void *_z_hashmap_get(const _z_hashmap_t *map, const void *key);
_z_list_t *_z_hashmap_get_all(const _z_hashmap_t *map, const void *key);
void _z_hashmap_remove(_z_hashmap_t *map, const void *key, z_element_free_f f);
_z_hashmap_entry_t _z_hashmap_extract(_z_hashmap_t *map, const void *key);

size_t _z_hashmap_capacity(const _z_hashmap_t *map);
size_t _z_hashmap_len(const _z_hashmap_t *map);
bool _z_hashmap_is_empty(const _z_hashmap_t *map);

z_result_t _z_hashmap_copy(_z_hashmap_t *dst, const _z_hashmap_t *src, z_element_clone_f f_c);
_z_hashmap_t _z_hashmap_clone(const _z_hashmap_t *src, z_element_clone_f f_c, z_element_free_f f_f);

void _z_hashmap_clear(_z_hashmap_t *map, z_element_free_f f);
void _z_hashmap_free(_z_hashmap_t **map, z_element_free_f f);
static inline void _z_hashmap_move(_z_hashmap_t *dst, _z_hashmap_t *src) {
    *dst = *src;
    *src = _z_hashmap_make(src->_capacity, src->_f_hash, src->_f_equals);
}

_z_hashmap_iterator_t _z_hashmap_iterator_make(const _z_hashmap_t *map);
bool _z_hashmap_iterator_next(_z_hashmap_iterator_t *iter);
void *_z_hashmap_iterator_key(const _z_hashmap_iterator_t *iter);
void *_z_hashmap_iterator_value(const _z_hashmap_iterator_t *iter);

#define _Z_HASHMAP_DEFINE_INNER(map_name, key_name, val_name, key_type, val_type)                                     \
    typedef _z_hashmap_entry_t map_name##_hashmap_entry_t;                                                            \
    static inline void map_name##_hashmap_entry_elem_free(void **e) {                                                 \
        map_name##_hashmap_entry_t *ptr = (map_name##_hashmap_entry_t *)*e;                                           \
        if (ptr != NULL) {                                                                                            \
            key_name##_elem_free(&ptr->_key);                                                                         \
            val_name##_elem_free(&ptr->_val);                                                                         \
            z_free(ptr);                                                                                              \
            *e = NULL;                                                                                                \
        }                                                                                                             \
    }                                                                                                                 \
    static inline void *map_name##_hashmap_entry_elem_clone(const void *e) {                                          \
        const map_name##_hashmap_entry_t *src = (map_name##_hashmap_entry_t *)e;                                      \
        map_name##_hashmap_entry_t *dst = (map_name##_hashmap_entry_t *)z_malloc(sizeof(map_name##_hashmap_entry_t)); \
        dst->_key = key_name##_elem_clone(src->_key);                                                                 \
        dst->_val = val_name##_elem_clone(src->_val);                                                                 \
        return dst;                                                                                                   \
    }                                                                                                                 \
    static inline bool map_name##_hashmap_entry_key_eq(const void *left, const void *right) {                         \
        const map_name##_hashmap_entry_t *l = (const map_name##_hashmap_entry_t *)left;                               \
        const map_name##_hashmap_entry_t *r = (const map_name##_hashmap_entry_t *)right;                              \
        return key_name##_elem_eq(l->_key, r->_key);                                                                  \
    }                                                                                                                 \
    typedef _z_hashmap_t map_name##_hashmap_t;                                                                        \
    typedef _z_hashmap_iterator_t map_name##_hashmap_iterator_t;                                                      \
    static inline void map_name##_hashmap_init(map_name##_hashmap_t *m) {                                             \
        _z_hashmap_init(m, _Z_DEFAULT_HASHMAP_CAPACITY, key_name##_elem_hash, map_name##_hashmap_entry_key_eq);       \
    }                                                                                                                 \
    static inline map_name##_hashmap_t map_name##_hashmap_make(void) {                                                \
        return _z_hashmap_make(_Z_DEFAULT_HASHMAP_CAPACITY, key_name##_elem_hash, map_name##_hashmap_entry_key_eq);   \
    }                                                                                                                 \
    static inline val_type *map_name##_hashmap_insert(map_name##_hashmap_t *m, key_type *k, val_type *v) {            \
        return (val_type *)_z_hashmap_insert(m, k, v, map_name##_hashmap_entry_elem_free, true);                      \
    }                                                                                                                 \
    static inline val_type *map_name##_hashmap_insert_push(map_name##_hashmap_t *m, key_type *k, val_type *v) {       \
        return (val_type *)_z_hashmap_insert(m, k, v, map_name##_hashmap_entry_elem_free, false);                     \
    }                                                                                                                 \
    static inline val_type *map_name##_hashmap_get(const map_name##_hashmap_t *m, const key_type *k) {                \
        return (val_type *)_z_hashmap_get(m, k);                                                                      \
    }                                                                                                                 \
    static inline _z_list_t *map_name##_hashmap_get_all(const map_name##_hashmap_t *m, const key_type *k) {           \
        return _z_hashmap_get_all(m, k);                                                                              \
    }                                                                                                                 \
    static inline map_name##_hashmap_t map_name##_hashmap_clone(const map_name##_hashmap_t *m) {                      \
        return _z_hashmap_clone(m, map_name##_hashmap_entry_elem_clone, map_name##_hashmap_entry_elem_free);          \
    }                                                                                                                 \
    static inline void map_name##_hashmap_remove(map_name##_hashmap_t *m, const key_type *k) {                        \
        _z_hashmap_remove(m, k, map_name##_hashmap_entry_elem_free);                                                  \
    }                                                                                                                 \
    static inline map_name##_hashmap_entry_t map_name##_hashmap_extract(map_name##_hashmap_t *m, const key_type *k) { \
        map_name##_hashmap_entry_t out;                                                                               \
        _z_hashmap_entry_t e = _z_hashmap_extract(m, k);                                                              \
        out._key = e._key;                                                                                            \
        out._val = e._val;                                                                                            \
        return out;                                                                                                   \
    }                                                                                                                 \
    static inline size_t map_name##_hashmap_capacity(map_name##_hashmap_t *m) { return _z_hashmap_capacity(m); }      \
    static inline size_t map_name##_hashmap_len(map_name##_hashmap_t *m) { return _z_hashmap_len(m); }                \
    static inline bool map_name##_hashmap_is_empty(const map_name##_hashmap_t *m) { return _z_hashmap_is_empty(m); }  \
    static inline void map_name##_hashmap_clear(map_name##_hashmap_t *m) {                                            \
        _z_hashmap_clear(m, map_name##_hashmap_entry_elem_free);                                                      \
    }                                                                                                                 \
    static inline void map_name##_hashmap_free(map_name##_hashmap_t **m) {                                            \
        _z_hashmap_free(m, map_name##_hashmap_entry_elem_free);                                                       \
    }                                                                                                                 \
    static inline z_result_t map_name##_hashmap_move(map_name##_hashmap_t *dst, map_name##_hashmap_t *src) {          \
        _z_hashmap_move(dst, src);                                                                                    \
        return _Z_RES_OK;                                                                                             \
    }                                                                                                                 \
    static inline map_name##_hashmap_iterator_t map_name##_hashmap_iterator_make(const map_name##_hashmap_t *m) {     \
        return _z_hashmap_iterator_make(m);                                                                           \
    }                                                                                                                 \
    static inline bool map_name##_hashmap_iterator_next(map_name##_hashmap_iterator_t *iter) {                        \
        return _z_hashmap_iterator_next(iter);                                                                        \
    }                                                                                                                 \
    static inline key_type *map_name##_hashmap_iterator_key(const map_name##_hashmap_iterator_t *iter) {              \
        return (key_type *)_z_hashmap_iterator_key(iter);                                                             \
    }                                                                                                                 \
    static inline val_type *map_name##_hashmap_iterator_value(const map_name##_hashmap_iterator_t *iter) {            \
        return (val_type *)_z_hashmap_iterator_value(iter);                                                           \
    }

#define _Z_HASHMAP_DEFINE(key_name, val_name, key_type, val_type) \
    _Z_HASHMAP_DEFINE_INNER(key_name##_##val_name, key_name, val_name, key_type, val_type)

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_HASHMAP_H */
