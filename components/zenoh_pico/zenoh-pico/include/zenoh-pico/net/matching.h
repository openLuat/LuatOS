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

#ifndef INCLUDE_ZENOH_PICO_NET_MATCHING_H
#define INCLUDE_ZENOH_PICO_NET_MATCHING_H

#include "zenoh-pico/net/filtering.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _z_matching_listener_t {
    uint32_t _id;
    _z_write_filter_ctx_weak_t _write_filter_ctx;
} _z_matching_listener_t;

#if Z_FEATURE_MATCHING == 1
z_result_t _z_matching_listener_declare(_z_matching_listener_t *listener, _z_session_t *s,
                                        const _z_write_filter_ctx_rc_t *ctx, _z_closure_matching_status_t *callback);
z_result_t _z_matching_listener_register(uint32_t *listener_id, _z_session_t *s, const _z_write_filter_ctx_rc_t *ctx,
                                         _z_closure_matching_status_t *callback);
z_result_t _z_matching_listener_undeclare(_z_matching_listener_t *listener);
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_matching_listener_t _z_matching_listener_null(void) { return (_z_matching_listener_t){0}; }
static inline bool _z_matching_listener_check(const _z_matching_listener_t *matching_listener) {
    return !_Z_RC_IS_NULL(&matching_listener->_write_filter_ctx);
}
void _z_matching_listener_clear(_z_matching_listener_t *listener);
void _z_matching_listener_free(_z_matching_listener_t **listener);
#endif  // Z_FEATURE_MATCHING == 1

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_NET_MATCHING_H */
