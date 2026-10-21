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

#ifndef ZENOH_PICO_COLLECTIONS_ELEMENT_H
#define ZENOH_PICO_COLLECTIONS_ELEMENT_H

#include <stdbool.h>
#include <stddef.h>

#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

/*-------- element functions --------*/
typedef size_t (*z_element_size_f)(void *e);
typedef void (*z_element_clear_f)(void *e);
typedef void (*z_element_free_f)(void **e);
typedef void (*z_element_copy_f)(void *dst, const void *src);
typedef void (*z_element_move_f)(void *dst, void *src);
typedef void *(*z_element_clone_f)(const void *e);
typedef bool (*z_element_eq_f)(const void *left, const void *right);
typedef int (*z_element_cmp_f)(const void *left, const void *right);
typedef size_t (*z_element_hash_f)(const void *e);

#define _Z_ELEM_DEFINE(name, type, elem_size_f, elem_clear_f, elem_copy_f, elem_move_f, elem_eq_f, elem_cmp_f, \
                       elem_hash_f)                                                                            \
    typedef bool (*name##_eq_f)(const type *left, const type *right);                                          \
    typedef int (*name##_cmp_f)(const type *left, const type *right);                                          \
    static inline void name##_elem_clear(void *e) { elem_clear_f((type *)e); }                                 \
    static inline void name##_elem_free(void **e) {                                                            \
        type *ptr = (type *)*e;                                                                                \
        if (ptr != NULL) {                                                                                     \
            elem_clear_f(ptr);                                                                                 \
            z_free(ptr);                                                                                       \
            *e = NULL;                                                                                         \
        }                                                                                                      \
    }                                                                                                          \
    static inline void name##_elem_move(void *dst, void *src) { elem_move_f((type *)dst, (type *)src); }       \
    static inline void name##_elem_copy(void *dst, const void *src) { elem_copy_f((type *)dst, (type *)src); } \
    static inline void *name##_elem_clone(const void *src) {                                                   \
        type *dst = (type *)z_malloc(elem_size_f((type *)src));                                                \
        if (dst != NULL) {                                                                                     \
            elem_copy_f(dst, (type *)src);                                                                     \
        }                                                                                                      \
        return dst;                                                                                            \
    }                                                                                                          \
    static inline bool name##_elem_eq(const void *left, const void *right) {                                   \
        return elem_eq_f((const type *)left, (const type *)right);                                             \
    }                                                                                                          \
    static inline int name##_elem_cmp(const void *left, const void *right) {                                   \
        return elem_cmp_f((const type *)left, (const type *)right);                                            \
    }                                                                                                          \
    static inline size_t name##_elem_hash(const void *e) { return elem_hash_f((const type *)e); }

/*------------------ void ----------------*/
typedef void _z_noop_t;

static inline size_t _z_noop_size(void *s) {
    (void)(s);
    return 0;
}

static inline void _z_noop_clear(void *s) { (void)(s); }

static inline void _z_noop_free(void **s) { (void)(s); }

static inline void _z_noop_copy(void *dst, const void *src) {
    _ZP_UNUSED(dst);
    _ZP_UNUSED(src);
}

static inline void _z_noop_move(void *dst, void *src) {
    _ZP_UNUSED(dst);
    _ZP_UNUSED(src);
}

static inline bool _z_noop_eq(const void *left, const void *right) {
    _ZP_UNUSED(left);
    _ZP_UNUSED(right);
    return true;
}

static inline int _z_noop_cmp(const void *left, const void *right) {
    _ZP_UNUSED(left);
    _ZP_UNUSED(right);
    return 0;
}

static inline size_t _z_noop_hash(const void *e) {
    _ZP_UNUSED(e);
    return 0;
}

_Z_ELEM_DEFINE(_z_noop, _z_noop_t, _z_noop_size, _z_noop_clear, _z_noop_copy, _z_noop_move, _z_noop_eq, _z_noop_cmp,
               _z_noop_hash)

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_ELEMENT_H */
