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

#include "zenoh-pico/collections/ring.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

/*-------- ring --------*/
z_result_t _z_ring_init(_z_ring_t *r, size_t capacity) {
    // We need one more element to differentiate wether the ring is empty or full
    capacity++;

    memset(r, 0, sizeof(_z_ring_t));
    if (capacity != (size_t)0) {
        r->_val = (void **)z_malloc(sizeof(void *) * capacity);
    }
    if (r->_val != NULL) {
        memset(r->_val, 0, capacity);
        r->_capacity = capacity;
    }
    return 0;
}

_z_ring_t _z_ring_make(size_t capacity) {
    _z_ring_t v;
    _z_ring_init(&v, capacity);
    return v;
}

size_t _z_ring_capacity(const _z_ring_t *r) { return r->_capacity - (size_t)1; }

size_t _z_ring_len(const _z_ring_t *r) {
    if (r->_w_idx >= r->_r_idx) {
        return r->_w_idx - r->_r_idx;
    } else {
        return r->_w_idx + (r->_capacity - r->_r_idx);
    }
}

bool _z_ring_is_empty(const _z_ring_t *r) { return r->_w_idx == r->_r_idx; }

bool _z_ring_is_full(const _z_ring_t *r) { return _z_ring_len(r) == _z_ring_capacity(r); }

void *_z_ring_push(_z_ring_t *r, void *e) {
    void *ret = e;
    if (!_z_ring_is_full(r)) {
        r->_val[r->_w_idx] = e;
        r->_w_idx = (r->_w_idx + (size_t)1) % r->_capacity;
        ret = NULL;
    }
    return ret;
}

void *_z_ring_push_force(_z_ring_t *r, void *e) {
    void *ret = _z_ring_push(r, e);
    if (ret != NULL) {
        ret = _z_ring_pull(r);
        _z_ring_push(r, e);
    }
    return ret;
}

void _z_ring_push_force_drop(_z_ring_t *r, void *e, z_element_free_f free_f) {
    void *ret = _z_ring_push_force(r, e);
    if (ret != NULL) {
        free_f(&ret);
    }
}

void *_z_ring_pull(_z_ring_t *r) {
    void *ret = NULL;
    if (!_z_ring_is_empty(r)) {
        ret = r->_val[r->_r_idx];
        r->_val[r->_r_idx] = NULL;
        r->_r_idx = (r->_r_idx + (size_t)1) % r->_capacity;
    }
    return ret;
}

void _z_ring_clear(_z_ring_t *r, z_element_free_f free_f) {
    void *e = _z_ring_pull(r);
    while (e != NULL) {
        free_f(&e);
        e = _z_ring_pull(r);
    }
    z_free(r->_val);

    r->_val = NULL;
    r->_capacity = (size_t)0;
    r->_len = (size_t)0;
    r->_r_idx = (size_t)0;
    r->_w_idx = (size_t)0;
}

void _z_ring_free(_z_ring_t **r, z_element_free_f free_f) {
    _z_ring_t *ptr = (_z_ring_t *)*r;
    if (ptr != NULL) {
        _z_ring_clear(ptr, free_f);
        z_free(ptr);
        *r = NULL;
    }
}

_z_ring_iterator_t _z_ring_iterator_make(const _z_ring_t *ring) {
    _z_ring_iterator_t iter = {0};

    iter._ring = ring;
    iter._r_idx = ring->_r_idx;
    iter._w_idx = ring->_w_idx;

    return iter;
}

bool _z_ring_iterator_next(_z_ring_iterator_t *iter) {
    if (iter->_r_idx != iter->_w_idx) {
        iter->_val = iter->_ring->_val[iter->_r_idx];
        iter->_r_idx = (iter->_r_idx + (size_t)1) % iter->_ring->_capacity;
        return true;
    }
    return false;
}

void *_z_ring_iterator_value(const _z_ring_iterator_t *iter) { return iter->_val; }

_z_ring_reverse_iterator_t _z_ring_reverse_iterator_make(const _z_ring_t *ring) {
    _z_ring_reverse_iterator_t iter = {0};

    iter._ring = ring;
    iter._r_idx = (ring->_w_idx == 0) ? ring->_capacity - 1 : ring->_w_idx - 1;
    iter._w_idx = (ring->_r_idx == 0) ? ring->_capacity - 1 : ring->_r_idx - 1;

    return iter;
}

bool _z_ring_reverse_iterator_next(_z_ring_reverse_iterator_t *iter) {
    if (iter->_r_idx != iter->_w_idx) {
        iter->_val = iter->_ring->_val[iter->_r_idx];
        iter->_r_idx = (iter->_r_idx == 0) ? iter->_ring->_capacity - 1 : iter->_r_idx - 1;
        return true;
    }
    return false;
}

void *_z_ring_reverse_iterator_value(const _z_ring_reverse_iterator_t *iter) { return iter->_val; }
