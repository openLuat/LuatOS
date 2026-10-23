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
#ifndef ZENOH_PICO_COLLECTIONS_FIFO_H
#define ZENOH_PICO_COLLECTIONS_FIFO_H

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/ring.h"

#ifdef __cplusplus
extern "C" {
#endif

/*-------- Fifo Buffer --------*/
typedef struct {
    _z_ring_t _ring;
} _z_fifo_t;

z_result_t _z_fifo_init(_z_fifo_t *fifo, size_t capacity);
_z_fifo_t _z_fifo_make(size_t capacity);

size_t _z_fifo_capacity(const _z_fifo_t *r);
size_t _z_fifo_len(const _z_fifo_t *r);
bool _z_fifo_is_empty(const _z_fifo_t *r);
bool _z_fifo_is_full(const _z_fifo_t *r);

void *_z_fifo_push(_z_fifo_t *r, void *e);
void _z_fifo_push_drop(_z_fifo_t *r, void *e, z_element_free_f f);
void *_z_fifo_pull(_z_fifo_t *r);

_z_fifo_t *_z_fifo_clone(const _z_fifo_t *xs, z_element_clone_f d_f);

void _z_fifo_clear(_z_fifo_t *v, z_element_free_f f);
void _z_fifo_free(_z_fifo_t **xs, z_element_free_f f_f);

#define _Z_FIFO_DEFINE(name, type)                                                                         \
    typedef _z_fifo_t name##_fifo_t;                                                                       \
    static inline z_result_t name##_fifo_init(name##_fifo_t *fifo, size_t capacity) {                      \
        return _z_fifo_init(fifo, capacity);                                                               \
    }                                                                                                      \
    static inline name##_fifo_t name##_fifo_make(size_t capacity) { return _z_fifo_make(capacity); }       \
    static inline size_t name##_fifo_capacity(const name##_fifo_t *r) { return _z_fifo_capacity(r); }      \
    static inline size_t name##_fifo_len(const name##_fifo_t *r) { return _z_fifo_len(r); }                \
    static inline bool name##_fifo_is_empty(const name##_fifo_t *r) { return _z_fifo_is_empty(r); }        \
    static inline bool name##_fifo_is_full(const name##_fifo_t *r) { return _z_fifo_is_full(r); }          \
    static inline type *name##_fifo_push(name##_fifo_t *r, type *e) { return _z_fifo_push(r, (void *)e); } \
    static inline void name##_fifo_push_drop(name##_fifo_t *r, type *e) {                                  \
        _z_fifo_push_drop(r, (void *)e, name##_elem_free);                                                 \
    }                                                                                                      \
    static inline type *name##_fifo_pull(name##_fifo_t *r) { return (type *)_z_fifo_pull(r); }             \
    static inline void name##_fifo_clear(name##_fifo_t *r) { _z_fifo_clear(r, name##_elem_free); }         \
    static inline void name##_fifo_free(name##_fifo_t **r) { _z_fifo_free(r, name##_elem_free); }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_FIFO_H */
