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

#ifndef ZENOH_PICO_COLLECTIONS_BACKGROUND_EXECUTOR_H
#define ZENOH_PICO_COLLECTIONS_BACKGROUND_EXECUTOR_H

#include "zenoh-pico/config.h"
#if Z_FEATURE_MULTI_THREAD == 1
#include <stddef.h>

#include "zenoh-pico/collections/refcount.h"
#include "zenoh-pico/runtime/executor.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _z_background_executor_inner_t _z_background_executor_inner_t;
void _z_background_executor_inner_clear(_z_background_executor_inner_t *be);

_Z_REFCOUNT_DEFINE_NO_FROM_VAL(_z_background_executor_inner, _z_background_executor_inner)

typedef struct _z_background_executor_t {
    _z_background_executor_inner_rc_t _inner;
} _z_background_executor_t;

z_result_t _z_background_executor_init(_z_background_executor_t *be, z_task_attr_t *task_attr);
// Initializes the executor without spawning a background thread.
// Tasks can be added via _z_background_executor_spawn but won't be executed until
// _z_background_executor_start is called.
z_result_t _z_background_executor_init_deferred(_z_background_executor_t *be);
// Spawns a background thread to run an executor that was previously created with _z_background_executor_init_deferred.
// Returns _Z_RES_OK in case of success or if the executor is already running, non-zero value otherwise.
z_result_t _z_background_executor_start(_z_background_executor_t *be, z_task_attr_t *task_attr);
// Stops the background executor thread without destroying the executor.
// Pending tasks are preserved and can be executed after restarting with _z_background_executor_start.
// Returns _Z_RES_OK in case of success or if the executor was already stopped, non-zero value otherwise.
z_result_t _z_background_executor_stop(_z_background_executor_t *be);
static inline void _z_background_executor_null(_z_background_executor_t *be) {
    be->_inner = _z_background_executor_inner_rc_null();
}
// Spawns a future to be executed in the background.
// The caller can optionally receive a handle to the future, which can be used to check the future's status or cancel
// it. If the caller does not care about the future's status, they can pass NULL as opt_handle_out.
z_result_t _z_background_executor_spawn(_z_background_executor_t *be, _z_fut_t *fut, _z_fut_handle_t *opt_handle_out);
z_result_t _z_background_executor_suspend(_z_background_executor_t *be);
z_result_t _z_background_executor_resume(_z_background_executor_t *be);
void _z_background_executor_destroy(_z_background_executor_t *be);
z_result_t _z_background_executor_get_fut_status(_z_background_executor_t *be, const _z_fut_handle_t *handle,
                                                 _z_fut_status_t *status_out);
z_result_t _z_background_executor_cancel_fut(_z_background_executor_t *be, const _z_fut_handle_t *handle);
z_result_t _z_background_executor_clone(_z_background_executor_t *dst, const _z_background_executor_t *src);
bool _z_background_executor_is_running(const _z_background_executor_t *be);
#ifdef __cplusplus
}
#endif
#endif /* Z_FEATURE_MULTI_THREAD */

#endif
