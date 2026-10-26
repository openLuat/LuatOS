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

#ifndef ZENOH_PICO_UTILS_MUTEX_H
#define ZENOH_PICO_UTILS_MUTEX_H

#include "zenoh-pico/config.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_MULTI_THREAD == 1
static inline z_result_t _z_mutex_rec_mt_lock(_z_mutex_rec_t *m) { return _z_mutex_rec_lock(m); }
static inline z_result_t _z_mutex_rec_mt_unlock(_z_mutex_rec_t *m) { return _z_mutex_rec_unlock(m); }
#else
static inline z_result_t _z_mutex_rec_mt_lock(_z_mutex_rec_t *m) {
    _ZP_UNUSED(m);
    return _Z_RES_OK;
}
static inline z_result_t _z_mutex_rec_mt_unlock(_z_mutex_rec_t *m) {
    _ZP_UNUSED(m);
    return _Z_RES_OK;
}
#endif

#ifdef __cplusplus
}
#endif

#endif
