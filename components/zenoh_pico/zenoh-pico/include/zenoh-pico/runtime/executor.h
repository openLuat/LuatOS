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

#ifndef ZENOH_PICO_RUNTIME_EXECUTOR_H
#define ZENOH_PICO_RUNTIME_EXECUTOR_H

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/atomic.h"
#include "zenoh-pico/collections/refcount.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum _z_fut_status_t {
    _Z_FUT_STATUS_RUNNING = 0,
    _Z_FUT_STATUS_READY = 1,
    _Z_FUT_STATUS_SLEEPING = 2,
    _Z_FUT_STATUS_SUSPENDED = 3,
} _z_fut_status_t;

typedef struct _z_fut_handle_t {
    size_t _id;
} _z_fut_handle_t;

static inline _z_fut_handle_t _z_fut_handle_null(void) {
    _z_fut_handle_t handle;
    handle._id = 0;
    return handle;
}

static inline bool _z_fut_handle_is_null(_z_fut_handle_t handle) { return handle._id == 0; }

typedef struct _z_fut_fn_result_t {
    _z_fut_status_t _status;
    z_clock_t _wake_up_time;
} _z_fut_fn_result_t;

static inline _z_fut_fn_result_t _z_fut_fn_result_ready(void) {
    _z_fut_fn_result_t result;
    result._status = _Z_FUT_STATUS_READY;
    return result;
}

static inline _z_fut_fn_result_t _z_fut_fn_result_continue(void) {
    _z_fut_fn_result_t result;
    result._status = _Z_FUT_STATUS_RUNNING;
    return result;
}

static inline _z_fut_fn_result_t _z_fut_fn_result_suspend(void) {
    _z_fut_fn_result_t result;
    result._status = _Z_FUT_STATUS_SUSPENDED;
    return result;
}

static inline _z_fut_fn_result_t _z_fut_fn_result_wake_up_after(unsigned long wake_up_time_ms) {
    _z_fut_fn_result_t result;
    result._status = _Z_FUT_STATUS_SLEEPING;
    result._wake_up_time = z_clock_now();
    z_clock_advance_ms(&result._wake_up_time, wake_up_time_ms);
    return result;
}

typedef struct _z_executor_t _z_executor_t;
typedef _z_fut_fn_result_t (*_z_fut_fn_t)(void *arg, _z_executor_t *executor);
typedef void (*_z_fut_destroy_fn_t)(void *arg);

typedef struct _z_fut_t {
    void *_fut_arg;
    _z_fut_fn_t _fut_fn;
    _z_fut_destroy_fn_t _destroy_fn;
} _z_fut_t;

static inline void _z_fut_destroy(_z_fut_t *fut) {
    if (fut->_destroy_fn != NULL) {
        fut->_destroy_fn(fut->_fut_arg);
    }
    fut->_fut_arg = NULL;
    fut->_fut_fn = NULL;
    fut->_destroy_fn = NULL;
}

static inline void _z_fut_move(_z_fut_t *dst, _z_fut_t *src) {
    dst->_fut_arg = src->_fut_arg;
    dst->_fut_fn = src->_fut_fn;
    dst->_destroy_fn = src->_destroy_fn;

    // Clear source
    src->_fut_arg = NULL;
    src->_fut_fn = NULL;
    src->_destroy_fn = NULL;
}

static inline _z_fut_t _z_fut_new(void *arg, _z_fut_fn_t fut_fn, _z_fut_destroy_fn_t destroy_fn) {
    _z_fut_t fut;
    fut._fut_arg = arg;
    fut._fut_fn = fut_fn;
    fut._destroy_fn = destroy_fn;
    return fut;
}

static inline _z_fut_t _z_fut_null(void) { return _z_fut_new(NULL, NULL, NULL); }

static inline bool _z_fut_is_null(const _z_fut_t *fut) { return fut->_fut_fn == NULL; }

// _z_fut_schedule_t packs status (bits [7:0]) and wake-up time in ms (bits [63:8]) into a single uint64_t.
// The wake-up time is only meaningful when status == _Z_FUT_STATUS_SLEEPING.
// This gives a maximum schedulable wake-up offset of 2^56 ms (~2.28 billion years) from the executor epoch.
typedef uint64_t _z_fut_schedule_t;

#define _Z_FUT_SCHEDULE_STATUS_MASK ((uint64_t)0xFFu)
#define _Z_FUT_SCHEDULE_TIME_SHIFT 8u

static inline _z_fut_status_t _z_fut_schedule_get_status(const _z_fut_schedule_t s) {
    return (_z_fut_status_t)(s & _Z_FUT_SCHEDULE_STATUS_MASK);
}
static inline uint64_t _z_fut_schedule_get_wake_up_time_ms(const _z_fut_schedule_t s) {
    return s >> _Z_FUT_SCHEDULE_TIME_SHIFT;
}

static inline _z_fut_schedule_t _z_fut_schedule_running(void) { return (uint64_t)_Z_FUT_STATUS_RUNNING; }
static inline _z_fut_schedule_t _z_fut_schedule_ready(void) { return (uint64_t)_Z_FUT_STATUS_READY; }
static inline _z_fut_schedule_t _z_fut_schedule_sleeping(uint64_t wake_up_time_ms) {
    return (uint64_t)_Z_FUT_STATUS_SLEEPING | (wake_up_time_ms << _Z_FUT_SCHEDULE_TIME_SHIFT);
}
static inline _z_fut_schedule_t _z_fut_schedule_suspended(void) { return (uint64_t)_Z_FUT_STATUS_SUSPENDED; }

typedef struct _z_fut_data_t {
    _z_fut_t _fut;
    _z_fut_schedule_t _schedule;
} _z_fut_data_t;

static inline void _z_fut_data_destroy(_z_fut_data_t *data) {
    _z_fut_destroy(&data->_fut);
    data->_schedule = _z_fut_schedule_ready();  // Reset status to ready after destroy
}

static inline void _z_fut_data_move(_z_fut_data_t *dst, _z_fut_data_t *src) {
    _z_fut_move(&dst->_fut, &src->_fut);
    dst->_schedule = src->_schedule;
    src->_schedule = _z_fut_schedule_ready();
}

static inline size_t _z_size_fut_data_hmap_hash(const size_t *key) { return *key; }

#ifndef _ZP_EXECUTOR_MAX_NUM_FUTURES
#define _ZP_EXECUTOR_MAX_NUM_FUTURES 64
#endif

#define _ZP_EXECUTOR_MAX_FUT_BUCKET_COUNT (_ZP_EXECUTOR_MAX_NUM_FUTURES * 3 / 2)  // 0.66 load factor

#define _ZP_HASHMAP_TEMPLATE_KEY_TYPE size_t
#define _ZP_HASHMAP_TEMPLATE_VAL_TYPE _z_fut_data_t
#define _ZP_HASHMAP_TEMPLATE_NAME _z_fut_data_hmap
#define _ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME _z_size_fut_data_hmap_hash
#define _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT _ZP_EXECUTOR_MAX_FUT_BUCKET_COUNT
#define _ZP_HASHMAP_TEMPLATE_CAPACITY _ZP_EXECUTOR_MAX_NUM_FUTURES
#define _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME _z_fut_data_destroy
#define _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME _z_fut_data_move
#include "zenoh-pico/collections/hashmap_template.h"

#define _ZP_DEQUE_TEMPLATE_ELEM_TYPE _z_fut_data_hmap_index_t
#define _ZP_DEQUE_TEMPLATE_NAME _z_fut_data_hmap_index_deque
#define _ZP_DEQUE_TEMPLATE_SIZE _ZP_EXECUTOR_MAX_NUM_FUTURES
#include "zenoh-pico/collections/deque_template.h"

// Compare two sleeping-task indices by their wake-up time stored in the hashmap.
// The context is a pointer to the task hashmap, which provides the wake-up times.
static inline int _z_sleeping_fut_idx_cmp(const _z_fut_data_hmap_index_t *a, const _z_fut_data_hmap_index_t *b,
                                          const _z_fut_data_hmap_t *tasks) {
    uint64_t ta =
        _z_fut_schedule_get_wake_up_time_ms(_z_fut_data_hmap_node_at((_z_fut_data_hmap_t *)tasks, *a)->val._schedule);
    uint64_t tb =
        _z_fut_schedule_get_wake_up_time_ms(_z_fut_data_hmap_node_at((_z_fut_data_hmap_t *)tasks, *b)->val._schedule);
    if (ta < tb) return -1;
    if (ta > tb) return 1;
    return 0;
}

#define _ZP_PQUEUE_TEMPLATE_ELEM_TYPE _z_fut_data_hmap_index_t
#define _ZP_PQUEUE_TEMPLATE_NAME _z_sleeping_fut_pqueue
#define _ZP_PQUEUE_TEMPLATE_CMP_CTX_TYPE _z_fut_data_hmap_t
#define _ZP_PQUEUE_TEMPLATE_ELEM_CMP_FN_NAME _z_sleeping_fut_idx_cmp
#define _ZP_PQUEUE_TEMPLATE_SIZE _ZP_EXECUTOR_MAX_NUM_FUTURES
#include "zenoh-pico/collections/pqueue_template.h"

typedef struct _z_executor_t {
    _z_fut_data_hmap_index_deque_t _ready_tasks;
    _z_sleeping_fut_pqueue_t _sleeping_tasks;
    _z_fut_data_hmap_t _tasks;
    z_clock_t _epoch;
    size_t _next_fut_id;
} _z_executor_t;

static inline void _z_executor_null(_z_executor_t *executor) {
    executor->_ready_tasks = _z_fut_data_hmap_index_deque_new();
    executor->_sleeping_tasks = _z_sleeping_fut_pqueue_new();
    executor->_tasks = _z_fut_data_hmap_new();
    executor->_next_fut_id = 0;
    // Set context after _tasks is initialised so the pointer is valid.
    _z_sleeping_fut_pqueue_set_ctx(&executor->_sleeping_tasks, &executor->_tasks);
}

static inline void _z_executor_init(_z_executor_t *executor) {
    _z_executor_null(executor);
    executor->_epoch = z_clock_now();
}

static inline _z_executor_t _z_executor_new(void) {
    _z_executor_t executor;
    _z_executor_init(&executor);
    return executor;
}

static inline void _z_executor_destroy(_z_executor_t *executor) {
    _z_fut_data_hmap_index_deque_destroy(&executor->_ready_tasks);
    _z_sleeping_fut_pqueue_destroy(&executor->_sleeping_tasks);
    _z_fut_data_hmap_destroy(&executor->_tasks);
}

// Spawn a new future to be executed.
// The executor takes the ownership of the future, and will destroy the future (by calling the destroy_fn) when the
// future is finished or cancelled. The caller can use the future handle to cancel the future or check its status.
_z_fut_handle_t _z_executor_spawn(_z_executor_t *executor, _z_fut_t *fut);

typedef enum _z_executor_spin_result_status_t {
    _Z_EXECUTOR_SPIN_RESULT_NO_TASKS,
    _Z_EXECUTOR_SPIN_RESULT_EXECUTED_TASK,
    _Z_EXECUTOR_SPIN_RESULT_SHOULD_WAIT,
    _Z_EXECUTOR_SPIN_RESULT_FAILED,
} _z_executor_spin_result_status_t;
typedef struct _z_executor_spin_result_t {
    _z_executor_spin_result_status_t status;
    z_clock_t next_wake_up_time;
} _z_executor_spin_result_t;

_z_executor_spin_result_t _z_executor_spin(_z_executor_t *executor);

_z_fut_status_t _z_executor_get_fut_status(const _z_executor_t *executor, const _z_fut_handle_t *handle);
bool _z_executor_cancel_fut(_z_executor_t *executor, const _z_fut_handle_t *handle);
bool _z_executor_resume_suspended_fut(_z_executor_t *executor, const _z_fut_handle_t *handle);

#ifdef __cplusplus
}
#endif

#endif
