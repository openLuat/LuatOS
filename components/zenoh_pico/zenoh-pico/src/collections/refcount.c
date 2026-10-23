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

#include "zenoh-pico/collections/refcount.h"

#include <string.h>

#include "zenoh-pico/collections/atomic.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"

#define _Z_RC_MAX_COUNT INT32_MAX  // Based on Rust lazy overflow check
typedef struct {
    _z_atomic_size_t _strong_cnt;
    _z_atomic_size_t _weak_cnt;
} _z_inner_rc_t;

static inline _z_inner_rc_t* _z_rc_inner(void* rc) { return (_z_inner_rc_t*)rc; }

z_result_t _z_rc_init(void** cnt) {
    *cnt = z_malloc(sizeof(_z_inner_rc_t));
    if ((*cnt) == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    _z_inner_rc_t* rc = *cnt;
    _z_atomic_size_init(&rc->_strong_cnt, 1);
    _z_atomic_size_init(&rc->_weak_cnt, 1);
    // Note we increase weak count by 1 when creating a new rc, to take ownership of counter.
    return _Z_RES_OK;
}

z_result_t _z_rc_increase_strong(void* cnt) {
    _z_inner_rc_t* c = (_z_inner_rc_t*)cnt;
    if (c == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }
    if (_z_atomic_size_fetch_add(&c->_strong_cnt, 1, _z_memory_order_relaxed) >= _Z_RC_MAX_COUNT) {
        _Z_ERROR("Rc strong count overflow");
        _Z_ERROR_RETURN(_Z_ERR_OVERFLOW);
    }
    return _Z_RES_OK;
}

z_result_t _z_rc_increase_weak(void* cnt) {
    _z_inner_rc_t* c = (_z_inner_rc_t*)cnt;
    if (c == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }
    if (_z_atomic_size_fetch_add(&c->_weak_cnt, 1, _z_memory_order_relaxed) >= _Z_RC_MAX_COUNT) {
        _Z_ERROR("Rc weak count overflow");
        _Z_ERROR_RETURN(_Z_ERR_OVERFLOW);
    }
    return _Z_RES_OK;
}

bool _z_rc_decrease_strong(void** cnt) {
    _z_inner_rc_t* c = (_z_inner_rc_t*)*cnt;
    if (_z_atomic_size_fetch_sub(&c->_strong_cnt, 1, _z_memory_order_release) > 1) {
        return false;
    }
    // destroy fake weak that we created during strong init
    _z_rc_decrease_weak(cnt);
    return true;
}

bool _z_rc_decrease_weak(void** cnt) {
    _z_inner_rc_t* c = (_z_inner_rc_t*)*cnt;
    if (_z_atomic_size_fetch_sub(&c->_weak_cnt, 1, _z_memory_order_release) > 1) {
        return false;
    }
    _z_atomic_thread_fence(
        _z_memory_order_acquire);  // ensure we see the latest state of strong count before we free the counter
    z_free(*cnt);
    *cnt = NULL;
    return true;
}

z_result_t _z_rc_weak_upgrade(void* cnt) {
    if (cnt == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }
    _z_inner_rc_t* c = (_z_inner_rc_t*)cnt;
    size_t prev = _z_atomic_size_load(&c->_strong_cnt, _z_memory_order_relaxed);
    while ((prev != 0) && (prev < _Z_RC_MAX_COUNT)) {
        if (_z_atomic_size_compare_exchange_weak(&c->_strong_cnt, &prev, prev + 1, _z_memory_order_acquire,
                                                 _z_memory_order_relaxed)) {
            return _Z_RES_OK;
        }
    }
    _Z_ERROR_RETURN(_Z_ERR_INVALID);
}

size_t _z_rc_weak_count(void* rc) {
    if (rc == NULL) {
        return 0;
    }
    size_t strong_count = _z_atomic_size_load(&_z_rc_inner(rc)->_strong_cnt, _z_memory_order_relaxed);
    size_t weak_count = _z_atomic_size_load(&_z_rc_inner(rc)->_weak_cnt, _z_memory_order_relaxed);
    if (weak_count == 0) {
        return 0;
    }
    return (strong_count > 0) ? weak_count - 1 : weak_count;  // substruct 1 weak ref that we added during strong init
}

size_t _z_rc_strong_count(void* rc) {
    return rc == NULL ? 0 : _z_atomic_size_load(&_z_rc_inner(rc)->_strong_cnt, _z_memory_order_relaxed);
}

typedef struct {
    _z_atomic_size_t _strong_cnt;
} _z_inner_simple_rc_t;

#define RC_CNT_SIZE sizeof(_z_inner_simple_rc_t)

static inline _z_inner_simple_rc_t* _z_simple_rc_inner(void* rc) { return (_z_inner_simple_rc_t*)rc; }

void* _z_simple_rc_value(void* rc) { return (void*)_z_ptr_u8_offset((uint8_t*)rc, (ptrdiff_t)RC_CNT_SIZE); }

z_result_t _z_simple_rc_init(void** rc, const void* val, size_t val_size) {
    *rc = z_malloc(RC_CNT_SIZE + val_size);
    if ((*rc) == NULL) {
        _Z_ERROR("Failed to allocate rc");
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    _z_inner_simple_rc_t* inner = _z_simple_rc_inner(*rc);
    _z_atomic_size_init(&inner->_strong_cnt, 1);
    memcpy(_z_simple_rc_value(*rc), val, val_size);
    return _Z_RES_OK;
}

z_result_t _z_simple_rc_increase(void* rc) {
    _z_inner_simple_rc_t* c = _z_simple_rc_inner(rc);
    if (_z_atomic_size_fetch_add(&c->_strong_cnt, 1, _z_memory_order_relaxed) >= _Z_RC_MAX_COUNT) {
        _Z_ERROR("Rc strong count overflow");
        _Z_ERROR_RETURN(_Z_ERR_OVERFLOW);
    }
    return _Z_RES_OK;
}

bool _z_simple_rc_decrease(void* rc) {
    _z_inner_simple_rc_t* c = _z_simple_rc_inner(rc);
    if (_z_atomic_size_fetch_sub(&c->_strong_cnt, 1, _z_memory_order_release) > 1) {
        return false;
    }
    return true;
}

size_t _z_simple_rc_strong_count(void* rc) {
    return rc == NULL ? 0 : _z_atomic_size_load(&(_z_simple_rc_inner(rc)->_strong_cnt), _z_memory_order_relaxed);
}
