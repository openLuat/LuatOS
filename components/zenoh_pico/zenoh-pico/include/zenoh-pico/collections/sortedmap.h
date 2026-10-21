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

#ifndef ZENOH_PICO_COLLECTIONS_SORTEDMAP_H
#define ZENOH_PICO_COLLECTIONS_SORTEDMAP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/list.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * A map entry.
 *
 * Members:
 *   void *_key: the key of the entry
 *   void *_val: the value of the entry
 */
typedef struct {
    void *_key;
    void *_val;
} _z_sortedmap_entry_t;

/**
 * A sorted map.
 *
 * Members:
 *   _z_list_t *_vals: a linked list containing the values
 *   z_element_cmp_f _f_cmp: the function used to compare keys
 */
typedef struct {
    _z_list_t *_vals;
    z_element_cmp_f _f_cmp;
} _z_sortedmap_t;

/**
 * Iterator for a generic key-value hashmap.
 */
typedef struct {
    _z_sortedmap_entry_t *_entry;
    const _z_sortedmap_t *_map;
    _z_list_t *_list_ptr;
    bool _initialized;
} _z_sortedmap_iterator_t;

void _z_sortedmap_init(_z_sortedmap_t *map, z_element_cmp_f f_cmp);
_z_sortedmap_t _z_sortedmap_make(z_element_cmp_f f_cmp);

void *_z_sortedmap_insert(_z_sortedmap_t *map, void *key, void *val, z_element_free_f f, bool replace);
void *_z_sortedmap_get(const _z_sortedmap_t *map, const void *key);
_z_sortedmap_entry_t *_z_sortedmap_pop_first(_z_sortedmap_t *map);
void _z_sortedmap_remove(_z_sortedmap_t *map, const void *key, z_element_free_f f);

size_t _z_sortedmap_len(const _z_sortedmap_t *map);
bool _z_sortedmap_is_empty(const _z_sortedmap_t *map);

z_result_t _z_sortedmap_copy(_z_sortedmap_t *dst, const _z_sortedmap_t *src, z_element_clone_f f_c);
_z_sortedmap_t _z_sortedmap_clone(const _z_sortedmap_t *src, z_element_clone_f f_c, z_element_free_f f_f);

void _z_sortedmap_clear(_z_sortedmap_t *map, z_element_free_f f);
void _z_sortedmap_free(_z_sortedmap_t **map, z_element_free_f f);
static inline void _z_sortedmap_move(_z_sortedmap_t *dst, _z_sortedmap_t *src) {
    *dst = *src;
    *src = _z_sortedmap_make(src->_f_cmp);
}

_z_sortedmap_iterator_t _z_sortedmap_iterator_make(const _z_sortedmap_t *map);
bool _z_sortedmap_iterator_next(_z_sortedmap_iterator_t *iter);
void *_z_sortedmap_iterator_key(const _z_sortedmap_iterator_t *iter);
void *_z_sortedmap_iterator_value(const _z_sortedmap_iterator_t *iter);

#define _Z_SORTEDMAP_DEFINE_INNER(map_name, key_name, val_name, key_type, val_type)                                \
    typedef _z_sortedmap_entry_t map_name##_sortedmap_entry_t;                                                     \
    static inline key_type *map_name##_sortedmap_entry_key(const map_name##_sortedmap_entry_t *entry) {            \
        return (key_type *)entry->_key;                                                                            \
    }                                                                                                              \
    static inline val_type *map_name##_sortedmap_entry_val(const map_name##_sortedmap_entry_t *entry) {            \
        return (val_type *)entry->_val;                                                                            \
    }                                                                                                              \
    static inline void map_name##_sortedmap_entry_free(map_name##_sortedmap_entry_t **entry) {                     \
        map_name##_sortedmap_entry_t *ptr = *entry;                                                                \
        if (ptr != NULL) {                                                                                         \
            key_name##_elem_free(&ptr->_key);                                                                      \
            val_name##_elem_free(&ptr->_val);                                                                      \
            z_free(ptr);                                                                                           \
            *entry = NULL;                                                                                         \
        }                                                                                                          \
    }                                                                                                              \
    static inline void map_name##_sortedmap_entry_elem_free(void **e) {                                            \
        map_name##_sortedmap_entry_free((map_name##_sortedmap_entry_t **)e);                                       \
    }                                                                                                              \
    static inline void *map_name##_sortedmap_entry_elem_clone(const void *e) {                                     \
        const map_name##_sortedmap_entry_t *src = (map_name##_sortedmap_entry_t *)e;                               \
        map_name##_sortedmap_entry_t *dst =                                                                        \
            (map_name##_sortedmap_entry_t *)z_malloc(sizeof(map_name##_sortedmap_entry_t));                        \
        dst->_key = key_name##_elem_clone(src->_key);                                                              \
        dst->_val = val_name##_elem_clone(src->_val);                                                              \
        return dst;                                                                                                \
    }                                                                                                              \
    typedef _z_sortedmap_t map_name##_sortedmap_t;                                                                 \
    typedef _z_sortedmap_iterator_t map_name##_sortedmap_iterator_t;                                               \
    static inline void map_name##_sortedmap_init(map_name##_sortedmap_t *m) {                                      \
        _z_sortedmap_init(m, key_name##_elem_cmp);                                                                 \
    }                                                                                                              \
    static inline map_name##_sortedmap_t map_name##_sortedmap_make(void) {                                         \
        return _z_sortedmap_make(key_name##_elem_cmp);                                                             \
    }                                                                                                              \
    static inline val_type *map_name##_sortedmap_insert(map_name##_sortedmap_t *m, key_type *k, val_type *v) {     \
        return (val_type *)_z_sortedmap_insert(m, k, v, map_name##_sortedmap_entry_elem_free, true);               \
    }                                                                                                              \
    static inline val_type *map_name##_sortedmap_get(const map_name##_sortedmap_t *m, const key_type *k) {         \
        return (val_type *)_z_sortedmap_get(m, k);                                                                 \
    }                                                                                                              \
    static inline map_name##_sortedmap_entry_t *map_name##_sortedmap_pop_first(map_name##_sortedmap_t *m) {        \
        return (map_name##_sortedmap_entry_t *)_z_sortedmap_pop_first(m);                                          \
    }                                                                                                              \
    static inline z_result_t map_name##_sortedmap_copy(map_name##_sortedmap_t *dst,                                \
                                                       const map_name##_sortedmap_t *src) {                        \
        return _z_sortedmap_copy(dst, src, map_name##_sortedmap_entry_elem_clone);                                 \
    }                                                                                                              \
    static inline map_name##_sortedmap_t map_name##_sortedmap_clone(const map_name##_sortedmap_t *m) {             \
        return _z_sortedmap_clone(m, map_name##_sortedmap_entry_elem_clone, map_name##_sortedmap_entry_elem_free); \
    }                                                                                                              \
    static inline void map_name##_sortedmap_remove(map_name##_sortedmap_t *m, const key_type *k) {                 \
        _z_sortedmap_remove(m, k, map_name##_sortedmap_entry_elem_free);                                           \
    }                                                                                                              \
    static inline size_t map_name##_sortedmap_len(map_name##_sortedmap_t *m) { return _z_sortedmap_len(m); }       \
    static inline bool map_name##_sortedmap_is_empty(const map_name##_sortedmap_t *m) {                            \
        return _z_sortedmap_is_empty(m);                                                                           \
    }                                                                                                              \
    static inline void map_name##_sortedmap_clear(map_name##_sortedmap_t *m) {                                     \
        _z_sortedmap_clear(m, map_name##_sortedmap_entry_elem_free);                                               \
    }                                                                                                              \
    static inline void map_name##_sortedmap_free(map_name##_sortedmap_t **m) {                                     \
        _z_sortedmap_free(m, map_name##_sortedmap_entry_elem_free);                                                \
    }                                                                                                              \
    static inline z_result_t map_name##_sortedmap_move(map_name##_sortedmap_t *dst, map_name##_sortedmap_t *src) { \
        _z_sortedmap_move(dst, src);                                                                               \
        return _Z_RES_OK;                                                                                          \
    }                                                                                                              \
    static inline map_name##_sortedmap_iterator_t map_name##_sortedmap_iterator_make(                              \
        const map_name##_sortedmap_t *m) {                                                                         \
        return _z_sortedmap_iterator_make(m);                                                                      \
    }                                                                                                              \
    static inline bool map_name##_sortedmap_iterator_next(map_name##_sortedmap_iterator_t *iter) {                 \
        return _z_sortedmap_iterator_next(iter);                                                                   \
    }                                                                                                              \
    static inline key_type *map_name##_sortedmap_iterator_key(const map_name##_sortedmap_iterator_t *iter) {       \
        return (key_type *)_z_sortedmap_iterator_key(iter);                                                        \
    }                                                                                                              \
    static inline val_type *map_name##_sortedmap_iterator_value(const map_name##_sortedmap_iterator_t *iter) {     \
        return (val_type *)_z_sortedmap_iterator_value(iter);                                                      \
    }

#define _Z_SORTEDMAP_DEFINE(key_name, val_name, key_type, val_type) \
    _Z_SORTEDMAP_DEFINE_INNER(key_name##_##val_name, key_name, val_name, key_type, val_type)

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_SORTEDMAP_H */
