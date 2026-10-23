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

#ifndef ZENOH_PICO_COLLECTIONS_LRUCACHE_H
#define ZENOH_PICO_COLLECTIONS_LRUCACHE_H

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

// Three way comparison function pointer
typedef int (*_z_lru_val_cmp_f)(const void *first, const void *second);

// Node struct: {node_data; generic type}
typedef void _z_lru_cache_node_t;

/*-------- Dynamically allocated vector --------*/
/**
 * A least recently used cache implementation
 */
typedef struct _z_lru_cache_t {
    size_t capacity;              // Max number of node
    size_t len;                   // Number of node
    _z_lru_cache_node_t *head;    // List head
    _z_lru_cache_node_t *tail;    // List tail
    _z_lru_cache_node_t **slist;  // Sorted node list
} _z_lru_cache_t;

_z_lru_cache_t _z_lru_cache_init(size_t capacity);
void *_z_lru_cache_get(_z_lru_cache_t *cache, void *value, _z_lru_val_cmp_f compare);
z_result_t _z_lru_cache_insert(_z_lru_cache_t *cache, void *value, size_t value_size, _z_lru_val_cmp_f compare);
void _z_lru_cache_clear(_z_lru_cache_t *cache, z_element_clear_f clear);
void _z_lru_cache_delete(_z_lru_cache_t *cache, z_element_clear_f clear);

#define _Z_LRU_CACHE_DEFINE(name, type, compare_f)                                                                  \
    typedef _z_lru_cache_t name##_lru_cache_t;                                                                      \
    static inline name##_lru_cache_t name##_lru_cache_init(size_t capacity) { return _z_lru_cache_init(capacity); } \
    static inline type *name##_lru_cache_get(name##_lru_cache_t *cache, type *val) {                                \
        return (type *)_z_lru_cache_get(cache, (void *)val, compare_f);                                             \
    }                                                                                                               \
    static inline z_result_t name##_lru_cache_insert(name##_lru_cache_t *cache, type *val) {                        \
        return _z_lru_cache_insert(cache, (void *)val, sizeof(type), compare_f);                                    \
    }                                                                                                               \
    static inline void name##_lru_cache_clear(name##_lru_cache_t *cache) {                                          \
        _z_lru_cache_clear(cache, name##_elem_clear);                                                               \
    }                                                                                                               \
    static inline void name##_lru_cache_delete(name##_lru_cache_t *cache) {                                         \
        _z_lru_cache_delete(cache, name##_elem_clear);                                                              \
    }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_LRUCACHE_H */
