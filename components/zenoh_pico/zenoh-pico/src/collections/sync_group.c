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

#include "zenoh-pico/collections/sync_group.h"

#include "assert.h"

static inline bool __unsafe_z_sync_group_has_no_alive_notifiers(const _z_sync_group_t* sync_group) {
    // NOTE: the function is unsafe because it requires sync_group_state mutex to be locked
    return _z_sync_group_state_rc_weak_count(&sync_group->_state) == 0;
}

z_result_t _z_sync_group_state_create(_z_sync_group_state_t* state) {
    state->is_closed = true;
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_init(&state->counter_mutex));
    _Z_CLEAN_RETURN_IF_ERR(_z_condvar_init(&state->counter_condvar), _z_mutex_drop(&state->counter_mutex));
#endif
    state->is_closed = false;
    return Z_OK;
}

void _z_sync_group_state_clear(_z_sync_group_state_t* state) {
    if (state != NULL) {
#if Z_FEATURE_MULTI_THREAD == 1
        _z_mutex_drop(&state->counter_mutex);
        _z_condvar_drop(&state->counter_condvar);
#endif
    }
}

z_result_t _z_sync_group_wait(_z_sync_group_t* sync_group) {
    if (_Z_RC_IS_NULL(&sync_group->_state)) {
        return _Z_ERR_NULL;
    }
    _z_sync_group_state_t* state = _Z_RC_IN_VAL(&sync_group->_state);
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_lock(&state->counter_mutex));
    while (!state->is_closed && !__unsafe_z_sync_group_has_no_alive_notifiers(sync_group)) {
        _Z_RETURN_IF_ERR(_z_condvar_wait(&state->counter_condvar, &state->counter_mutex));
    }
    z_result_t ret = _Z_RES_OK;
    if (state->is_closed) {
        ret = Z_SYNC_GROUP_CLOSED;
    } else {
        state->is_closed = true;
    }
    _z_mutex_unlock(&state->counter_mutex);
    return ret;
#else
    if (state->is_closed) {
        return Z_SYNC_GROUP_CLOSED;
    } else if (__unsafe_z_sync_group_has_no_alive_notifiers(sync_group)) {
        state->is_closed = true;
        return _Z_RES_OK;
    } else {
        return _Z_ERR_GENERIC;
    }
#endif
}

void _z_sync_group_close(_z_sync_group_t* sync_group) {
    if (_Z_RC_IS_NULL(&sync_group->_state)) {
        return;
    }
    _z_sync_group_state_t* state = _Z_RC_IN_VAL(&sync_group->_state);
#if Z_FEATURE_MULTI_THREAD == 1
    if (_z_mutex_lock(&state->counter_mutex) != _Z_RES_OK) {
        return;
    }
#endif
    state->is_closed = true;
#if Z_FEATURE_MULTI_THREAD == 1
    _z_condvar_signal_all(&state->counter_condvar);
    _z_mutex_unlock(&state->counter_mutex);
#endif
}

z_result_t _z_sync_group_wait_deadline(_z_sync_group_t* sync_group, const z_clock_t* deadline) {
    if (_Z_RC_IS_NULL(&sync_group->_state)) {
        return _Z_ERR_NULL;
    }
    _z_sync_group_state_t* state = _Z_RC_IN_VAL(&sync_group->_state);
#if Z_FEATURE_MULTI_THREAD == 1
    z_result_t ret = _Z_RES_OK;
    _Z_RETURN_IF_ERR(_z_mutex_lock(&state->counter_mutex));
    while (!state->is_closed && !__unsafe_z_sync_group_has_no_alive_notifiers(sync_group)) {
        ret = _z_condvar_wait_until(&state->counter_condvar, &state->counter_mutex, deadline);
        if (ret == Z_ETIMEDOUT) {
            break;
        } else if (ret != _Z_RES_OK) {
            return ret;
        }
    }
    if (state->is_closed) {
        ret = Z_SYNC_GROUP_CLOSED;
    } else if (ret == _Z_RES_OK) {
        state->is_closed = true;
    }
    _z_mutex_unlock(&state->counter_mutex);
    return ret;
#else
    _ZP_UNUSED(deadline);
    if (state->is_closed) {
        return Z_SYNC_GROUP_CLOSED;
    } else if (__unsafe_z_sync_group_has_no_alive_notifiers(sync_group)) {
        state->is_closed = true;
        return _Z_RES_OK;
    } else {
        return Z_ETIMEDOUT;
    }
#endif
}

z_result_t _z_sync_group_create(_z_sync_group_t* sync_group) {
    _z_sync_group_state_t* state = (_z_sync_group_state_t*)z_malloc(sizeof(_z_sync_group_state_t));
    if (state == NULL) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }

    _Z_CLEAN_RETURN_IF_ERR(_z_sync_group_state_create(state), z_free(state));
    sync_group->_state = _z_sync_group_state_rc_new(state);
    if (_Z_RC_IS_NULL(&sync_group->_state)) {
        _z_sync_group_state_clear(state);
        z_free(state);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    return _Z_RES_OK;
}

void _z_sync_group_drop(_z_sync_group_t* sync_group) { _z_sync_group_state_rc_drop(&sync_group->_state); }

z_result_t _z_sync_group_create_notifier(const _z_sync_group_t* sync_group, _z_sync_group_notifier_t* notifier) {
    if (_Z_RC_IS_NULL(&sync_group->_state)) {
        return _Z_ERR_NULL;
    }
    *notifier = _z_sync_group_notifier_null();
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_lock(&_Z_RC_IN_VAL(&sync_group->_state)->counter_mutex));
#endif
    if (_Z_RC_IN_VAL(&sync_group->_state)->is_closed) {
#if Z_FEATURE_MULTI_THREAD == 1
        _z_mutex_unlock(&_Z_RC_IN_VAL(&sync_group->_state)->counter_mutex);
#endif
        return Z_SYNC_GROUP_CLOSED;
    }
    notifier->_state = _z_sync_group_state_rc_clone_as_weak(&sync_group->_state);
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_unlock(&_Z_RC_IN_VAL(&sync_group->_state)->counter_mutex);
#endif
    return _Z_RC_IS_NULL(&notifier->_state) ? _Z_ERR_SYSTEM_OUT_OF_MEMORY : _Z_RES_OK;
}

void _z_sync_group_notifier_drop(_z_sync_group_notifier_t* notifier) {
    if (_Z_RC_IS_NULL(&notifier->_state)) {
        return;
    }
    _z_sync_group_state_rc_t state_rc = _z_sync_group_state_weak_upgrade(&notifier->_state);
    if (!_Z_RC_IS_NULL(&state_rc)) {
#if Z_FEATURE_MULTI_THREAD == 1
        if (_z_mutex_lock(&_Z_RC_IN_VAL(&state_rc)->counter_mutex) != _Z_RES_OK) {
            _z_sync_group_state_weak_drop(&notifier->_state);
            _z_sync_group_state_rc_drop(&state_rc);
            return;
        }
#endif
        _z_sync_group_state_weak_drop(&notifier->_state);
#if Z_FEATURE_MULTI_THREAD == 1
        _z_condvar_signal_all(&_Z_RC_IN_VAL(&state_rc)->counter_condvar);
        _z_mutex_unlock(&_Z_RC_IN_VAL(&state_rc)->counter_mutex);
#endif
        _z_sync_group_state_rc_drop(&state_rc);
    } else {
        _z_sync_group_state_weak_drop(&notifier->_state);
    }
}

bool _z_sync_group_is_closed(const _z_sync_group_t* sync_group) {
#if Z_FEATURE_MULTI_THREAD == 1
    if (_z_mutex_lock(&_Z_RC_IN_VAL(&sync_group->_state)->counter_mutex) != _Z_RES_OK) {
        return true;
    }
#endif
    bool ret = _Z_RC_IN_VAL(&sync_group->_state)->is_closed;
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_unlock(&_Z_RC_IN_VAL(&sync_group->_state)->counter_mutex);
#endif
    return ret;
}
