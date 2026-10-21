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

#ifndef ZENOH_PICO_RUNTIME_RUNTIME_H
#define ZENOH_PICO_RUNTIME_RUNTIME_H

#include "zenoh-pico/config.h"

#define _ZP_EXECUTOR_MAX_NUM_FUTURES Z_RUNTIME_MAX_TASKS
#if Z_FEATURE_MULTI_THREAD == 1
#include "zenoh-pico/runtime/background_executor.h"
#else
#include "zenoh-pico/runtime/executor.h"
#endif
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_MULTI_THREAD == 1
typedef _z_background_executor_t _z_runtime_t;
static inline _z_fut_handle_t _z_runtime_spawn(_z_runtime_t *runtime, _z_fut_t *fut) {
    _z_fut_handle_t handle;
    _z_background_executor_spawn(runtime, fut, &handle);
    return handle;
}
static inline z_result_t _z_runtime_cancel_fut(_z_runtime_t *runtime, _z_fut_handle_t *handle) {
    return _z_background_executor_cancel_fut(runtime, handle);
}
static inline z_result_t _z_runtime_init(_z_runtime_t *runtime) {
    return _z_background_executor_init_deferred(runtime);
}
static inline void _z_runtime_clear(_z_runtime_t *runtime) { _z_background_executor_destroy(runtime); }
static inline void _z_runtime_null(_z_runtime_t *runtime) { _z_background_executor_null(runtime); }
static inline z_result_t _z_runtime_start(_z_runtime_t *runtime, z_task_attr_t *task_attr) {
    return _z_background_executor_start(runtime, task_attr);
}

static inline z_result_t _z_runtime_stop(_z_runtime_t *runtime) { return _z_background_executor_stop(runtime); }
#else
typedef _z_executor_t _z_runtime_t;
static inline _z_fut_handle_t _z_runtime_spawn(_z_runtime_t *runtime, _z_fut_t *fut) {
    return _z_executor_spawn(runtime, fut);
}
static inline z_result_t _z_runtime_init(_z_runtime_t *runtime) {
    _z_executor_init(runtime);
    return _Z_RES_OK;
}
static inline void _z_runtime_clear(_z_runtime_t *runtime) { _z_executor_destroy(runtime); }
static inline void _z_runtime_null(_z_runtime_t *runtime) { _z_executor_null(runtime); }
static inline z_result_t _z_runtime_cancel_fut(_z_runtime_t *runtime, _z_fut_handle_t *handle) {
    _z_executor_cancel_fut(runtime, handle);
    return _Z_RES_OK;
}
static inline void _z_runtime_spin_once(_z_runtime_t *runtime) { _z_executor_spin(runtime); }

static inline z_result_t _z_runtime_stop(_z_runtime_t *runtime) {
    _ZP_UNUSED(runtime);
    return _Z_RES_OK;
}
#endif

#ifdef __cplusplus
}  // extern "C"
#endif

#endif
