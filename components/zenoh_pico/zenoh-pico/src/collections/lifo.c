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
#include "zenoh-pico/collections/lifo.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

/*-------- lifo --------*/
z_result_t _z_lifo_init(_z_lifo_t *r, size_t capacity) {
    memset(r, 0, sizeof(_z_lifo_t));
    if (capacity != (size_t)0) {
        r->_val = (void **)z_malloc(sizeof(void *) * capacity);
    }
    if (r->_val != NULL) {
        memset(r->_val, 0, capacity);
        r->_capacity = capacity;
    }
    return 0;
}

_z_lifo_t _z_lifo_make(size_t capacity) {
    _z_lifo_t v;
    _z_lifo_init(&v, capacity);
    return v;
}

size_t _z_lifo_capacity(const _z_lifo_t *r) { return r->_capacity; }
size_t _z_lifo_len(const _z_lifo_t *r) { return r->_len; }
bool _z_lifo_is_empty(const _z_lifo_t *r) { return r->_len == 0; }
bool _z_lifo_is_full(const _z_lifo_t *r) { return r->_len == r->_capacity; }

void *_z_lifo_push(_z_lifo_t *r, void *e) {
    void *ret = e;
    if (!_z_lifo_is_full(r)) {
        r->_val[r->_len] = e;
        r->_len++;
        ret = NULL;
    }
    return ret;
}

void _z_lifo_push_drop(_z_lifo_t *r, void *e, z_element_free_f free_f) {
    void *ret = _z_lifo_push(r, e);
    if (ret != NULL) {
        free_f(&ret);
    }
}

void *_z_lifo_pull(_z_lifo_t *r) {
    void *ret = NULL;
    if (!_z_lifo_is_empty(r)) {
        r->_len--;
        ret = r->_val[r->_len];
    }
    return ret;
}

void _z_lifo_clear(_z_lifo_t *r, z_element_free_f free_f) {
    void *e = _z_lifo_pull(r);
    while (e != NULL) {
        free_f(&e);
        e = _z_lifo_pull(r);
    }
    z_free(r->_val);

    r->_val = NULL;
    r->_capacity = (size_t)0;
    r->_len = (size_t)0;
}

void _z_lifo_free(_z_lifo_t **r, z_element_free_f free_f) {
    _z_lifo_t *ptr = (_z_lifo_t *)*r;
    if (ptr != NULL) {
        _z_lifo_clear(ptr, free_f);
        z_free(ptr);
        *r = NULL;
    }
}
