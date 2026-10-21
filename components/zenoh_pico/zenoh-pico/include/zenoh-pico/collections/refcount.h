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

#ifndef ZENOH_PICO_COLLECTIONS_REFCOUNT_H
#define ZENOH_PICO_COLLECTIONS_REFCOUNT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_rc_init(void **cnt);
z_result_t _z_rc_increase_strong(void *cnt);
z_result_t _z_rc_increase_weak(void *cnt);
bool _z_rc_decrease_strong(void **cnt);
bool _z_rc_decrease_weak(void **cnt);
z_result_t _z_rc_weak_upgrade(void *cnt);

size_t _z_rc_weak_count(void *cnt);
size_t _z_rc_strong_count(void *cnt);

void *_z_simple_rc_value(void *rc);
z_result_t _z_simple_rc_init(void **rc, const void *val, size_t val_size);
z_result_t _z_simple_rc_increase(void *rc);
bool _z_simple_rc_decrease(void *rc);

size_t _z_simple_rc_strong_count(void *rc);

#define _Z_REFCOUNT_DEFINE_STRUCTS(name, type)                                               \
    typedef struct name##_rc_t {                                                             \
        type##_t *_val;                                                                      \
        void *_cnt;                                                                          \
    } name##_rc_t;                                                                           \
                                                                                             \
    typedef struct name##_weak_t {                                                           \
        type##_t *_val;                                                                      \
        void *_cnt;                                                                          \
    } name##_weak_t;                                                                         \
    static inline void name##_weak_to_rc_inner(const name##_weak_t *weak, name##_rc_t *rc) { \
        rc->_val = weak->_val;                                                               \
        rc->_cnt = weak->_cnt;                                                               \
    }                                                                                        \
    static inline void name##_rc_to_weak_inner(const name##_rc_t *rc, name##_weak_t *weak) { \
        weak->_val = rc->_val;                                                               \
        weak->_cnt = rc->_cnt;                                                               \
    }                                                                                        \
    static inline void name##_rc_clear_inner(name##_rc_t *rc) { type##_clear(rc->_val); }

#define _Z_REFCOUNT_DEFINE_NO_FROM_VAL_INNER(name, type)                                                             \
                                                                                                                     \
    static inline name##_rc_t name##_rc_null(void) { return (name##_rc_t){0}; }                                      \
    static inline name##_weak_t name##_weak_null(void) { return (name##_weak_t){0}; }                                \
    static inline name##_rc_t name##_rc_clone(const name##_rc_t *p) {                                                \
        return _z_rc_increase_strong(p->_cnt) == _Z_RES_OK ? *p : name##_rc_null();                                  \
    }                                                                                                                \
    static inline name##_rc_t *name##_rc_clone_as_ptr(const name##_rc_t *p) {                                        \
        name##_rc_t *c = (name##_rc_t *)z_malloc(sizeof(name##_rc_t));                                               \
        if (c != NULL) {                                                                                             \
            *c = name##_rc_clone(p);                                                                                 \
            if (c->_cnt == NULL) {                                                                                   \
                z_free(c);                                                                                           \
                c = NULL;                                                                                            \
            }                                                                                                        \
        }                                                                                                            \
        return c;                                                                                                    \
    }                                                                                                                \
    static inline name##_weak_t name##_rc_clone_as_weak(const name##_rc_t *p) {                                      \
        if (_z_rc_increase_weak(p->_cnt) == _Z_RES_OK) {                                                             \
            name##_weak_t ret;                                                                                       \
            name##_rc_to_weak_inner(p, &ret);                                                                        \
            return ret;                                                                                              \
        }                                                                                                            \
        return name##_weak_null();                                                                                   \
    }                                                                                                                \
    static inline name##_weak_t *name##_rc_clone_as_weak_ptr(const name##_rc_t *p) {                                 \
        name##_weak_t *c = (name##_weak_t *)z_malloc(sizeof(name##_weak_t));                                         \
        if (c != NULL) {                                                                                             \
            *c = name##_rc_clone_as_weak(p);                                                                         \
            if (c->_cnt == NULL) {                                                                                   \
                z_free(c);                                                                                           \
                c = NULL;                                                                                            \
            }                                                                                                        \
        }                                                                                                            \
        return c;                                                                                                    \
    }                                                                                                                \
    static inline z_result_t name##_rc_copy(name##_rc_t *dst, const name##_rc_t *p) {                                \
        *dst = name##_rc_clone(p);                                                                                   \
        if (dst->_cnt == NULL) {                                                                                     \
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);                                                            \
        }                                                                                                            \
        return _Z_RES_OK;                                                                                            \
    }                                                                                                                \
    static inline bool name##_rc_eq(const name##_rc_t *left, const name##_rc_t *right) {                             \
        return (left->_val == right->_val);                                                                          \
    }                                                                                                                \
    static inline bool name##_rc_decr(name##_rc_t *p) {                                                              \
        if ((p == NULL) || (p->_cnt == NULL)) {                                                                      \
            return false;                                                                                            \
        }                                                                                                            \
        if (_z_rc_decrease_strong(&p->_cnt)) {                                                                       \
            return true;                                                                                             \
        }                                                                                                            \
        return false;                                                                                                \
    }                                                                                                                \
    static inline bool name##_rc_drop(name##_rc_t *p) {                                                              \
        if (p == NULL) {                                                                                             \
            return false;                                                                                            \
        }                                                                                                            \
        bool res = false;                                                                                            \
        if (name##_rc_decr(p) && p->_val != NULL) {                                                                  \
            name##_rc_clear_inner(p);                                                                                \
            z_free(p->_val);                                                                                         \
            res = true;                                                                                              \
        }                                                                                                            \
        *p = name##_rc_null();                                                                                       \
        return res;                                                                                                  \
    }                                                                                                                \
    static inline name##_weak_t name##_weak_clone(const name##_weak_t *p) {                                          \
        return _z_rc_increase_weak(p->_cnt) == _Z_RES_OK ? *p : name##_weak_null();                                  \
    }                                                                                                                \
    static inline void name##_weak_copy(name##_weak_t *dst, const name##_weak_t *p) { *dst = name##_weak_clone(p); } \
    static inline name##_rc_t name##_weak_upgrade(const name##_weak_t *p) {                                          \
        if (_z_rc_weak_upgrade(p->_cnt) == _Z_RES_OK) {                                                              \
            name##_rc_t ret;                                                                                         \
            name##_weak_to_rc_inner(p, &ret);                                                                        \
            return ret;                                                                                              \
        }                                                                                                            \
        return name##_rc_null();                                                                                     \
    }                                                                                                                \
    static inline bool name##_weak_eq(const name##_weak_t *left, const name##_weak_t *right) {                       \
        return (left->_val == right->_val);                                                                          \
    }                                                                                                                \
    static inline bool name##_weak_drop(name##_weak_t *p) {                                                          \
        if ((p == NULL) || (p->_cnt == NULL)) {                                                                      \
            return false;                                                                                            \
        }                                                                                                            \
        bool res = false;                                                                                            \
        if (_z_rc_decrease_weak(&p->_cnt)) {                                                                         \
            res = true;                                                                                              \
        }                                                                                                            \
        *p = name##_weak_null();                                                                                     \
        return res;                                                                                                  \
    }                                                                                                                \
    static inline size_t name##_rc_size(name##_rc_t *p) {                                                            \
        _ZP_UNUSED(p);                                                                                               \
        return sizeof(name##_rc_t);                                                                                  \
    }                                                                                                                \
    static inline size_t name##_rc_strong_count(const name##_rc_t *p) { return _z_rc_strong_count(p->_cnt); }        \
    static inline size_t name##_rc_weak_count(const name##_rc_t *p) { return _z_rc_weak_count(p->_cnt); }            \
    static inline size_t name##_weak_strong_count(const name##_weak_t *p) { return _z_rc_strong_count(p->_cnt); }    \
    static inline size_t name##_weak_weak_count(const name##_weak_t *p) { return _z_rc_weak_count(p->_cnt); }        \
    static inline name##_t *name##_weak_as_unsafe_ptr(name##_weak_t *p) { return p->_val; }

typedef void _z_void_t;
typedef void (*_z_void_rc_deleter)(void *);
typedef struct _z_void_rc_t {
    void *_val;
    void *_cnt;
    _z_void_rc_deleter _deleter;
} _z_void_rc_t;

typedef struct _z_void_weak_t {
    void *_val;
    void *_cnt;
    _z_void_rc_deleter _deleter;
} _z_void_weak_t;

static inline void _z_void_weak_to_rc_inner(const _z_void_weak_t *weak, _z_void_rc_t *rc) {
    rc->_val = weak->_val;
    rc->_cnt = weak->_cnt;
    rc->_deleter = weak->_deleter;
}

static inline void _z_void_rc_to_weak_inner(const _z_void_rc_t *rc, _z_void_weak_t *weak) {
    weak->_val = rc->_val;
    weak->_cnt = rc->_cnt;
    weak->_deleter = rc->_deleter;
}

static inline void _z_void_rc_clear_inner(_z_void_rc_t *rc) {
    if (rc->_deleter != NULL) {
        rc->_deleter(rc->_val);
    }
}
_Z_REFCOUNT_DEFINE_NO_FROM_VAL_INNER(_z_void, _z_void)
static inline _z_void_rc_t _z_void_rc_rc_new(void *val, _z_void_rc_deleter deleter) {
    _z_void_rc_t p = _z_void_rc_null();
    if (_z_rc_init(&p._cnt) == _Z_RES_OK) {
        p._val = val;
        p._deleter = deleter;
    }
    return p;
}

#define _Z_REFCOUNT_DEFINE_NO_FROM_VAL(name, type)                                                \
    _Z_REFCOUNT_DEFINE_STRUCTS(name, type)                                                        \
    _Z_REFCOUNT_DEFINE_NO_FROM_VAL_INNER(name, type)                                              \
    static inline name##_rc_t name##_rc_new(type##_t *val) {                                      \
        name##_rc_t p = name##_rc_null();                                                         \
        if (_z_rc_init(&p._cnt) == _Z_RES_OK) {                                                   \
            p._val = val;                                                                         \
        }                                                                                         \
        return p;                                                                                 \
    }                                                                                             \
    static inline void __##name##_z_void_rc_deleter(void *val) { type##_clear((type##_t *)val); } \
    static inline _z_void_rc_t name##_rc_to_void(type##_rc_t *rc) {                               \
        _z_void_rc_t p = _z_void_rc_null();                                                       \
        p._val = (void *)rc->_val;                                                                \
        p._cnt = rc->_cnt;                                                                        \
        p._deleter = __##name##_z_void_rc_deleter;                                                \
        *rc = name##_rc_null();                                                                   \
        return p;                                                                                 \
    }

#define _Z_REFCOUNT_DEFINE(name, type)                                      \
    _Z_REFCOUNT_DEFINE_NO_FROM_VAL(name, type)                              \
    static inline name##_rc_t name##_rc_new_from_val(const type##_t *val) { \
        type##_t *v = (type##_t *)z_malloc(sizeof(type##_t));               \
        if (v == NULL) {                                                    \
            return name##_rc_null();                                        \
        }                                                                   \
        *v = *val;                                                          \
        name##_rc_t p = name##_rc_new(v);                                   \
        if (p._cnt == NULL) {                                               \
            z_free(v);                                                      \
            return name##_rc_null();                                        \
        }                                                                   \
        return p;                                                           \
    }                                                                       \
    static inline name##_rc_t name##_rc_new_undefined(void) {               \
        type##_t *v = (type##_t *)z_malloc(sizeof(type##_t));               \
        if (v == NULL) {                                                    \
            return name##_rc_null();                                        \
        }                                                                   \
        name##_rc_t p = name##_rc_new(v);                                   \
        if (p._cnt == NULL) {                                               \
            z_free(v);                                                      \
            return name##_rc_null();                                        \
        }                                                                   \
        return p;                                                           \
    }

#define _Z_SIMPLE_REFCOUNT_DEFINE(name, type)                                                                 \
    typedef struct name##_simple_rc_t {                                                                       \
        void *_val;                                                                                           \
    } name##_simple_rc_t;                                                                                     \
                                                                                                              \
    static inline name##_simple_rc_t name##_simple_rc_null(void) { return (name##_simple_rc_t){0}; }          \
                                                                                                              \
    static inline name##_simple_rc_t name##_simple_rc_new_from_val(const type##_t *val) {                     \
        name##_simple_rc_t p = name##_simple_rc_null();                                                       \
        _z_simple_rc_init(&p._val, val, sizeof(type##_t));                                                    \
        return p;                                                                                             \
    }                                                                                                         \
    static inline name##_simple_rc_t name##_simple_rc_clone(const name##_simple_rc_t *p) {                    \
        return _z_simple_rc_increase(p->_val) == _Z_RES_OK ? *p : name##_simple_rc_null();                    \
    }                                                                                                         \
    static inline name##_simple_rc_t *name##_simple_rc_clone_as_ptr(const name##_simple_rc_t *p) {            \
        name##_simple_rc_t *c = (name##_simple_rc_t *)z_malloc(sizeof(name##_simple_rc_t));                   \
        if (c != NULL) {                                                                                      \
            *c = name##_simple_rc_clone(p);                                                                   \
            if (c->_val == NULL) {                                                                            \
                z_free(c);                                                                                    \
                c = NULL;                                                                                     \
            }                                                                                                 \
        }                                                                                                     \
        return c;                                                                                             \
    }                                                                                                         \
    static inline void name##_simple_rc_copy(name##_simple_rc_t *dst, const name##_simple_rc_t *p) {          \
        *dst = name##_simple_rc_clone(p);                                                                     \
    }                                                                                                         \
    static inline bool name##_simple_rc_eq(const name##_simple_rc_t *left, const name##_simple_rc_t *right) { \
        return (left->_val == right->_val);                                                                   \
    }                                                                                                         \
    static inline bool name##_simple_rc_decr(name##_simple_rc_t *p) {                                         \
        if (_z_simple_rc_decrease(p->_val)) {                                                                 \
            return true;                                                                                      \
        }                                                                                                     \
        return false;                                                                                         \
    }                                                                                                         \
    static inline bool name##_simple_rc_drop(name##_simple_rc_t *p) {                                         \
        bool res;                                                                                             \
        if ((p->_val != NULL) && name##_simple_rc_decr(p)) {                                                  \
            type##_clear((type##_t *)_z_simple_rc_value(p->_val));                                            \
            z_free(p->_val);                                                                                  \
            res = true;                                                                                       \
        } else {                                                                                              \
            res = false;                                                                                      \
        }                                                                                                     \
        p->_val = NULL;                                                                                       \
        return res;                                                                                           \
    }                                                                                                         \
    static inline size_t name##_simple_rc_count(const name##_simple_rc_t *p) {                                \
        return _z_simple_rc_strong_count(p->_val);                                                            \
    }                                                                                                         \
    static inline size_t name##_simple_rc_size(name##_simple_rc_t *p) {                                       \
        _ZP_UNUSED(p);                                                                                        \
        return sizeof(name##_simple_rc_t);                                                                    \
    }                                                                                                         \
    static inline type##_t *name##_simple_rc_value(const name##_simple_rc_t *p) {                             \
        return (type##_t *)_z_simple_rc_value(p->_val);                                                       \
    }                                                                                                         \
    static inline bool name##_simple_rc_is_null(const name##_simple_rc_t *p) { return p->_val == NULL; }

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_REFCOUNT_H */
