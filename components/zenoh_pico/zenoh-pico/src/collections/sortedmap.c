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

#include "zenoh-pico/collections/sortedmap.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

#include "zenoh-pico/utils/logging.h"

/*-------- sortedmap --------*/
void _z_sortedmap_init(_z_sortedmap_t *map, z_element_cmp_f f_cmp) {
    map->_vals = NULL;
    map->_f_cmp = f_cmp;
}

_z_sortedmap_t _z_sortedmap_make(z_element_cmp_f f_cmp) {
    _z_sortedmap_t map;
    _z_sortedmap_init(&map, f_cmp);
    return map;
}

size_t _z_sortedmap_len(const _z_sortedmap_t *map) { return _z_list_len(map->_vals); }

bool _z_sortedmap_is_empty(const _z_sortedmap_t *map) { return _z_sortedmap_len(map) == (size_t)0; }

z_result_t _z_sortedmap_copy(_z_sortedmap_t *dst, const _z_sortedmap_t *src, z_element_clone_f f_c) {
    assert((dst != NULL) && (src != NULL));
    if (src->_vals != NULL) {
        dst->_vals = _z_list_clone(src->_vals, f_c);
        if (dst->_vals == NULL) {
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
    }
    dst->_f_cmp = src->_f_cmp;
    return _Z_RES_OK;
}

_z_sortedmap_t _z_sortedmap_clone(const _z_sortedmap_t *src, z_element_clone_f f_c, z_element_free_f f_f) {
    _z_sortedmap_t dst = {._vals = NULL, ._f_cmp = src->_f_cmp};
    if (src->_vals == NULL) {
        return dst;
    }
    if (_z_sortedmap_copy(&dst, src, f_c) != _Z_RES_OK) {
        // Free the map
        _z_sortedmap_clear(&dst, f_f);
    }
    return dst;
}

void *_z_sortedmap_insert(_z_sortedmap_t *map, void *k, void *v, z_element_free_f f_f, bool replace) {
    if (map == NULL) {
        return NULL;
    }

    _z_list_t *prev = NULL;
    _z_list_t *curr = map->_vals;

    while (curr != NULL) {
        _z_sortedmap_entry_t *entry = (_z_sortedmap_entry_t *)_z_list_value(curr);
        int cmp = map->_f_cmp(k, entry->_key);

        if (cmp == 0) {
            if (!replace) {
                return NULL;
            }
            map->_vals = _z_list_drop_element(map->_vals, prev, f_f);
            break;
        } else if (cmp < 0) {
            break;  // Found insertion point
        }

        prev = curr;
        curr = _z_list_next(curr);
    }

    _z_sortedmap_entry_t *entry = (_z_sortedmap_entry_t *)z_malloc(sizeof(_z_sortedmap_entry_t));
    if (entry == NULL) {
        return NULL;
    }
    entry->_key = k;
    entry->_val = v;

    if (prev == NULL) {
        map->_vals = _z_list_push(map->_vals, entry);
        if (map->_vals == NULL) {
            z_free(entry);
            return NULL;
        }
    } else {
        _z_list_t *list = _z_list_push_after(prev, entry);
        if (list == NULL) {
            z_free(entry);
            return NULL;
        }
    }

    return v;
}

void *_z_sortedmap_get(const _z_sortedmap_t *map, const void *k) {
    void *ret = NULL;

    if (map->_vals != NULL) {
        _z_list_t *l = map->_vals;
        while (l != NULL) {
            // Check if the key matches
            _z_sortedmap_entry_t *entry = (_z_sortedmap_entry_t *)_z_list_value(l);
            if (map->_f_cmp(k, entry->_key) == 0) {
                ret = entry->_val;
                break;
            }
            l = _z_list_next(l);
        }
    }
    return ret;
}

_z_sortedmap_entry_t *_z_sortedmap_pop_first(_z_sortedmap_t *map) {
    _z_sortedmap_entry_t *ret = NULL;

    if (map->_vals != NULL) {
        _z_list_t *l = map->_vals;
        if (l != NULL) {
            ret = (_z_sortedmap_entry_t *)_z_list_value(l);
            map->_vals = _z_list_drop_element(map->_vals, NULL, _z_noop_free);
        }
    }
    return ret;
}

void _z_sortedmap_remove(_z_sortedmap_t *map, const void *k, z_element_free_f f) {
    if (map->_vals != NULL) {
        _z_list_t *prev = NULL;
        _z_list_t *curr = map->_vals;

        while (curr != NULL) {
            _z_sortedmap_entry_t *entry = (_z_sortedmap_entry_t *)_z_list_value(curr);
            if (map->_f_cmp(k, entry->_key) == 0) {
                map->_vals = _z_list_drop_element(map->_vals, prev, f);
                break;
            }
            prev = curr;
            curr = _z_list_next(curr);
        }
    }
}

_z_sortedmap_iterator_t _z_sortedmap_iterator_make(const _z_sortedmap_t *map) {
    _z_sortedmap_iterator_t iter = {0};
    iter._map = map;
    iter._list_ptr = map->_vals;
    return iter;
}

bool _z_sortedmap_iterator_next(_z_sortedmap_iterator_t *iter) {
    if (!iter->_initialized) {
        iter->_list_ptr = iter->_map->_vals;
        iter->_initialized = true;
    } else if (iter->_list_ptr != NULL) {
        iter->_list_ptr = _z_list_next(iter->_list_ptr);
    }

    if (iter->_list_ptr != NULL) {
        iter->_entry = (_z_sortedmap_entry_t *)_z_list_value(iter->_list_ptr);
        return true;
    }

    return false;
}

void *_z_sortedmap_iterator_key(const _z_sortedmap_iterator_t *iter) { return iter->_entry->_key; }

void *_z_sortedmap_iterator_value(const _z_sortedmap_iterator_t *iter) { return iter->_entry->_val; }

void _z_sortedmap_clear(_z_sortedmap_t *map, z_element_free_f f_f) {
    if (map->_vals != NULL) {
        _z_list_free(&map->_vals, f_f);
        map->_vals = NULL;
    }
}

void _z_sortedmap_free(_z_sortedmap_t **map, z_element_free_f f) {
    _z_sortedmap_t *ptr = *map;
    if (ptr != NULL) {
        _z_sortedmap_clear(ptr, f);

        z_free(ptr);
        *map = NULL;
    }
}
