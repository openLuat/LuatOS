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

#ifndef ZENOH_PICO_API_MACROS_H
#define ZENOH_PICO_API_MACROS_H

#include "zenoh-pico/api/advanced_publisher.h"
#include "zenoh-pico/api/advanced_subscriber.h"
#include "zenoh-pico/api/handlers.h"
#include "zenoh-pico/api/liveliness.h"
#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/api/serialization.h"
#include "zenoh-pico/api/types.h"

#if ZENOH_C_STANDARD != 99

#ifndef __cplusplus

// clang-format off

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_LOAN \
    , z_owned_transport_t : z_transport_loan                                    \
    , z_owned_link_t : z_link_loan                                              \
    , z_owned_transport_event_t : z_transport_event_loan                        \
    , z_owned_link_event_t : z_link_event_loan                                  \
    , z_owned_transport_events_listener_t : z_transport_events_listener_loan    \
    , z_owned_link_events_listener_t : z_link_events_listener_loan              \
    , z_owned_closure_transport_t : z_closure_transport_loan                    \
    , z_owned_closure_link_t : z_closure_link_loan                              \
    , z_owned_closure_transport_event_t : z_closure_transport_event_loan        \
    , z_owned_closure_link_event_t : z_closure_link_event_loan
#else
#define _Z_GENERIC_CONNECTIVITY_LOAN
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_LOAN_MUT \
    , z_owned_transport_t : z_transport_loan_mut                                    \
    , z_owned_link_t : z_link_loan_mut                                              \
    , z_owned_transport_event_t : z_transport_event_loan_mut                        \
    , z_owned_link_event_t : z_link_event_loan_mut                                  \
    , z_owned_transport_events_listener_t : z_transport_events_listener_loan_mut    \
    , z_owned_link_events_listener_t : z_link_events_listener_loan_mut
#else
#define _Z_GENERIC_CONNECTIVITY_LOAN_MUT
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_DROP \
    , z_moved_transport_t* : z_transport_drop                                    \
    , z_moved_link_t* : z_link_drop                                              \
    , z_moved_transport_event_t* : z_transport_event_drop                        \
    , z_moved_link_event_t* : z_link_event_drop                                  \
    , z_moved_transport_events_listener_t* : z_transport_events_listener_drop    \
    , z_moved_link_events_listener_t* : z_link_events_listener_drop              \
    , z_moved_closure_transport_t* : z_closure_transport_drop                    \
    , z_moved_closure_link_t* : z_closure_link_drop                              \
    , z_moved_closure_transport_event_t* : z_closure_transport_event_drop        \
    , z_moved_closure_link_event_t* : z_closure_link_event_drop
#else
#define _Z_GENERIC_CONNECTIVITY_DROP
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_CHECK \
    , z_owned_transport_t : z_internal_transport_check                                    \
    , z_owned_link_t : z_internal_link_check                                              \
    , z_owned_transport_event_t : z_internal_transport_event_check                        \
    , z_owned_link_event_t : z_internal_link_event_check                                  \
    , z_owned_transport_events_listener_t : z_internal_transport_events_listener_check    \
    , z_owned_link_events_listener_t : z_internal_link_events_listener_check              \
    , z_owned_closure_transport_t : z_internal_closure_transport_check                    \
    , z_owned_closure_link_t : z_internal_closure_link_check                              \
    , z_owned_closure_transport_event_t : z_internal_closure_transport_event_check        \
    , z_owned_closure_link_event_t : z_internal_closure_link_event_check
#else
#define _Z_GENERIC_CONNECTIVITY_CHECK
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_MOVE \
    , z_owned_transport_t : z_transport_move                                    \
    , z_owned_link_t : z_link_move                                              \
    , z_owned_transport_event_t : z_transport_event_move                        \
    , z_owned_link_event_t : z_link_event_move                                  \
    , z_owned_transport_events_listener_t : z_transport_events_listener_move    \
    , z_owned_link_events_listener_t : z_link_events_listener_move              \
    , z_owned_closure_transport_t : z_closure_transport_move                    \
    , z_owned_closure_link_t : z_closure_link_move                              \
    , z_owned_closure_transport_event_t : z_closure_transport_event_move        \
    , z_owned_closure_link_event_t : z_closure_link_event_move
#else
#define _Z_GENERIC_CONNECTIVITY_MOVE
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_TAKE \
    , z_owned_transport_t *: z_transport_take                                    \
    , z_owned_link_t *: z_link_take                                              \
    , z_owned_transport_event_t *: z_transport_event_take                        \
    , z_owned_link_event_t *: z_link_event_take                                  \
    , z_owned_transport_events_listener_t *: z_transport_events_listener_take    \
    , z_owned_link_events_listener_t *: z_link_events_listener_take              \
    , z_owned_closure_transport_t *: z_closure_transport_take                    \
    , z_owned_closure_link_t *: z_closure_link_take                              \
    , z_owned_closure_transport_event_t *: z_closure_transport_event_take        \
    , z_owned_closure_link_event_t *: z_closure_link_event_take
#else
#define _Z_GENERIC_CONNECTIVITY_TAKE
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_CLONE \
    , z_owned_transport_t* : z_transport_clone              \
    , z_owned_link_t* : z_link_clone                        \
    , z_owned_transport_event_t* : z_transport_event_clone  \
    , z_owned_link_event_t* : z_link_event_clone
#else
#define _Z_GENERIC_CONNECTIVITY_CLONE
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_TAKE_FROM_LOANED \
    , z_owned_transport_t* : z_transport_take_from_loaned              \
    , z_owned_link_t* : z_link_take_from_loaned                        \
    , z_owned_transport_event_t* : z_transport_event_take_from_loaned  \
    , z_owned_link_event_t* : z_link_event_take_from_loaned
#else
#define _Z_GENERIC_CONNECTIVITY_TAKE_FROM_LOANED
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_NULL \
    , z_owned_transport_t * : z_internal_transport_null                                    \
    , z_owned_link_t * : z_internal_link_null                                              \
    , z_owned_transport_event_t * : z_internal_transport_event_null                        \
    , z_owned_link_event_t * : z_internal_link_event_null                                  \
    , z_owned_transport_events_listener_t * : z_internal_transport_events_listener_null    \
    , z_owned_link_events_listener_t * : z_internal_link_events_listener_null              \
    , z_owned_closure_transport_t * : z_internal_closure_transport_null                    \
    , z_owned_closure_link_t * : z_internal_closure_link_null                              \
    , z_owned_closure_transport_event_t * : z_internal_closure_transport_event_null        \
    , z_owned_closure_link_event_t * : z_internal_closure_link_event_null
#else
#define _Z_GENERIC_CONNECTIVITY_NULL
#endif

#if Z_FEATURE_CONNECTIVITY == 1
#define _Z_GENERIC_CONNECTIVITY_CALL \
    , z_loaned_closure_transport_t : z_closure_transport_call              \
    , z_loaned_closure_link_t : z_closure_link_call                        \
    , z_loaned_closure_transport_event_t : z_closure_transport_event_call  \
    , z_loaned_closure_link_event_t : z_closure_link_event_call
#else
#define _Z_GENERIC_CONNECTIVITY_CALL
#endif

/**
 * Defines a generic function for loaning any of the ``z_owned_X_t`` types.
 *
 * Parameters:
 *   x: The instance to loan.
 *
 * Returns:
 *   Returns the loaned type associated with `x`.
 */

#define z_loan(x) _Generic((x), \
                  z_owned_keyexpr_t : z_keyexpr_loan,                                  \
                  z_view_keyexpr_t : z_view_keyexpr_loan,                              \
                  z_owned_config_t : z_config_loan,                                    \
                  z_owned_session_t : z_session_loan,                                  \
                  z_owned_subscriber_t : z_subscriber_loan,                            \
                  z_owned_publisher_t : z_publisher_loan,                              \
                  ze_owned_advanced_subscriber_t : ze_advanced_subscriber_loan,        \
                  ze_owned_advanced_publisher_t : ze_advanced_publisher_loan,          \
                  z_owned_querier_t : z_querier_loan,                                  \
                  z_owned_matching_listener_t : z_matching_listener_loan,              \
                  ze_owned_sample_miss_listener_t : ze_sample_miss_listener_loan,      \
                  z_owned_queryable_t : z_queryable_loan,                              \
                  z_owned_liveliness_token_t : z_liveliness_token_loan,                \
                  z_owned_reply_t : z_reply_loan,                                      \
                  z_owned_hello_t : z_hello_loan,                                      \
                  z_owned_string_t : z_string_loan,                                    \
                  z_view_string_t : z_view_string_loan,                                \
                  z_owned_string_array_t : z_string_array_loan,                        \
                  z_owned_sample_t : z_sample_loan,                                    \
                  z_owned_query_t : z_query_loan,                                      \
                  z_owned_slice_t : z_slice_loan,                                      \
                  z_view_slice_t : z_view_slice_loan,                                  \
                  z_owned_bytes_t : z_bytes_loan,                                      \
                  z_owned_encoding_t : z_encoding_loan,                                \
                  z_owned_task_t : z_task_loan,                                        \
                  z_owned_mutex_t : z_mutex_loan,                                      \
                  z_owned_condvar_t : z_condvar_loan,                                  \
                  z_owned_fifo_handler_query_t : z_fifo_handler_query_loan,            \
                  z_owned_fifo_handler_reply_t : z_fifo_handler_reply_loan,            \
                  z_owned_fifo_handler_sample_t : z_fifo_handler_sample_loan,          \
                  z_owned_ring_handler_query_t : z_ring_handler_query_loan,            \
                  z_owned_ring_handler_reply_t : z_ring_handler_reply_loan,            \
                  z_owned_ring_handler_sample_t : z_ring_handler_sample_loan,          \
                  z_owned_reply_err_t : z_reply_err_loan,                              \
                  z_owned_closure_sample_t : z_closure_sample_loan,                    \
                  z_owned_closure_reply_t : z_closure_reply_loan,                      \
                  z_owned_closure_query_t : z_closure_query_loan,                      \
                  z_owned_closure_hello_t : z_closure_hello_loan,                      \
                  z_owned_closure_zid_t : z_closure_zid_loan,                          \
                  z_owned_closure_matching_status_t : z_closure_matching_status_loan,  \
                  ze_owned_closure_miss_t : ze_closure_miss_loan,                      \
                  ze_owned_serializer_t : ze_serializer_loan,                          \
                  z_owned_bytes_writer_t : z_bytes_writer_loan,                        \
                  z_owned_cancellation_token_t : z_cancellation_token_loan             \
                  _Z_GENERIC_CONNECTIVITY_LOAN                                         \
            )(&x)

#define z_loan_mut(x) _Generic((x), \
                  z_owned_keyexpr_t : z_keyexpr_loan_mut,                              \
                  z_owned_config_t : z_config_loan_mut,                                \
                  z_owned_session_t : z_session_loan_mut,                              \
                  z_owned_publisher_t : z_publisher_loan_mut,                          \
                  ze_owned_advanced_publisher_t : ze_advanced_publisher_loan_mut,      \
                  ze_owned_advanced_subscriber_t : ze_advanced_subscriber_loan_mut,    \
                  z_owned_querier_t : z_querier_loan_mut,                              \
                  z_owned_matching_listener_t : z_matching_listener_loan_mut,          \
                  ze_owned_sample_miss_listener_t : ze_sample_miss_listener_loan_mut,  \
                  z_owned_queryable_t : z_queryable_loan_mut,                          \
                  z_owned_liveliness_token_t : z_liveliness_token_loan_mut,            \
                  z_owned_subscriber_t : z_subscriber_loan_mut,                        \
                  z_owned_reply_t : z_reply_loan_mut,                                  \
                  z_owned_hello_t : z_hello_loan_mut,                                  \
                  z_owned_string_t : z_string_loan_mut,                                \
                  z_view_string_t : z_view_string_loan_mut,                            \
                  z_owned_string_array_t : z_string_array_loan_mut,                    \
                  z_owned_sample_t : z_sample_loan_mut,                                \
                  z_owned_query_t : z_query_loan_mut,                                  \
                  z_owned_slice_t : z_slice_loan_mut,                                  \
                  z_view_slice_t : z_view_slice_loan_mut,                              \
                  z_owned_bytes_t : z_bytes_loan_mut,                                  \
                  z_owned_task_t : z_task_loan_mut,                                    \
                  z_owned_mutex_t : z_mutex_loan_mut,                                  \
                  z_owned_condvar_t : z_condvar_loan_mut,                              \
                  z_owned_reply_err_t : z_reply_err_loan_mut,                          \
                  ze_owned_serializer_t : ze_serializer_loan_mut,                      \
                  z_owned_bytes_writer_t : z_bytes_writer_loan_mut,                    \
                  z_owned_cancellation_token_t : z_cancellation_token_loan_mut         \
                  _Z_GENERIC_CONNECTIVITY_LOAN_MUT                                     \
            )(&x)

/**
 * Defines a generic function for dropping any of the ``z_owned_X_t`` types.
 *
 * Parameters:
 *   x: The instance to drop.
 */
#define z_drop(x) _Generic((x), \
                  z_moved_keyexpr_t* : z_keyexpr_drop,                                 \
                  z_moved_config_t* : z_config_drop,                                   \
                  z_moved_session_t* : z_session_drop,                                 \
                  z_moved_subscriber_t* : z_subscriber_drop,                           \
                  z_moved_publisher_t* : z_publisher_drop,                             \
                  ze_moved_advanced_subscriber_t* : ze_advanced_subscriber_drop,       \
                  ze_moved_advanced_publisher_t* : ze_advanced_publisher_drop,         \
                  z_moved_querier_t* : z_querier_drop,                                 \
                  z_moved_matching_listener_t* : z_matching_listener_drop,             \
                  ze_moved_sample_miss_listener_t* : ze_sample_miss_listener_drop,     \
                  z_moved_queryable_t* : z_queryable_drop,                             \
                  z_moved_liveliness_token_t* : z_liveliness_token_drop,               \
                  z_moved_reply_t* : z_reply_drop,                                     \
                  z_moved_hello_t* : z_hello_drop,                                     \
                  z_moved_string_t* : z_string_drop,                                   \
                  z_moved_string_array_t* : z_string_array_drop,                       \
                  z_moved_sample_t* : z_sample_drop,                                   \
                  z_moved_query_t* : z_query_drop,                                     \
                  z_moved_encoding_t* : z_encoding_drop,                               \
                  z_moved_slice_t* : z_slice_drop,                                     \
                  z_moved_bytes_t* : z_bytes_drop,                                     \
                  z_moved_closure_sample_t* : z_closure_sample_drop,                   \
                  z_moved_closure_query_t* : z_closure_query_drop,                     \
                  z_moved_closure_reply_t* : z_closure_reply_drop,                     \
                  z_moved_closure_hello_t* : z_closure_hello_drop,                     \
                  z_moved_closure_zid_t* : z_closure_zid_drop,                         \
                  z_moved_closure_matching_status_t* : z_closure_matching_status_drop, \
                  ze_moved_closure_miss_t* : ze_closure_miss_drop,                     \
                  z_moved_task_t* : z_task_join,                                       \
                  z_moved_mutex_t* : z_mutex_drop,                                     \
                  z_moved_condvar_t* : z_condvar_drop,                                 \
                  z_moved_fifo_handler_query_t* : z_fifo_handler_query_drop,           \
                  z_moved_fifo_handler_reply_t* : z_fifo_handler_reply_drop,           \
                  z_moved_fifo_handler_sample_t* : z_fifo_handler_sample_drop,         \
                  z_moved_ring_handler_query_t* : z_ring_handler_query_drop,           \
                  z_moved_ring_handler_reply_t* : z_ring_handler_reply_drop,           \
                  z_moved_ring_handler_sample_t* : z_ring_handler_sample_drop,         \
                  z_moved_reply_err_t* : z_reply_err_drop,                             \
                  ze_moved_serializer_t* : ze_serializer_drop,                         \
                  z_moved_bytes_writer_t* : z_bytes_writer_drop,                       \
                  z_moved_cancellation_token_t* : z_cancellation_token_drop            \
                  _Z_GENERIC_CONNECTIVITY_DROP                                         \
            )(x)

/**
 * Defines a generic function for checking the validity of any of the ``z_owned_X_t`` types.
 *
 * Parameters:
 *   x: The instance to check.
 *
 * Returns:
 *   Returns ``true`` if valid, or ``false`` otherwise.
 */

#define z_internal_check(x) _Generic((x), \
                  z_owned_keyexpr_t : z_internal_keyexpr_check,                                  \
                  z_owned_reply_err_t : z_internal_reply_err_check,                              \
                  z_owned_config_t : z_internal_config_check,                                    \
                  z_owned_session_t : z_internal_session_check,                                  \
                  z_owned_subscriber_t : z_internal_subscriber_check,                            \
                  z_owned_publisher_t : z_internal_publisher_check,                              \
                  ze_owned_advanced_subscriber_t : ze_internal_advanced_subscriber_check,        \
                  ze_owned_advanced_publisher_t : ze_internal_advanced_publisher_check,          \
                  z_owned_querier_t : z_internal_querier_check,                                  \
                  z_owned_matching_listener_t : z_internal_matching_listener_check,              \
                  ze_owned_sample_miss_listener_t : ze_internal_sample_miss_listener_check,      \
                  z_owned_queryable_t : z_internal_queryable_check,                              \
                  z_owned_liveliness_token_t : z_internal_liveliness_token_check,                \
                  z_owned_reply_t : z_internal_reply_check,                                      \
                  z_owned_hello_t : z_internal_hello_check,                                      \
                  z_owned_string_t : z_internal_string_check,                                    \
                  z_owned_string_array_t : z_internal_string_array_check,                        \
                  z_owned_closure_sample_t : z_internal_closure_sample_check,                    \
                  z_owned_closure_query_t : z_internal_closure_query_check,                      \
                  z_owned_closure_reply_t : z_internal_closure_reply_check,                      \
                  z_owned_closure_hello_t : z_internal_closure_hello_check,                      \
                  z_owned_closure_zid_t : z_internal_closure_zid_check,                          \
                  z_owned_closure_matching_status_t : z_internal_closure_matching_status_check,  \
                  ze_owned_closure_miss_t : ze_internal_closure_miss_check,                      \
                  z_owned_slice_t : z_internal_slice_check,                                      \
                  z_owned_bytes_t : z_internal_bytes_check,                                      \
                  z_owned_sample_t : z_internal_sample_check,                                    \
                  z_owned_query_t : z_internal_query_check,                                      \
                  z_owned_encoding_t : z_internal_encoding_check,                                \
                  ze_owned_serializer_t : ze_internal_serializer_check,                          \
                  z_owned_bytes_writer_t : z_internal_bytes_writer_check,                        \
                  z_owned_cancellation_token_t : z_internal_cancellation_token_check             \
                  _Z_GENERIC_CONNECTIVITY_CHECK                                                  \
            )(&x)

/**
 * Defines a generic function for calling closure stored in any of ``z_owned_closure_X_t``
 *
 * Parameters:
 *   x: The closure to call
 */
#define z_call(x, ...) \
    _Generic((x), z_loaned_closure_sample_t : z_closure_sample_call,                   \
                  z_loaned_closure_query_t : z_closure_query_call,                     \
                  z_loaned_closure_reply_t : z_closure_reply_call,                     \
                  z_loaned_closure_hello_t : z_closure_hello_call,                     \
                  z_loaned_closure_zid_t : z_closure_zid_call,                         \
                  z_loaned_closure_matching_status_t : z_closure_matching_status_call, \
                  ze_loaned_closure_miss_t : ze_closure_miss_call                      \
                  _Z_GENERIC_CONNECTIVITY_CALL                                         \
            ) (&x, __VA_ARGS__)

#define z_try_recv(x, ...) \
    _Generic((x), \
        const z_loaned_fifo_handler_query_t* : z_fifo_handler_query_try_recv, \
        const z_loaned_fifo_handler_reply_t* : z_fifo_handler_reply_try_recv, \
        const z_loaned_fifo_handler_sample_t* : z_fifo_handler_sample_try_recv, \
        const z_loaned_ring_handler_query_t* : z_ring_handler_query_try_recv, \
        const z_loaned_ring_handler_reply_t* : z_ring_handler_reply_try_recv, \
        const z_loaned_ring_handler_sample_t* : z_ring_handler_sample_try_recv \
    )(x, __VA_ARGS__)

#define z_recv(x, ...) \
    _Generic((x), \
        const z_loaned_fifo_handler_query_t* : z_fifo_handler_query_recv, \
        const z_loaned_fifo_handler_reply_t* : z_fifo_handler_reply_recv, \
        const z_loaned_fifo_handler_sample_t* : z_fifo_handler_sample_recv, \
        const z_loaned_ring_handler_query_t* : z_ring_handler_query_recv, \
        const z_loaned_ring_handler_reply_t* : z_ring_handler_reply_recv, \
        const z_loaned_ring_handler_sample_t* : z_ring_handler_sample_recv \
    )(x, __VA_ARGS__)

/**
 * Defines a generic function for moving any of the ``z_owned_X_t`` types.
 *
 * Parameters:
 *   x: The instance to move.
 *
 * Returns:
 *   Returns the instance associated with `x`.
 */
#define z_move(x) _Generic((x), \
                  z_owned_keyexpr_t : z_keyexpr_move,                                   \
                  z_owned_config_t : z_config_move,                                     \
                  z_owned_session_t : z_session_move,                                   \
                  z_owned_subscriber_t : z_subscriber_move,                             \
                  z_owned_publisher_t : z_publisher_move,                               \
                  ze_owned_advanced_subscriber_t : ze_advanced_subscriber_move,         \
                  ze_owned_advanced_publisher_t : ze_advanced_publisher_move,           \
                  z_owned_querier_t : z_querier_move,                                   \
                  z_owned_matching_listener_t: z_matching_listener_move,                \
                  ze_owned_sample_miss_listener_t: ze_sample_miss_listener_move,        \
                  z_owned_queryable_t : z_queryable_move,                               \
                  z_owned_liveliness_token_t : z_liveliness_token_move,                 \
                  z_owned_reply_t : z_reply_move,                                       \
                  z_owned_hello_t : z_hello_move,                                       \
                  z_owned_string_t : z_string_move,                                     \
                  z_owned_string_array_t : z_string_array_move,                         \
                  z_owned_closure_sample_t : z_closure_sample_move,                     \
                  z_owned_closure_query_t : z_closure_query_move,                       \
                  z_owned_closure_reply_t : z_closure_reply_move,                       \
                  z_owned_closure_hello_t : z_closure_hello_move,                       \
                  z_owned_closure_zid_t  : z_closure_zid_move,                          \
                  z_owned_closure_matching_status_t  : z_closure_matching_status_move,  \
                  ze_owned_closure_miss_t  : ze_closure_miss_move,                      \
                  z_owned_sample_t : z_sample_move,                                     \
                  z_owned_query_t : z_query_move,                                       \
                  z_owned_slice_t : z_slice_move,                                       \
                  z_owned_bytes_t : z_bytes_move,                                       \
                  z_owned_encoding_t : z_encoding_move,                                 \
                  z_owned_task_t : z_task_move,                                         \
                  z_owned_mutex_t : z_mutex_move,                                       \
                  z_owned_condvar_t : z_condvar_move,                                   \
                  z_owned_ring_handler_query_t : z_ring_handler_query_move,             \
                  z_owned_ring_handler_reply_t : z_ring_handler_reply_move,             \
                  z_owned_ring_handler_sample_t : z_ring_handler_sample_move,           \
                  z_owned_fifo_handler_query_t : z_fifo_handler_query_move,             \
                  z_owned_fifo_handler_reply_t : z_fifo_handler_reply_move,             \
                  z_owned_fifo_handler_sample_t : z_fifo_handler_sample_move,           \
                  z_owned_reply_err_t : z_reply_err_move,                               \
                  ze_owned_serializer_t : ze_serializer_move,                           \
                  z_owned_bytes_writer_t : z_bytes_writer_move,                         \
                  z_owned_cancellation_token_t : z_cancellation_token_move              \
                  _Z_GENERIC_CONNECTIVITY_MOVE                                         \
            )(&x)

/**
 * Defines a generic function for extracting the ``z_owned_X_t`` type from ``z_moved_X_t``
 *
 * Parameters:
 *   x: The pointer to destinaton ``z_owned_X_t``
 *   src: The source ``z_moved_X_t``
 *
 * Returns:
 *   Returns the instance associated with `x`.
 */
#define z_take(this_, x)                                                       \
    _Generic((this_),                                                          \
        z_owned_bytes_t *: z_bytes_take,                                       \
        z_owned_closure_hello_t *: z_closure_hello_take,                       \
        z_owned_closure_query_t *: z_closure_query_take,                       \
        z_owned_closure_reply_t *: z_closure_reply_take,                       \
        z_owned_closure_sample_t *: z_closure_sample_take,                     \
        z_owned_closure_zid_t * : z_closure_zid_take,                          \
        z_owned_closure_matching_status_t * : z_closure_matching_status_take,  \
        ze_owned_closure_miss_t * : ze_closure_miss_take,                      \
        z_owned_condvar_t *: z_condvar_take,                                   \
        z_owned_config_t *: z_config_take,                                     \
        z_owned_encoding_t *: z_encoding_take,                                 \
        z_owned_fifo_handler_query_t *: z_fifo_handler_query_take,             \
        z_owned_fifo_handler_reply_t *: z_fifo_handler_reply_take,             \
        z_owned_fifo_handler_sample_t *: z_fifo_handler_sample_take,           \
        z_owned_hello_t *: z_hello_take,                                       \
        z_owned_keyexpr_t *: z_keyexpr_take,                                   \
        z_owned_mutex_t *: z_mutex_take,                                       \
        z_owned_publisher_t *: z_publisher_take,                               \
        ze_owned_advanced_publisher_t *: ze_advanced_publisher_take,           \
        z_owned_querier_t *: z_querier_take,                                   \
        z_owned_matching_listener_t *: z_matching_listener_take,               \
        ze_owned_sample_miss_listener_t *: ze_sample_miss_listener_take,       \
        z_owned_query_t *: z_query_take,                                       \
        z_owned_queryable_t *: z_queryable_take,                               \
        z_owned_liveliness_token_t *: z_liveliness_token_take,                 \
        z_owned_reply_t *: z_reply_take,                                       \
        z_owned_reply_err_t *: z_reply_err_take,                               \
        z_owned_ring_handler_query_t *: z_ring_handler_query_take,             \
        z_owned_ring_handler_reply_t *: z_ring_handler_reply_take,             \
        z_owned_ring_handler_sample_t *: z_ring_handler_sample_take,           \
        z_owned_sample_t *: z_sample_take,                                     \
        z_owned_session_t *: z_session_take,                                   \
        z_owned_slice_t *: z_slice_take,                                       \
        z_owned_string_array_t *: z_string_array_take,                         \
        z_owned_string_t *: z_string_take,                                     \
        z_owned_subscriber_t *: z_subscriber_take,                             \
        ze_owned_serializer_t *: ze_serializer_take,                           \
        z_owned_bytes_writer_t *: z_bytes_writer_take,                         \
        z_owned_cancellation_token_t *: z_cancellation_token_take              \
        _Z_GENERIC_CONNECTIVITY_TAKE                                         \
    )(this_, x)

/**
 * Defines a generic function for cloning of the ``z_owned_X_t`` types.
 *
 * Parameters:
 *   dst: The clone destination.
 *   src: The instance to clone.
 *
 * Returns:
 *   `0` in case of success, negative error code otherwise.
 */
#define z_clone(dst, src) _Generic((dst),                                    \
                  z_owned_keyexpr_t* : z_keyexpr_clone,                      \
                  z_owned_query_t* : z_query_clone,                          \
                  z_owned_sample_t* : z_sample_clone,                        \
                  z_owned_bytes_t* : z_bytes_clone,                          \
                  z_owned_encoding_t* : z_encoding_clone,                    \
                  z_owned_reply_err_t* : z_reply_err_clone,                  \
                  z_owned_reply_t* : z_reply_clone,                          \
                  z_owned_hello_t* : z_hello_clone,                          \
                  z_owned_string_t* : z_string_clone,                        \
                  z_owned_slice_t* : z_slice_clone,                          \
                  z_owned_string_array_t* : z_string_array_clone,            \
                  z_owned_config_t* : z_config_clone,                        \
                  z_owned_cancellation_token_t* : z_cancellation_token_clone \
                  _Z_GENERIC_CONNECTIVITY_CLONE                              \
            )(dst, src)

/**
 * Defines a generic function for moving of the ``z_owned_X_t`` types.
 *
 * Parameters:
 *   dst: The take destination.
 *   src: The instance to take contents from.
 *
 * Returns:
 *   `0` in case of success, negative error code otherwise.
 */
#define z_take_from_loaned(dst, src) _Generic((dst),                               \
                  z_owned_keyexpr_t* : z_keyexpr_take_from_loaned,                 \
                  z_owned_query_t* : z_query_take_from_loaned,                     \
                  z_owned_sample_t* : z_sample_take_from_loaned,                   \
                  z_owned_bytes_t* : z_bytes_take_from_loaned,                     \
                  z_owned_encoding_t* : z_encoding_take_from_loaned,               \
                  z_owned_reply_err_t* : z_reply_err_take_from_loaned,             \
                  z_owned_reply_t* : z_reply_take_from_loaned,                     \
                  z_owned_hello_t* : z_hello_take_from_loaned,                     \
                  z_owned_string_t* : z_string_take_from_loaned,                   \
                  z_owned_slice_t* : z_slice_take_from_loaned,                     \
                  z_owned_string_array_t* : z_string_array_take_from_loaned,       \
                  z_owned_config_t* : z_config_take_from_loaned,                   \
                  z_owned_bytes_writer_t* : z_bytes_writer_take_from_loaned,       \
                  ze_owned_serializer_t* : ze_serializer_take_from_loaned,         \
                  z_cancellation_token_t* : z_cancellation_token_take_from_loaned  \
                  _Z_GENERIC_CONNECTIVITY_TAKE_FROM_LOANED                       \
            )(dst, src)

/**
 * Defines a generic function for making null object of any of the ``z_owned_X_t`` types.
 *
 * Parameters:
 *   x: The instance to nullify.
 */
#define z_internal_null(x) _Generic((x), \
                  z_owned_session_t * : z_internal_session_null,                                  \
                  z_owned_publisher_t * : z_internal_publisher_null,                              \
                  ze_owned_advanced_subscriber_t * : ze_internal_advanced_subscriber_null,        \
                  ze_owned_advanced_publisher_t * : ze_internal_advanced_publisher_null,          \
                  z_owned_querier_t * : z_internal_querier_null,                                  \
                  z_owned_matching_listener_t * : z_internal_matching_listener_null,              \
                  ze_owned_sample_miss_listener_t * : ze_internal_sample_miss_listener_null,      \
                  z_owned_keyexpr_t * : z_internal_keyexpr_null,                                  \
                  z_owned_config_t * : z_internal_config_null,                                    \
                  z_owned_subscriber_t * : z_internal_subscriber_null,                            \
                  z_owned_queryable_t * : z_internal_queryable_null,                              \
                  z_owned_liveliness_token_t * : z_internal_liveliness_token_null,                \
                  z_owned_query_t * : z_internal_query_null,                                      \
                  z_owned_reply_t * : z_internal_reply_null,                                      \
                  z_owned_hello_t * : z_internal_hello_null,                                      \
                  z_owned_string_t * : z_internal_string_null,                                    \
                  z_owned_string_array_t * : z_internal_string_array_null,                        \
                  z_owned_slice_t  *: z_internal_slice_null,                                      \
                  z_owned_bytes_t  *: z_internal_bytes_null,                                      \
                  z_owned_closure_sample_t * : z_internal_closure_sample_null,                    \
                  z_owned_closure_query_t * : z_internal_closure_query_null,                      \
                  z_owned_closure_reply_t * : z_internal_closure_reply_null,                      \
                  z_owned_closure_hello_t * : z_internal_closure_hello_null,                      \
                  z_owned_closure_zid_t * : z_internal_closure_zid_null,                          \
                  z_owned_closure_matching_status_t * : z_internal_closure_matching_status_null,  \
                  ze_owned_closure_miss_t * : ze_internal_closure_miss_null,                      \
                  z_owned_sample_t * : z_internal_sample_null,                                    \
                  z_owned_encoding_t * : z_internal_encoding_null,                                \
                  z_owned_reply_err_t * : z_internal_reply_err_null,                              \
                  ze_owned_serializer_t * : ze_internal_serializer_null,                          \
                  z_owned_bytes_writer_t * : z_internal_bytes_writer_null,                        \
                  z_owned_cancellation_token_t * : z_internal_cancellation_token_null             \
                  _Z_GENERIC_CONNECTIVITY_NULL                                                    \
            )(x)

// clang-format on

#define _z_closure_overloader(closure, callback, dropper, ctx, ...) \
    do {                                                            \
        (closure)->_val.call = callback;                            \
        (closure)->_val.drop = dropper;                             \
        (closure)->_val.context = ctx;                              \
    } while (0);

/**
 * Defines a variadic macro to ease the definition of callback closures.
 *
 * Parameters:
 *   callback: the typical ``callback`` function. ``context`` will be passed as its last argument.
 *   dropper: allows the callback's state to be freed. ``context`` will be passed as its last argument.
 *   context: a pointer to an arbitrary state.
 *
 * Returns:
 *   Returns the new closure.
 */
#define z_closure(...) _z_closure_overloader(__VA_ARGS__, 0, 0, 0)

#else  // __cplusplus

// clang-format off

// z_loan definition
inline const z_loaned_keyexpr_t* z_loan(const z_owned_keyexpr_t& x) { return z_keyexpr_loan(&x); }
inline const z_loaned_keyexpr_t* z_loan(const z_view_keyexpr_t& x) { return z_view_keyexpr_loan(&x); }
inline const z_loaned_config_t* z_loan(const z_owned_config_t& x) { return z_config_loan(&x); }
inline const z_loaned_session_t* z_loan(const z_owned_session_t& x) { return z_session_loan(&x); }
inline const z_loaned_subscriber_t* z_loan(const z_owned_subscriber_t& x) { return z_subscriber_loan(&x); }
inline const z_loaned_publisher_t* z_loan(const z_owned_publisher_t& x) { return z_publisher_loan(&x); }
inline const ze_loaned_advanced_subscriber_t* z_loan(const ze_owned_advanced_subscriber_t& x) { return ze_advanced_subscriber_loan(&x); }
inline const ze_loaned_advanced_publisher_t* z_loan(const ze_owned_advanced_publisher_t& x) { return ze_advanced_publisher_loan(&x); }
inline const z_loaned_querier_t* z_loan(const z_owned_querier_t& x) { return z_querier_loan(&x); }
inline const z_loaned_matching_listener_t* z_loan(const z_owned_matching_listener_t& x) { return z_matching_listener_loan(&x); }
inline const ze_loaned_sample_miss_listener_t* z_loan(const ze_owned_sample_miss_listener_t& x) { return ze_sample_miss_listener_loan(&x); }
inline const z_loaned_queryable_t* z_loan(const z_owned_queryable_t& x) { return z_queryable_loan(&x); }
inline const z_loaned_liveliness_token_t* z_loan(const z_owned_liveliness_token_t& x) { return z_liveliness_token_loan(&x); }
inline const z_loaned_reply_t* z_loan(const z_owned_reply_t& x) { return z_reply_loan(&x); }
inline const z_loaned_hello_t* z_loan(const z_owned_hello_t& x) { return z_hello_loan(&x); }
inline const z_loaned_string_t* z_loan(const z_owned_string_t& x) { return z_string_loan(&x); }
inline const z_loaned_string_t* z_loan(const z_view_string_t& x) { return z_view_string_loan(&x); }
inline const z_loaned_string_array_t* z_loan(const z_owned_string_array_t& x) { return z_string_array_loan(&x); }
inline const z_loaned_sample_t* z_loan(const z_owned_sample_t& x) { return z_sample_loan(&x); }
inline const z_loaned_query_t* z_loan(const z_owned_query_t& x) { return z_query_loan(&x); }
inline const z_loaned_slice_t* z_loan(const z_owned_slice_t& x) { return z_slice_loan(&x); }
inline const z_loaned_slice_t* z_loan(const z_view_slice_t& x) { return z_view_slice_loan(&x); }
inline const z_loaned_bytes_t* z_loan(const z_owned_bytes_t& x) { return z_bytes_loan(&x); }
inline const z_loaned_encoding_t* z_loan(const z_owned_encoding_t& x) { return z_encoding_loan(&x); }
inline const z_loaned_task_t* z_loan(const z_owned_task_t& x) { return z_task_loan(&x); }
inline const z_loaned_mutex_t* z_loan(const z_owned_mutex_t& x) { return z_mutex_loan(&x); }
inline const z_loaned_condvar_t* z_loan(const z_owned_condvar_t& x) { return z_condvar_loan(&x); }
inline const z_loaned_reply_err_t* z_loan(const z_owned_reply_err_t& x) { return z_reply_err_loan(&x); }
inline const z_loaned_closure_sample_t* z_loan(const z_owned_closure_sample_t& x) { return z_closure_sample_loan(&x); }
inline const z_loaned_closure_reply_t* z_loan(const z_owned_closure_reply_t& x) { return z_closure_reply_loan(&x); }
inline const z_loaned_closure_query_t* z_loan(const z_owned_closure_query_t& x) { return z_closure_query_loan(&x); }
inline const z_loaned_closure_hello_t* z_loan(const z_owned_closure_hello_t& x) { return z_closure_hello_loan(&x); }
inline const z_loaned_closure_zid_t* z_loan(const z_owned_closure_zid_t& x) { return z_closure_zid_loan(&x); }
inline const z_loaned_closure_matching_status_t* z_loan(const z_owned_closure_matching_status_t& x) { return z_closure_matching_status_loan(&x); }
inline const ze_loaned_closure_miss_t* z_loan(const ze_owned_closure_miss_t& x) { return ze_closure_miss_loan(&x); }
inline const z_loaned_fifo_handler_query_t* z_loan(const z_owned_fifo_handler_query_t& x) { return z_fifo_handler_query_loan(&x); }
inline const z_loaned_fifo_handler_reply_t* z_loan(const z_owned_fifo_handler_reply_t& x) { return z_fifo_handler_reply_loan(&x); }
inline const z_loaned_fifo_handler_sample_t* z_loan(const z_owned_fifo_handler_sample_t& x) { return z_fifo_handler_sample_loan(&x); }
inline const z_loaned_ring_handler_query_t* z_loan(const z_owned_ring_handler_query_t& x) { return z_ring_handler_query_loan(&x); }
inline const z_loaned_ring_handler_reply_t* z_loan(const z_owned_ring_handler_reply_t& x) { return z_ring_handler_reply_loan(&x); }
inline const z_loaned_ring_handler_sample_t* z_loan(const z_owned_ring_handler_sample_t& x) { return z_ring_handler_sample_loan(&x); }
inline const z_loaned_bytes_writer_t* z_loan(const z_owned_bytes_writer_t& x) { return z_bytes_writer_loan(&x); }
inline const ze_loaned_serializer_t* z_loan(const ze_owned_serializer_t& x) { return ze_serializer_loan(&x); }
inline const z_loaned_cancellation_token_t* z_loan(const z_owned_cancellation_token_t& x) { return z_cancellation_token_loan(&x); }
#if Z_FEATURE_CONNECTIVITY == 1
inline const z_loaned_transport_t* z_loan(const z_owned_transport_t& x) { return z_transport_loan(&x); }
inline const z_loaned_link_t* z_loan(const z_owned_link_t& x) { return z_link_loan(&x); }
inline const z_loaned_transport_event_t* z_loan(const z_owned_transport_event_t& x) { return z_transport_event_loan(&x); }
inline const z_loaned_link_event_t* z_loan(const z_owned_link_event_t& x) { return z_link_event_loan(&x); }
inline const z_loaned_transport_events_listener_t* z_loan(const z_owned_transport_events_listener_t& x) { return z_transport_events_listener_loan(&x); }
inline const z_loaned_link_events_listener_t* z_loan(const z_owned_link_events_listener_t& x) { return z_link_events_listener_loan(&x); }
inline const z_loaned_closure_transport_t* z_loan(const z_owned_closure_transport_t& x) { return z_closure_transport_loan(&x); }
inline const z_loaned_closure_link_t* z_loan(const z_owned_closure_link_t& x) { return z_closure_link_loan(&x); }
inline const z_loaned_closure_transport_event_t* z_loan(const z_owned_closure_transport_event_t& x) { return z_closure_transport_event_loan(&x); }
inline const z_loaned_closure_link_event_t* z_loan(const z_owned_closure_link_event_t& x) { return z_closure_link_event_loan(&x); }
#endif

// z_loan_mut definition
inline z_loaned_keyexpr_t* z_loan_mut(z_owned_keyexpr_t& x) { return z_keyexpr_loan_mut(&x); }
inline z_loaned_keyexpr_t* z_loan_mut(z_view_keyexpr_t& x) { return z_view_keyexpr_loan_mut(&x); }
inline z_loaned_config_t* z_loan_mut(z_owned_config_t& x) { return z_config_loan_mut(&x); }
inline z_loaned_session_t* z_loan_mut(z_owned_session_t& x) { return z_session_loan_mut(&x); }
inline z_loaned_publisher_t* z_loan_mut(z_owned_publisher_t& x) { return z_publisher_loan_mut(&x); }
inline ze_loaned_advanced_publisher_t* z_loan_mut(ze_owned_advanced_publisher_t& x) { return ze_advanced_publisher_loan_mut(&x); }
inline z_loaned_querier_t* z_loan_mut(z_owned_querier_t& x) { return z_querier_loan_mut(&x); }
inline z_loaned_matching_listener_t* z_loan_mut(z_owned_matching_listener_t& x) { return z_matching_listener_loan_mut(&x); }
inline ze_loaned_sample_miss_listener_t* z_loan_mut(ze_owned_sample_miss_listener_t& x) { return ze_sample_miss_listener_loan_mut(&x); }
inline z_loaned_queryable_t* z_loan_mut(z_owned_queryable_t& x) { return z_queryable_loan_mut(&x); }
inline z_loaned_liveliness_token_t* z_loan_mut(z_owned_liveliness_token_t& x) { return z_liveliness_token_loan_mut(&x); }
inline z_loaned_subscriber_t* z_loan_mut(z_owned_subscriber_t& x) { return z_subscriber_loan_mut(&x); }
inline ze_loaned_advanced_subscriber_t* z_loan_mut(ze_owned_advanced_subscriber_t& x) { return ze_advanced_subscriber_loan_mut(&x); }
inline z_loaned_reply_t* z_loan_mut(z_owned_reply_t& x) { return z_reply_loan_mut(&x); }
inline z_loaned_hello_t* z_loan_mut(z_owned_hello_t& x) { return z_hello_loan_mut(&x); }
inline z_loaned_string_t* z_loan_mut(z_owned_string_t& x) { return z_string_loan_mut(&x); }
inline z_loaned_string_t* z_loan_mut(z_view_string_t& x) { return z_view_string_loan_mut(&x); }
inline z_loaned_slice_t* z_loan_mut(z_view_slice_t& x) { return z_view_slice_loan_mut(&x); }
inline z_loaned_string_array_t* z_loan_mut(z_owned_string_array_t& x) { return z_string_array_loan_mut(&x); }
inline z_loaned_sample_t* z_loan_mut(z_owned_sample_t& x) { return z_sample_loan_mut(&x); }
inline z_loaned_query_t* z_loan_mut(z_owned_query_t& x) { return z_query_loan_mut(&x); }
inline z_loaned_slice_t* z_loan_mut(z_owned_slice_t& x) { return z_slice_loan_mut(&x); }
inline z_loaned_bytes_t* z_loan_mut(z_owned_bytes_t& x) { return z_bytes_loan_mut(&x); }
inline z_loaned_encoding_t* z_loan_mut(z_owned_encoding_t& x) { return z_encoding_loan_mut(&x); }
inline z_loaned_task_t* z_loan_mut(z_owned_task_t& x) { return z_task_loan_mut(&x); }
inline z_loaned_mutex_t* z_loan_mut(z_owned_mutex_t& x) { return z_mutex_loan_mut(&x); }
inline z_loaned_condvar_t* z_loan_mut(z_owned_condvar_t& x) { return z_condvar_loan_mut(&x); }
inline z_loaned_reply_err_t* z_loan_mut(z_owned_reply_err_t& x) { return z_reply_err_loan_mut(&x); }
inline z_loaned_bytes_writer_t* z_loan_mut(z_owned_bytes_writer_t& x) { return z_bytes_writer_loan_mut(&x); }
inline ze_loaned_serializer_t* z_loan_mut(ze_owned_serializer_t& x) { return ze_serializer_loan_mut(&x); }
inline z_loaned_cancellation_token_t* z_loan_mut(z_owned_cancellation_token_t& x) { return z_cancellation_token_loan_mut(&x); }
#if Z_FEATURE_CONNECTIVITY == 1
inline z_loaned_transport_t* z_loan_mut(z_owned_transport_t& x) { return z_transport_loan_mut(&x); }
inline z_loaned_link_t* z_loan_mut(z_owned_link_t& x) { return z_link_loan_mut(&x); }
inline z_loaned_transport_event_t* z_loan_mut(z_owned_transport_event_t& x) { return z_transport_event_loan_mut(&x); }
inline z_loaned_link_event_t* z_loan_mut(z_owned_link_event_t& x) { return z_link_event_loan_mut(&x); }
inline z_loaned_transport_events_listener_t* z_loan_mut(z_owned_transport_events_listener_t& x) { return z_transport_events_listener_loan_mut(&x); }
inline z_loaned_link_events_listener_t* z_loan_mut(z_owned_link_events_listener_t& x) { return z_link_events_listener_loan_mut(&x); }
#endif

// z_drop definition
inline void z_drop(z_moved_session_t* v) { z_session_drop(v); }
inline void z_drop(z_moved_publisher_t* v) { z_publisher_drop(v); }
inline void z_drop(ze_moved_advanced_publisher_t* v) { ze_advanced_publisher_drop(v); }
inline void z_drop(z_moved_querier_t* v) { z_querier_drop(v); }
inline void z_drop(z_moved_matching_listener_t* v) { z_matching_listener_drop(v); }
inline void z_drop(ze_moved_sample_miss_listener_t* v) { ze_sample_miss_listener_drop(v); }
inline void z_drop(z_moved_keyexpr_t* v) { z_keyexpr_drop(v); }
inline void z_drop(z_moved_config_t* v) { z_config_drop(v); }
inline void z_drop(z_moved_subscriber_t* v) { z_subscriber_drop(v); }
inline void z_drop(ze_moved_advanced_subscriber_t* v) { ze_advanced_subscriber_drop(v); }
inline void z_drop(z_moved_queryable_t* v) { z_queryable_drop(v); }
inline void z_drop(z_moved_liveliness_token_t* v) { z_liveliness_token_drop(v); }
inline void z_drop(z_moved_reply_t* v) { z_reply_drop(v); }
inline void z_drop(z_moved_hello_t* v) { z_hello_drop(v); }
inline void z_drop(z_moved_string_t* v) { z_string_drop(v); }
inline void z_drop(z_moved_slice_t* v) { z_slice_drop(v); }
inline void z_drop(z_moved_string_array_t* v) { z_string_array_drop(v); }
inline void z_drop(z_moved_sample_t* v) { z_sample_drop(v); }
inline void z_drop(z_moved_query_t* v) { z_query_drop(v); }
inline void z_drop(z_moved_bytes_t* v) { z_bytes_drop(v); }
inline void z_drop(z_moved_encoding_t* v) { z_encoding_drop(v); }
inline void z_drop(z_moved_mutex_t* v) { z_mutex_drop(v); }
inline void z_drop(z_moved_condvar_t* v) { z_condvar_drop(v); }
inline void z_drop(z_moved_reply_err_t* v) { z_reply_err_drop(v); }
inline void z_drop(z_moved_closure_sample_t* v) { z_closure_sample_drop(v); }
inline void z_drop(z_moved_closure_query_t* v) { z_closure_query_drop(v); }
inline void z_drop(z_moved_closure_reply_t* v) { z_closure_reply_drop(v); }
inline void z_drop(z_moved_closure_hello_t* v) { z_closure_hello_drop(v); }
inline void z_drop(z_moved_closure_zid_t* v) { z_closure_zid_drop(v); }
inline void z_drop(z_moved_closure_matching_status_t* v) { z_closure_matching_status_drop(v); }
inline void z_drop(ze_moved_closure_miss_t* v) { ze_closure_miss_drop(v); }
inline void z_drop(z_moved_ring_handler_sample_t* v) { z_ring_handler_sample_drop(v); }
inline void z_drop(z_moved_fifo_handler_sample_t* v) { z_fifo_handler_sample_drop(v); }
inline void z_drop(z_moved_ring_handler_query_t* v) { z_ring_handler_query_drop(v); }
inline void z_drop(z_moved_fifo_handler_query_t* v) { z_fifo_handler_query_drop(v); }
inline void z_drop(z_moved_ring_handler_reply_t* v) { z_ring_handler_reply_drop(v); }
inline void z_drop(z_moved_fifo_handler_reply_t* v) { z_fifo_handler_reply_drop(v); }
inline void z_drop(z_moved_bytes_writer_t* v) { z_bytes_writer_drop(v); }
inline void z_drop(ze_moved_serializer_t* v) { ze_serializer_drop(v); }
inline void z_drop(z_moved_cancellation_token_t* v) { z_cancellation_token_drop(v); }
#if Z_FEATURE_CONNECTIVITY == 1
inline void z_drop(z_moved_transport_t* v) { z_transport_drop(v); }
inline void z_drop(z_moved_link_t* v) { z_link_drop(v); }
inline void z_drop(z_moved_transport_event_t* v) { z_transport_event_drop(v); }
inline void z_drop(z_moved_link_event_t* v) { z_link_event_drop(v); }
inline void z_drop(z_moved_transport_events_listener_t* v) { z_transport_events_listener_drop(v); }
inline void z_drop(z_moved_link_events_listener_t* v) { z_link_events_listener_drop(v); }
inline void z_drop(z_moved_closure_transport_t* v) { z_closure_transport_drop(v); }
inline void z_drop(z_moved_closure_link_t* v) { z_closure_link_drop(v); }
inline void z_drop(z_moved_closure_transport_event_t* v) { z_closure_transport_event_drop(v); }
inline void z_drop(z_moved_closure_link_event_t* v) { z_closure_link_event_drop(v); }
#endif

// z_internal_null definition
inline void z_internal_null(z_owned_session_t* v) { z_internal_session_null(v); }
inline void z_internal_null(z_owned_publisher_t* v) { z_internal_publisher_null(v); }
inline void z_internal_null(ze_owned_advanced_publisher_t* v) { ze_internal_advanced_publisher_null(v); }
inline void z_internal_null(z_owned_querier_t* v) { z_internal_querier_null(v); }
inline void z_internal_null(z_owned_matching_listener_t* v) { z_internal_matching_listener_null(v); }
inline void z_internal_null(ze_owned_sample_miss_listener_t* v) { ze_internal_sample_miss_listener_null(v); }
inline void z_internal_null(z_owned_keyexpr_t* v) { z_internal_keyexpr_null(v); }
inline void z_internal_null(z_owned_config_t* v) { z_internal_config_null(v); }
inline void z_internal_null(z_owned_subscriber_t* v) { z_internal_subscriber_null(v); }
inline void z_internal_null(ze_owned_advanced_subscriber_t* v) { ze_internal_advanced_subscriber_null(v); }
inline void z_internal_null(z_owned_queryable_t* v) { z_internal_queryable_null(v); }
inline void z_internal_null(z_owned_liveliness_token_t* v) { z_internal_liveliness_token_null(v); }
inline void z_internal_null(z_owned_query_t* v) { z_internal_query_null(v); }
inline void z_internal_null(z_owned_sample_t* v) { z_internal_sample_null(v); }
inline void z_internal_null(z_owned_reply_t* v) { z_internal_reply_null(v); }
inline void z_internal_null(z_owned_hello_t* v) { z_internal_hello_null(v); }
inline void z_internal_null(z_owned_string_t* v) { z_internal_string_null(v); }
inline void z_internal_null(z_owned_bytes_t* v) { z_internal_bytes_null(v); }
inline void z_internal_null(z_owned_encoding_t* v) { z_internal_encoding_null(v); }
inline void z_internal_null(z_owned_reply_err_t* v) { z_internal_reply_err_null(v); }
inline void z_internal_null(z_owned_closure_sample_t* v) { z_internal_closure_sample_null(v); }
inline void z_internal_null(z_owned_closure_query_t* v) { z_internal_closure_query_null(v); }
inline void z_internal_null(z_owned_closure_reply_t* v) { z_internal_closure_reply_null(v); }
inline void z_internal_null(z_owned_closure_hello_t* v) { z_internal_closure_hello_null(v); }
inline void z_internal_null(z_owned_closure_zid_t* v) { z_internal_closure_zid_null(v); }
inline void z_internal_null(z_owned_closure_matching_status_t* v) { z_internal_closure_matching_status_null(v); }
inline void z_internal_null(ze_owned_closure_miss_t* v) { ze_internal_closure_miss_null(v); }
inline void z_internal_null(z_owned_ring_handler_query_t* v) { return z_internal_ring_handler_query_null(v); }
inline void z_internal_null(z_owned_ring_handler_reply_t* v) { return z_internal_ring_handler_reply_null(v); }
inline void z_internal_null(z_owned_ring_handler_sample_t* v) { return z_internal_ring_handler_sample_null(v); }
inline void z_internal_null(z_owned_fifo_handler_query_t* v) { return z_internal_fifo_handler_query_null(v); }
inline void z_internal_null(z_owned_fifo_handler_reply_t* v) { return z_internal_fifo_handler_reply_null(v); }
inline void z_internal_null(z_owned_fifo_handler_sample_t* v) { return z_internal_fifo_handler_sample_null(v); }
inline void z_internal_null(z_owned_bytes_writer_t* v) { return z_internal_bytes_writer_null(v); }
inline void z_internal_null(ze_owned_serializer_t* v) { return ze_internal_serializer_null(v); }
inline void z_internal_null(z_owned_cancellation_token_t* v) { return z_internal_cancellation_token_null(v); }
#if Z_FEATURE_CONNECTIVITY == 1
inline void z_internal_null(z_owned_transport_t* v) { z_internal_transport_null(v); }
inline void z_internal_null(z_owned_link_t* v) { z_internal_link_null(v); }
inline void z_internal_null(z_owned_transport_event_t* v) { z_internal_transport_event_null(v); }
inline void z_internal_null(z_owned_link_event_t* v) { z_internal_link_event_null(v); }
inline void z_internal_null(z_owned_transport_events_listener_t* v) { z_internal_transport_events_listener_null(v); }
inline void z_internal_null(z_owned_link_events_listener_t* v) { z_internal_link_events_listener_null(v); }
inline void z_internal_null(z_owned_closure_transport_t* v) { z_internal_closure_transport_null(v); }
inline void z_internal_null(z_owned_closure_link_t* v) { z_internal_closure_link_null(v); }
inline void z_internal_null(z_owned_closure_transport_event_t* v) { z_internal_closure_transport_event_null(v); }
inline void z_internal_null(z_owned_closure_link_event_t* v) { z_internal_closure_link_event_null(v); }
#endif

// z_internal_check definition
inline bool z_internal_check(const z_owned_session_t& v) { return z_internal_session_check(&v); }
inline bool z_internal_check(const z_owned_publisher_t& v) { return z_internal_publisher_check(&v); }
inline bool z_internal_check(const ze_owned_advanced_publisher_t& v) { return ze_internal_advanced_publisher_check(&v); }
inline bool z_internal_check(const z_owned_querier_t& v) { return z_internal_querier_check(&v); }
inline bool z_internal_check(const z_owned_matching_listener_t& v) { return z_internal_matching_listener_check(&v); }
inline bool z_internal_check(const ze_owned_sample_miss_listener_t& v) { return ze_internal_sample_miss_listener_check(&v); }
inline bool z_internal_check(const z_owned_keyexpr_t& v) { return z_internal_keyexpr_check(&v); }
inline bool z_internal_check(const z_owned_config_t& v) { return z_internal_config_check(&v); }
inline bool z_internal_check(const z_owned_subscriber_t& v) { return z_internal_subscriber_check(&v); }
inline bool z_internal_check(const ze_owned_advanced_subscriber_t& v) { return ze_internal_advanced_subscriber_check(&v); }
inline bool z_internal_check(const z_owned_queryable_t& v) { return z_internal_queryable_check(&v); }
inline bool z_internal_check(const z_owned_liveliness_token_t& v) { return z_internal_liveliness_token_check(&v); }
inline bool z_internal_check(const z_owned_reply_t& v) { return z_internal_reply_check(&v); }
inline bool z_internal_check(const z_owned_query_t& v) { return z_internal_query_check(&v); }
inline bool z_internal_check(const z_owned_hello_t& v) { return z_internal_hello_check(&v); }
inline bool z_internal_check(const z_owned_string_t& v) { return z_internal_string_check(&v); }
inline bool z_internal_check(const z_owned_sample_t& v) { return z_internal_sample_check(&v); }
inline bool z_internal_check(const z_owned_bytes_t& v) { return z_internal_bytes_check(&v); }
inline bool z_internal_check(const z_owned_encoding_t& v) { return z_internal_encoding_check(&v); }
inline bool z_internal_check(const z_owned_reply_err_t& v) { return z_internal_reply_err_check(&v); }
inline bool z_internal_check(const z_owned_fifo_handler_query_t& v) { return z_internal_fifo_handler_query_check(&v); }
inline bool z_internal_check(const z_owned_fifo_handler_reply_t& v) { return z_internal_fifo_handler_reply_check(&v); }
inline bool z_internal_check(const z_owned_fifo_handler_sample_t& v) { return z_internal_fifo_handler_sample_check(&v); }
inline bool z_internal_check(const z_owned_ring_handler_query_t& v) { return z_internal_ring_handler_query_check(&v); }
inline bool z_internal_check(const z_owned_ring_handler_reply_t& v) { return z_internal_ring_handler_reply_check(&v); }
inline bool z_internal_check(const z_owned_ring_handler_sample_t& v) { return z_internal_ring_handler_sample_check(&v); }
inline bool z_internal_check(const z_owned_bytes_writer_t& v) { return z_internal_bytes_writer_check(&v); }
inline bool z_internal_check(const ze_owned_serializer_t& v) { return ze_internal_serializer_check(&v); }
inline bool z_internal_check(const z_owned_cancellation_token_t& v) { return z_internal_cancellation_token_check(&v); }
#if Z_FEATURE_CONNECTIVITY == 1
inline bool z_internal_check(const z_owned_transport_t& v) { return z_internal_transport_check(&v); }
inline bool z_internal_check(const z_owned_link_t& v) { return z_internal_link_check(&v); }
inline bool z_internal_check(const z_owned_transport_event_t& v) { return z_internal_transport_event_check(&v); }
inline bool z_internal_check(const z_owned_link_event_t& v) { return z_internal_link_event_check(&v); }
inline bool z_internal_check(const z_owned_transport_events_listener_t& v) { return z_internal_transport_events_listener_check(&v); }
inline bool z_internal_check(const z_owned_link_events_listener_t& v) { return z_internal_link_events_listener_check(&v); }
inline bool z_internal_check(const z_owned_closure_transport_t& v) { return z_internal_closure_transport_check(&v); }
inline bool z_internal_check(const z_owned_closure_link_t& v) { return z_internal_closure_link_check(&v); }
inline bool z_internal_check(const z_owned_closure_transport_event_t& v) { return z_internal_closure_transport_event_check(&v); }
inline bool z_internal_check(const z_owned_closure_link_event_t& v) { return z_internal_closure_link_event_check(&v); }
#endif

// z_call definition
inline void z_call(const z_loaned_closure_sample_t &closure, z_loaned_sample_t *sample) 
    { z_closure_sample_call(&closure, sample); }
inline void z_call(const z_loaned_closure_query_t &closure, z_loaned_query_t *query)
    { z_closure_query_call(&closure, query); }
inline void z_call(const z_loaned_closure_reply_t &closure, z_loaned_reply_t *reply)
    { z_closure_reply_call(&closure, reply); }
inline void z_call(const z_loaned_closure_hello_t &closure, z_loaned_hello_t *hello)
    { z_closure_hello_call(&closure, hello); }
inline void z_call(const z_loaned_closure_zid_t &closure, const z_id_t *zid)
    { z_closure_zid_call(&closure, zid); }
inline void z_call(const z_loaned_closure_matching_status_t &closure, const z_matching_status_t *status)
    { z_closure_matching_status_call(&closure, status); }
inline void z_call(const ze_loaned_closure_miss_t &closure, const ze_miss_t *miss)
    { ze_closure_miss_call(&closure, miss); }
#if Z_FEATURE_CONNECTIVITY == 1
inline void z_call(const z_loaned_closure_transport_t &closure, z_loaned_transport_t *transport)
    { z_closure_transport_call(&closure, transport); }
inline void z_call(const z_loaned_closure_link_t &closure, z_loaned_link_t *link)
    { z_closure_link_call(&closure, link); }
inline void z_call(const z_loaned_closure_transport_event_t &closure, z_loaned_transport_event_t *event)
    { z_closure_transport_event_call(&closure, event); }
inline void z_call(const z_loaned_closure_link_event_t &closure, z_loaned_link_event_t *event)
    { z_closure_link_event_call(&closure, event); }
#endif

inline void z_closure(
    z_owned_closure_hello_t* closure,
    void (*call)(z_loaned_hello_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_query_t* closure,
    void (*call)(z_loaned_query_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_reply_t* closure,
    void (*call)(z_loaned_reply_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_sample_t* closure,
    void (*call)(z_loaned_sample_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_zid_t* closure,
    void (*call)(const z_id_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_matching_status_t* closure,
    void (*call)(const z_matching_status_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    ze_owned_closure_miss_t* closure,
    void (*call)(const ze_miss_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
#if Z_FEATURE_CONNECTIVITY == 1
inline void z_closure(
    z_owned_closure_transport_t* closure,
    void (*call)(z_loaned_transport_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_link_t* closure,
    void (*call)(z_loaned_link_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_transport_event_t* closure,
    void (*call)(z_loaned_transport_event_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
inline void z_closure(
    z_owned_closure_link_event_t* closure,
    void (*call)(z_loaned_link_event_t*, void*),
    void (*drop)(void*),
    void *context) {
    closure->_val.context = context;
    closure->_val.drop = drop;
    closure->_val.call = call;
}
#endif

inline z_result_t z_try_recv(const z_loaned_fifo_handler_query_t* this_, z_owned_query_t* query) {
    return z_fifo_handler_query_try_recv(this_, query);
}
inline z_result_t z_try_recv(const z_loaned_fifo_handler_reply_t* this_, z_owned_reply_t* reply) {
    return z_fifo_handler_reply_try_recv(this_, reply);
}
inline z_result_t z_try_recv(const z_loaned_fifo_handler_sample_t* this_, z_owned_sample_t* sample) {
    return z_fifo_handler_sample_try_recv(this_, sample);
}
inline z_result_t z_try_recv(const z_loaned_ring_handler_query_t* this_, z_owned_query_t* query) {
    return z_ring_handler_query_try_recv(this_, query);
}
inline z_result_t z_try_recv(const z_loaned_ring_handler_reply_t* this_, z_owned_reply_t* reply) {
    return z_ring_handler_reply_try_recv(this_, reply);
}
inline z_result_t z_try_recv(const z_loaned_ring_handler_sample_t* this_, z_owned_sample_t* sample) {
    return z_ring_handler_sample_try_recv(this_, sample);
}


inline z_result_t z_recv(const z_loaned_fifo_handler_query_t* this_, z_owned_query_t* query) {
    return z_fifo_handler_query_recv(this_, query);
}
inline z_result_t z_recv(const z_loaned_fifo_handler_reply_t* this_, z_owned_reply_t* reply) {
    return z_fifo_handler_reply_recv(this_, reply);
}
inline z_result_t z_recv(const z_loaned_fifo_handler_sample_t* this_, z_owned_sample_t* sample) {
    return z_fifo_handler_sample_recv(this_, sample);
}
inline z_result_t z_recv(const z_loaned_ring_handler_query_t* this_, z_owned_query_t* query) {
    return z_ring_handler_query_recv(this_, query);
}
inline z_result_t z_recv(const z_loaned_ring_handler_reply_t* this_, z_owned_reply_t* reply) {
    return z_ring_handler_reply_recv(this_, reply);
}
inline z_result_t z_recv(const z_loaned_ring_handler_sample_t* this_, z_owned_sample_t* sample) {
    return z_ring_handler_sample_recv(this_, sample);
}

// clang-format on

inline z_moved_bytes_t* z_move(z_owned_bytes_t& x) { return z_bytes_move(&x); }
inline z_moved_closure_hello_t* z_move(z_owned_closure_hello_t& closure) { return z_closure_hello_move(&closure); }
inline z_moved_closure_query_t* z_move(z_owned_closure_query_t& closure) { return z_closure_query_move(&closure); }
inline z_moved_closure_reply_t* z_move(z_owned_closure_reply_t& closure) { return z_closure_reply_move(&closure); }
inline z_moved_closure_sample_t* z_move(z_owned_closure_sample_t& closure) { return z_closure_sample_move(&closure); }
inline z_moved_closure_zid_t* z_move(z_owned_closure_zid_t& closure) { return z_closure_zid_move(&closure); }
inline z_moved_closure_matching_status_t* z_move(z_owned_closure_matching_status_t& closure) {
    return z_closure_matching_status_move(&closure);
}
inline ze_moved_closure_miss_t* z_move(ze_owned_closure_miss_t& closure) { return ze_closure_miss_move(&closure); }
inline z_moved_config_t* z_move(z_owned_config_t& x) { return z_config_move(&x); }
inline z_moved_encoding_t* z_move(z_owned_encoding_t& x) { return z_encoding_move(&x); }
inline z_moved_reply_err_t* z_move(z_owned_reply_err_t& x) { return z_reply_err_move(&x); }
inline z_moved_hello_t* z_move(z_owned_hello_t& x) { return z_hello_move(&x); }
inline z_moved_keyexpr_t* z_move(z_owned_keyexpr_t& x) { return z_keyexpr_move(&x); }
inline z_moved_publisher_t* z_move(z_owned_publisher_t& x) { return z_publisher_move(&x); }
inline ze_moved_advanced_publisher_t* z_move(ze_owned_advanced_publisher_t& x) {
    return ze_advanced_publisher_move(&x);
}
inline z_moved_querier_t* z_move(z_owned_querier_t& x) { return z_querier_move(&x); }
inline z_moved_matching_listener_t* z_move(z_owned_matching_listener_t& x) { return z_matching_listener_move(&x); }
inline ze_moved_sample_miss_listener_t* z_move(ze_owned_sample_miss_listener_t& x) {
    return ze_sample_miss_listener_move(&x);
}
inline z_moved_query_t* z_move(z_owned_query_t& x) { return z_query_move(&x); }
inline z_moved_queryable_t* z_move(z_owned_queryable_t& x) { return z_queryable_move(&x); }
inline z_moved_liveliness_token_t* z_move(z_owned_liveliness_token_t& x) { return z_liveliness_token_move(&x); }
inline z_moved_reply_t* z_move(z_owned_reply_t& x) { return z_reply_move(&x); }
inline z_moved_sample_t* z_move(z_owned_sample_t& x) { return z_sample_move(&x); }
inline z_moved_session_t* z_move(z_owned_session_t& x) { return z_session_move(&x); }
inline z_moved_slice_t* z_move(z_owned_slice_t& x) { return z_slice_move(&x); }
inline z_moved_string_array_t* z_move(z_owned_string_array_t& x) { return z_string_array_move(&x); }
inline z_moved_string_t* z_move(z_owned_string_t& x) { return z_string_move(&x); }
inline z_moved_subscriber_t* z_move(z_owned_subscriber_t& x) { return z_subscriber_move(&x); }
inline ze_moved_advanced_subscriber_t* z_move(ze_owned_advanced_subscriber_t& x) {
    return ze_advanced_subscriber_move(&x);
}
inline z_moved_fifo_handler_query_t* z_move(z_owned_fifo_handler_query_t& x) { return z_fifo_handler_query_move(&x); }
inline z_moved_fifo_handler_reply_t* z_move(z_owned_fifo_handler_reply_t& x) { return z_fifo_handler_reply_move(&x); }
inline z_moved_fifo_handler_sample_t* z_move(z_owned_fifo_handler_sample_t& x) {
    return z_fifo_handler_sample_move(&x);
}
inline z_moved_ring_handler_query_t* z_move(z_owned_ring_handler_query_t& x) { return z_ring_handler_query_move(&x); }
inline z_moved_ring_handler_reply_t* z_move(z_owned_ring_handler_reply_t& x) { return z_ring_handler_reply_move(&x); }
inline z_moved_ring_handler_sample_t* z_move(z_owned_ring_handler_sample_t& x) {
    return z_ring_handler_sample_move(&x);
}
inline z_moved_bytes_writer_t* z_move(z_owned_bytes_writer_t& x) { return z_bytes_writer_move(&x); }
inline ze_moved_serializer_t* z_move(ze_owned_serializer_t& x) { return ze_serializer_move(&x); }
inline z_moved_cancellation_token_t* z_move(z_owned_cancellation_token_t& x) { return z_cancellation_token_move(&x); }
#if Z_FEATURE_CONNECTIVITY == 1
inline z_moved_transport_t* z_move(z_owned_transport_t& x) { return z_transport_move(&x); }
inline z_moved_link_t* z_move(z_owned_link_t& x) { return z_link_move(&x); }
inline z_moved_transport_event_t* z_move(z_owned_transport_event_t& x) { return z_transport_event_move(&x); }
inline z_moved_link_event_t* z_move(z_owned_link_event_t& x) { return z_link_event_move(&x); }
inline z_moved_transport_events_listener_t* z_move(z_owned_transport_events_listener_t& x) {
    return z_transport_events_listener_move(&x);
}
inline z_moved_link_events_listener_t* z_move(z_owned_link_events_listener_t& x) {
    return z_link_events_listener_move(&x);
}
inline z_moved_closure_transport_t* z_move(z_owned_closure_transport_t& x) { return z_closure_transport_move(&x); }
inline z_moved_closure_link_t* z_move(z_owned_closure_link_t& x) { return z_closure_link_move(&x); }
inline z_moved_closure_transport_event_t* z_move(z_owned_closure_transport_event_t& x) {
    return z_closure_transport_event_move(&x);
}
inline z_moved_closure_link_event_t* z_move(z_owned_closure_link_event_t& x) { return z_closure_link_event_move(&x); }
#endif

// z_take definition
inline void z_take(z_owned_session_t* this_, z_moved_session_t* v) { return z_session_take(this_, v); }
inline void z_take(z_owned_publisher_t* this_, z_moved_publisher_t* v) { return z_publisher_take(this_, v); }
inline void z_take(ze_owned_advanced_publisher_t* this_, ze_moved_advanced_publisher_t* v) {
    return ze_advanced_publisher_take(this_, v);
}
inline void z_take(z_owned_querier_t* this_, z_moved_querier_t* v) { return z_querier_take(this_, v); }
inline void z_take(z_owned_matching_listener_t* this_, z_moved_matching_listener_t* v) {
    return z_matching_listener_take(this_, v);
}
inline void z_take(ze_owned_sample_miss_listener_t* this_, ze_moved_sample_miss_listener_t* v) {
    return ze_sample_miss_listener_take(this_, v);
}
inline void z_take(z_owned_keyexpr_t* this_, z_moved_keyexpr_t* v) { z_keyexpr_take(this_, v); }
inline void z_take(z_owned_config_t* this_, z_moved_config_t* v) { z_config_take(this_, v); }
inline void z_take(z_owned_subscriber_t* this_, z_moved_subscriber_t* v) { return z_subscriber_take(this_, v); }
inline void z_take(ze_owned_advanced_subscriber_t* this_, ze_moved_advanced_subscriber_t* v) {
    return ze_advanced_subscriber_take(this_, v);
}
inline void z_take(z_owned_queryable_t* this_, z_moved_queryable_t* v) { return z_queryable_take(this_, v); }
inline void z_take(z_owned_liveliness_token_t* this_, z_moved_liveliness_token_t* v) {
    return z_liveliness_token_take(this_, v);
}
inline void z_take(z_owned_reply_t* this_, z_moved_reply_t* v) { z_reply_take(this_, v); }
inline void z_take(z_owned_hello_t* this_, z_moved_hello_t* v) { z_hello_take(this_, v); }
inline void z_take(z_owned_string_t* this_, z_moved_string_t* v) { z_string_take(this_, v); }
inline void z_take(z_owned_slice_t* this_, z_moved_slice_t* v) { z_slice_take(this_, v); }
inline void z_take(z_owned_string_array_t* this_, z_moved_string_array_t* v) { z_string_array_take(this_, v); }
inline void z_take(z_owned_sample_t* this_, z_moved_sample_t* v) { z_sample_take(this_, v); }
inline void z_take(z_owned_query_t* this_, z_moved_query_t* v) { z_query_take(this_, v); }
inline void z_take(z_owned_bytes_t* this_, z_moved_bytes_t* v) { z_bytes_take(this_, v); }
inline void z_take(z_owned_encoding_t* this_, z_moved_encoding_t* v) { z_encoding_take(this_, v); }
inline void z_take(z_owned_mutex_t* this_, z_moved_mutex_t* v) { z_mutex_take(this_, v); }
inline void z_take(z_owned_condvar_t* this_, z_moved_condvar_t* v) { z_condvar_take(this_, v); }
inline void z_take(z_owned_reply_err_t* this_, z_moved_reply_err_t* v) { z_reply_err_take(this_, v); }
inline void z_take(z_owned_closure_sample_t* this_, z_moved_closure_sample_t* v) { z_closure_sample_take(this_, v); }
inline void z_take(z_owned_closure_query_t* this_, z_moved_closure_query_t* v) { z_closure_query_take(this_, v); }
inline void z_take(z_owned_closure_reply_t* this_, z_moved_closure_reply_t* v) { z_closure_reply_take(this_, v); }
inline void z_take(z_owned_closure_hello_t* this_, z_moved_closure_hello_t* v) { z_closure_hello_take(this_, v); }
inline void z_take(z_owned_closure_zid_t* this_, z_moved_closure_zid_t* v) { z_closure_zid_take(this_, v); }
inline void z_take(z_owned_closure_matching_status_t* this_, z_moved_closure_matching_status_t* v) {
    z_closure_matching_status_take(this_, v);
}
inline void z_take(ze_owned_closure_miss_t* this_, ze_moved_closure_miss_t* v) { ze_closure_miss_take(this_, v); }
inline void z_take(z_owned_ring_handler_sample_t* this_, z_moved_ring_handler_sample_t* v) {
    z_ring_handler_sample_take(this_, v);
}
inline void z_take(z_owned_fifo_handler_sample_t* this_, z_moved_fifo_handler_sample_t* v) {
    z_fifo_handler_sample_take(this_, v);
}
inline void z_take(z_owned_ring_handler_query_t* this_, z_moved_ring_handler_query_t* v) {
    z_ring_handler_query_take(this_, v);
}
inline void z_take(z_owned_fifo_handler_query_t* this_, z_moved_fifo_handler_query_t* v) {
    z_fifo_handler_query_take(this_, v);
}
inline void z_take(z_owned_ring_handler_reply_t* this_, z_moved_ring_handler_reply_t* v) {
    z_ring_handler_reply_take(this_, v);
}
inline void z_take(z_owned_fifo_handler_reply_t* this_, z_moved_fifo_handler_reply_t* v) {
    z_fifo_handler_reply_take(this_, v);
}
inline void z_take(z_owned_bytes_writer_t* this_, z_moved_bytes_writer_t* v) { z_bytes_writer_take(this_, v); }
inline void z_take(ze_owned_serializer_t* this_, ze_moved_serializer_t* v) { ze_serializer_take(this_, v); }
inline void z_take(z_owned_cancellation_token_t* this_, z_moved_cancellation_token_t* v) {
    z_cancellation_token_take(this_, v);
}
#if Z_FEATURE_CONNECTIVITY == 1
inline void z_take(z_owned_transport_t* this_, z_moved_transport_t* v) { z_transport_take(this_, v); }
inline void z_take(z_owned_link_t* this_, z_moved_link_t* v) { z_link_take(this_, v); }
inline void z_take(z_owned_transport_event_t* this_, z_moved_transport_event_t* v) { z_transport_event_take(this_, v); }
inline void z_take(z_owned_link_event_t* this_, z_moved_link_event_t* v) { z_link_event_take(this_, v); }
inline void z_take(z_owned_transport_events_listener_t* this_, z_moved_transport_events_listener_t* v) {
    z_transport_events_listener_take(this_, v);
}
inline void z_take(z_owned_link_events_listener_t* this_, z_moved_link_events_listener_t* v) {
    z_link_events_listener_take(this_, v);
}
inline void z_take(z_owned_closure_transport_t* this_, z_moved_closure_transport_t* v) {
    z_closure_transport_take(this_, v);
}
inline void z_take(z_owned_closure_link_t* this_, z_moved_closure_link_t* v) { z_closure_link_take(this_, v); }
inline void z_take(z_owned_closure_transport_event_t* this_, z_moved_closure_transport_event_t* v) {
    z_closure_transport_event_take(this_, v);
}
inline void z_take(z_owned_closure_link_event_t* this_, z_moved_closure_link_event_t* v) {
    z_closure_link_event_take(this_, v);
}
#endif

// z_clone definition
inline z_result_t z_clone(z_owned_bytes_t* dst, const z_loaned_bytes_t* this_) { return z_bytes_clone(dst, this_); }
inline z_result_t z_clone(z_owned_config_t* dst, const z_loaned_config_t* this_) { return z_config_clone(dst, this_); }
inline z_result_t z_clone(z_owned_encoding_t* dst, const z_loaned_encoding_t* this_) {
    return z_encoding_clone(dst, this_);
}
inline z_result_t z_clone(z_owned_keyexpr_t* dst, const z_loaned_keyexpr_t* this_) {
    return z_keyexpr_clone(dst, this_);
}
inline z_result_t z_clone(z_owned_query_t* dst, const z_loaned_query_t* this_) { return z_query_clone(dst, this_); }
inline z_result_t z_clone(z_owned_reply_t* dst, const z_loaned_reply_t* this_) { return z_reply_clone(dst, this_); }
inline z_result_t z_clone(z_owned_reply_err_t* dst, const z_loaned_reply_err_t* this_) {
    return z_reply_err_clone(dst, this_);
}
inline z_result_t z_clone(z_owned_sample_t* dst, const z_loaned_sample_t* this_) { return z_sample_clone(dst, this_); }
inline z_result_t z_clone(z_owned_slice_t* dst, const z_loaned_slice_t* this_) { return z_slice_clone(dst, this_); }
inline z_result_t z_clone(z_owned_string_t* dst, const z_loaned_string_t* this_) { return z_string_clone(dst, this_); }
inline z_result_t z_clone(z_owned_string_array_t* dst, const z_loaned_string_array_t* this_) {
    return z_string_array_clone(dst, this_);
}
inline z_result_t z_clone(z_owned_hello_t* dst, const z_loaned_hello_t* this_) { return z_hello_clone(dst, this_); }
#if Z_FEATURE_CONNECTIVITY == 1
inline z_result_t z_clone(z_owned_transport_t* dst, const z_loaned_transport_t* this_) {
    return z_transport_clone(dst, this_);
}
inline z_result_t z_clone(z_owned_link_t* dst, const z_loaned_link_t* this_) { return z_link_clone(dst, this_); }
inline z_result_t z_clone(z_owned_transport_event_t* dst, const z_loaned_transport_event_t* this_) {
    return z_transport_event_clone(dst, this_);
}
inline z_result_t z_clone(z_owned_link_event_t* dst, const z_loaned_link_event_t* this_) {
    return z_link_event_clone(dst, this_);
}
#endif

// z_take_from_loaned definition
inline z_result_t z_take_from_loaned(z_owned_bytes_t* dst, z_loaned_bytes_t* this_) {
    return z_bytes_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_config_t* dst, z_loaned_config_t* this_) {
    return z_config_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_encoding_t* dst, z_loaned_encoding_t* this_) {
    return z_encoding_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_keyexpr_t* dst, z_loaned_keyexpr_t* this_) {
    return z_keyexpr_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_query_t* dst, z_loaned_query_t* this_) {
    return z_query_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_reply_t* dst, z_loaned_reply_t* this_) {
    return z_reply_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_reply_err_t* dst, z_loaned_reply_err_t* this_) {
    return z_reply_err_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_sample_t* dst, z_loaned_sample_t* this_) {
    return z_sample_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_slice_t* dst, z_loaned_slice_t* this_) {
    return z_slice_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_string_t* dst, z_loaned_string_t* this_) {
    return z_string_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_string_array_t* dst, z_loaned_string_array_t* this_) {
    return z_string_array_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_hello_t* dst, z_loaned_hello_t* this_) {
    return z_hello_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_bytes_writer_t* dst, z_loaned_bytes_writer_t* this_) {
    return z_bytes_writer_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(ze_owned_serializer_t* dst, ze_loaned_serializer_t* this_) {
    return ze_serializer_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_cancellation_token_t* dst, z_loaned_cancellation_token_t* this_) {
    return z_cancellation_token_take_from_loaned(dst, this_);
}
#if Z_FEATURE_CONNECTIVITY == 1
inline z_result_t z_take_from_loaned(z_owned_transport_t* dst, z_loaned_transport_t* this_) {
    return z_transport_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_link_t* dst, z_loaned_link_t* this_) {
    return z_link_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_transport_event_t* dst, z_loaned_transport_event_t* this_) {
    return z_transport_event_take_from_loaned(dst, this_);
}
inline z_result_t z_take_from_loaned(z_owned_link_event_t* dst, z_loaned_link_event_t* this_) {
    return z_link_event_take_from_loaned(dst, this_);
}
#endif

template <class T>
struct z_loaned_to_owned_type_t {};
template <class T>
struct z_owned_to_loaned_type_t {};
template <>
struct z_loaned_to_owned_type_t<z_loaned_bytes_t> {
    typedef z_owned_bytes_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_bytes_t> {
    typedef z_loaned_bytes_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_config_t> {
    typedef z_owned_config_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_config_t> {
    typedef z_loaned_config_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_encoding_t> {
    typedef z_owned_encoding_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_encoding_t> {
    typedef z_loaned_encoding_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_reply_err_t> {
    typedef z_owned_reply_err_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_reply_err_t> {
    typedef z_loaned_reply_err_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_hello_t> {
    typedef z_owned_hello_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_hello_t> {
    typedef z_loaned_hello_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_keyexpr_t> {
    typedef z_owned_keyexpr_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_keyexpr_t> {
    typedef z_loaned_keyexpr_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_publisher_t> {
    typedef z_owned_publisher_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_publisher_t> {
    typedef z_loaned_publisher_t type;
};
template <>
struct z_loaned_to_owned_type_t<ze_loaned_advanced_publisher_t> {
    typedef ze_owned_advanced_publisher_t type;
};
template <>
struct z_owned_to_loaned_type_t<ze_owned_advanced_publisher_t> {
    typedef ze_loaned_advanced_publisher_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_querier_t> {
    typedef z_owned_querier_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_querier_t> {
    typedef z_loaned_querier_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_matching_listener_t> {
    typedef z_owned_matching_listener_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_matching_listener_t> {
    typedef z_loaned_matching_listener_t type;
};
template <>
struct z_loaned_to_owned_type_t<ze_loaned_sample_miss_listener_t> {
    typedef ze_owned_sample_miss_listener_t type;
};
template <>
struct z_owned_to_loaned_type_t<ze_owned_sample_miss_listener_t> {
    typedef ze_loaned_sample_miss_listener_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_query_t> {
    typedef z_owned_query_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_query_t> {
    typedef z_loaned_query_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_queryable_t> {
    typedef z_owned_queryable_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_queryable_t> {
    typedef z_loaned_queryable_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_liveliness_token_t> {
    typedef z_owned_liveliness_token_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_liveliness_token_t> {
    typedef z_loaned_liveliness_token_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_reply_t> {
    typedef z_owned_reply_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_reply_t> {
    typedef z_loaned_reply_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_sample_t> {
    typedef z_owned_sample_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_sample_t> {
    typedef z_loaned_sample_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_session_t> {
    typedef z_owned_session_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_session_t> {
    typedef z_loaned_session_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_slice_t> {
    typedef z_owned_slice_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_slice_t> {
    typedef z_loaned_slice_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_string_array_t> {
    typedef z_owned_string_array_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_string_array_t> {
    typedef z_loaned_string_array_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_string_t> {
    typedef z_owned_string_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_string_t> {
    typedef z_loaned_string_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_subscriber_t> {
    typedef z_owned_subscriber_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_subscriber_t> {
    typedef z_loaned_subscriber_t type;
};
template <>
struct z_loaned_to_owned_type_t<ze_loaned_advanced_subscriber_t> {
    typedef ze_owned_advanced_subscriber_t type;
};
template <>
struct z_owned_to_loaned_type_t<ze_owned_advanced_subscriber_t> {
    typedef ze_loaned_advanced_subscriber_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_sample_t> {
    typedef z_loaned_closure_sample_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_sample_t> {
    typedef z_owned_closure_sample_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_reply_t> {
    typedef z_loaned_closure_reply_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_reply_t> {
    typedef z_owned_closure_reply_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_query_t> {
    typedef z_loaned_closure_query_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_query_t> {
    typedef z_owned_closure_query_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_hello_t> {
    typedef z_loaned_closure_hello_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_hello_t> {
    typedef z_owned_closure_hello_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_zid_t> {
    typedef z_loaned_closure_zid_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_zid_t> {
    typedef z_owned_closure_zid_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_matching_status_t> {
    typedef z_loaned_closure_matching_status_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_matching_status_t> {
    typedef z_owned_closure_matching_status_t type;
};
template <>
struct z_owned_to_loaned_type_t<ze_owned_closure_miss_t> {
    typedef ze_loaned_closure_miss_t type;
};
template <>
struct z_loaned_to_owned_type_t<ze_loaned_closure_miss_t> {
    typedef ze_owned_closure_miss_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_fifo_handler_query_t> {
    typedef z_owned_fifo_handler_query_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_fifo_handler_query_t> {
    typedef z_loaned_fifo_handler_query_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_fifo_handler_reply_t> {
    typedef z_owned_fifo_handler_reply_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_fifo_handler_reply_t> {
    typedef z_loaned_fifo_handler_reply_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_fifo_handler_sample_t> {
    typedef z_owned_fifo_handler_sample_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_fifo_handler_sample_t> {
    typedef z_loaned_fifo_handler_sample_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_ring_handler_query_t> {
    typedef z_owned_ring_handler_query_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_ring_handler_query_t> {
    typedef z_loaned_ring_handler_query_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_ring_handler_reply_t> {
    typedef z_owned_ring_handler_reply_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_ring_handler_reply_t> {
    typedef z_loaned_ring_handler_reply_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_ring_handler_sample_t> {
    typedef z_owned_ring_handler_sample_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_ring_handler_sample_t> {
    typedef z_loaned_ring_handler_sample_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_bytes_writer_t> {
    typedef z_owned_bytes_writer_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_bytes_writer_t> {
    typedef z_loaned_bytes_writer_t type;
};
template <>
struct z_loaned_to_owned_type_t<ze_loaned_serializer_t> {
    typedef ze_owned_serializer_t type;
};
template <>
struct z_owned_to_loaned_type_t<ze_owned_serializer_t> {
    typedef ze_loaned_serializer_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_cancellation_token_t> {
    typedef z_owned_cancellation_token_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_cancellation_token_t> {
    typedef z_loaned_cancellation_token_t type;
};

#if Z_FEATURE_CONNECTIVITY == 1
template <>
struct z_loaned_to_owned_type_t<z_loaned_transport_t> {
    typedef z_owned_transport_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_transport_t> {
    typedef z_loaned_transport_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_link_t> {
    typedef z_owned_link_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_link_t> {
    typedef z_loaned_link_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_transport_event_t> {
    typedef z_owned_transport_event_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_transport_event_t> {
    typedef z_loaned_transport_event_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_link_event_t> {
    typedef z_owned_link_event_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_link_event_t> {
    typedef z_loaned_link_event_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_transport_events_listener_t> {
    typedef z_owned_transport_events_listener_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_transport_events_listener_t> {
    typedef z_loaned_transport_events_listener_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_link_events_listener_t> {
    typedef z_owned_link_events_listener_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_link_events_listener_t> {
    typedef z_loaned_link_events_listener_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_transport_t> {
    typedef z_owned_closure_transport_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_transport_t> {
    typedef z_loaned_closure_transport_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_link_t> {
    typedef z_owned_closure_link_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_link_t> {
    typedef z_loaned_closure_link_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_transport_event_t> {
    typedef z_owned_closure_transport_event_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_transport_event_t> {
    typedef z_loaned_closure_transport_event_t type;
};
template <>
struct z_loaned_to_owned_type_t<z_loaned_closure_link_event_t> {
    typedef z_owned_closure_link_event_t type;
};
template <>
struct z_owned_to_loaned_type_t<z_owned_closure_link_event_t> {
    typedef z_loaned_closure_link_event_t type;
};
#endif

#endif

#endif /* ZENOH_C_STANDARD != 99 */

#endif /* ZENOH_PICO_API_MACROS_H */
