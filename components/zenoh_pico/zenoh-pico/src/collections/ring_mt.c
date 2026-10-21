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

#include "zenoh-pico/collections/ring_mt.h"

#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/utils/logging.h"

/*-------- Ring Buffer Multithreaded --------*/
z_result_t _z_ring_mt_init(_z_ring_mt_t *ring, size_t capacity) {
    _Z_RETURN_IF_ERR(_z_ring_init(&ring->_ring, capacity))

#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_init(&ring->_mutex))
    _Z_RETURN_IF_ERR(_z_condvar_init(&ring->_cv_not_empty))
#endif
    ring->is_closed = false;
    return _Z_RES_OK;
}

_z_ring_mt_t *_z_ring_mt_new(size_t capacity) {
    _z_ring_mt_t *ring = (_z_ring_mt_t *)z_malloc(sizeof(_z_ring_mt_t));
    if (ring == NULL) {
        _Z_ERROR("z_malloc failed");
        return NULL;
    }

    z_result_t ret = _z_ring_mt_init(ring, capacity);
    if (ret != _Z_RES_OK) {
        _Z_ERROR("_z_ring_mt_init failed: %i", ret);
        return NULL;
    }

    return ring;
}

void _z_ring_mt_clear(_z_ring_mt_t *ring, z_element_free_f free_f) {
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_drop(&ring->_mutex);
    _z_condvar_drop(&ring->_cv_not_empty);
#endif

    _z_ring_clear(&ring->_ring, free_f);
}

void _z_ring_mt_free(_z_ring_mt_t *ring, z_element_free_f free_f) {
    _z_ring_mt_clear(ring, free_f);

    z_free(ring);
}

z_result_t _z_ring_mt_push(const void *elem, void *context, z_element_free_f element_free) {
    if (elem == NULL || context == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }

    _z_ring_mt_t *r = (_z_ring_mt_t *)context;

#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_lock(&r->_mutex))
#endif

    _z_ring_push_force_drop(&r->_ring, (void *)elem, element_free);

#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_condvar_signal(&r->_cv_not_empty))
    _Z_RETURN_IF_ERR(_z_mutex_unlock(&r->_mutex))
#endif
    return _Z_RES_OK;
}

z_result_t _z_ring_mt_close(_z_ring_mt_t *ring) {
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_lock(&ring->_mutex))
    ring->is_closed = true;
    _Z_RETURN_IF_ERR(_z_condvar_signal_all(&ring->_cv_not_empty))
    _Z_RETURN_IF_ERR(_z_mutex_unlock(&ring->_mutex))
#else
    ring->is_closed = true;
#endif
    return _Z_RES_OK;
}

z_result_t _z_ring_mt_pull(void *dst, void *context, z_element_move_f element_move) {
    _z_ring_mt_t *r = (_z_ring_mt_t *)context;

#if Z_FEATURE_MULTI_THREAD == 1
    void *src = NULL;
    _Z_RETURN_IF_ERR(_z_mutex_lock(&r->_mutex))
    while (src == NULL) {
        src = _z_ring_pull(&r->_ring);
        if (src == NULL) {
            if (r->is_closed) break;
            _Z_RETURN_IF_ERR(_z_condvar_wait(&r->_cv_not_empty, &r->_mutex))
        }
    }
    _Z_RETURN_IF_ERR(_z_mutex_unlock(&r->_mutex))
#else   // Z_FEATURE_MULTI_THREAD == 1
    void *src = _z_ring_pull(&r->_ring);
#endif  // Z_FEATURE_MULTI_THREAD == 1

    if (r->is_closed && src == NULL) {
        return _Z_RES_CHANNEL_CLOSED;
    }

    if (src != NULL) {
        element_move(dst, src);
    }

    return _Z_RES_OK;
}

z_result_t _z_ring_mt_try_pull(void *dst, void *context, z_element_move_f element_move) {
    _z_ring_mt_t *r = (_z_ring_mt_t *)context;

#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_lock(&r->_mutex))
#endif

    void *src = _z_ring_pull(&r->_ring);

#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_unlock(&r->_mutex))
#endif

    if (src != NULL) {
        element_move(dst, src);
    } else if (r->is_closed) {
        return _Z_RES_CHANNEL_CLOSED;
    } else {
        return _Z_RES_CHANNEL_NODATA;
    }
    return _Z_RES_OK;
}
