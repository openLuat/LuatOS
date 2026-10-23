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
#include "zenoh-pico/collections/fifo.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

/*-------- fifo --------*/
z_result_t _z_fifo_init(_z_fifo_t *r, size_t capacity) {
    _z_ring_init(&r->_ring, capacity);
    return 0;
}

_z_fifo_t _z_fifo_make(size_t capacity) {
    _z_fifo_t v;
    _z_fifo_init(&v, capacity);
    return v;
}

size_t _z_fifo_capacity(const _z_fifo_t *r) { return _z_ring_capacity(&r->_ring); }
size_t _z_fifo_len(const _z_fifo_t *r) { return _z_ring_len(&r->_ring); }
bool _z_fifo_is_empty(const _z_fifo_t *r) { return _z_ring_is_empty(&r->_ring); }
bool _z_fifo_is_full(const _z_fifo_t *r) { return _z_fifo_len(r) == _z_fifo_capacity(r); }

void *_z_fifo_push(_z_fifo_t *r, void *e) { return _z_ring_push(&r->_ring, e); }
void _z_fifo_push_drop(_z_fifo_t *r, void *e, z_element_free_f free_f) {
    void *ret = _z_fifo_push(r, e);
    if (ret != NULL) {
        free_f(&ret);
    }
}
void *_z_fifo_pull(_z_fifo_t *r) { return _z_ring_pull(&r->_ring); }
void _z_fifo_clear(_z_fifo_t *r, z_element_free_f free_f) { _z_ring_clear(&r->_ring, free_f); }
void _z_fifo_free(_z_fifo_t **r, z_element_free_f free_f) {
    _z_fifo_t *ptr = (_z_fifo_t *)*r;
    if (ptr != NULL) {
        _z_fifo_clear(ptr, free_f);
        z_free(ptr);
        *r = NULL;
    }
}
