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

#include "zenoh-pico/collections/hashmap.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

#include "zenoh-pico/utils/logging.h"

/*-------- hashmap --------*/
void _z_hashmap_init(_z_hashmap_t *map, size_t capacity, z_element_hash_f f_hash, z_element_eq_f f_equals) {
    map->_capacity = capacity;
    map->_vals = NULL;
    map->_f_hash = f_hash;
    map->_f_equals = f_equals;
}

_z_hashmap_t _z_hashmap_make(size_t capacity, z_element_hash_f f_hash, z_element_eq_f f_equals) {
    _z_hashmap_t map;
    _z_hashmap_init(&map, capacity, f_hash, f_equals);
    return map;
}

size_t _z_hashmap_capacity(const _z_hashmap_t *map) { return map->_capacity; }

size_t _z_hashmap_len(const _z_hashmap_t *map) {
    size_t len = 0;

    if (map->_vals != NULL) {
        for (size_t idx = 0; idx < map->_capacity; idx++) {
            len = len + _z_list_len(map->_vals[idx]);
        }
    }

    return len;
}

z_result_t _z_hashmap_copy(_z_hashmap_t *dst, const _z_hashmap_t *src, z_element_clone_f f_c) {
    assert((dst != NULL) && (src != NULL) && (dst->_capacity == src->_capacity));
    for (size_t idx = 0; idx < src->_capacity; idx++) {
        const _z_list_t *src_list = src->_vals[idx];
        if (src_list == NULL) {
            continue;
        }
        // Allocate entry
        dst->_vals[idx] = _z_list_clone(src_list, f_c);
        if (dst->_vals[idx] == NULL) {
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
    }
    dst->_f_hash = src->_f_hash;
    dst->_f_equals = src->_f_equals;
    return _Z_RES_OK;
}

_z_hashmap_t _z_hashmap_clone(const _z_hashmap_t *src, z_element_clone_f f_c, z_element_free_f f_f) {
    _z_hashmap_t dst = {
        ._capacity = src->_capacity, ._vals = NULL, ._f_hash = src->_f_hash, ._f_equals = src->_f_equals};
    if (src->_vals == NULL) {
        return dst;
    }
    // Lazily allocate and initialize to NULL all the pointers
    size_t len = dst._capacity * sizeof(_z_list_t *);
    dst._vals = (_z_list_t **)z_malloc(len);
    if (dst._vals == NULL) {
        return dst;
    }
    (void)memset(dst._vals, 0, len);
    // Copy elements
    if (_z_hashmap_copy(&dst, src, f_c) != _Z_RES_OK) {
        // Free the map
        _z_hashmap_clear(&dst, f_f);
    }
    return dst;
}

bool _z_hashmap_is_empty(const _z_hashmap_t *map) { return _z_hashmap_len(map) == (size_t)0; }

void _z_hashmap_remove(_z_hashmap_t *map, const void *k, z_element_free_f f) {
    if (map->_vals != NULL) {
        size_t idx = map->_f_hash(k) % map->_capacity;
        _z_hashmap_entry_t e;
        e._key = (void *)k;  // k will not be mutated by this operation
        e._val = NULL;

        map->_vals[idx] = _z_list_drop_filter(map->_vals[idx], f, map->_f_equals, &e, true);
    }
}

_z_hashmap_entry_t _z_hashmap_extract(_z_hashmap_t *map, const void *key) {
    _z_hashmap_entry_t out;
    out._key = NULL;
    out._val = NULL;
    if (map->_vals != NULL) {
        size_t idx = map->_f_hash(key) % map->_capacity;
        _z_hashmap_entry_t e;
        e._key = (void *)key;  // k will not be mutated by this operation
        e._val = NULL;
        _z_list_t *extracted;
        map->_vals[idx] = _z_list_extract_filter(map->_vals[idx], map->_f_equals, &e, &extracted, true);
        if (extracted != NULL) {
            _z_hashmap_entry_t *kv = (_z_hashmap_entry_t *)((extracted)->_val);
            out._key = kv->_key;
            out._val = kv->_val;
            z_free(kv);
            z_free(extracted);
        }
    }
    return out;
}

void *_z_hashmap_insert(_z_hashmap_t *map, void *k, void *v, z_element_free_f f_f, bool replace) {
    if (map->_vals == NULL) {
        // Lazily allocate and initialize to NULL all the pointers
        size_t len = map->_capacity * sizeof(_z_list_t *);
        map->_vals = (_z_list_t **)z_malloc(len);
        if (map->_vals != NULL) {
            (void)memset(map->_vals, 0, len);
        } else {
            return NULL;
        }
    }

    if (replace) {
        // Free any old value
        _z_hashmap_remove(map, k, f_f);
    }

    // Insert the element
    _z_hashmap_entry_t *entry = (_z_hashmap_entry_t *)z_malloc(sizeof(_z_hashmap_entry_t));
    if (entry != NULL) {
        entry->_key = k;
        entry->_val = v;

        size_t idx = map->_f_hash(k) % map->_capacity;
        map->_vals[idx] = _z_list_push(map->_vals[idx], entry);
    } else {
        return NULL;
    }

    return v;
}

void *_z_hashmap_get(const _z_hashmap_t *map, const void *k) {
    void *ret = NULL;

    if (map->_vals != NULL) {
        size_t idx = map->_f_hash(k) % map->_capacity;

        _z_hashmap_entry_t e;
        e._key = (void *)k;  // k will not be mutated by this operation
        e._val = NULL;

        _z_list_t *xs = _z_list_find(map->_vals[idx], map->_f_equals, &e);
        if (xs != NULL) {
            _z_hashmap_entry_t *h = (_z_hashmap_entry_t *)_z_list_value(xs);
            ret = h->_val;
        }
    }

    return ret;
}

_z_list_t *_z_hashmap_get_all(const _z_hashmap_t *map, const void *k) {
    if (map->_vals != NULL) {
        size_t idx = map->_f_hash(k) % map->_capacity;

        _z_hashmap_entry_t e;
        e._key = (void *)k;  // k will not be mutated by this operation
        e._val = NULL;

        return _z_list_find(map->_vals[idx], map->_f_equals, &e);
    }
    return NULL;
}

_z_hashmap_iterator_t _z_hashmap_iterator_make(const _z_hashmap_t *map) {
    _z_hashmap_iterator_t iter = {0};

    iter._map = map;

    return iter;
}

bool _z_hashmap_iterator_next(_z_hashmap_iterator_t *iter) {
    if (iter->_map->_vals == NULL) {
        return false;
    }

    while (iter->_idx < iter->_map->_capacity) {
        if (iter->_list_ptr == NULL) {
            iter->_list_ptr = iter->_map->_vals[iter->_idx];
        } else {
            iter->_list_ptr = _z_list_next(iter->_list_ptr);
        }
        if (iter->_list_ptr == NULL) {
            iter->_idx++;
            continue;
        }

        iter->_entry = iter->_list_ptr->_val;

        return true;
    }
    return false;
}

void *_z_hashmap_iterator_key(const _z_hashmap_iterator_t *iter) { return iter->_entry->_key; }

void *_z_hashmap_iterator_value(const _z_hashmap_iterator_t *iter) { return iter->_entry->_val; }

void _z_hashmap_clear(_z_hashmap_t *map, z_element_free_f f_f) {
    if (map->_vals != NULL) {
        for (size_t idx = 0; idx < map->_capacity; idx++) {
            _z_list_free(&map->_vals[idx], f_f);
        }

        z_free(map->_vals);
        map->_vals = NULL;
    }
}

void _z_hashmap_free(_z_hashmap_t **map, z_element_free_f f) {
    _z_hashmap_t *ptr = *map;
    if (ptr != NULL) {
        _z_hashmap_clear(ptr, f);

        z_free(ptr);
        *map = NULL;
    }
}
