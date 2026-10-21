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
#ifndef ZENOH_PICO_COLLECTIONS_LIFO_H
#define ZENOH_PICO_COLLECTIONS_LIFO_H

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
} _z_lifo_t;

z_result_t _z_lifo_init(_z_lifo_t *lifo, size_t capacity);
_z_lifo_t _z_lifo_make(size_t capacity);

size_t _z_lifo_capacity(const _z_lifo_t *r);
size_t _z_lifo_len(const _z_lifo_t *r);
bool _z_lifo_is_empty(const _z_lifo_t *r);
bool _z_lifo_is_full(const _z_lifo_t *r);

void *_z_lifo_push(_z_lifo_t *r, void *e);
void _z_lifo_push_drop(_z_lifo_t *r, void *e, z_element_free_f f);
void *_z_lifo_pull(_z_lifo_t *r);

_z_lifo_t *_z_lifo_clone(const _z_lifo_t *xs, z_element_clone_f d_f);

void _z_lifo_clear(_z_lifo_t *v, z_element_free_f f);
void _z_lifo_free(_z_lifo_t **xs, z_element_free_f f_f);

#define _Z_LIFO_DEFINE(name, type)                                                                         \
    typedef _z_lifo_t name##_lifo_t;                                                                       \
    static inline z_result_t name##_lifo_init(name##_lifo_t *lifo, size_t capacity) {                      \
        return _z_lifo_init(lifo, capacity);                                                               \
    }                                                                                                      \
    static inline name##_lifo_t name##_lifo_make(size_t capacity) { return _z_lifo_make(capacity); }       \
    static inline size_t name##_lifo_capacity(const name##_lifo_t *r) { return _z_lifo_capacity(r); }      \
    static inline size_t name##_lifo_len(const name##_lifo_t *r) { return _z_lifo_len(r); }                \
    static inline bool name##_lifo_is_empty(const name##_lifo_t *r) { return _z_lifo_is_empty(r); }        \
    static inline bool name##_lifo_is_full(const name##_lifo_t *r) { return _z_lifo_is_full(r); }          \
    static inline type *name##_lifo_push(name##_lifo_t *r, type *e) { return _z_lifo_push(r, (void *)e); } \
    static inline void name##_lifo_push_drop(name##_lifo_t *r, type *e) {                                  \
        _z_lifo_push_drop(r, (void *)e, name##_elem_free);                                                 \
    }                                                                                                      \
    static inline type *name##_lifo_pull(name##_lifo_t *r) { return (type *)_z_lifo_pull(r); }             \
    static inline void name##_lifo_clear(name##_lifo_t *r) { _z_lifo_clear(r, name##_elem_free); }         \
    static inline void name##_lifo_free(name##_lifo_t **r) { _z_lifo_free(r, name##_elem_free); }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_LIFO_H */
