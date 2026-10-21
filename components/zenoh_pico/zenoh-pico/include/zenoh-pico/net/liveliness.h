//
// Copyright (c) 2024 ZettaScale Technology
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

#ifndef INCLUDE_ZENOH_PICO_NET_LIVELINESS_H
#define INCLUDE_ZENOH_PICO_NET_LIVELINESS_H

#include "zenoh-pico/api/liveliness.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/net/subscribe.h"
#include "zenoh-pico/protocol/core.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_LIVELINESS == 1

z_result_t _z_declare_liveliness_token(const _z_session_rc_t *zn, _z_liveliness_token_t *ret_token,
                                       const _z_declared_keyexpr_t *keyexpr);
z_result_t _z_undeclare_liveliness_token(_z_liveliness_token_t *token);

#if Z_FEATURE_SUBSCRIPTION == 1
/**
 * Declare a :c:type:`_z_subscriber_t` for the given liveliness key.
 *
 * Parameters:
 *     subscriber: The subscriber to initialize.
 *     zn: The zenoh-net session. The caller keeps its ownership.
 *     keyexpr: The resource key to subscribe.
 *     callback: The callback function that will be called each time a matching liveliness token changed.
 *     history: Enable current interest to return history tokens.
 *     arg: A pointer that will be passed to the **callback** on each call.
 *
 * Returns:
 *     0 in case of success, negative error code otherwise.
 */
z_result_t _z_declare_liveliness_subscriber(_z_subscriber_t *subscriber, const _z_session_rc_t *zn,
                                            const _z_declared_keyexpr_t *keyexpr, _z_closure_sample_callback_t callback,
                                            _z_drop_handler_t dropper, bool history, void *arg);

z_result_t _z_register_liveliness_subscriber(uint32_t *out_sub_id, const _z_session_rc_t *zn,
                                             const _z_declared_keyexpr_t *keyexpr,
                                             _z_closure_sample_callback_t callback, _z_drop_handler_t dropper,
                                             bool history, void *arg,
                                             const _z_sync_group_t *opt_callback_drop_sync_group);

/**
 * Undeclare a liveliness :c:type:`_z_subscriber_t`.
 *
 * Parameters:
 *     sub: The :c:type:`_z_subscriber_t` to undeclare. The callee releases the
 *          subscriber upon successful return.
 * Returns:
 *     0 if success, or a negative value identifying the error.
 */
z_result_t _z_undeclare_liveliness_subscriber(_z_subscriber_t *sub);
#endif  // Z_FEATURE_SUBSCRIPTION == 1

#if Z_FEATURE_QUERY == 1
/**
 * Query liveliness token state.
 *
 * Parameters:
 *     session: The zenoh-net session.
 *     keyexpr: The resource key to liveliness token.
 *     callback: The callback function that will be called on reception of replies for this query.
 *     dropper: The callback function that will be called on upon completion of the callback.
 *     arg: A pointer that will be passed to the **callback** on each call.
 *     timeout_ms: The timeout value of this query.
 *     opt_cancellation_token: Optional cancellation token, can be NULL.
 */
z_result_t _z_liveliness_query(const _z_session_rc_t *session, const _z_declared_keyexpr_t *keyexpr,
                               _z_closure_reply_callback_t callback, _z_drop_handler_t dropper, void *arg,
                               uint64_t timeout_ms, _z_cancellation_token_rc_t *opt_cancellation_token);
#endif  // Z_FEATURE_QUERY == 1

#endif  // Z_FEATURE_LIVELINESS == 1

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_NET_LIVELINESS_H */
