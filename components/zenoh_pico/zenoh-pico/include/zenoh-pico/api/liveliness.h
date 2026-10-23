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
//
#ifndef INCLUDE_ZENOH_PICO_API_LIVELINESS_H
#define INCLUDE_ZENOH_PICO_API_LIVELINESS_H

#include <stdbool.h>
#include <stdint.h>

#include "olv_macros.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/protocol/core.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t _id;
    _z_session_weak_t _zn;
} _z_liveliness_token_t;

_z_liveliness_token_t _z_liveliness_token_null(void);
_Z_OWNED_TYPE_VALUE(_z_liveliness_token_t, liveliness_token)
_Z_OWNED_FUNCTIONS_DEF(liveliness_token)

#if Z_FEATURE_LIVELINESS == 1

/**************** Liveliness Token ****************/

/**
 * The options for :c:func:`z_liveliness_declare_token()`.
 */
typedef struct z_liveliness_token_options_t {
    uint8_t __dummy;
} z_liveliness_token_options_t;

/**
 * Constructs default value for :c:type:`z_liveliness_token_options_t`.
 */
z_result_t z_liveliness_token_options_default(z_liveliness_token_options_t *options);

/**
 * Constructs and declares a liveliness token on the network.
 *
 * Liveliness token subscribers on an intersecting key expression will receive a PUT sample when connectivity
 * is achieved, and a DELETE sample if it's lost.
 *
 * Parameters:
 *   zs: A Zenos session to declare the liveliness token.
 *   token: An uninitialized memory location where liveliness token will be constructed.
 *   keyexpr: A keyexpr to declare a liveliess token for.
 *   options: Liveliness token declaration options.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_liveliness_declare_token(const z_loaned_session_t *zs, z_owned_liveliness_token_t *token,
                                      const z_loaned_keyexpr_t *keyexpr, const z_liveliness_token_options_t *options);

/**
 * Undeclare a liveliness token, notifying subscribers of its destruction.
 *
 * Parameters:
 *   token: Moved :c:type:`z_owned_liveliness_token_t` to undeclare.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_liveliness_undeclare_token(z_moved_liveliness_token_t *token);

/**************** Liveliness Subscriber ****************/

#if Z_FEATURE_SUBSCRIPTION == 1
/**
 * The options for :c:func:`z_liveliness_declare_subscriber()`
 */
typedef struct z_liveliness_subscriber_options_t {
    bool history;
} z_liveliness_subscriber_options_t;

/**
 * Constucts default value for :c:type:`z_liveliness_subscriber_options_t`.
 */
z_result_t z_liveliness_subscriber_options_default(z_liveliness_subscriber_options_t *options);

/**
 * Declares a subscriber on liveliness tokens that intersect `keyexpr`.
 *
 * Parameters:
 *   zs: The Zenoh session.
 *   sub: An uninitialized memory location where subscriber will be constructed.
 *   keyexpr: The key expression to subscribe to.
 *   callback: The callback function that will be called each time a liveliness token status is changed.
 *   options: The options to be passed to the liveliness subscriber declaration.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_liveliness_declare_subscriber(const z_loaned_session_t *zs, z_owned_subscriber_t *sub,
                                           const z_loaned_keyexpr_t *keyexpr, z_moved_closure_sample_t *callback,
                                           z_liveliness_subscriber_options_t *options);
/**
 * Declares a background subscriber on liveliness tokens that intersect `keyexpr`.
 * Subscriber callback will be called to process the messages, until the corresponding session is closed or dropped.
 *
 * Parameters:
 *   zs: The Zenoh session.
 *   keyexpr: The key expression to subscribe to.
 *   callback: The callback function that will be called each time a liveliness token status is changed.
 *   options: The options to be passed to the liveliness subscriber declaration.
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 */
z_result_t z_liveliness_declare_background_subscriber(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                                      z_moved_closure_sample_t *callback,
                                                      z_liveliness_subscriber_options_t *options);

#endif  // Z_FEATURE_SUBSCRIPTION == 1

/**************** Liveliness Query ****************/

#if Z_FEATURE_QUERY == 1
/**
 * The options for :c:func:`z_liveliness_get()`
 *
 * Members:
 *   uint64_t timeout_ms: Liveliness query timeout in milliseconds. 0 corresponds to default get request timeout.
 *   z_moved_cancellation_token_t *cancellation_token: Token to allow cancelling get operation (unstable).
 */
typedef struct z_liveliness_get_options_t {
    uint64_t timeout_ms;
#ifdef Z_FEATURE_UNSTABLE_API
    z_moved_cancellation_token_t *cancellation_token;
#endif
} z_liveliness_get_options_t;

/**
 * Constructs default value :c:type:`z_liveliness_get_options_t`.
 */
z_result_t z_liveliness_get_options_default(z_liveliness_get_options_t *options);

/**
 * Queries liveliness tokens currently on the network with a key expression intersecting with `keyexpr`.
 *
 * Parameters:
 *   zs: The Zenoh session.
 *   keyexpr: The key expression to query liveliness tokens for.
 *   callback: The callback function that will be called for each received reply.
 *   options: Additional options for the liveliness get operation.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_liveliness_get(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                            z_moved_closure_reply_t *callback, z_liveliness_get_options_t *options);

#endif  // Z_FEATURE_QUERY == 1

#endif  // Z_FEATURE_LIVELINESS == 1

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_ZENOH_PICO_API_LIVELINESS_H
