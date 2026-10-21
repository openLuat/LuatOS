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

#ifndef ZENOH_PICO_COLLECTIONS_LIST_H
#define ZENOH_PICO_COLLECTIONS_LIST_H

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/element.h"

#ifdef __cplusplus
extern "C" {
#endif

/*-------- Single-linked List --------*/
/**
 * A single-linked list. Elements are stored as pointers.
 *
 *  Members:
 *   void *lal: The pointer to the inner value.
 *   struct z_list *tail: A pointer to the next element in the list.
 */
typedef struct _z_l_t {
    void *_val;
    struct _z_l_t *_next;
} _z_list_t;

size_t _z_list_len(const _z_list_t *xs);
static inline bool _z_list_is_empty(const _z_list_t *xs) { return xs == NULL; }
static inline void *_z_list_value(const _z_list_t *xs) { return xs->_val; }
static inline _z_list_t *_z_list_next(const _z_list_t *xs) { return xs->_next; }

_z_list_t *_z_list_push(_z_list_t *xs, void *x);
_z_list_t *_z_list_push_after(_z_list_t *xs, void *x);
_z_list_t *_z_list_push_back(_z_list_t *xs, void *x);
_z_list_t *_z_list_push_sorted(_z_list_t *xs, z_element_cmp_f c_f, void *x);
_z_list_t *_z_list_pop(_z_list_t *xs, z_element_free_f f_f, void **x);

_z_list_t *_z_list_find(const _z_list_t *xs, z_element_eq_f f_f, const void *e);
_z_list_t *_z_list_drop_element(_z_list_t *list, _z_list_t *prev, z_element_free_f f_f);
_z_list_t *_z_list_drop_filter(_z_list_t *xs, z_element_free_f f_f, z_element_eq_f c_f, const void *left,
                               bool only_first);
_z_list_t *_z_list_extract_filter(_z_list_t *xs, z_element_eq_f c_f, const void *left, _z_list_t **extracted,
                                  bool only_first);

_z_list_t *_z_list_clone(const _z_list_t *xs, z_element_clone_f d_f);
void _z_list_free(_z_list_t **xs, z_element_free_f f_f);

#define _Z_LIST_DEFINE(name, type)                                                                                    \
    typedef _z_list_t name##_list_t;                                                                                  \
    static inline name##_list_t *name##_list_new(void) { return NULL; }                                               \
    static inline size_t name##_list_len(const name##_list_t *l) { return _z_list_len(l); }                           \
    static inline bool name##_list_is_empty(const name##_list_t *l) { return _z_list_is_empty(l); }                   \
    static inline type *name##_list_value(const name##_list_t *l) { return (type *)_z_list_value(l); }                \
    static inline name##_list_t *name##_list_next(const name##_list_t *l) { return _z_list_next(l); }                 \
    static inline name##_list_t *name##_list_push(name##_list_t *l, type *e) { return _z_list_push(l, e); }           \
    static inline name##_list_t *name##_list_push_after(name##_list_t *l, type *e) {                                  \
        return _z_list_push_after(l, e);                                                                              \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_push_back(name##_list_t *l, type *e) { return _z_list_push_back(l, e); } \
    static inline name##_list_t *name##_list_push_sorted(name##_list_t *l, type *e) {                                 \
        return _z_list_push_sorted(l, name##_elem_cmp, e);                                                            \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_pop(name##_list_t *l, type **x) {                                        \
        return _z_list_pop(l, name##_elem_free, (void **)x);                                                          \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_find(const name##_list_t *l, name##_eq_f c_f, const type *e) {           \
        return _z_list_find(l, (z_element_eq_f)c_f, e);                                                               \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_drop_element(name##_list_t *l, name##_list_t *p) {                       \
        return _z_list_drop_element(l, p, name##_elem_free);                                                          \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_drop_first_filter(name##_list_t *l, name##_eq_f c_f, const type *e) {    \
        return _z_list_drop_filter(l, name##_elem_free, (z_element_eq_f)c_f, e, true);                                \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_drop_all_filter(name##_list_t *l, name##_eq_f c_f, const type *e) {      \
        return _z_list_drop_filter(l, name##_elem_free, (z_element_eq_f)c_f, e, false);                               \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_extract_all_filter(name##_list_t *l, name##_list_t **extracted,          \
                                                                name##_eq_f c_f, const type *e) {                     \
        return _z_list_extract_filter(l, (z_element_eq_f)c_f, e, extracted, false);                                   \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_extract_first_filter(name##_list_t *l, name##_list_t **extracted,        \
                                                                  name##_eq_f c_f, const type *e) {                   \
        return _z_list_extract_filter(l, (z_element_eq_f)c_f, e, extracted, true);                                    \
    }                                                                                                                 \
    static inline name##_list_t *name##_list_clone(name##_list_t *l) { return _z_list_clone(l, name##_elem_clone); }  \
    static inline void name##_list_free(name##_list_t **l) { _z_list_free(l, name##_elem_free); }

/*-------- Sized Single-linked List --------*/
/**
 * A single-linked list. Elements are stored as value.
 *
 *  Members:
 *   _z_slist_node_t *data: Pointer to internal data
 */

// Node struct: {next node_address; generic type}
typedef void _z_slist_t;

static inline bool _z_slist_is_empty(const _z_slist_t *node) { return node == NULL; }
_z_slist_t *_z_slist_push_empty(_z_slist_t *node, size_t value_size);
_z_slist_t *_z_slist_push(_z_slist_t *node, const void *value, size_t value_size, z_element_copy_f d_f,
                          bool use_elem_f);
_z_slist_t *_z_slist_push_back(_z_slist_t *node, const void *value, size_t value_size, z_element_copy_f d_f,
                               bool use_elem_f);
void *_z_slist_value(const _z_slist_t *node);
_z_slist_t *_z_slist_next(const _z_slist_t *node);
size_t _z_slist_len(const _z_slist_t *node);
_z_slist_t *_z_slist_pop(_z_slist_t *node, z_element_clear_f f_f);
_z_slist_t *_z_slist_find(const _z_slist_t *node, z_element_eq_f c_f, const void *target_val);
_z_slist_t *_z_slist_drop_element(_z_slist_t *list, _z_slist_t *prev, z_element_clear_f f_f);
_z_slist_t *_z_slist_drop_filter(_z_slist_t *head, z_element_clear_f f_f, z_element_eq_f c_f, const void *target_val,
                                 bool only_first);
_z_slist_t *_z_slist_extract_filter(_z_slist_t *head, z_element_eq_f c_f, const void *target_val,
                                    _z_slist_t **extracted, bool only_first);
_z_slist_t *_z_slist_clone(const _z_slist_t *node, size_t value_size, z_element_copy_f d_f, bool use_elem_f);
void _z_slist_free(_z_slist_t **node, z_element_clear_f f);

#define _Z_SLIST_DEFINE(name, type, use_elem_f)                                                                       \
    typedef _z_slist_t name##_slist_t;                                                                                \
    static inline name##_slist_t *name##_slist_new(void) { return NULL; }                                             \
    static inline size_t name##_slist_len(const name##_slist_t *l) { return _z_slist_len(l); }                        \
    static inline bool name##_slist_is_empty(const name##_slist_t *l) { return _z_slist_is_empty(l); }                \
    static inline name##_slist_t *name##_slist_next(const name##_slist_t *l) { return _z_slist_next(l); }             \
    static inline type *name##_slist_value(const name##_slist_t *l) { return (type *)_z_slist_value(l); }             \
    static inline name##_slist_t *name##_slist_push_empty(name##_slist_t *l) {                                        \
        return _z_slist_push_empty(l, sizeof(type));                                                                  \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_push(name##_slist_t *l, const type *e) {                               \
        return _z_slist_push(l, e, sizeof(type), name##_elem_copy, use_elem_f);                                       \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_push_back(name##_slist_t *l, const type *e) {                          \
        return _z_slist_push_back(l, e, sizeof(type), name##_elem_copy, use_elem_f);                                  \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_pop(name##_slist_t *l) { return _z_slist_pop(l, name##_elem_clear); }  \
    static inline name##_slist_t *name##_slist_find(const name##_slist_t *l, name##_eq_f c_f, const type *e) {        \
        return _z_slist_find(l, (z_element_eq_f)c_f, e);                                                              \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_drop_element(name##_slist_t *l, name##_slist_t *p) {                   \
        return _z_slist_drop_element(l, p, name##_elem_clear);                                                        \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_drop_all_filter(name##_slist_t *l, name##_eq_f c_f, const type *e) {   \
        return _z_slist_drop_filter(l, name##_elem_clear, (z_element_eq_f)c_f, e, false);                             \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_drop_first_filter(name##_slist_t *l, name##_eq_f c_f, const type *e) { \
        return _z_slist_drop_filter(l, name##_elem_clear, (z_element_eq_f)c_f, e, true);                              \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_extract_all_filter(name##_slist_t *l, name##_slist_t **extracted,      \
                                                                  name##_eq_f c_f, const type *e) {                   \
        return _z_slist_extract_filter(l, (z_element_eq_f)c_f, e, extracted, false);                                  \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_extract_first_filter(name##_slist_t *l, name##_slist_t **extracted,    \
                                                                    name##_eq_f c_f, const type *e) {                 \
        return _z_slist_extract_filter(l, (z_element_eq_f)c_f, e, extracted, true);                                   \
    }                                                                                                                 \
    static inline name##_slist_t *name##_slist_clone(name##_slist_t *l) {                                             \
        return _z_slist_clone(l, sizeof(type), name##_elem_copy, use_elem_f);                                         \
    }                                                                                                                 \
    static inline void name##_slist_free(name##_slist_t **l) { _z_slist_free(l, name##_elem_clear); }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_LIST_H */
