//
// Copyright (c) 2022 ZettaScale Technology
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

#ifndef ZENOH_PICO_COLLECTIONS_SYNC_GROUP_H
#define ZENOH_PICO_COLLECTIONS_SYNC_GROUP_H

#include "refcount.h"
#include "stdint.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/result.h"

typedef struct {
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_t counter_mutex;
    _z_condvar_t counter_condvar;
#endif
    bool is_closed;
} _z_sync_group_state_t;

z_result_t _z_sync_group_state_create(_z_sync_group_state_t* sync_group);
void _z_sync_group_state_clear(_z_sync_group_state_t* sync_group_state);

_Z_REFCOUNT_DEFINE_NO_FROM_VAL(_z_sync_group_state, _z_sync_group_state)

typedef struct {
    _z_sync_group_state_rc_t _state;
} _z_sync_group_t;

typedef struct {
    _z_sync_group_state_weak_t _state;
} _z_sync_group_notifier_t;

static inline _z_sync_group_t _z_sync_group_null(void) {
    _z_sync_group_t sg = {0};
    return sg;
}

static inline _z_sync_group_notifier_t _z_sync_group_notifier_null(void) {
    _z_sync_group_notifier_t n = {0};
    return n;
}

static inline _z_sync_group_notifier_t _z_sync_group_notifier_steal(_z_sync_group_notifier_t* notifier) {
    _z_sync_group_notifier_t n = *notifier;
    *notifier = _z_sync_group_notifier_null();
    return n;
}

z_result_t _z_sync_group_create(_z_sync_group_t* sync_group);
z_result_t _z_sync_group_wait(_z_sync_group_t* sync_group);
void _z_sync_group_close(_z_sync_group_t* sync_group);
z_result_t _z_sync_group_wait_deadline(_z_sync_group_t* sync_group, const z_clock_t* deadline);
static inline bool _z_sync_group_check(const _z_sync_group_t* sync_group) {
    return !_Z_RC_IS_NULL(&sync_group->_state);
}
bool _z_sync_group_is_closed(const _z_sync_group_t* sync_group);
void _z_sync_group_drop(_z_sync_group_t* sync_group);
z_result_t _z_sync_group_create_notifier(const _z_sync_group_t* sync_group, _z_sync_group_notifier_t* notifier);
void _z_sync_group_notifier_drop(_z_sync_group_notifier_t* notifier);
static inline bool _z_sync_group_notifier_check(const _z_sync_group_notifier_t* notifier) {
    return !_Z_RC_IS_NULL(&notifier->_state);
}

#endif
