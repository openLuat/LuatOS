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

#ifndef INCLUDE_ZENOH_PICO_NET_PUBLISH_H
#define INCLUDE_ZENOH_PICO_NET_PUBLISH_H

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/net/filtering.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Return type when declaring a publisher.
 */
typedef struct _z_publisher_t {
    _z_declared_keyexpr_t _key;
    _z_zint_t _id;
    _z_session_weak_t _zn;
    _z_encoding_t _encoding;
    z_congestion_control_t _congestion_control;
    z_priority_t _priority;
    z_reliability_t reliability;
    bool _is_express;
    z_locality_t _allowed_destination;
    _z_write_filter_t _filter;
} _z_publisher_t;

#if Z_FEATURE_PUBLICATION == 1
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_publisher_t _z_publisher_null(void) { return (_z_publisher_t){0}; }
static inline bool _z_publisher_check(const _z_publisher_t *publisher) { return !_Z_RC_IS_NULL(&publisher->_zn); }
#endif

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_NET_PUBLISH_H */
