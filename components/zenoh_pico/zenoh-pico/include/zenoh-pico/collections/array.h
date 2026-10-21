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

#ifndef ZENOH_PICO_COLLECTIONS_ARRAY_H
#define ZENOH_PICO_COLLECTIONS_ARRAY_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/*------------------ Internal Array Macros ------------------*/
#define _Z_ARRAY_DEFINE(name, type)                                                                 \
    typedef struct {                                                                                \
        size_t _len;                                                                                \
        type *_val;                                                                                 \
    } name##_array_t;                                                                               \
    static inline name##_array_t name##_array_empty(void) {                                         \
        name##_array_t a;                                                                           \
        a._val = NULL;                                                                              \
        a._len = 0;                                                                                 \
        return a;                                                                                   \
    }                                                                                               \
    static inline name##_array_t name##_array_make(size_t capacity) {                               \
        name##_array_t a;                                                                           \
        a._val = (type *)z_malloc(capacity * sizeof(type));                                         \
        if (a._val != NULL) {                                                                       \
            a._len = capacity;                                                                      \
        } else {                                                                                    \
            a._len = 0;                                                                             \
        }                                                                                           \
        return a;                                                                                   \
    }                                                                                               \
    static inline void name##_array_move(name##_array_t *dst, name##_array_t *src) {                \
        dst->_len = src->_len;                                                                      \
        dst->_val = src->_val;                                                                      \
        src->_len = 0;                                                                              \
        src->_val = NULL;                                                                           \
    }                                                                                               \
    static inline void name##_array_copy(name##_array_t *dst, name##_array_t *src) {                \
        dst->_len = src->_len;                                                                      \
        memcpy(&dst->_val, &src->_val, src->_len);                                                  \
    }                                                                                               \
    static inline type *name##_array_get(const name##_array_t *a, size_t k) { return &a->_val[k]; } \
    static inline size_t name##_array_len(const name##_array_t *a) { return a->_len; }              \
    static inline bool name##_array_is_empty(const name##_array_t *a) { return a->_len == 0; }      \
    static inline void name##_array_clear(name##_array_t *a) {                                      \
        for (size_t i = 0; i < a->_len; i++) {                                                      \
            name##_elem_clear(&a->_val[i]);                                                         \
        }                                                                                           \
        z_free(a->_val);                                                                            \
        a->_len = 0;                                                                                \
        a->_val = NULL;                                                                             \
    }                                                                                               \
    static inline void name##_array_free(name##_array_t **a) {                                      \
        name##_array_t *ptr = *a;                                                                   \
        if (ptr != NULL) {                                                                          \
            name##_array_clear(ptr);                                                                \
            z_free(ptr);                                                                            \
            *a = NULL;                                                                              \
        }                                                                                           \
    }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_ARRAY_H */
