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
#ifndef INCLUDE_ZENOH_PICO_API_ADVANCED_SUBSCRIBER_H
#define INCLUDE_ZENOH_PICO_API_ADVANCED_SUBSCRIBER_H

#include "olv_macros.h"
#include "zenoh-pico/api/liveliness.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/collections/hashmap.h"
#include "zenoh-pico/collections/refcount.h"
#include "zenoh-pico/collections/sortedmap.h"
#include "zenoh-pico/runtime/runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline size_t _z_uint32_size(const uint32_t *e) {
    _ZP_UNUSED(e);
    return sizeof(uint32_t);
}
static inline void _z_uint32_copy(uint32_t *dst, const uint32_t *src) { *dst = *src; }
static inline int _z_uint32_cmp(const uint32_t *left, const uint32_t *right) {
    if (*left < *right) return -1;
    if (*left > *right) return 1;
    return 0;
}
_Z_ELEM_DEFINE(_z_uint32, uint32_t, _z_uint32_size, _z_noop_clear, _z_uint32_copy, _z_noop_move, _z_noop_eq,
               _z_uint32_cmp, _z_noop_hash)
_Z_SORTEDMAP_DEFINE(_z_uint32, _z_sample, uint32_t, _z_sample_t)

_Z_SORTEDMAP_DEFINE(_z_timestamp, _z_sample, _z_timestamp_t, _z_sample_t)

typedef struct {
    _z_session_weak_t _zn;
    bool _has_last_delivered;
    uint32_t _last_delivered;
    uint64_t _pending_queries;
    _z_uint32__z_sample_sortedmap_t _pending_samples;
    _z_fut_handle_t _periodic_query_handle;
    z_owned_keyexpr_t _query_keyexpr;
} _ze_advanced_subscriber_sequenced_state_t;

static inline size_t _ze_advanced_subscriber_sequenced_state_size(_ze_advanced_subscriber_sequenced_state_t *s) {
    _ZP_UNUSED(s);
    return sizeof(_ze_advanced_subscriber_sequenced_state_t);
}
void _ze_advanced_subscriber_sequenced_state_clear(_ze_advanced_subscriber_sequenced_state_t *s);

_Z_ELEM_DEFINE(_ze_advanced_subscriber_sequenced_state, _ze_advanced_subscriber_sequenced_state_t,
               _ze_advanced_subscriber_sequenced_state_size, _ze_advanced_subscriber_sequenced_state_clear,
               _z_noop_copy, _z_noop_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)

typedef struct {
    bool _has_last_delivered;
    _z_timestamp_t _last_delivered;
    uint64_t _pending_queries;
    _z_timestamp__z_sample_sortedmap_t _pending_samples;
} _ze_advanced_subscriber_timestamped_state_t;

static inline size_t _ze_advanced_subscriber_timestamped_state_size(_ze_advanced_subscriber_timestamped_state_t *s) {
    _ZP_UNUSED(s);
    return sizeof(_ze_advanced_subscriber_timestamped_state_t);
}
void _ze_advanced_subscriber_timestamped_state_clear(_ze_advanced_subscriber_timestamped_state_t *s);

_Z_ELEM_DEFINE(_ze_advanced_subscriber_timestamped_state, _ze_advanced_subscriber_timestamped_state_t,
               _ze_advanced_subscriber_timestamped_state_size, _ze_advanced_subscriber_timestamped_state_clear,
               _z_noop_copy, _z_noop_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)

_Z_HASHMAP_DEFINE(_z_entity_global_id, _ze_advanced_subscriber_sequenced_state, _z_entity_global_id_t,
                  _ze_advanced_subscriber_sequenced_state_t)
_Z_HASHMAP_DEFINE(_z_id, _ze_advanced_subscriber_timestamped_state, z_id_t, _ze_advanced_subscriber_timestamped_state_t)

static inline _ze_closure_miss_t _ze_closure_miss_null(void) {
    _ze_closure_miss_t miss = {0};
    return miss;
}
static inline void _ze_closure_miss_drop(_ze_closure_miss_t *closure) {
    if (closure->drop != NULL) {
        closure->drop(closure->context);
    }
    *closure = _ze_closure_miss_null();
}

static inline void _ze_closure_miss_copy(_ze_closure_miss_t *dst, const _ze_closure_miss_t *src) { *dst = *src; }
static inline void _ze_closure_miss_move(_ze_closure_miss_t *dst, _ze_closure_miss_t *src) {
    *dst = *src;
    *src = _ze_closure_miss_null();
}

_Z_ELEM_DEFINE(_ze_closure_miss, _ze_closure_miss_t, _z_noop_size, _ze_closure_miss_drop, _ze_closure_miss_copy,
               _z_noop_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_INT_MAP_DEFINE(_ze_closure_miss, _ze_closure_miss_t)

typedef struct {
#if Z_FEATURE_MULTI_THREAD == 1
    z_owned_mutex_t _mutex;
#endif
    size_t _next_id;
    uint64_t _global_pending_queries;
    _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_t _sequenced_states;
    _z_id__ze_advanced_subscriber_timestamped_state_hashmap_t _timestamped_states;
    _z_session_weak_t _zn;
    z_owned_keyexpr_t _keyexpr;
    bool _retransmission;
    bool _has_period;
    uint64_t _period_ms;
    size_t _history_depth;
    uint64_t _history_age;
    z_query_target_t _query_target;
    uint64_t _query_timeout;
    _z_closure_sample_callback_t _callback;
    _z_drop_handler_t _dropper;
    void *_ctx;
    _ze_closure_miss_intmap_t _miss_handlers;
    bool _has_token;
    z_owned_liveliness_token_t _token;
    z_owned_cancellation_token_t _cancellation_token;
    bool _is_undeclaring;
} _ze_advanced_subscriber_state_t;

_ze_advanced_subscriber_state_t _ze_advanced_subscriber_state_null(void);
void _ze_advanced_subscriber_state_clear(_ze_advanced_subscriber_state_t *state);

_Z_REFCOUNT_DEFINE(_ze_advanced_subscriber_state, _ze_advanced_subscriber_state)

typedef struct {
    z_owned_subscriber_t _subscriber;
    bool _has_liveliness_subscriber;
    z_owned_subscriber_t _liveliness_subscriber;
    bool _has_heartbeat_subscriber;
    z_owned_subscriber_t _heartbeat_subscriber;
    _ze_advanced_subscriber_state_rc_t _state;
} _ze_advanced_subscriber_t;

_Z_OWNED_TYPE_VALUE_PREFIX(ze, _ze_advanced_subscriber_t, advanced_subscriber)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_TAKE_FROM_LOANED_DEF_PREFIX(ze, advanced_subscriber)

typedef struct {
    size_t _id;
    _ze_advanced_subscriber_state_weak_t _statesref;
} _ze_sample_miss_listener_t;

static inline _ze_sample_miss_listener_t _ze_sample_miss_listener_null(void) { return (_ze_sample_miss_listener_t){0}; }
static inline bool _ze_sample_miss_listener_check(const _ze_sample_miss_listener_t *miss_listener) {
    return !_Z_SIMPLE_RC_IS_NULL(&miss_listener->_statesref);
}

_Z_OWNED_TYPE_VALUE_PREFIX(ze, _ze_sample_miss_listener_t, sample_miss_listener)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_TAKE_FROM_LOANED_DEF_PREFIX(ze, sample_miss_listener)

#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_ADVANCED_SUBSCRIPTION == 1

/**
 * Settings for retrieving historical data for Advanced Subscriber.
 *
 * Members:
 *   bool is_enabled: Must be set to ``true``, to enable the history data recovery.
 *   bool detect_late_publishers: Enable detection of late joiner publishers and query for
 *     their historical data. Late joiner detection can only be achieved for Publishers that
 *     enable publisher_detection. History can only be retransmitted by Publishers that enable
 *     caching.
 *   size_t max_samples: Number of samples to query for each resource. ``0`` corresponds to no
 *     limit on number of samples.
 *   uint64_t max_age_ms: Maximum age of samples to query. ``0`` corresponds to no limit on samples'
 *     age.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    bool is_enabled;
    bool detect_late_publishers;
    size_t max_samples;
    uint64_t max_age_ms;
} ze_advanced_subscriber_history_options_t;

/**
 * Settings for detection of the last sample(s) miss by Advanced Subscriber.
 *
 * Members:
 *   bool is_enabled: Must be set to ``true``, to enable the last sample(s) miss detection.
 *   uint64_t periodic_queries_period_ms: Period for queries for not yet received Samples.
 *     These queries allow to retrieve the last Sample(s) if the last Sample(s) is/are lost.
 *     So it is useful for sporadic publications but useless for periodic publications with a
 *     period smaller or equal to this period. If set to 0, the last sample(s) miss detection
 *     will be performed based on publisher's heartbeat if the latter is enabled.
 *
 * Note: periodic queries require the periodic scheduler to be started via :c:func:`zp_start_periodic_scheduler_task`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    bool is_enabled;
    uint64_t periodic_queries_period_ms;
} ze_advanced_subscriber_last_sample_miss_detection_options_t;

/**
 * Settings for recovering lost messages for Advanced Subscriber.
 *
 * Members:
 *   bool is_enabled: Must be set to ``true``, to enable the lost sample recovery.
 *   ze_advanced_subscriber_last_sample_miss_detection_options_t last_sample_miss_detection:
 *     Setting for detecting last sample(s) miss. Note that it does not affect intermediate sample
 *     miss detection/retrieval (which is performed automatically as long as recovery is enabled).
 *     If this option is disabled, subscriber will be unable to detect/request retransmission of
 *     missed sample until it receives a more recent one from the same publisher.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    bool is_enabled;
    ze_advanced_subscriber_last_sample_miss_detection_options_t last_sample_miss_detection;
} ze_advanced_subscriber_recovery_options_t;

/**
 * Represents the set of options that can be applied to an advanced subscriber,
 * upon its declaration via :c:func:`ze_declare_advanced_subscriber`.
 *
 * Members:
 *   z_subscriber_options_t subscriber_options: Base subscriber options.
 *   ze_advanced_subscriber_history_options_t history: Settings for querying historical data.
 *     History can only be retransmitted by Publishers that enable caching.
 *   ze_advanced_subscriber_recovery_options_t recovery: Settings for retransmission of detected
 *     lost Samples. Retransmission of lost samples can only be done by Publishers that enable
 *     caching and sample_miss_detection.
 *   uint64_t query_timeout_ms: Timeout to be used for history and recovery queries.  Default value
 *     will be used if set to ``0``.
 *   bool subscriber_detection: Allow this subscriber to be detected through liveliness.
 *   const z_loaned_keyexpr_t *subscriber_detection_metadata: An optional key expression to be added
 *     to the liveliness token key expression. It can be used to convey meta data.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    z_subscriber_options_t subscriber_options;
    ze_advanced_subscriber_history_options_t history;
    ze_advanced_subscriber_recovery_options_t recovery;
    uint64_t query_timeout_ms;
    bool subscriber_detection;
    const z_loaned_keyexpr_t *subscriber_detection_metadata;
} ze_advanced_subscriber_options_t;

/**
 * Declares an advanced subscriber for a given keyexpr. Note that dropping the subscriber drops its
 * callback.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the advanced subscriber through.
 *   subscriber: Pointer to an uninitialized :c:type:`ze_owned_advanced_subscriber_t`.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to subscribe to.
 *   callback: Pointer to a :c:type:`z_moved_closure_sample_t` that will be called each time a data
 *     matching the subscribed expression is received.
 *   options: Pointer to a :c:type:`ze_advanced_subscriber_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_declare_advanced_subscriber(const z_loaned_session_t *zs, ze_owned_advanced_subscriber_t *subscriber,
                                          const z_loaned_keyexpr_t *keyexpr, z_moved_closure_sample_t *callback,
                                          ze_advanced_subscriber_options_t *options);

/**
 * Declares a background advanced subscriber. Subscriber callback will be called to process the messages,
 * until the corresponding session is closed or dropped.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the advanced subscriber through.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to subscribe to.
 *   callback: Pointer to a :c:type:`z_moved_closure_sample_t` that will be called each time a data
 *     matching the subscribed expression is received.
 *   options: Pointer to a :c:type:`ze_advanced_subscriber_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_declare_background_advanced_subscriber(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                                     z_moved_closure_sample_t *callback,
                                                     ze_advanced_subscriber_options_t *options);

/**
 * Undeclares the advanced subscriber.
 *
 * Parameters:
 *   subscriber: Moved :c:type:`ze_owned_advanced_subscriber_t` to undeclare.
 *
 * Return:
 *   ``0`` if undeclare is successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_undeclare_advanced_subscriber(ze_moved_advanced_subscriber_t *subscriber);

/**
 * Gets the keyexpr from an advanced subscriber.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`ze_loaned_advanced_subscriber_t` to get the keyexpr from.
 *
 * Return:
 *   The keyexpr wrapped as a :c:type:`z_loaned_keyexpr_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
const z_loaned_keyexpr_t *ze_advanced_subscriber_keyexpr(const ze_loaned_advanced_subscriber_t *subscriber);

/**
 * Gets the entity global Id from an advanced subscriber.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`ze_loaned_advanced_subscriber_t` to get the entity global Id from.
 *
 * Return:
 *   The entity gloabl Id wrapped as a :c:type:`z_entity_global_global_id_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_entity_global_id_t ze_advanced_subscriber_id(const ze_loaned_advanced_subscriber_t *subscriber);

/**
 * Declares a sample miss listener, registering a callback for notifying subscriber about missed samples.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`ze_loaned_advanced_subscriber_t` instance to associate with sample miss listener.
 *   sample_miss_listener: Pointer to an uninitialized :c:type:`ze_owned_sample_miss_listener_t` where sample miss
 *     listener will be constructed. The sample miss listener's callback will be automatically dropped when the
 * subscriber is dropped. callback: Pointer to a :c:type:`ze_moved_closure_miss_t` that will be called every time a
 * sample miss is detected.
 *
 * Return:
 *   ``0`` if successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_subscriber_declare_sample_miss_listener(const ze_loaned_advanced_subscriber_t *subscriber,
                                                               ze_owned_sample_miss_listener_t *sample_miss_listener,
                                                               ze_moved_closure_miss_t *callback);

/**
 * Declares a sample miss listener, registering a callback for notifying subscriber about missed samples.
 * The callback will be run in the background until the corresponding subscriber is dropped.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`ze_loaned_advanced_subscriber_t` instance to associate with sample miss listener.
 *   callback: Pointer to a :c:type:`ze_moved_closure_miss_t` that will be called every time a sample miss is detected.
 *
 * Return:
 *   ``0`` if successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_subscriber_declare_background_sample_miss_listener(
    const ze_loaned_advanced_subscriber_t *subscriber, ze_moved_closure_miss_t *callback);

/**
 * Undeclares the given sample miss listener, droping and invalidating it.
 *
 * Parameters:
 *   sample_miss_listener: Moved :c:type:`ze_moved_sample_miss_listener_t` to undeclare
 *
 * Return:
 *   ``0`` if successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_undeclare_sample_miss_listener(ze_moved_sample_miss_listener_t *sample_miss_listener);

/**
 * Declares a liveliness token listener for matching publishers detection. Only advanced publishers, enabling publisher
 * detection can be detected.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`ze_loaned_advanced_subscriber_t` instance.
 *   liveliness_subscriber: Pointer to an uninitialized :c:type:`z_owned_subscriber_t` where the liveliness subscriber
 *     will be constructed.
 *   callback: Pointer to a :c:type:`z_moved_closure_sample_t` that will be called each time a liveliness token status
 *     is changed.
 *   options: Pointer to a :c:type:`z_liveliness_subscriber_options_t` to configure the liveliness subscriber.
 *
 * Return:
 *   ``0`` if successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_subscriber_detect_publishers(const ze_loaned_advanced_subscriber_t *subscriber,
                                                    z_owned_subscriber_t *liveliness_subscriber,
                                                    z_moved_closure_sample_t *callback,
                                                    z_liveliness_subscriber_options_t *options);

/**
 * Declares a background subscriber on liveliness tokens of matching publishers. Subscriber callback will be called to
 * process the messages, until the corresponding session is closed or dropped. Only advanced publishers, enabling
 * publisher detection can be detected.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`ze_loaned_advanced_subscriber_t` instance.
 *   callback: Pointer to a :c:type:`z_moved_closure_sample_t` that will be called each time a liveliness token status
 *     is changed.
 *   options: Pointer to a :c:type:`z_liveliness_subscriber_options_t` to configure the liveliness subscriber.
 *
 * Return:
 *   ``0`` if successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_subscriber_detect_publishers_background(const ze_loaned_advanced_subscriber_t *subscriber,
                                                               z_moved_closure_sample_t *callback,
                                                               z_liveliness_subscriber_options_t *options);

/**
 * Builds a :c:type:`ze_advanced_subscriber_history_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_subscriber_history_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_subscriber_history_options_default(ze_advanced_subscriber_history_options_t *options);

/**
 * Builds a :c:type:`ze_advanced_subscriber_recovery_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_subscriber_recovery_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_subscriber_recovery_options_default(ze_advanced_subscriber_recovery_options_t *options);

/**
 * Builds a :c:type:`ze_advanced_subscriber_last_sample_miss_detection_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_subscriber_last_sample_miss_detection_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_subscriber_last_sample_miss_detection_options_default(
    ze_advanced_subscriber_last_sample_miss_detection_options_t *options);

/**
 * Builds a :c:type:`ze_advanced_subscriber_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_subscriber_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_subscriber_options_default(ze_advanced_subscriber_options_t *options);

#endif  // Z_FEATURE_ADVANCED_SUBSCRIPTION == 1
#endif  // Z_FEATURE_UNSTABLE_API

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_ZENOH_PICO_API_ADVANCED_SUBSCRIBER_H
