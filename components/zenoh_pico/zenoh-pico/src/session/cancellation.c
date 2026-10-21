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

#include "zenoh-pico/session/cancellation.h"

#include "zenoh-pico/session/liveliness.h"
#include "zenoh-pico/session/query.h"

static inline void _z_cancellation_handlers_storage_clear(_z_cancellation_handlers_storage_t *storage) {
    _z_cancellation_token_on_cancel_handler_intmap_clear(&storage->_handlers);
    _z_sync_group_notifier_drop(&storage->_cancel_sync_notifier);
}

static inline void _z_cancellation_handlers_storage_remove(_z_cancellation_handlers_storage_t *storage,
                                                           size_t handler_id) {
    _z_cancellation_token_on_cancel_handler_intmap_remove(&storage->_handlers, handler_id);
}

void _z_cancellation_token_clear_all_except_mutex(_z_cancellation_token_t *ct) {
    _z_cancellation_handlers_storage_clear(&ct->_handlers);
    _z_sync_group_drop(&ct->_sync_group);
}

z_result_t _z_cancellation_token_on_cancel_handler_call(_z_cancellation_token_on_cancel_handler_t *handler) {
    z_result_t ret = handler->_on_cancel != NULL ? handler->_on_cancel(handler->_arg) : _Z_RES_OK;
    _z_cancellation_token_on_cancel_handler_drop(handler);
    return ret;
}

static inline _z_cancellation_handlers_storage_t _z_cancellation_handlers_storage_null(void) {
    _z_cancellation_handlers_storage_t storage;
    _z_cancellation_token_on_cancel_handler_intmap_init(&storage._handlers);
    storage._next_handler_id = 0;
    storage._cancel_sync_notifier = _z_sync_group_notifier_null();
    return storage;
}

z_result_t _z_cancellation_handlers_storage_add(_z_cancellation_handlers_storage_t *storage,
                                                _z_cancellation_token_on_cancel_handler_t *handler,
                                                size_t *out_handler_id) {
    _z_cancellation_token_on_cancel_handler_t *handler_on_heap =
        (_z_cancellation_token_on_cancel_handler_t *)z_malloc(sizeof(_z_cancellation_token_on_cancel_handler_t));
    if (handler_on_heap == NULL) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    _z_cancellation_token_on_cancel_handler_t *ret = _z_cancellation_token_on_cancel_handler_intmap_insert(
        &storage->_handlers, storage->_next_handler_id, handler_on_heap);
    if (ret == NULL) {
        z_free(handler_on_heap);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    _z_cancellation_token_on_cancel_handler_move(ret, handler);
    *out_handler_id = storage->_next_handler_id++;
    return _Z_RES_OK;
}

void _z_cancellation_handlers_storage_cancel(_z_cancellation_handlers_storage_t *storage, z_result_t *ret) {
    *ret = _Z_RES_OK;
    _z_cancellation_token_on_cancel_handler_intmap_iterator_t it =
        _z_cancellation_token_on_cancel_handler_intmap_iterator_make(&storage->_handlers);
    while (*ret == _Z_RES_OK && _z_cancellation_token_on_cancel_handler_intmap_iterator_next(&it)) {
        _z_cancellation_token_on_cancel_handler_t *h =
            _z_cancellation_token_on_cancel_handler_intmap_iterator_value(&it);
        *ret = _z_cancellation_token_on_cancel_handler_call(h);
    }
    // drop sync handler in the end to ensure that all concurrent cancel calls return only once all work is done
    _z_cancellation_handlers_storage_clear(storage);
}

z_result_t _z_cancellation_token_drop_cancel_sync_notifier(void *arg) {
    _z_sync_group_notifier_t *n = (_z_sync_group_notifier_t *)arg;
    _z_sync_group_notifier_drop(n);
    return _Z_RES_OK;
}

z_result_t _z_cancellation_token_create(_z_cancellation_token_t *ct) {
    z_result_t ret = _Z_RES_OK;
    ct->_cancel_result = _Z_RES_OK;
    ct->_handlers = _z_cancellation_handlers_storage_null();
    ret = _z_sync_group_create(&ct->_sync_group);
    // add notifier to synchronize cancel operation
    _Z_SET_IF_OK(ret, _z_sync_group_create_notifier(&ct->_sync_group, &ct->_handlers._cancel_sync_notifier));
    _Z_CLEAN_RETURN_IF_ERR(ret, _z_cancellation_token_clear_all_except_mutex(ct));
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_CLEAN_RETURN_IF_ERR(_z_mutex_init(&ct->_mutex), _z_sync_group_drop(&ct->_sync_group);
                           _z_cancellation_token_clear_all_except_mutex(ct));
#endif
    return _Z_RES_OK;
}

static inline z_result_t _z_cancellation_token_lock(const _z_cancellation_token_t *ct) {
#if Z_FEATURE_MULTI_THREAD == 1
    return _z_mutex_lock((_z_mutex_t *)&ct->_mutex);
#else
    _ZP_UNUSED(ct);
    return _Z_RES_OK;
#endif
}

static inline z_result_t _z_cancellation_token_unlock(const _z_cancellation_token_t *ct) {
#if Z_FEATURE_MULTI_THREAD == 1
    return _z_mutex_unlock((_z_mutex_t *)&ct->_mutex);
#else
    _ZP_UNUSED(ct);
    return _Z_RES_OK;
#endif
}

static inline bool _z_unsafe_cancellation_token_has_started_cancel(const _z_cancellation_token_t *ct) {
    return !_z_sync_group_notifier_check(&ct->_handlers._cancel_sync_notifier);
}

bool _z_cancellation_token_is_cancelled(const _z_cancellation_token_t *ct) {
    return _z_sync_group_is_closed(&ct->_sync_group);
}

z_result_t _z_cancellation_token_call_handlers(_z_cancellation_token_t *ct) {
    bool set_cancel_result = false;
    if (_z_cancellation_token_lock(ct) != _Z_RES_OK) {
        return _Z_ERR_SYSTEM_GENERIC;
    }
    set_cancel_result = _z_sync_group_notifier_check(&ct->_handlers._cancel_sync_notifier);
    _z_cancellation_handlers_storage_t s = ct->_handlers;
    ct->_handlers = _z_cancellation_handlers_storage_null();
    _z_cancellation_token_unlock(ct);
    if (set_cancel_result) {
        _z_cancellation_handlers_storage_cancel(&s, &ct->_cancel_result);
        if (ct->_cancel_result != _Z_RES_OK) {
            _z_sync_group_close(&ct->_sync_group);
        }
    }
    return _Z_RES_OK;
}

z_result_t _z_cancellation_token_cancel(_z_cancellation_token_t *ct) {
    _Z_RETURN_IF_ERR(_z_cancellation_token_call_handlers(ct));
    _z_sync_group_wait(&ct->_sync_group);
    return ct->_cancel_result;
}

z_result_t _z_cancellation_token_cancel_with_timeout(_z_cancellation_token_t *ct, uint32_t timeout_ms) {
    z_clock_t deadline = z_clock_now();
    z_clock_advance_ms(&deadline, timeout_ms);

    _Z_RETURN_IF_ERR(_z_cancellation_token_call_handlers(ct));
    if (_z_sync_group_wait_deadline(&ct->_sync_group, &deadline) == Z_ETIMEDOUT) {
        return Z_ETIMEDOUT;
    } else {
        return ct->_cancel_result;
    }
}

void _z_cancellation_token_clear(_z_cancellation_token_t *ct) {
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_drop(&ct->_mutex);
#endif
    _z_cancellation_token_clear_all_except_mutex(ct);
}

z_result_t _z_cancellation_token_add_on_cancel_handler(_z_cancellation_token_t *ct,
                                                       _z_cancellation_token_on_cancel_handler_t *handler,
                                                       size_t *out_handler_id) {
    _Z_RETURN_IF_ERR(_z_cancellation_token_lock(ct));
    z_result_t ret = _z_unsafe_cancellation_token_has_started_cancel(ct)
                         ? Z_ERR_CANCELLED
                         : _z_cancellation_handlers_storage_add(&ct->_handlers, handler, out_handler_id);
    _z_cancellation_token_unlock(ct);
    return ret;
}

z_result_t _z_cancellation_token_remove_on_cancel_handler(_z_cancellation_token_t *ct, size_t handler_id) {
    _Z_RETURN_IF_ERR(_z_cancellation_token_lock(ct));
    _z_cancellation_handlers_storage_remove(&ct->_handlers, handler_id);
    _z_cancellation_token_unlock(ct);
    return _Z_RES_OK;
}

z_result_t _z_cancellation_token_get_notifier(_z_cancellation_token_t *ct, _z_sync_group_notifier_t *notifier) {
    z_result_t ret = _z_sync_group_create_notifier(&ct->_sync_group, notifier);
    return ret == Z_SYNC_GROUP_CLOSED ? Z_ERR_CANCELLED : ret;
}
