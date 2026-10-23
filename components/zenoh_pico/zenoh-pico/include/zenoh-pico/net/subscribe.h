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
//

#ifndef ZENOH_PICO_SUBSCRIBE_NETAPI_H
#define ZENOH_PICO_SUBSCRIBE_NETAPI_H

#include <stdint.h>

#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Return type when declaring a subscriber.
 */
typedef struct {
    uint32_t _entity_id;
    _z_session_weak_t _zn;
    _z_sync_group_t _callback_drop_sync_group;
} _z_subscriber_t;

#if Z_FEATURE_SUBSCRIPTION == 1
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_subscriber_t _z_subscriber_null(void) { return (_z_subscriber_t){0}; }
static inline bool _z_subscriber_check(const _z_subscriber_t *subscriber) { return !_Z_RC_IS_NULL(&subscriber->_zn); }
void _z_subscriber_clear(_z_subscriber_t *sub);
void _z_subscriber_free(_z_subscriber_t **sub);

#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SUBSCRIBE_NETAPI_H */
