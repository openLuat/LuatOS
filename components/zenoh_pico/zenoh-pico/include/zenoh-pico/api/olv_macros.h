//
// Copyright (c) 2024 ZettaScale Technology
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
#ifndef INCLUDE_ZENOH_PICO_API_OLV_MACROS_H
#define INCLUDE_ZENOH_PICO_API_OLV_MACROS_H

// Gets internal value from refcounted type (e.g. z_loaned_session_t, z_query_t)
#define _Z_RC_IN_VAL(arg) ((arg)->_val)

// Checks if refcounted type is initialized
#define _Z_RC_IS_NULL(arg) ((arg)->_cnt == NULL)

// Gets internal value from refcounted owned type (e.g. z_owned_session_t, z_owned_query_t)
#define _Z_OWNED_RC_IN_VAL(arg) ((arg)->_rc._val)

// Checks if simple refcounted type is initialized
#define _Z_SIMPLE_RC_IS_NULL(arg) ((arg)->_val == NULL)

// Owned/Loaned/View type macros
//
// !!! FOR INTERNAL USAGE ONLY !!!

#define _Z_MOVED_TYPE_PREFIX(prefix, name) \
    typedef struct {                       \
        prefix##_owned_##name##_t _this;   \
    } prefix##_moved_##name##_t;

#define _Z_LOANED_TYPE_PREFIX(prefix, type, name) typedef type prefix##_loaned_##name##_t;

// For value types
#define _Z_OWNED_TYPE_VALUE_PREFIX(prefix, type, name) \
    typedef struct {                                   \
        type _val;                                     \
    } prefix##_owned_##name##_t;                       \
    _Z_LOANED_TYPE_PREFIX(prefix, type, name)          \
    _Z_MOVED_TYPE_PREFIX(prefix, name)

#define _Z_OWNED_TYPE_VALUE(type, name) _Z_OWNED_TYPE_VALUE_PREFIX(z, type, name)

// For refcounted types
#define _Z_OWNED_TYPE_RC_PREFIX(prefix, type, name) \
    typedef struct {                                \
        type _rc;                                   \
    } prefix##_owned_##name##_t;                    \
    _Z_LOANED_TYPE_PREFIX(prefix, type, name)       \
    _Z_MOVED_TYPE_PREFIX(prefix, name)

#define _Z_OWNED_TYPE_RC(type, name) _Z_OWNED_TYPE_RC_PREFIX(z, type, name)

#define _Z_VIEW_TYPE(type, name) \
    typedef struct {             \
        type _val;               \
    } z_view_##name##_t;

#define _Z_OWNED_FUNCTIONS_NO_COPY_NO_TAKE_FROM_LOANED_DEF_PREFIX(prefix, name)                     \
    void prefix##_internal_##name##_null(prefix##_owned_##name##_t *obj);                           \
    bool prefix##_internal_##name##_check(const prefix##_owned_##name##_t *obj);                    \
    const prefix##_loaned_##name##_t *prefix##_##name##_loan(const prefix##_owned_##name##_t *obj); \
    prefix##_loaned_##name##_t *prefix##_##name##_loan_mut(prefix##_owned_##name##_t *obj);         \
    prefix##_moved_##name##_t *prefix##_##name##_move(prefix##_owned_##name##_t *obj);              \
    void prefix##_##name##_take(prefix##_owned_##name##_t *obj, prefix##_moved_##name##_t *src);    \
    void prefix##_##name##_drop(prefix##_moved_##name##_t *obj);

#define _Z_OWNED_FUNCTIONS_NO_COPY_DEF_PREFIX(prefix, name)                 \
    _Z_OWNED_FUNCTIONS_NO_COPY_NO_TAKE_FROM_LOANED_DEF_PREFIX(prefix, name) \
    z_result_t prefix##_##name##_take_from_loaned(prefix##_owned_##name##_t *dst, prefix##_loaned_##name##_t *src);

#define _Z_OWNED_FUNCTIONS_DEF_PREFIX(prefix, name)     \
    _Z_OWNED_FUNCTIONS_NO_COPY_DEF_PREFIX(prefix, name) \
    z_result_t prefix##_##name##_clone(prefix##_owned_##name##_t *obj, const prefix##_loaned_##name##_t *src);

#define _Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(name) _Z_OWNED_FUNCTIONS_NO_COPY_NO_TAKE_FROM_LOANED_DEF_PREFIX(z, name)
#define _Z_OWNED_FUNCTIONS_NO_COPY_DEF(name) _Z_OWNED_FUNCTIONS_NO_COPY_DEF_PREFIX(z, name)
#define _Z_OWNED_FUNCTIONS_DEF(name) _Z_OWNED_FUNCTIONS_DEF_PREFIX(z, name)

#define _Z_OWNED_FUNCTIONS_SYSTEM_DEF(name)                                    \
    void z_internal_##name##_null(z_owned_##name##_t *obj);                    \
    void z_##name##_take(z_owned_##name##_t *obj, z_moved_##name##_t *src);    \
    const z_loaned_##name##_t *z_##name##_loan(const z_owned_##name##_t *obj); \
    z_loaned_##name##_t *z_##name##_loan_mut(z_owned_##name##_t *obj);         \
    z_moved_##name##_t *z_##name##_move(z_owned_##name##_t *obj);

#define _Z_VIEW_FUNCTIONS_DEF(name)                                                 \
    bool z_view_##name##_is_empty(const z_view_##name##_t *obj);                    \
    const z_loaned_##name##_t *z_view_##name##_loan(const z_view_##name##_t *name); \
    z_loaned_##name##_t *z_view_##name##_loan_mut(z_view_##name##_t *name);         \
    void z_view_##name##_empty(z_view_##name##_t *name);

#define _ZP_NOTHING

#define _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX_INNER(prefix, name, attribute)                             \
    attribute prefix##_moved_##name##_t *prefix##_##name##_move(prefix##_owned_##name##_t *obj) {           \
        return (prefix##_moved_##name##_t *)(obj);                                                          \
    }                                                                                                       \
    attribute void prefix##_##name##_take(prefix##_owned_##name##_t *obj, prefix##_moved_##name##_t *src) { \
        *obj = src->_this;                                                                                  \
        prefix##_internal_##name##_null(&src->_this);                                                       \
    }

#define _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE(name) _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX_INNER(z, name, _ZP_NOTHING)

#define _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX(prefix, name) \
    _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX_INNER(prefix, name, _ZP_NOTHING)

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX_INNER(prefix, type, name, f_check, f_null, f_drop, \
                                                                   attribute)                                   \
    attribute void prefix##_internal_##name##_null(prefix##_owned_##name##_t *obj) { obj->_val = f_null(); }    \
    _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX_INNER(prefix, name, attribute)                                     \
    attribute bool prefix##_internal_##name##_check(const prefix##_owned_##name##_t *obj) {                     \
        return f_check((&obj->_val));                                                                           \
    }                                                                                                           \
    attribute const prefix##_loaned_##name##_t *prefix##_##name##_loan(const prefix##_owned_##name##_t *obj) {  \
        return &obj->_val;                                                                                      \
    }                                                                                                           \
    attribute prefix##_loaned_##name##_t *prefix##_##name##_loan_mut(prefix##_owned_##name##_t *obj) {          \
        return &obj->_val;                                                                                      \
    }                                                                                                           \
    attribute void prefix##_##name##_drop(prefix##_moved_##name##_t *obj) {                                     \
        if (obj != NULL) f_drop((&obj->_this._val));                                                            \
    }

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL_PREFIX_INNER(prefix, type, name, f_check, f_null, f_move, f_drop,        \
                                                           attribute)                                                  \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX_INNER(prefix, type, name, f_check, f_null, f_drop, attribute) \
    attribute z_result_t prefix##_##name##_take_from_loaned(prefix##_owned_##name##_t *obj,                            \
                                                            prefix##_loaned_##name##_t *src) {                         \
        return f_move((&obj->_val), src);                                                                              \
    }

#define _Z_OWNED_FUNCTIONS_VALUE_IMPL_PREFIX_INNER(prefix, type, name, f_check, f_null, f_copy, f_move, f_drop,        \
                                                   attribute)                                                          \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL_PREFIX_INNER(prefix, type, name, f_check, f_null, f_move, f_drop, attribute) \
    attribute z_result_t prefix##_##name##_clone(prefix##_owned_##name##_t *obj,                                       \
                                                 const prefix##_loaned_##name##_t *src) {                              \
        return f_copy((&obj->_val), src);                                                                              \
    }

#define _Z_OWNED_FUNCTIONS_VALUE_IMP_PREFIX(prefix, type, name, f_check, f_null, f_copy, f_move, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_IMPL_PREFIX_INNER(z, type, name, f_check, f_null, f_copy, f_move, f_drop, _ZP_NOTHING)

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX(prefix, type, name, f_check, f_null, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX_INNER(prefix, type, name, f_check, f_null, f_drop, _ZP_NOTHING)

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL_PREFIX(prefix, type, name, f_check, f_null, f_move, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL_PREFIX_INNER(prefix, type, name, f_check, f_null, f_move, f_drop, _ZP_NOTHING)

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(type, name, f_check, f_null, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX(z, type, name, f_check, f_null, f_drop)

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL(type, name, f_check, f_null, f_move, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL_PREFIX(z, type, name, f_check, f_null, f_move, f_drop)

#define _Z_OWNED_FUNCTIONS_VALUE_IMPL(type, name, f_check, f_null, f_copy, f_move, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_IMP_PREFIX(z, type, name, f_check, f_null, f_copy, f_move, f_drop)

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_INLINE_IMPL(type, name, f_check, f_null, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX_INNER(z, type, name, f_check, f_null, f_drop, static inline)

#define _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_INLINE_IMPL(type, name, f_check, f_null, f_move, f_drop) \
    _Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL_PREFIX_INNER(z, type, name, f_check, f_null, f_move, f_drop, static inline)

#define _Z_OWNED_FUNCTIONS_RC_IMPL_CLONE_DROP_INNER(name, attribute)                                 \
    attribute z_result_t z_##name##_clone(z_owned_##name##_t *obj, const z_loaned_##name##_t *src) { \
        z_result_t ret = _Z_RES_OK;                                                                  \
        obj->_rc = _z_##name##_rc_clone((z_loaned_##name##_t *)src);                                 \
        if (_Z_RC_IS_NULL(&obj->_rc)) {                                                              \
            _Z_ERROR_LOG(_Z_ERR_SYSTEM_OUT_OF_MEMORY);                                               \
            ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;                                                       \
        }                                                                                            \
        return ret;                                                                                  \
    }                                                                                                \
    attribute void z_##name##_drop(z_moved_##name##_t *obj) {                                        \
        if (obj != NULL && !_Z_RC_IS_NULL(&obj->_this._rc)) {                                        \
            _z_##name##_rc_drop(&obj->_this._rc);                                                    \
        }                                                                                            \
    }

#define _Z_OWNED_FUNCTIONS_RC_IMPL_NULL_CHECK_LOAN_INNER(name, attribute)                                         \
    attribute void z_internal_##name##_null(z_owned_##name##_t *val) { val->_rc = _z_##name##_rc_null(); }        \
    attribute bool z_internal_##name##_check(const z_owned_##name##_t *val) { return !_Z_RC_IS_NULL(&val->_rc); } \
    attribute const z_loaned_##name##_t *z_##name##_loan(const z_owned_##name##_t *val) { return &val->_rc; }     \
    attribute z_loaned_##name##_t *z_##name##_loan_mut(z_owned_##name##_t *val) { return &val->_rc; }

#define _Z_OWNED_FUNCTIONS_RC_IMPL_INNER(name, attribute)             \
    _Z_OWNED_FUNCTIONS_RC_IMPL_NULL_CHECK_LOAN_INNER(name, attribute) \
    _Z_OWNED_FUNCTIONS_RC_IMPL_CLONE_DROP_INNER(name, attribute)      \
    _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX_INNER(z, name, attribute)

#define _Z_OWNED_FUNCTIONS_RC_IMPL_NO_DROP_CLONE_INNER(name, attribute) \
    _Z_OWNED_FUNCTIONS_RC_IMPL_NULL_CHECK_LOAN_INNER(name, attribute)   \
    _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX_INNER(z, name, attribute)

#define _Z_OWNED_FUNCTIONS_RC_IMPL(name) _Z_OWNED_FUNCTIONS_RC_IMPL_INNER(name, _ZP_NOTHING)
#define _Z_OWNED_FUNCTIONS_RC_INLINE_IMPL(name) _Z_OWNED_FUNCTIONS_RC_IMPL_INNER(name, static inline)

#define _Z_OWNED_FUNCTIONS_RC_IMPL_NO_DROP_CLONE(name) _Z_OWNED_FUNCTIONS_RC_IMPL_NO_DROP_CLONE_INNER(name, _ZP_NOTHING)

#define _Z_OWNED_FUNCTIONS_SYSTEM_IMPL(type, name)                                                   \
    _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE(name)                                                          \
    void z_internal_##name##_null(z_owned_##name##_t *obj) { (void)obj; }                            \
    const z_loaned_##name##_t *z_##name##_loan(const z_owned_##name##_t *obj) { return &obj->_val; } \
    z_loaned_##name##_t *z_##name##_loan_mut(z_owned_##name##_t *obj) { return &obj->_val; }

#define _Z_VIEW_FUNCTIONS_IMPL(type, name, f_check, f_null)                                              \
    bool z_view_##name##_is_empty(const z_view_##name##_t *obj) { return !f_check((&obj->_val)); }       \
    const z_loaned_##name##_t *z_view_##name##_loan(const z_view_##name##_t *obj) { return &obj->_val; } \
    z_loaned_##name##_t *z_view_##name##_loan_mut(z_view_##name##_t *obj) { return &obj->_val; }         \
    void z_view_##name##_empty(z_view_##name##_t *obj) { obj->_val = f_null(); }

#define _Z_OWNED_FUNCTIONS_CLOSURE_DEF_PREFIX(prefix, name)                                      \
    void prefix##_internal_##name##_null(prefix##_owned_##name##_t *name);                       \
    bool prefix##_internal_##name##_check(const prefix##_owned_##name##_t *val);                 \
    prefix##_moved_##name##_t *prefix##_##name##_move(prefix##_owned_##name##_t *val);           \
    void prefix##_##name##_take(prefix##_owned_##name##_t *obj, prefix##_moved_##name##_t *src); \
    void prefix##_##name##_drop(prefix##_moved_##name##_t *obj);                                 \
    const prefix##_loaned_##name##_t *prefix##_##name##_loan(const prefix##_owned_##name##_t *val);

#define _Z_OWNED_FUNCTIONS_CLOSURE_DEF(name) _Z_OWNED_FUNCTIONS_CLOSURE_DEF_PREFIX(z, name)

// For value types
#define _Z_OWNED_TYPE_VALUE_PREFIX(prefix, type, name) \
    typedef struct {                                   \
        type _val;                                     \
    } prefix##_owned_##name##_t;                       \
    _Z_LOANED_TYPE_PREFIX(prefix, type, name)          \
    _Z_MOVED_TYPE_PREFIX(prefix, name)

#define _Z_OWNED_FUNCTIONS_CLOSURE_IMPL_PREFIX(prefix, name, f_call, f_drop)                                       \
    _Z_OWNED_FUNCTIONS_IMPL_MOVE_TAKE_PREFIX(prefix, name)                                                         \
    void prefix##_internal_##name##_null(prefix##_owned_##name##_t *val) {                                         \
        val->_val.call = NULL;                                                                                     \
        val->_val.drop = NULL;                                                                                     \
        val->_val.context = NULL;                                                                                  \
    }                                                                                                              \
    bool prefix##_internal_##name##_check(const prefix##_owned_##name##_t *val) { return val->_val.call != NULL; } \
    void prefix##_##name##_drop(prefix##_moved_##name##_t *obj) {                                                  \
        if (obj->_this._val.drop != NULL) {                                                                        \
            (obj->_this._val.drop)(obj->_this._val.context);                                                       \
            obj->_this._val.drop = NULL;                                                                           \
        }                                                                                                          \
        obj->_this._val.call = NULL;                                                                               \
        obj->_this._val.context = NULL;                                                                            \
    }                                                                                                              \
    const prefix##_loaned_##name##_t *prefix##_##name##_loan(const prefix##_owned_##name##_t *val) {               \
        return &val->_val;                                                                                         \
    }                                                                                                              \
    z_result_t prefix##_##name(prefix##_owned_##name##_t *closure, f_call call, f_drop drop, void *context) {      \
        closure->_val.call = call;                                                                                 \
        closure->_val.drop = drop;                                                                                 \
        closure->_val.context = context;                                                                           \
                                                                                                                   \
        return _Z_RES_OK;                                                                                          \
    }

#define _Z_OWNED_FUNCTIONS_CLOSURE_IMPL(name, f_call, f_drop) \
    _Z_OWNED_FUNCTIONS_CLOSURE_IMPL_PREFIX(z, name, f_call, f_drop)

#endif /* INCLUDE_ZENOH_PICO_API_OLV_MACROS_H */
