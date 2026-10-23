#include "zenoh-pico/runtime/background_executor.h"

#if Z_FEATURE_MULTI_THREAD == 1
typedef struct _z_background_executor_inner_t {
    _z_executor_t _executor;
    _z_mutex_t _mutex;
    _z_condvar_t _condvar;
    _z_atomic_size_t _waiters;
    size_t _thread_idx;
    _z_atomic_bool_t _started;
    _z_atomic_size_t _thread_checkers;
    _z_task_t _task;
} _z_background_executor_inner_t;

static inline bool _is_called_from_executor(_z_background_executor_inner_t *be) {
    bool res = false;
    _z_atomic_size_fetch_add(&be->_thread_checkers, 1, _z_memory_order_acq_rel);
    if (_z_atomic_bool_load(&be->_started, _z_memory_order_acquire)) {  // only check task id if executor is started
        _z_task_id_t current_task_id = _z_task_current_id();
        _z_task_id_t executor_task_id = _z_task_get_id(&be->_task);
        res = _z_task_id_equal(&current_task_id, &executor_task_id);
    }
    _z_atomic_size_fetch_sub(&be->_thread_checkers, 1, _z_memory_order_acq_rel);
    return res;
}

z_result_t _z_background_executor_inner_suspend_and_lock(_z_background_executor_inner_t *be,
                                                         bool check_executor_thread) {
    if (check_executor_thread && _is_called_from_executor(be)) {
        return _Z_ERR_INVALID;  // suspend cannot be called from executor thread
    }
    _z_atomic_size_fetch_add(&be->_waiters, 1, _z_memory_order_acq_rel);
    return _z_mutex_lock(&be->_mutex);
}

z_result_t _z_background_executor_inner_suspend(_z_background_executor_inner_t *be) {
    _Z_RETURN_IF_ERR(_z_background_executor_inner_suspend_and_lock(be, true));
    return _z_mutex_unlock(&be->_mutex);
}

z_result_t _z_background_executor_inner_unlock_and_resume(_z_background_executor_inner_t *be) {
    _z_atomic_size_fetch_sub(&be->_waiters, 1, _z_memory_order_acq_rel);
    _Z_CLEAN_RETURN_IF_ERR(_z_condvar_signal_all(&be->_condvar), _z_mutex_unlock(&be->_mutex));
    return _z_mutex_unlock(&be->_mutex);
}

z_result_t _z_background_executor_inner_resume(_z_background_executor_inner_t *be) {
    if (_is_called_from_executor(be)) {
        return _Z_ERR_INVALID;  // resume cannot be called from executor thread
    }
    _Z_RETURN_IF_ERR(_z_mutex_lock(&be->_mutex));
    return _z_background_executor_inner_unlock_and_resume(be);
}

z_result_t _z_background_executor_inner_run_forever(_z_background_executor_inner_t *be, size_t thread_idx) {
    _Z_RETURN_IF_ERR(_z_mutex_lock(&be->_mutex));
    while (true) {
        while (_z_atomic_size_load(&be->_waiters, _z_memory_order_acquire) > 0) {
            if (thread_idx <
                be->_thread_idx) {  // extra check to allow to stop executor thread even if there are waiters
                break;              // stop requested, exit the loop and end the thread
            }
            // if there are waiters, sleep until they are resumed
            _Z_CLEAN_RETURN_IF_ERR(_z_condvar_wait(&be->_condvar, &be->_mutex), _z_mutex_unlock(&be->_mutex));
        }
        if (thread_idx < be->_thread_idx) {
            break;  // stop requested, exit the loop and end the thread
        }
        _z_executor_spin_result_t res = _z_executor_spin(&be->_executor);
        if (res.status == _Z_EXECUTOR_SPIN_RESULT_NO_TASKS) {  // no pending tasks, sleep until next task is added
            _Z_CLEAN_RETURN_IF_ERR(_z_condvar_wait(&be->_condvar, &be->_mutex), _z_mutex_unlock(&be->_mutex));
        } else if (res.status == _Z_EXECUTOR_SPIN_RESULT_SHOULD_WAIT) {  // we have pending timed tasks but they are not
                                                                         // ready yet, sleep until the next one is ready
            z_clock_t now = z_clock_now();
            if (zp_clock_elapsed_ms_since(&res.next_wake_up_time, &now) > 1) {  // sleep until next task is ready
                z_result_t wait_result = _z_condvar_wait_until(&be->_condvar, &be->_mutex, &res.next_wake_up_time);
                if (wait_result != Z_ETIMEDOUT && wait_result != _Z_RES_OK) {
                    return _z_mutex_unlock(&be->_mutex);
                }
            }
        }
    }
    return _z_mutex_unlock(&be->_mutex);
}

z_result_t _z_background_executor_inner_spawn(_z_background_executor_inner_t *be, _z_fut_t *fut,
                                              _z_fut_handle_t *handle) {
    z_result_t ret = _Z_RES_OK;
    if (_is_called_from_executor(be)) {
        *handle = _z_executor_spawn(&be->_executor, fut);
    } else {
        _Z_RETURN_IF_ERR(_z_background_executor_inner_suspend_and_lock(be, false));
        *handle = _z_executor_spawn(&be->_executor, fut);
        ret = _z_background_executor_inner_unlock_and_resume(be);
    }
    return _z_fut_handle_is_null(*handle) ? _Z_ERR_SYSTEM_OUT_OF_MEMORY : ret;
}

z_result_t _z_background_executor_inner_get_fut_status(_z_background_executor_inner_t *be,
                                                       const _z_fut_handle_t *handle, _z_fut_status_t *status_out) {
    if (_is_called_from_executor(be)) {
        *status_out = _z_executor_get_fut_status(&be->_executor, handle);
        return _Z_RES_OK;
    } else {
        _Z_RETURN_IF_ERR(_z_background_executor_inner_suspend_and_lock(be, false));
        *status_out = _z_executor_get_fut_status(&be->_executor, handle);
        return _z_background_executor_inner_unlock_and_resume(be);
    }
}

z_result_t _z_background_executor_inner_cancel_fut(_z_background_executor_inner_t *be, const _z_fut_handle_t *handle) {
    if (_is_called_from_executor(be)) {
        return _z_executor_cancel_fut(&be->_executor, handle) ? _Z_RES_OK : _Z_ERR_INVALID;
    } else {
        _Z_RETURN_IF_ERR(_z_background_executor_inner_suspend_and_lock(be, false));
        _z_executor_cancel_fut(&be->_executor, handle);
        return _z_background_executor_inner_unlock_and_resume(be);
    }
}

z_result_t _z_background_executor_inner_stop(_z_background_executor_inner_t *be) {
    _Z_RETURN_IF_ERR(_z_background_executor_inner_suspend_and_lock(be, true));
    // executor is now suspended, so no API can be called from its thread
    // in addition we are holding the mutex, so no other thread can request to stop or start the executor
    if (!_z_atomic_bool_load(&be->_started, _z_memory_order_acquire)) {
        return _z_background_executor_inner_unlock_and_resume(be);
    }
    while (_z_atomic_size_load(&be->_thread_checkers, _z_memory_order_acquire) > 0) {
        z_sleep_us(10);
    }
    be->_thread_idx++;
    _z_atomic_bool_store(&be->_started, false, _z_memory_order_release);
    _z_task_t task_to_join = be->_task;
    z_result_t ret = _z_background_executor_inner_unlock_and_resume(be);
    // after resume the executor thread will proceed to stop directly without trying to execute any tasks
    _Z_SET_IF_OK(ret, _z_task_join(&task_to_join));
    return ret;
}

void _z_background_executor_inner_clear(_z_background_executor_inner_t *be) {
    _z_background_executor_inner_stop(be);
    _z_executor_destroy(&be->_executor);
    _z_condvar_drop(&be->_condvar);
    _z_mutex_drop(&be->_mutex);
}

void *_z_background_executor_inner_task_fn(void *arg) {
    _z_background_executor_inner_t *be = (_z_background_executor_inner_t *)arg;
    size_t thread_idx = be->_thread_idx;  // this is safe since _z_background_executor_inner_start holds the mutex until
                                          // be->_started is set to true.
    _z_atomic_bool_store(&be->_started, true, _z_memory_order_release);
    _z_background_executor_inner_run_forever(be, thread_idx);
    return NULL;
}

z_result_t _z_background_executor_inner_init_deferred(_z_background_executor_inner_t *be) {
    _Z_RETURN_IF_ERR(_z_mutex_init(&be->_mutex));
    _Z_CLEAN_RETURN_IF_ERR(_z_condvar_init(&be->_condvar), _z_mutex_drop(&be->_mutex));
    _z_executor_init(&be->_executor);
    _z_atomic_size_init(&be->_waiters, 0);
    _z_atomic_size_init(&be->_thread_checkers, 0);
    be->_thread_idx = 0;
    _z_atomic_bool_init(&be->_started, false);
    return _Z_RES_OK;
}

z_result_t _z_background_executor_inner_start(_z_background_executor_inner_t *be, z_task_attr_t *task_attr) {
    _Z_RETURN_IF_ERR(_z_background_executor_inner_suspend_and_lock(be, true));
    if (_z_atomic_bool_load(&be->_started, _z_memory_order_acquire)) {
        // already started, just return
        return _z_background_executor_inner_unlock_and_resume(be);
    }
    z_result_t ret = _z_task_init(&be->_task, task_attr, _z_background_executor_inner_task_fn, be);
    if (ret == _Z_RES_OK) {
        while (!_z_atomic_bool_load(&be->_started, _z_memory_order_acquire)) {
            z_sleep_us(10);  // wait until the executor thread sets the state to started
        }
    }
    // resume the executor thread to let it proceed to run
    z_result_t ret2 = _z_background_executor_inner_unlock_and_resume(be);
    _Z_SET_IF_OK(ret, ret2);
    return ret;
}

z_result_t _z_background_executor_init_deferred(_z_background_executor_t *be) {
    be->_inner = _z_background_executor_inner_rc_null();
    _z_background_executor_inner_t *inner =
        (_z_background_executor_inner_t *)z_malloc(sizeof(_z_background_executor_inner_t));
    if (!inner) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    if (_z_background_executor_inner_init_deferred(inner) != _Z_RES_OK) {
        z_free(inner);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    be->_inner = _z_background_executor_inner_rc_new(inner);
    if (_Z_RC_IS_NULL(&be->_inner)) {
        _z_background_executor_inner_clear(inner);
        z_free(inner);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    return _Z_RES_OK;
}

z_result_t _z_background_executor_start(_z_background_executor_t *be, z_task_attr_t *task_attr) {
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return _Z_ERR_INVALID;
    }
    return _z_background_executor_inner_start(_Z_RC_IN_VAL(&be->_inner), task_attr);
}

z_result_t _z_background_executor_stop(_z_background_executor_t *be) {
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return _Z_ERR_INVALID;
    }
    return _z_background_executor_inner_stop(_Z_RC_IN_VAL(&be->_inner));
}

z_result_t _z_background_executor_init(_z_background_executor_t *be, z_task_attr_t *task_attr) {
    _Z_RETURN_IF_ERR(_z_background_executor_init_deferred(be));
    _Z_CLEAN_RETURN_IF_ERR(_z_background_executor_start(be, task_attr), _z_background_executor_destroy(be));
    return _Z_RES_OK;
}

z_result_t _z_background_executor_spawn(_z_background_executor_t *be, _z_fut_t *fut, _z_fut_handle_t *handle_out) {
    _z_fut_handle_t dummy_handle;
    if (handle_out == NULL) {
        handle_out = &dummy_handle;
    }
    *handle_out = _z_fut_handle_null();
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return _Z_ERR_INVALID;
    }
    return _z_background_executor_inner_spawn(_Z_RC_IN_VAL(&be->_inner), fut, handle_out);
}

z_result_t _z_background_executor_suspend(_z_background_executor_t *be) {
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return _Z_ERR_INVALID;
    }
    return _z_background_executor_inner_suspend(_Z_RC_IN_VAL(&be->_inner));
}

z_result_t _z_background_executor_resume(_z_background_executor_t *be) {
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return _Z_ERR_INVALID;
    }
    return _z_background_executor_inner_resume(_Z_RC_IN_VAL(&be->_inner));
}

void _z_background_executor_destroy(_z_background_executor_t *be) { _z_background_executor_inner_rc_drop(&be->_inner); }

z_result_t _z_background_executor_get_fut_status(_z_background_executor_t *be, const _z_fut_handle_t *handle,
                                                 _z_fut_status_t *status_out) {
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return _Z_ERR_INVALID;
    }
    return _z_background_executor_inner_get_fut_status(_Z_RC_IN_VAL(&be->_inner), handle, status_out);
}

z_result_t _z_background_executor_cancel_fut(_z_background_executor_t *be, const _z_fut_handle_t *handle) {
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return _Z_ERR_INVALID;
    }
    return _z_background_executor_inner_cancel_fut(_Z_RC_IN_VAL(&be->_inner), handle);
}

z_result_t _z_background_executor_clone(_z_background_executor_t *dst, const _z_background_executor_t *src) {
    if (_Z_RC_IS_NULL(&src->_inner)) {
        dst->_inner = _z_background_executor_inner_rc_null();
        return _Z_RES_OK;
    }
    dst->_inner = _z_background_executor_inner_rc_clone(&src->_inner);
    if (_Z_RC_IS_NULL(&dst->_inner)) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    return _Z_RES_OK;
}

bool _z_background_executor_is_running(const _z_background_executor_t *be) {
    if (_Z_RC_IS_NULL(&be->_inner)) {
        return false;
    }
    return _z_atomic_bool_load(&_Z_RC_IN_VAL(&be->_inner)->_started, _z_memory_order_acquire);
}
#else
// to prevent "empty compilation unit" warning when multi-threading is disabled
typedef int _z_background_executor_inner_t;
#endif
