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
#ifndef ZENOH_PICO_COLLECTIONS_RING_H
#define ZENOH_PICO_COLLECTIONS_RING_H

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/element.h"

#ifdef __cplusplus
extern "C" {
#endif

/*-------- Ring Buffer --------*/
typedef struct {
    void **_val;
    size_t _capacity;
    size_t _len;
    size_t _r_idx;
    size_t _w_idx;
} _z_ring_t;

/**
 * Forward iterator of a ring buffer.
 */
typedef struct {
    void *_val;

    const _z_ring_t *_ring;
    size_t _r_idx;
    size_t _w_idx;
} _z_ring_iterator_t;

/**
 * Reverse iterator of a ring buffer.
 */
typedef struct {
    void *_val;

    const _z_ring_t *_ring;
    size_t _r_idx;
    size_t _w_idx;
} _z_ring_reverse_iterator_t;

z_result_t _z_ring_init(_z_ring_t *ring, size_t capacity);
_z_ring_t _z_ring_make(size_t capacity);

size_t _z_ring_capacity(const _z_ring_t *r);
size_t _z_ring_len(const _z_ring_t *r);
bool _z_ring_is_empty(const _z_ring_t *r);
bool _z_ring_is_full(const _z_ring_t *r);

void *_z_ring_push(_z_ring_t *r, void *e);
void *_z_ring_push_force(_z_ring_t *r, void *e);
void _z_ring_push_force_drop(_z_ring_t *r, void *e, z_element_free_f f);
void *_z_ring_pull(_z_ring_t *r);

_z_ring_t *_z_ring_clone(const _z_ring_t *xs, z_element_clone_f d_f);

void _z_ring_clear(_z_ring_t *v, z_element_free_f f);
void _z_ring_free(_z_ring_t **xs, z_element_free_f f_f);

_z_ring_iterator_t _z_ring_iterator_make(const _z_ring_t *ring);
bool _z_ring_iterator_next(_z_ring_iterator_t *iter);
void *_z_ring_iterator_value(const _z_ring_iterator_t *iter);

_z_ring_reverse_iterator_t _z_ring_reverse_iterator_make(const _z_ring_t *ring);
bool _z_ring_reverse_iterator_next(_z_ring_reverse_iterator_t *iter);
void *_z_ring_reverse_iterator_value(const _z_ring_reverse_iterator_t *iter);

#define _Z_RING_DEFINE(name, type)                                                                                     \
    typedef _z_ring_t name##_ring_t;                                                                                   \
    typedef _z_ring_iterator_t name##_ring_iterator_t;                                                                 \
    typedef _z_ring_reverse_iterator_t name##_ring_reverse_iterator_t;                                                 \
    static inline z_result_t name##_ring_init(name##_ring_t *ring, size_t capacity) {                                  \
        return _z_ring_init(ring, capacity);                                                                           \
    }                                                                                                                  \
    static inline name##_ring_t name##_ring_make(size_t capacity) { return _z_ring_make(capacity); }                   \
    static inline size_t name##_ring_capacity(const name##_ring_t *r) { return _z_ring_capacity(r); }                  \
    static inline size_t name##_ring_len(const name##_ring_t *r) { return _z_ring_len(r); }                            \
    static inline bool name##_ring_is_empty(const name##_ring_t *r) { return _z_ring_is_empty(r); }                    \
    static inline bool name##_ring_is_full(const name##_ring_t *r) { return _z_ring_is_full(r); }                      \
    static inline type *name##_ring_push(name##_ring_t *r, type *e) { return (type *)_z_ring_push(r, (void *)e); }     \
    static inline type *name##_ring_push_force(name##_ring_t *r, type *e) {                                            \
        return (type *)_z_ring_push_force(r, (void *)e);                                                               \
    }                                                                                                                  \
    static inline void name##_ring_push_force_drop(name##_ring_t *r, type *e) {                                        \
        _z_ring_push_force_drop(r, (void *)e, name##_elem_free);                                                       \
    }                                                                                                                  \
    static inline type *name##_ring_pull(name##_ring_t *r) { return (type *)_z_ring_pull(r); }                         \
    static inline void name##_ring_clear(name##_ring_t *r) { _z_ring_clear(r, name##_elem_free); }                     \
    static inline void name##_ring_free(name##_ring_t **r) { _z_ring_free(r, name##_elem_free); }                      \
    static inline name##_ring_iterator_t name##_ring_iterator_make(const name##_ring_t *ring) {                        \
        return _z_ring_iterator_make(ring);                                                                            \
    }                                                                                                                  \
    static inline bool name##_ring_iterator_next(name##_ring_iterator_t *iter) { return _z_ring_iterator_next(iter); } \
    static inline type *name##_ring_iterator_value(const name##_ring_iterator_t *iter) {                               \
        return (type *)_z_ring_iterator_value(iter);                                                                   \
    }                                                                                                                  \
    static inline name##_ring_reverse_iterator_t name##_ring_reverse_iterator_make(const name##_ring_t *ring) {        \
        return _z_ring_reverse_iterator_make(ring);                                                                    \
    }                                                                                                                  \
    static inline bool name##_ring_reverse_iterator_next(name##_ring_reverse_iterator_t *iter) {                       \
        return _z_ring_reverse_iterator_next(iter);                                                                    \
    }                                                                                                                  \
    static inline type *name##_ring_reverse_iterator_value(const name##_ring_reverse_iterator_t *iter) {               \
        return (type *)_z_ring_reverse_iterator_value(iter);                                                           \
    }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_RING_H */
