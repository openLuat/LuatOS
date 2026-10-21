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

#include "zenoh-pico/runtime/executor.h"

_z_fut_handle_t _z_executor_spawn(_z_executor_t *executor, _z_fut_t *fut) {
    _z_fut_data_t fut_data;
    _z_fut_move(&fut_data._fut, fut);
    fut_data._schedule = _z_fut_schedule_running();
    if (executor->_next_fut_id == 0) {
        executor->_next_fut_id++;  // Skip 0 since it's reserved for null handle
    }
    _z_fut_data_hmap_index_t idx = _z_fut_data_hmap_insert(&executor->_tasks, &executor->_next_fut_id, &fut_data);
    _z_fut_handle_t handle = _z_fut_handle_null();
    if (!_z_fut_data_hmap_index_valid(idx)) {
        return handle;
    }
    handle._id = executor->_next_fut_id;
    executor->_next_fut_id++;
    // can't fail since we have enough capacity for all tasks in the hashmap
    _z_fut_data_hmap_index_deque_push_back(&executor->_ready_tasks, &idx);
    return handle;
}

_z_executor_spin_result_t _z_executor_get_next_fut(_z_executor_t *executor, _z_fut_data_hmap_index_t *task_idx) {
    _z_executor_spin_result_t result;
    result.status = _Z_EXECUTOR_SPIN_RESULT_NO_TASKS;
    _z_fut_data_hmap_index_t *sleeping_idx_ptr = _z_sleeping_fut_pqueue_peek(&executor->_sleeping_tasks);
    if (sleeping_idx_ptr != NULL) {
        z_clock_t now = z_clock_now();
        uint64_t wake_up_time_ms = _z_fut_schedule_get_wake_up_time_ms(
            _z_fut_data_hmap_node_at(&executor->_tasks, *sleeping_idx_ptr)->val._schedule);
        z_clock_t wake_up_time = executor->_epoch;
        z_clock_advance_ms(&wake_up_time, (unsigned long)wake_up_time_ms);
        if (zp_clock_elapsed_ms_since(&now, &wake_up_time) > 0) {
            // The sleeping task is ready to execute
            _z_fut_data_hmap_index_t sleeping_idx;
            _z_sleeping_fut_pqueue_pop(&executor->_sleeping_tasks, &sleeping_idx);
            if (_z_fut_data_hmap_index_deque_pop_front(&executor->_ready_tasks, task_idx)) {
                // We have a non-sleeping task to execute, we should re-enqueue the ready sleeping task as non-sleeping
                // one and execute the non-sleeping task first.
                _z_fut_data_hmap_index_deque_push_back(&executor->_ready_tasks, &sleeping_idx);
                // Mark the sleeping task as ready since it's now
                // re-enqueued to the ready task queue and can be executed.
                _z_fut_data_hmap_node_at(&executor->_tasks, sleeping_idx)->val._schedule = _z_fut_schedule_ready();
            } else {
                // No non-sleeping task, execute the ready sleeping task directly.
                *task_idx = sleeping_idx;
            }
            result.status = _Z_EXECUTOR_SPIN_RESULT_EXECUTED_TASK;
        } else if (_z_fut_data_hmap_index_deque_pop_front(&executor->_ready_tasks, task_idx)) {
            // We have a non-sleeping task to execute
            result.status = _Z_EXECUTOR_SPIN_RESULT_EXECUTED_TASK;
        } else {
            // No non-sleeping task, we should wait for the sleeping task to be ready.
            result.status = _Z_EXECUTOR_SPIN_RESULT_SHOULD_WAIT;
            result.next_wake_up_time = wake_up_time;
        }
    } else if (_z_fut_data_hmap_index_deque_pop_front(&executor->_ready_tasks, task_idx)) {
        // We have a non-sleeping task to execute
        result.status = _Z_EXECUTOR_SPIN_RESULT_EXECUTED_TASK;
    }
    return result;
}

_z_executor_spin_result_t _z_executor_spin(_z_executor_t *executor) {
    _z_fut_data_hmap_index_t fut_idx;
    _z_fut_data_t *fut_data = NULL;
    _z_executor_spin_result_t result;
    // Set context before spinning to make sure the sleeping task queue can access the task pool to compare the wake-up
    // time, in case executor was moved.
    _z_sleeping_fut_pqueue_set_ctx(&executor->_sleeping_tasks, &executor->_tasks);
    while (true) {  // Loop until we find non-null task to execute
        result = _z_executor_get_next_fut(executor, &fut_idx);
        if (result.status == _Z_EXECUTOR_SPIN_RESULT_NO_TASKS ||
            result.status == _Z_EXECUTOR_SPIN_RESULT_SHOULD_WAIT) {  // No tasks to execute
            return result;
        }
        fut_data = &_z_fut_data_hmap_node_at(&executor->_tasks, fut_idx)->val;
        if (fut_data->_fut._fut_fn == NULL) {  // idle task, just skip it and check the next task.
            _z_fut_data_hmap_remove_at(&executor->_tasks, fut_idx, NULL);  // Remove the idle task from the task pool
            continue;
        } else if (_z_fut_schedule_get_status(fut_data->_schedule) != _Z_FUT_STATUS_SUSPENDED) {
            break;
        }
    }

    _z_fut_fn_result_t fn_result = fut_data->_fut._fut_fn(fut_data->_fut._fut_arg, executor);
    if (fn_result._status == _Z_FUT_STATUS_RUNNING) {
        // The task is still running, we should re-enqueue it to the executor.
        fut_data->_schedule = _z_fut_schedule_running();
        // can't fail since we have enough capacity for all tasks in the hashmap
        _z_fut_data_hmap_index_deque_push_back(&executor->_ready_tasks, &fut_idx);
    } else if (fn_result._status == _Z_FUT_STATUS_SLEEPING) {
        // The task is sleeping, we should move it to the sleeping task queue with the wake-up time.
        fut_data->_schedule =
            _z_fut_schedule_sleeping((uint64_t)zp_clock_elapsed_ms_since(&fn_result._wake_up_time, &executor->_epoch));
        // can't fail since we have enough capacity for all tasks in the hashmap
        _z_sleeping_fut_pqueue_push(&executor->_sleeping_tasks, &fut_idx);
    } else if (fn_result._status == _Z_FUT_STATUS_READY) {
        // The task is ready, we should destroy it to free the resource.
        _z_fut_data_hmap_remove_at(&executor->_tasks, fut_idx, NULL);
    } else if (fn_result._status == _Z_FUT_STATUS_SUSPENDED) {
        // The task is suspended, we should keep it in the task pool with the suspended status, and it will be skipped
        // in the next spin until it's resumed by external events.
        fut_data->_schedule = _z_fut_schedule_suspended();
    }
    return result;
}

_z_fut_status_t _z_executor_get_fut_status(const _z_executor_t *executor, const _z_fut_handle_t *handle) {
    if (_z_fut_handle_is_null(*handle)) {
        return _Z_FUT_STATUS_READY;  // Invalid handle is considered as ready (i.e., not running or sleeping)
    }
    _z_fut_data_t *fut_data = _z_fut_data_hmap_get((_z_fut_data_hmap_t *)&executor->_tasks, &handle->_id);
    if (fut_data == NULL) {
        return _Z_FUT_STATUS_READY;  // If the task is not found in the task pool, it means it's already completed and
                                     // removed, we consider it as ready (i.e., not running or sleeping)
    }
    return _z_fut_schedule_get_status(fut_data->_schedule);
}

bool _z_executor_cancel_fut(_z_executor_t *executor, const _z_fut_handle_t *handle) {
    if (_z_fut_handle_is_null(*handle)) {
        return false;
    }
    _z_fut_data_t *fut = _z_fut_data_hmap_get(&executor->_tasks, &handle->_id);
    if (fut == NULL) {
        return false;
    }
    // We leave the cancelled task in the NULL state, to let executor remove it while spinning,
    // since we don't want to break the sleeping/ready task queue order by removing the cancelled task immediately.
    _z_fut_data_destroy(fut);

    return true;
}

bool _z_executor_resume_suspended_fut(_z_executor_t *executor, const _z_fut_handle_t *handle) {
    if (_z_fut_handle_is_null(*handle)) {
        return false;
    }
    _z_fut_data_hmap_index_t fut_idx = _z_fut_data_hmap_get_idx(&executor->_tasks, &handle->_id);
    if (!_z_fut_data_hmap_index_valid(fut_idx)) {
        return false;
    }
    _z_fut_data_t *fut = &_z_fut_data_hmap_node_at(&executor->_tasks, fut_idx)->val;
    if (_z_fut_schedule_get_status(fut->_schedule) != _Z_FUT_STATUS_SUSPENDED) {
        return false;
    }
    // Mark the suspended task as ready, and re-enqueue it to the ready task queue.
    fut->_schedule = _z_fut_schedule_ready();
    // can't fail since we have enough capacity for all tasks in the hashmap
    _z_fut_data_hmap_index_deque_push_back(&executor->_ready_tasks, &fut_idx);

    return true;
}
