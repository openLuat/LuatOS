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

// user needs to define the following macros before including this file
// _ZP_DEQUE_TEMPLATE_ELEM_TYPE: the type of the elements in the buffer
// _ZP_DEQUE_TEMPLATE_NAME: the name of the buffer type to generate (without the _t suffix)
// _ZP_DEQUE_TEMPLATE_SIZE: the maximum size of the circular buffer (optional, default is 16)
// _ZP_DEQUE_TEMPLATE_ALLOCATOR_TYPE: the type of the allocator to use for the buffer nodes (optional, default is a
// simple z_malloc/z_free allocator) _ZP_DEQUE_TEMPLATE_ELEM_DESTROY_FN_NAME: the name of the function to destroy an
// element (optional, default is a no-op function) _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME: the name of the function to
// move an element (optional, default is an element-wise move function that uses the copy function and then clears the
// source element)

#include <stdbool.h>
#include <stddef.h>

#include "zenoh-pico/collections/cat.h"

#ifndef _ZP_DEQUE_TEMPLATE_ELEM_TYPE
#error "_ZP_DEQUE_TEMPLATE_ELEM_TYPE must be defined before including deque_template.h"
#define _ZP_DEQUE_TEMPLATE_ELEM_TYPE int
#endif
#ifndef _ZP_DEQUE_TEMPLATE_SIZE
#define _ZP_DEQUE_TEMPLATE_SIZE 16
#endif
#ifndef _ZP_DEQUE_TEMPLATE_NAME
#define _ZP_DEQUE_TEMPLATE_NAME _ZP_CAT(_ZP_CAT(_ZP_DEQUE_TEMPLATE_ELEM_TYPE, deque), _ZP_DEQUE_TEMPLATE_SIZE)
#endif

#ifndef _ZP_DEQUE_TEMPLATE_ELEM_DESTROY_FN_NAME
#define _ZP_DEQUE_TEMPLATE_ELEM_DESTROY_FN_NAME(x) (void)(x)
#endif
#ifndef _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME
#define _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME(dst, src) \
    *(dst) = *(src);                                   \
    _ZP_DEQUE_TEMPLATE_ELEM_DESTROY_FN_NAME(src);
#endif

#define _ZP_DEQUE_TEMPLATE_TYPE _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, t)
typedef struct _ZP_DEQUE_TEMPLATE_TYPE {
    _ZP_DEQUE_TEMPLATE_ELEM_TYPE _buffer[_ZP_DEQUE_TEMPLATE_SIZE];
    size_t _start;
    size_t _end;
} _ZP_DEQUE_TEMPLATE_TYPE;

static inline _ZP_DEQUE_TEMPLATE_TYPE _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, new)(void) {
    _ZP_DEQUE_TEMPLATE_TYPE deque = {0};
    return deque;
}
static inline size_t _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, size)(const _ZP_DEQUE_TEMPLATE_TYPE *deque) {
    if (deque->_start < deque->_end) {
        return deque->_end - deque->_start;
    } else if (deque->_start == 0 && deque->_end == 0) {
        return 0;
    }
    return _ZP_DEQUE_TEMPLATE_SIZE - deque->_start + deque->_end;
}
static inline void _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, destroy)(_ZP_DEQUE_TEMPLATE_TYPE *deque) {
    size_t count = _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, size)(deque);
    for (size_t i = 0; i < count; i++) {
        size_t idx = deque->_start + i;
        if (i >= _ZP_DEQUE_TEMPLATE_SIZE) {
            idx -= _ZP_DEQUE_TEMPLATE_SIZE;
        }
        _ZP_DEQUE_TEMPLATE_ELEM_DESTROY_FN_NAME(&deque->_buffer[idx]);
    }
    deque->_start = 0;
    deque->_end = 0;
}
static inline bool _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, is_empty)(const _ZP_DEQUE_TEMPLATE_TYPE *deque) {
    return _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, size)(deque) == 0;
}
static inline bool _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, push_back)(_ZP_DEQUE_TEMPLATE_TYPE *deque,
                                                               _ZP_DEQUE_TEMPLATE_ELEM_TYPE *elem) {
    if (_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, size)(deque) == _ZP_DEQUE_TEMPLATE_SIZE) {
        return false;
    }
    if (deque->_end == _ZP_DEQUE_TEMPLATE_SIZE) {
        deque->_end = 0;
    }
    _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME(&deque->_buffer[deque->_end], elem);
    deque->_end++;
    return true;
}
static inline bool _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, pop_back)(_ZP_DEQUE_TEMPLATE_TYPE *deque,
                                                              _ZP_DEQUE_TEMPLATE_ELEM_TYPE *out) {
    if (_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, is_empty)(deque)) {
        return false;
    }
    if (deque->_end == 0) {
        deque->_end = _ZP_DEQUE_TEMPLATE_SIZE;
    }
    deque->_end--;
    _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME(out, &deque->_buffer[deque->_end]);
    if (deque->_end == deque->_start) {
        deque->_end = 0;
        deque->_start = 0;
    }
    return true;
}
static inline _ZP_DEQUE_TEMPLATE_ELEM_TYPE *_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, back)(_ZP_DEQUE_TEMPLATE_TYPE *deque) {
    if (_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, is_empty)(deque)) {
        return NULL;
    }
    size_t idx = deque->_end == 0 ? _ZP_DEQUE_TEMPLATE_SIZE - 1 : deque->_end - 1;
    return &deque->_buffer[idx];
}
static inline bool _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, push_front)(_ZP_DEQUE_TEMPLATE_TYPE *deque,
                                                                _ZP_DEQUE_TEMPLATE_ELEM_TYPE *elem) {
    if (_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, size)(deque) == _ZP_DEQUE_TEMPLATE_SIZE) {
        return false;
    }
    if (deque->_start == 0) {
        deque->_start = _ZP_DEQUE_TEMPLATE_SIZE;
    }
    deque->_start--;
    _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME(&deque->_buffer[deque->_start], elem);
    return true;
}
static inline bool _ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, pop_front)(_ZP_DEQUE_TEMPLATE_TYPE *deque,
                                                               _ZP_DEQUE_TEMPLATE_ELEM_TYPE *out) {
    if (_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, is_empty)(deque)) {
        return false;
    }
    _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME(out, &deque->_buffer[deque->_start]);
    deque->_start++;
    if (deque->_end == deque->_start) {
        deque->_end = 0;
        deque->_start = 0;
    }
    return true;
}
static inline _ZP_DEQUE_TEMPLATE_ELEM_TYPE *_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, front)(_ZP_DEQUE_TEMPLATE_TYPE *deque) {
    if (_ZP_CAT(_ZP_DEQUE_TEMPLATE_NAME, is_empty)(deque)) {
        return NULL;
    }
    return &deque->_buffer[deque->_start];
}

#undef _ZP_DEQUE_TEMPLATE_TYPE
#undef _ZP_DEQUE_TEMPLATE_ELEM_TYPE
#undef _ZP_DEQUE_TEMPLATE_NAME
#undef _ZP_DEQUE_TEMPLATE_NODE_TYPE
#undef _ZP_DEQUE_TEMPLATE_ELEM_DESTROY_FN_NAME
#undef _ZP_DEQUE_TEMPLATE_ELEM_MOVE_FN_NAME
#undef _ZP_DEQUE_TEMPLATE_SIZE
