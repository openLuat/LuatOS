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

// user needs to define the following macros before including this file:
// _ZP_PQUEUE_TEMPLATE_ELEM_TYPE: the type of the elements in the priority queue
// _ZP_PQUEUE_TEMPLATE_NAME: the name of the priority queue type to generate (without the _t suffix)
// _ZP_PQUEUE_TEMPLATE_SIZE: the maximum size of the priority queue (optional, default is 16)
// _ZP_PQUEUE_TEMPLATE_ELEM_DESTROY_FN_NAME: the name of the function to destroy an element (optional, default is a
// no-op) _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME: the name of the function to move an element (optional, default is
// element-wise copy + destroy source) _ZP_PQUEUE_TEMPLATE_ELEM_CMP_FN_NAME: the name of the comparison function
// (elem_a, elem_b) -> int
//   should return <0 if a has higher priority than b, 0 if equal, >0 if b has higher priority than a
//   (i.e. min-priority queue by default: smallest element is at the top)
//
// Optional context support:
//   _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE: the type of an optional context passed to the compare function.
//       When defined, the compare macro signature becomes (elem_a, elem_b, ctx_ptr) where ctx_ptr is of type
//       _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE *.  The context is stored inside the queue struct and supplied to every
//       sift_up / sift_down call automatically.  Use new_with_ctx(ctx) to initialise it; new() zero-initialises it.
//       When not defined (the default), the compare macro keeps its original (elem_a, elem_b) signature and no
//       context is stored.

#include <stdbool.h>
#include <stddef.h>

#include "zenoh-pico/collections/cat.h"

#ifndef _ZP_PQUEUE_TEMPLATE_ELEM_TYPE
#error "_ZP_PQUEUE_TEMPLATE_ELEM_TYPE must be defined before including pqueue_template.h"
#define _ZP_PQUEUE_TEMPLATE_ELEM_TYPE int
#endif
#ifndef _ZP_PQUEUE_TEMPLATE_SIZE
#define _ZP_PQUEUE_TEMPLATE_SIZE 16
#endif
#ifndef _ZP_PQUEUE_TEMPLATE_NAME
#define _ZP_PQUEUE_TEMPLATE_NAME _ZP_CAT(_ZP_CAT(_ZP_PQUEUE_TEMPLATE_ELEM_TYPE, pqueue), _ZP_PQUEUE_TEMPLATE_SIZE)
#endif
#ifndef _ZP_PQUEUE_TEMPLATE_ELEM_CMP_FN_NAME
#error "_ZP_PQUEUE_TEMPLATE_ELEM_CMP_FN_NAME must be defined before including pqueue_template.h"
#endif
#ifndef _ZP_PQUEUE_TEMPLATE_ELEM_DESTROY_FN_NAME
#define _ZP_PQUEUE_TEMPLATE_ELEM_DESTROY_FN_NAME(x) (void)(x)
#endif
#ifndef _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME
#define _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(dst, src) \
    *(dst) = *(src);                                    \
    _ZP_PQUEUE_TEMPLATE_ELEM_DESTROY_FN_NAME(src);
#endif

// ── Context support ───────────────────────────────────────────────────────────
// Internally the template always calls _ZP_PQUEUE_TEMPLATE_ELEM_CMP_INTERNAL(a, b, ctx_ptr).
// When _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE is defined the user-supplied CMP_FN receives the pointer;
// otherwise we define the internal macro to call the 2-argument CMP_FN and ignore ctx.

#ifdef _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE
// Context-aware path: user compare macro is (elem_a, elem_b, ctx_ptr)
#define _ZP_PQUEUE_TEMPLATE_ELEM_CMP_INTERNAL(a, b, pqueue) \
    _ZP_PQUEUE_TEMPLATE_ELEM_CMP_FN_NAME((a), (b), (pqueue->_cmp_ctx))
#else
// Context-free path: user compare macro is (elem_a, elem_b); ctx ignored
#define _ZP_PQUEUE_TEMPLATE_ELEM_CMP_INTERNAL(a, b, pqueue) _ZP_PQUEUE_TEMPLATE_ELEM_CMP_FN_NAME((a), (b))
#endif

#define _ZP_PQUEUE_TEMPLATE_TYPE _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, t)
typedef struct _ZP_PQUEUE_TEMPLATE_TYPE {
    _ZP_PQUEUE_TEMPLATE_ELEM_TYPE _buffer[_ZP_PQUEUE_TEMPLATE_SIZE];
    size_t _size;
#ifdef _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE
    _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE *_cmp_ctx;
#endif
} _ZP_PQUEUE_TEMPLATE_TYPE;

static inline _ZP_PQUEUE_TEMPLATE_TYPE _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, new)(void) {
    _ZP_PQUEUE_TEMPLATE_TYPE pqueue = {0};
    return pqueue;
}

#ifdef _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE
// new_with_ctx: initialise the queue and store a context pointer for comparisons.
static inline _ZP_PQUEUE_TEMPLATE_TYPE _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME,
                                               new_with_ctx)(_ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE *ctx) {
    _ZP_PQUEUE_TEMPLATE_TYPE pqueue = {0};
    pqueue._cmp_ctx = ctx;
    return pqueue;
}
// set_ctx: overwrite the context pointer in an existing queue.
// This is useful if the context needs to be updated after the queue is created (for example in case of move of
// self-referencing structs), or if new() was used to create a zero-initialised queue and the context pointer needs to
// be set later.
static inline void _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, set_ctx)(_ZP_PQUEUE_TEMPLATE_TYPE *pqueue,
                                                              _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE *ctx) {
    pqueue->_cmp_ctx = ctx;
}
#endif

static inline void _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, destroy)(_ZP_PQUEUE_TEMPLATE_TYPE *pqueue) {
    for (size_t i = 0; i < pqueue->_size; i++) {
        _ZP_PQUEUE_TEMPLATE_ELEM_DESTROY_FN_NAME(&pqueue->_buffer[i]);
    }
    pqueue->_size = 0;
}
static inline size_t _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, size)(const _ZP_PQUEUE_TEMPLATE_TYPE *pqueue) {
    return pqueue->_size;
}
static inline bool _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, is_empty)(const _ZP_PQUEUE_TEMPLATE_TYPE *pqueue) {
    return pqueue->_size == 0;
}
static inline _ZP_PQUEUE_TEMPLATE_ELEM_TYPE *_ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, peek)(_ZP_PQUEUE_TEMPLATE_TYPE *pqueue) {
    if (pqueue->_size == 0) {
        return NULL;
    }
    return &pqueue->_buffer[0];
}
static inline void _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, sift_up)(_ZP_PQUEUE_TEMPLATE_TYPE *pqueue, size_t i) {
    while (i > 0) {
        size_t parent = (i - 1) / 2;
        if (_ZP_PQUEUE_TEMPLATE_ELEM_CMP_INTERNAL(&pqueue->_buffer[i], &pqueue->_buffer[parent], pqueue) < 0) {
            _ZP_PQUEUE_TEMPLATE_ELEM_TYPE tmp;
            _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&tmp, &pqueue->_buffer[parent]);
            _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&pqueue->_buffer[parent], &pqueue->_buffer[i]);
            _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&pqueue->_buffer[i], &tmp);
            i = parent;
        } else {
            break;
        }
    }
}
static inline void _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, sift_down)(_ZP_PQUEUE_TEMPLATE_TYPE *pqueue, size_t i) {
    while (true) {
        size_t left = 2 * i + 1;
        size_t right = 2 * i + 2;
        size_t best = i;
        if (left < pqueue->_size &&
            _ZP_PQUEUE_TEMPLATE_ELEM_CMP_INTERNAL(&pqueue->_buffer[left], &pqueue->_buffer[best], pqueue) < 0) {
            best = left;
        }
        if (right < pqueue->_size &&
            _ZP_PQUEUE_TEMPLATE_ELEM_CMP_INTERNAL(&pqueue->_buffer[right], &pqueue->_buffer[best], pqueue) < 0) {
            best = right;
        }
        if (best == i) {
            break;
        }
        _ZP_PQUEUE_TEMPLATE_ELEM_TYPE tmp;
        _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&tmp, &pqueue->_buffer[i]);
        _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&pqueue->_buffer[i], &pqueue->_buffer[best]);
        _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&pqueue->_buffer[best], &tmp);
        i = best;
    }
}
static inline bool _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, push)(_ZP_PQUEUE_TEMPLATE_TYPE *pqueue,
                                                           _ZP_PQUEUE_TEMPLATE_ELEM_TYPE *elem) {
    if (pqueue->_size == _ZP_PQUEUE_TEMPLATE_SIZE) {
        return false;
    }
    _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&pqueue->_buffer[pqueue->_size], elem);
    _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, sift_up)(pqueue, pqueue->_size);
    pqueue->_size++;
    return true;
}
static inline bool _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, pop)(_ZP_PQUEUE_TEMPLATE_TYPE *pqueue,
                                                          _ZP_PQUEUE_TEMPLATE_ELEM_TYPE *out) {
    if (pqueue->_size == 0) {
        return false;
    }
    _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(out, &pqueue->_buffer[0]);
    pqueue->_size--;
    if (pqueue->_size > 0) {
        _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME(&pqueue->_buffer[0], &pqueue->_buffer[pqueue->_size]);
        _ZP_CAT(_ZP_PQUEUE_TEMPLATE_NAME, sift_down)(pqueue, 0);
    }
    return true;
}

#undef _ZP_PQUEUE_TEMPLATE_ELEM_TYPE
#undef _ZP_PQUEUE_TEMPLATE_NAME
#undef _ZP_PQUEUE_TEMPLATE_SIZE
#undef _ZP_PQUEUE_TEMPLATE_ELEM_DESTROY_FN_NAME
#undef _ZP_PQUEUE_TEMPLATE_ELEM_MOVE_FN_NAME
#undef _ZP_PQUEUE_TEMPLATE_ELEM_CMP_FN_NAME
#undef _ZP_PQUEUE_TEMPLATE_TYPE
#ifdef _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE
#undef _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE
#endif
#undef _ZP_PQUEUE_TEMPLATE_ELEM_CMP_INTERNAL
