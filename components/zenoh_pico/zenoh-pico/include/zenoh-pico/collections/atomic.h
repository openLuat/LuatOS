//
// Copyright (c) 2026 ZettaScale Technology
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

#ifndef ZENOH_PICO_COLLECTIONS_ATOMIC_H
#define ZENOH_PICO_COLLECTIONS_ATOMIC_H
#include <stdbool.h>
#include <stddef.h>

typedef struct {
    size_t _value;
} _z_atomic_size_t;

typedef enum {
    _z_memory_order_relaxed,
    _z_memory_order_acquire,
    _z_memory_order_release,
    _z_memory_order_acq_rel,
    _z_memory_order_seq_cst
} _z_memory_order_t;

void _z_atomic_size_init(_z_atomic_size_t *var, size_t value);
size_t _z_atomic_size_load(_z_atomic_size_t *var, _z_memory_order_t order);
void _z_atomic_size_store(_z_atomic_size_t *var, size_t val, _z_memory_order_t order);
size_t _z_atomic_size_fetch_add(_z_atomic_size_t *var, size_t val, _z_memory_order_t order);
size_t _z_atomic_size_fetch_sub(_z_atomic_size_t *var, size_t val, _z_memory_order_t order);
bool _z_atomic_size_compare_exchange_strong(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                            _z_memory_order_t success, _z_memory_order_t failure);
bool _z_atomic_size_compare_exchange_weak(_z_atomic_size_t *var, size_t *expected, size_t desired,
                                          _z_memory_order_t success, _z_memory_order_t failure);
void _z_atomic_thread_fence(_z_memory_order_t order);

typedef _z_atomic_size_t _z_atomic_bool_t;
static inline void _z_atomic_bool_init(_z_atomic_bool_t *var, bool value) { _z_atomic_size_init(var, value ? 1 : 0); }
static inline bool _z_atomic_bool_load(_z_atomic_bool_t *var, _z_memory_order_t order) {
    return _z_atomic_size_load(var, order) != 0;
}
static inline void _z_atomic_bool_store(_z_atomic_bool_t *var, bool val, _z_memory_order_t order) {
    _z_atomic_size_store(var, val ? 1 : 0, order);
}
static inline bool _z_atomic_bool_compare_exchange_strong(_z_atomic_bool_t *var, bool *expected, bool desired,
                                                          _z_memory_order_t success, _z_memory_order_t failure) {
    size_t expected_val = *expected ? 1 : 0;
    bool result = _z_atomic_size_compare_exchange_strong(var, &expected_val, desired ? 1 : 0, success, failure);
    *expected = expected_val != 0;
    return result;
}
static inline bool _z_atomic_bool_compare_exchange_weak(_z_atomic_bool_t *var, bool *expected, bool desired,
                                                        _z_memory_order_t success, _z_memory_order_t failure) {
    size_t expected_val = *expected ? 1 : 0;
    bool result = _z_atomic_size_compare_exchange_weak(var, &expected_val, desired ? 1 : 0, success, failure);
    *expected = expected_val != 0;
    return result;
}

#endif
