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
#ifndef INCLUDE_ZENOH_PICO_API_ADVANCED_PUBLISHER_H
#define INCLUDE_ZENOH_PICO_API_ADVANCED_PUBLISHER_H

#include <stdbool.h>

#include "olv_macros.h"
#include "zenoh-pico/api/liveliness.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/collections/advanced_cache.h"
#include "zenoh-pico/collections/atomic.h"
#include "zenoh-pico/collections/seqnumber.h"
#include "zenoh-pico/runtime/runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    _ZE_ADVANCED_PUBLISHER_SEQUENCING_NONE = 0,
    _ZE_ADVANCED_PUBLISHER_SEQUENCING_TIMESTAMP = 1,
    _ZE_ADVANCED_PUBLISHER_SEQUENCING_SEQUENCE_NUMBER = 2
} _ze_advanced_publisher_sequencing_t;

/**
 * Whatami values, defined as a bitmask.
 *
 * Enumerators:
 *   ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE: Disable heartbeat-based last sample miss detection.
 *   ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_PERIODIC: Allow last sample miss detection through periodic
 *     heartbeat. Periodically send the last published Sample's sequence number to allow last sample recovery.
 *   ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_SPORADIC: Allow last sample miss detection through sporadic
 *     heartbeat. Each period, the last published Sample's sequence number is sent with
 *     `Z_CONGESTION_CONTROL_DROP` but only if it changed since last period.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef enum {
    ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE,
    ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_PERIODIC,
    ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_SPORADIC,
} ze_advanced_publisher_heartbeat_mode_t;
#define ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_DEFAULT ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE

typedef struct _ze_advanced_publisher_state_t {
    _z_atomic_size_t _seqnumber;
    ze_advanced_publisher_heartbeat_mode_t _heartbeat_mode;
    _z_session_weak_t _zn;
    z_owned_publisher_t _publisher;
    _z_fut_handle_t _state_publisher_task_handle;
    uint64_t _heartbeat_period_ms;
    uint32_t _last_published_sn;
} _ze_advanced_publisher_state_t;

void _ze_advanced_publisher_state_clear(_ze_advanced_publisher_state_t *state);

_Z_REFCOUNT_DEFINE_NO_FROM_VAL(_ze_advanced_publisher_state, _ze_advanced_publisher_state)

typedef struct {
    z_owned_publisher_t _publisher;
    _ze_advanced_cache_t *_cache;
    bool _has_liveliness;
    z_owned_liveliness_token_t _liveliness;
    _ze_advanced_publisher_sequencing_t _sequencing;
    _ze_advanced_publisher_state_rc_t _state;
} _ze_advanced_publisher_t;

_Z_OWNED_TYPE_VALUE_PREFIX(ze, _ze_advanced_publisher_t, advanced_publisher)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_TAKE_FROM_LOANED_DEF_PREFIX(ze, advanced_publisher)

#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_ADVANCED_PUBLICATION == 1

/**************** Advanced Publisher ****************/

/**
 * Represents the set of options for sample miss detection on an advanced publisher.
 *
 * Members:
 *   bool is_enabled: Must be set to ``true``, to enable sample miss detection by adding
 *     sequence numbers.
 *   enum ze_advanced_publisher_heartbeat_mode_t heartbeat_mode: Allow last sample miss
 *     detection through sporadic or periodic heartbeat.
 *   uint64_t heartbeat_period_ms: If heartbeat_mode is not ``NONE``, the publisher will send
 *     heartbeats with the specified period, which can be used by Advanced Subscribers for last
 *     sample(s) miss detection (if last sample miss detection with zero query period is enabled).
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    bool is_enabled;
    ze_advanced_publisher_heartbeat_mode_t heartbeat_mode;
    uint64_t heartbeat_period_ms;
} ze_advanced_publisher_sample_miss_detection_options_t;

/**
 * Represents the set of options that can be applied to an advanced publisher,
 * upon its declaration via :c:func:`ze_declare_advanced_publisher`.
 *
 * Members:
 *   z_publisher_options_t publisher_options: Base publisher options.
 *   ze_advanced_publisher_cache_options_t cache: Publisher cache settings.
 *   ze_advanced_publisher_sample_miss_detection_options_t sample_miss_detection: Allow
 *     matching Subscribers to detect lost samples and optionally ask for retransmission.
 *     Retransmission can only be done if history is enabled on subscriber side.
 *   bool publisher_detection: Allow this publisher to be detected through liveliness.
 *   z_loaned_keyexpr_t *publisher_detection_metadata: An optional key expression to be added
 *     to the liveliness token key expression. It can be used to convey meta data.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    z_publisher_options_t publisher_options;
    ze_advanced_publisher_cache_options_t cache;
    ze_advanced_publisher_sample_miss_detection_options_t sample_miss_detection;
    bool publisher_detection;
    z_loaned_keyexpr_t *publisher_detection_metadata;
} ze_advanced_publisher_options_t;

/**
 * Builds a :c:type:`ze_advanced_publisher_cache_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_publisher_cache_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_publisher_cache_options_default(ze_advanced_publisher_cache_options_t *options);

/**
 * Builds a :c:type:`ze_advanced_publisher_sample_miss_detection_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_publisher_sample_miss_detection_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_publisher_sample_miss_detection_options_default(
    ze_advanced_publisher_sample_miss_detection_options_t *options);

/**
 * Builds a :c:type:`ze_advanced_publisher_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_publisher_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_publisher_options_default(ze_advanced_publisher_options_t *options);

/**
 * Declares an advanced publisher for a given keyexpr.
 *
 * Data can be put and deleted with this advanced publisher with the help of the
 * :c:func:`ze_advanced_publisher_put` and :c:func:`ze_advanced_publisher_delete` functions.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the advanced publisher through.
 *   pub: Pointer to an uninitialized :c:type:`ze_owned_advanced_publisher_t`.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the advanced publisher with.
 *   options: Pointer to a :c:type:`ze_advanced_publisher_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_declare_advanced_publisher(const z_loaned_session_t *zs, ze_owned_advanced_publisher_t *pub,
                                         const z_loaned_keyexpr_t *keyexpr,
                                         const ze_advanced_publisher_options_t *options);

/**
 * Undeclares the advanced publisher.
 *
 * Parameters:
 *   pub: Moved :c:type:`ze_owned_advanced_publisher_t` to undeclare.
 *
 * Return:
 *   ``0`` if undeclare is successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_undeclare_advanced_publisher(ze_moved_advanced_publisher_t *pub);

/**
 * Represents the set of options passed to the `ze_advanced_publisher_put()` function.
 *
 * Members:
 *   z_publisher_put_options_t put_options: Base put options.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    z_publisher_put_options_t put_options;
} ze_advanced_publisher_put_options_t;

/**
 * Builds a :c:type:`ze_advanced_publisher_put_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_publisher_put_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_publisher_put_options_default(ze_advanced_publisher_put_options_t *options);

/**
 * Represents the set of options passed to the `ze_advanced_publisher_delete()` function.
 *
 * Members:
 *   z_publisher_delete_options_t delete_options: Base delete options.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    z_publisher_delete_options_t delete_options;
} ze_advanced_publisher_delete_options_t;

/**
 * Builds a :c:type:`ze_advanced_publisher_delete_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`ze_advanced_publisher_delete_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_advanced_publisher_delete_options_default(ze_advanced_publisher_delete_options_t *options);

/**
 * Puts data for the keyexpr bound to the given advanced publisher.
 *
 * Parameters:
 *   pub: Pointer to a :c:type:`ze_loaned_advanced_publisher_t` from where to put the data.
 *   payload: Moved :c:type:`z_owned_bytes_t` containing the data to put.
 *   options: Pointer to a :c:type:`ze_advanced_publisher_put_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_publisher_put(const ze_loaned_advanced_publisher_t *pub, z_moved_bytes_t *payload,
                                     const ze_advanced_publisher_put_options_t *options);

/**
 * Deletes data from the keyexpr bound to the given advanced publisher.
 *
 * Parameters:
 *   pub: Pointer to a :c:type:`ze_loaned_advanced_publisher_t` from where to delete the data.
 *   options: Pointer to a :c:type:`ze_advanced_publisher_delete_options_t` to configure the delete operation.
 *
 * Return:
 *   ``0`` if delete operation is successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_publisher_delete(const ze_loaned_advanced_publisher_t *pub,
                                        const ze_advanced_publisher_delete_options_t *options);

/**
 * Gets the keyexpr from an advanced publisher.
 *
 * Parameters:
 *   publisher: Pointer to a :c:type:`ze_loaned_advanced_publisher_t` to get the keyexpr from.
 *
 * Return:
 *   The keyexpr wrapped as a :c:type:`z_loaned_keyexpr_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
const z_loaned_keyexpr_t *ze_advanced_publisher_keyexpr(const ze_loaned_advanced_publisher_t *pub);

/**
 * Gets the entity global Id from an advanced publisher.
 *
 * Parameters:
 *   publisher: Pointer to a :c:type:`ze_loaned_advanced_publisher_t` to get the entity global Id from.
 *
 * Return:
 *   The entity global Id wrapped as a :c:type:`z_entity_global_global_id_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_entity_global_id_t ze_advanced_publisher_id(const ze_loaned_advanced_publisher_t *pub);

#if Z_FEATURE_MATCHING == 1
/**
 * Gets advanced publisher matching status - i.e. if there are any subscribers matching its key expression.
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_publisher_get_matching_status(const ze_loaned_advanced_publisher_t *publisher,
                                                     z_matching_status_t *matching_status);

/**
 * Constructs matching listener, registering a callback for notifying subscribers matching with a given advanced
 * publisher.
 *
 * Parameters:
 *   publisher: An advanced publisher to associate with matching listener.
 *   matching_listener: An uninitialized memory location where matching listener will be constructed. The matching
 *     listener's callback will be automatically dropped when the publisher is dropped.
 *   callback: A closure that will be called every time the matching status of the publisher changes (If last subscriber
 *     disconnects or when the first subscriber connects).
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_publisher_declare_matching_listener(const ze_loaned_advanced_publisher_t *publisher,
                                                           z_owned_matching_listener_t *matching_listener,
                                                           z_moved_closure_matching_status_t *callback);

/**
 * Declares a matching listener, registering a callback for notifying subscribers matching with a given advanced
 * publisher. The callback will be run in the background until the corresponding advanced publisher is dropped.
 *
 * Parameters:
 *   publisher: An advanced publisher to associate with matching listener.
 *   callback: A closure that will be called every time the matching status of the publisher changes (If last subscriber
 *     disconnects or when the first subscriber connects).
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_advanced_publisher_declare_background_matching_listener(const ze_loaned_advanced_publisher_t *publisher,
                                                                      z_moved_closure_matching_status_t *callback);
#endif  // Z_FEATURE_MATCHING == 1
#endif  // Z_FEATURE_ADVANCED_PUBLICATION == 1
#endif  // Z_FEATURE_UNSTABLE_API

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_ZENOH_PICO_API_ADVANCED_PUBLISHER_H
