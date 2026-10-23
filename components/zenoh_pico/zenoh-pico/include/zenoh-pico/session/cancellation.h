//
// Copyright (c) 2025 ZettaScale Technology
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

#ifndef ZENOH_PICO_SESSION_CANCELLATION_H
#define ZENOH_PICO_SESSION_CANCELLATION_H

#include "zenoh-pico/collections/intmap.h"
#include "zenoh-pico/collections/sync_group.h"
#include "zenoh-pico/system/platform.h"

typedef z_result_t (*_z_cancellation_token_on_cancel_handler_callback)(void* arg);
typedef void (*_z_cancellation_token_on_cancel_handler_dropper)(void* arg);

typedef struct {
    _z_cancellation_token_on_cancel_handler_callback _on_cancel;
    _z_cancellation_token_on_cancel_handler_dropper _on_drop;
    void* _arg;
} _z_cancellation_token_on_cancel_handler_t;

z_result_t _z_cancellation_token_on_cancel_handler_call(_z_cancellation_token_on_cancel_handler_t* handler);

static inline _z_cancellation_token_on_cancel_handler_t _z_cancellation_token_on_cancel_handler_null(void) {
    _z_cancellation_token_on_cancel_handler_t h = {0};
    return h;
}

static inline void _z_cancellation_token_on_cancel_handler_drop(_z_cancellation_token_on_cancel_handler_t* h) {
    if (h->_on_drop != NULL) {
        h->_on_drop(h->_arg);
    }
    h->_on_cancel = NULL;
    h->_arg = NULL;
    h->_on_drop = NULL;
}

static inline void _z_cancellation_token_on_cancel_handler_move(_z_cancellation_token_on_cancel_handler_t* dst,
                                                                _z_cancellation_token_on_cancel_handler_t* src) {
    *dst = *src;
    *src = _z_cancellation_token_on_cancel_handler_null();
}

_Z_ELEM_DEFINE(_z_cancellation_token_on_cancel_handler, _z_cancellation_token_on_cancel_handler_t, _z_noop_size,
               _z_cancellation_token_on_cancel_handler_drop, _z_noop_copy, _z_cancellation_token_on_cancel_handler_move,
               _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_INT_MAP_DEFINE(_z_cancellation_token_on_cancel_handler, _z_cancellation_token_on_cancel_handler_t)

typedef struct {
    _z_cancellation_token_on_cancel_handler_intmap_t _handlers;
    size_t _next_handler_id;
    _z_sync_group_notifier_t _cancel_sync_notifier;
} _z_cancellation_handlers_storage_t;

typedef struct {
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_t _mutex;
#endif
    _z_cancellation_handlers_storage_t _handlers;
    _z_sync_group_t _sync_group;
    z_result_t _cancel_result;
} _z_cancellation_token_t;

z_result_t _z_cancellation_token_create(_z_cancellation_token_t* ct);
bool _z_cancellation_token_is_cancelled(const _z_cancellation_token_t* ct);
z_result_t _z_cancellation_token_cancel(_z_cancellation_token_t* ct);
z_result_t _z_cancellation_token_cancel_with_timeout(_z_cancellation_token_t* ct, uint32_t timeout_ms);
void _z_cancellation_token_clear(_z_cancellation_token_t* ct);

// if return value is not _Z_RES_OK, handler is not consumed
z_result_t _z_cancellation_token_add_on_cancel_handler(_z_cancellation_token_t* ct,
                                                       _z_cancellation_token_on_cancel_handler_t* handler,
                                                       size_t* handler_id);

z_result_t _z_cancellation_token_remove_on_cancel_handler(_z_cancellation_token_t* ct, size_t handler_id);
z_result_t _z_cancellation_token_get_notifier(_z_cancellation_token_t* ct, _z_sync_group_notifier_t* notifier);

_Z_REFCOUNT_DEFINE(_z_cancellation_token, _z_cancellation_token)

#endif
