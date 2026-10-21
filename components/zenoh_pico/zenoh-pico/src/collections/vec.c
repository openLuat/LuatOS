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

#include "zenoh-pico/collections/vec.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

#include "zenoh-pico/utils/logging.h"

/*-------- vec --------*/
_z_vec_t _z_vec_make(size_t capacity) {
    _z_vec_t v = {0};
    if (capacity != 0) {
        v._val = (void **)z_malloc(sizeof(void *) * capacity);
        if (v._val != NULL) {
            v._capacity = capacity;
        }
    }
    return v;
}

void _z_vec_copy(_z_vec_t *dst, const _z_vec_t *src, z_element_clone_f d_f) {
    dst->_capacity = src->_capacity;
    dst->_len = src->_len;
    dst->_val = (void **)z_malloc(sizeof(void *) * src->_capacity);
    if (dst->_val != NULL) {
        for (size_t i = 0; i < src->_len; i++) {
            dst->_val[i] = d_f(src->_val[i]);
        }
    }
}

void _z_vec_move(_z_vec_t *dst, _z_vec_t *src) {
    *dst = *src;
    *src = _z_vec_null();
}

void _z_vec_reset(_z_vec_t *v, z_element_free_f free_f) {
    for (size_t i = 0; i < v->_len; i++) {
        free_f(&v->_val[i]);
    }

    v->_len = 0;
}

void _z_vec_clear(_z_vec_t *v, z_element_free_f free_f) {
    for (size_t i = 0; i < v->_len; i++) {
        free_f(&v->_val[i]);
    }
    _z_vec_release(v);
}

void _z_vec_release(_z_vec_t *v) {
    z_free(v->_val);
    v->_val = NULL;

    v->_capacity = 0;
    v->_len = 0;
}

void _z_vec_free(_z_vec_t **v, z_element_free_f free_f) {
    _z_vec_t *ptr = (_z_vec_t *)*v;

    if (ptr != NULL) {
        _z_vec_clear(ptr, free_f);

        z_free(ptr);
        *v = NULL;
    }
}

void _z_vec_append(_z_vec_t *v, void *e) {
    if (v->_len == v->_capacity) {
        // Allocate a new vector
        size_t _capacity = (v->_capacity << 1) | 0x01;
        void **_val = (void **)z_malloc(_capacity * sizeof(void *));
        if (_val != NULL) {
            (void)memcpy(_val, v->_val, v->_capacity * sizeof(void *));

            // Free the old vector
            z_free(v->_val);

            // Update the current vector
            v->_val = _val;
            v->_capacity = _capacity;

            v->_val[v->_len] = e;
            v->_len = v->_len + 1;
        }
    } else {
        v->_val[v->_len] = e;
        v->_len = v->_len + 1;
    }
}

void _z_vec_set(_z_vec_t *v, size_t i, void *e, z_element_free_f free_f) {
    assert(i < v->_len);

    if (v->_val[i] != NULL) {
        free_f(&v->_val[i]);
    }
    v->_val[i] = e;
}

void _z_vec_remove(_z_vec_t *v, size_t pos, z_element_free_f free_f) {
    free_f(&v->_val[pos]);
    for (size_t i = pos; i < v->_len; i++) {
        v->_val[pos] = v->_val[pos + (size_t)1];
    }

    v->_val[v->_len] = NULL;
    v->_len = v->_len - 1;
}

/*-------- svec --------*/
_z_svec_t _z_svec_make(size_t capacity, size_t element_size) {
    _z_svec_t v = _z_svec_null();
    if (capacity != 0) {
        v._val = z_malloc(element_size * capacity);
    }
    if (v._val != NULL) {
        v._capacity = capacity;
    }
    return v;
}

void _z_svec_init(_z_svec_t *v, size_t offset, size_t element_size) {
    assert(offset <= v->_capacity);
    void *start = _z_svec_get_mut(v, offset, element_size);
    memset(start, 0, (v->_capacity - offset) * element_size);
}

static inline void __z_svec_move_inner(void *dst, void *src, z_element_move_f move, size_t num_elements,
                                       size_t element_size, bool use_elem_f) {
    if (use_elem_f) {
        size_t offset = 0;
        for (size_t i = 0; i < num_elements; i++) {
            move((uint8_t *)dst + offset, (uint8_t *)src + offset);
            offset += element_size;
        }
    } else {
        memmove(dst, src, num_elements * element_size);
    }
}

void _z_svec_move(_z_svec_t *dst, _z_svec_t *src) {
    *dst = *src;
    *src = _z_svec_null();
}

z_result_t _z_svec_copy(_z_svec_t *dst, const _z_svec_t *src, z_element_copy_f copy, size_t element_size,
                        bool use_elem_f) {
    *dst = _z_svec_null();
    if (src->_capacity == 0) {
        return _Z_RES_OK;
    }
    dst->_val = z_malloc(element_size * src->_capacity);
    if (dst->_val == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    dst->_capacity = src->_capacity;
    dst->_len = src->_len;
    // Copy data to new vector
    if (use_elem_f) {
        size_t offset = 0;
        for (size_t i = 0; i < src->_len; i++) {
            copy((uint8_t *)dst->_val + offset, (uint8_t *)src->_val + offset);
            offset += element_size;
        }
    } else {
        memcpy(dst->_val, src->_val, src->_len * element_size);
    }
    return _Z_RES_OK;
}

void _z_svec_reset(_z_svec_t *v, z_element_clear_f clear, size_t element_size) {
    if (clear != NULL) {
        size_t offset = 0;
        for (size_t i = 0; i < v->_len; i++) {
            clear((uint8_t *)v->_val + offset);
            offset += element_size;
        }
    }
    v->_len = 0;
}

void _z_svec_clear(_z_svec_t *v, z_element_clear_f clear_f, size_t element_size) {
    _z_svec_reset(v, clear_f, element_size);
    if (!v->_aliased) {
        _z_svec_release(v);
    }
}

void _z_svec_release(_z_svec_t *v) {
    z_free(v->_val);
    v->_capacity = 0;
    v->_val = NULL;
}

void _z_svec_free(_z_svec_t **v, z_element_clear_f clear, size_t element_size) {
    _z_svec_t *ptr = (_z_svec_t *)*v;

    if (ptr != NULL) {
        _z_svec_clear(ptr, clear, element_size);

        z_free(ptr);
        *v = NULL;
    }
}

z_result_t _z_svec_expand(_z_svec_t *v, z_element_move_f move, size_t element_size, bool use_elem_f) {
    // Allocate a new vector
    size_t _capacity = v->_capacity == 0 ? 1 : v->_capacity << 1;
    void *_val = (void *)z_malloc(_capacity * element_size);
    if (_val == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    // Move and clear old data
    __z_svec_move_inner(_val, v->_val, move, v->_len, element_size, use_elem_f);
    z_free(v->_val);
    // Update the current vector
    v->_val = _val;
    v->_capacity = _capacity;
    return _Z_RES_OK;
}

z_result_t _z_svec_append(_z_svec_t *v, const void *e, z_element_move_f move, size_t element_size, bool use_elem_f) {
    if (v->_len == v->_capacity) {
        _Z_RETURN_IF_ERR(_z_svec_expand(v, move, element_size, use_elem_f));
    }
    // Append element
    memcpy((uint8_t *)v->_val + v->_len * element_size, e, element_size);
    v->_len++;
    return _Z_RES_OK;
}

void _z_svec_set(_z_svec_t *v, size_t i, void *e, z_element_clear_f clear, size_t element_size) {
    assert(i < v->_len);
    clear((uint8_t *)v->_val + i * element_size);
    memcpy((uint8_t *)v->_val + i * element_size, e, element_size);
}

void _z_svec_remove(_z_svec_t *v, size_t pos, z_element_clear_f clear, z_element_move_f move, size_t element_size,
                    bool use_elem_f) {
    assert(pos < v->_len);
    clear((uint8_t *)v->_val + pos * element_size);
    __z_svec_move_inner((uint8_t *)v->_val + pos * element_size, (uint8_t *)v->_val + (pos + 1) * element_size, move,
                        (v->_len - pos - 1) * element_size, element_size, use_elem_f);

    v->_len--;
}
