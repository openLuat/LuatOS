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
//   Błażej Sowa, <blazej@fictionlab.pl>
//
#ifndef INCLUDE_ZENOH_PICO_API_TYPES_H
#define INCLUDE_ZENOH_PICO_API_TYPES_H

#include "olv_macros.h"
#include "zenoh-pico/collections/bytes.h"
#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/list.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/net/encoding.h"
#include "zenoh-pico/net/matching.h"
#include "zenoh-pico/net/publish.h"
#include "zenoh-pico/net/query.h"
#include "zenoh-pico/net/reply.h"
#include "zenoh-pico/net/sample.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/net/subscribe.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/cancellation.h"
#include "zenoh-pico/session/session.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Represents a Zenoh ID.
 *
 * In general, valid Zenoh IDs are LSB-first 128bit unsigned and non-zero integers.
 *
 * Members:
 *   uint8_t id[16]: The array containing the 16 octets of a Zenoh ID.
 */
typedef _z_id_t z_id_t;

/**
 *  Represents an ID globally identifying an entity in a Zenoh system.
 */
typedef _z_entity_global_id_t z_entity_global_id_t;

/*
 * Represents timestamp value in Zenoh
 */
typedef _z_timestamp_t z_timestamp_t;

/**
 * Represents an array of bytes.
 */
_Z_OWNED_TYPE_VALUE(_z_slice_t, slice)
_Z_VIEW_TYPE(_z_slice_t, slice)

/**
 * Represents a container for slices.
 */
_Z_OWNED_TYPE_VALUE(_z_bytes_t, bytes)

/**
 * Represents a writer for data.
 */
_Z_OWNED_TYPE_VALUE(_z_bytes_writer_t, bytes_writer)

/**
 * A reader for data.
 */
typedef _z_bytes_reader_t z_bytes_reader_t;

/**
 * An iterator over slices of data.
 */
typedef struct {
    const _z_bytes_t *_bytes;
    size_t _slice_idx;
} z_bytes_slice_iterator_t;

/**
 * Represents a string without null-terminator.
 */
_Z_OWNED_TYPE_VALUE(_z_string_t, string)
_Z_VIEW_TYPE(_z_string_t, string)

/**
 * Represents a key expression in Zenoh.
 */
_Z_OWNED_TYPE_VALUE(_z_declared_keyexpr_t, keyexpr)
_Z_VIEW_TYPE(_z_declared_keyexpr_t, keyexpr)

/**
 * Represents a Zenoh configuration, used to configure Zenoh sessions upon opening.
 */
_Z_OWNED_TYPE_VALUE(_z_config_t, config)

/**
 * Represents a Zenoh Session.
 */
_Z_OWNED_TYPE_RC(_z_session_rc_t, session)

/**
 * Represents a Zenoh Subscriber entity.
 */
_Z_OWNED_TYPE_VALUE(_z_subscriber_t, subscriber)

/**
 * Represents a Zenoh Publisher entity.
 */
_Z_OWNED_TYPE_VALUE(_z_publisher_t, publisher)

/**
 * Represents a Zenoh Querier entity.
 */
_Z_OWNED_TYPE_VALUE(_z_querier_t, querier)

/**
 * Represents a Zenoh Matching listener entity.
 */
_Z_OWNED_TYPE_VALUE(_z_matching_listener_t, matching_listener)

/**
 * Represents a Zenoh Queryable entity.
 */
_Z_OWNED_TYPE_VALUE(_z_queryable_t, queryable)

/**
 * Represents a Zenoh Query entity, received by Zenoh Queryable entities.
 */
_Z_OWNED_TYPE_RC(_z_query_rc_t, query)

/**
 * Represents the encoding of a payload, in a MIME-like format.
 */
_Z_OWNED_TYPE_VALUE(_z_encoding_t, encoding)

/**
 * Represents a Zenoh reply error.
 */
_Z_OWNED_TYPE_VALUE(_z_value_t, reply_err)

/**
 * Represents sample source information.
 */
typedef _z_source_info_t z_source_info_t;

/**
 * A struct that indicates if there exist Subscribers matching the Publisher's key expression or Queryables matching
 * Querier's key expression and target.
 * Members:
 *   bool matching: true if there exist matching Zenoh entities, false otherwise.
 */
typedef _z_matching_status_t z_matching_status_t;

/**
 * Represents the configuration used to configure a subscriber upon declaration :c:func:`z_declare_subscriber`.
 */
typedef struct {
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    z_locality_t allowed_origin;
#else
    uint8_t __dummy;  // keep struct non-empty when locality is disabled
#endif
} z_subscriber_options_t;

/**
 * Represents the configuration used to configure a zenoh upon opening :c:func:`z_open`.
 *
 * Members:
 *   bool auto_start_read_task: Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are
 * now started automatically when session is created.
 *   bool auto_start_lease_task: Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started
 * automatically when session is created.
 *   z_task_attr_t* executor_task_attributes: the attributes to pass to zenoh session executor thread running read,
 * lease, keep alive, join, connect and other tasks in the background (only when Z_FEATURE_MULTI_THREAD is enabled).
 *   bool auto_start_admin_space: auto-start admin space after ``z_open()`` (default
 * false; only when admin space feature is enabled).
 */
typedef struct {
#if Z_FEATURE_MULTI_THREAD == 1
    bool auto_start_read_task;
    bool auto_start_lease_task;
    z_task_attr_t *executor_task_attributes;
#endif
#if (Z_FEATURE_ADMIN_SPACE == 1)
    bool auto_start_admin_space;
#endif
#if Z_FEATURE_ADMIN_SPACE == 0 && (Z_FEATURE_MULTI_THREAD == 0)
    uint8_t __dummy;  // avoid empty struct
#endif
} z_open_options_t;

/**
 * Represents the configuration used to configure a zenoh upon closing :c:func:`z_close`.
 */
typedef struct {
    uint8_t __dummy;  // Just to avoid empty structures that might cause undefined behavior
} z_close_options_t;

/**
 * Represents the reply consolidation mode to apply on replies to a :c:func:`z_get`.
 *
 * Members:
 *   z_consolidation_mode_t mode: the consolidation mode, see :c:type:`z_consolidation_mode_t`
 */
typedef struct {
    z_consolidation_mode_t mode;
} z_query_consolidation_t;

/**
 * A cancellation token used to interrupt get requests (unstable).
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
_Z_OWNED_TYPE_RC(_z_cancellation_token_rc_t, cancellation_token)

/**
 * Represents the configuration used to configure a publisher upon declaration with :c:func:`z_declare_publisher`.
 *
 * Members:
 *   z_moved_encoding_t *encoding: Default encoding for messages put by this publisher.
 *   z_congestion_control_t congestion_control: The congestion control to apply when routing messages from this
 *     publisher.
 *   z_priority_t priority: The priority of messages issued by this publisher.
 *   bool is_express: If ``true``, Zenoh will not wait to batch this operation with others to reduce the bandwidth.
 *   z_reliability_t reliability: The reliability that should be used to transmit the data (unstable).
 */
typedef struct {
    z_moved_encoding_t *encoding;
    z_congestion_control_t congestion_control;
    z_priority_t priority;
    bool is_express;
#ifdef Z_FEATURE_UNSTABLE_API
    z_reliability_t reliability;
#endif
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    z_locality_t allowed_destination;
#endif
} z_publisher_options_t;

/**
 * Options passed to the :c:func:`z_declare_querier()` function.
 *
 * Members:
 *   z_moved_encoding_t *encoding: Default encoding for values sent by this querier.
 *   z_query_target_t target: The Queryables that should be target of the querier queries.
 *   z_query_consolidation_t consolidation: The replies consolidation strategy to apply on replies to the querier
 *     queries.
 *   z_congestion_control_t congestion_control: The congestion control to apply when routing the querier queries.
 *   bool is_express: If set to ``true``, the querier queries will not be batched. This usually has a positive impact on
 *     latency but negative impact on throughput.
 *   z_priority_t priority: The priority of the querier queries.
 *   uint64_t timeout_ms: The timeout for the querier queries in milliseconds. 0 corresponds to default get request
 *     timeout.
 *   z_reply_keyexpr_t accept_replies: The accepted replies for the querier queries.
 */
typedef struct z_querier_options_t {
    z_moved_encoding_t *encoding;
    z_query_target_t target;
    z_query_consolidation_t consolidation;
    z_congestion_control_t congestion_control;
    bool is_express;
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    z_locality_t allowed_destination;
#endif
    z_priority_t priority;
    uint64_t timeout_ms;
    z_reply_keyexpr_t accept_replies;
} z_querier_options_t;

/**
 * Options passed to the :c:func:`z_querier_get()` function.
 *
 * Members:
 *   z_moved_bytes_t *payload: An optional payload to attach to the query.
 *   z_moved_encoding_t *encoding: An optional encoding of the query payload and or attachment.
 *   z_moved_bytes_t *attachment: An optional attachment to attach to the query.
 *   z_source_info_t* source_info: The source info for the request (unstable).
 *   z_moved_cancellation_token_t *cancellation_token: Token to allow cancelling get operation (unstable).
 */
typedef struct z_querier_get_options_t {
    z_moved_bytes_t *payload;
    z_moved_encoding_t *encoding;
    z_moved_bytes_t *attachment;
#ifdef Z_FEATURE_UNSTABLE_API
    z_moved_cancellation_token_t *cancellation_token;
    z_source_info_t *source_info;
#endif
} z_querier_get_options_t;

/**
 * Represents the configuration used to configure a queryable upon declaration :c:func:`z_declare_queryable`.
 *
 * Members:
 *   bool complete: The completeness of the queryable.
 */
typedef struct {
    bool complete;
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    z_locality_t allowed_origin;
#endif
} z_queryable_options_t;

/**
 * Represents the configuration used to configure a query reply sent via :c:func:`z_query_reply`.
 *
 * Members:
 *   z_moved_encoding_t* encoding: The encoding of the payload.
 *   z_congestion_control_t congestion_control: **Deprecated**. This field is ignored.
 *     Congestion control for replies is taken from the query.
 *   z_priority_t priority: **Deprecated**. This field is ignored.
 *     Priority for replies is taken from the query.
 *   z_timestamp_t *timestamp: The API level timestamp (e.g. of the data when it was created).
 *   bool is_express: If ``true``, Zenoh will not wait to batch this operation with others to reduce the bandwidth.
 *   z_moved_bytes_t* attachment: An optional attachment to the response.
 *   z_source_info_t* source_info: The source info for the message (unstable).
 */
typedef struct {
    z_moved_encoding_t *encoding;
    z_congestion_control_t congestion_control;  // Deprecated: ignored, taken from query
    z_priority_t priority;                      // Deprecated: ignored, taken from query
    z_timestamp_t *timestamp;
    bool is_express;
    z_moved_bytes_t *attachment;
#ifdef Z_FEATURE_UNSTABLE_API
    z_source_info_t *source_info;
#endif
} z_query_reply_options_t;

/**
 * Represents the configuration used to configure a query reply delete sent via :c:func:`z_query_reply_del`.
 *
 * Members:
 *   z_congestion_control_t congestion_control: **Deprecated**. This field is ignored.
 *     Congestion control for replies is taken from the query.
 *   z_priority_t priority: **Deprecated**. This field is ignored.
 *     Priority for replies is taken from the query.
 *   z_timestamp_t *timestamp: The API level timestamp (e.g. of the data when it was created).
 *   bool is_express: If ``true``, Zenoh will not wait to batch this operation with others to reduce the bandwidth.
 *   z_moved_bytes_t* attachment: An optional attachment to the response.
 *   z_source_info_t* source_info: The source info for the message (unstable).
 */
typedef struct {
    z_congestion_control_t congestion_control;  // Deprecated: ignored, taken from query
    z_priority_t priority;                      // Deprecated: ignored, taken from query
    z_timestamp_t *timestamp;
    bool is_express;
    z_moved_bytes_t *attachment;
#ifdef Z_FEATURE_UNSTABLE_API
    z_source_info_t *source_info;
#endif
} z_query_reply_del_options_t;

/**
 * Represents the configuration used to configure a query reply error sent via :c:func:`z_query_reply_err`.
 *
 * Members:
 *   z_moved_encoding_t* encoding: The encoding of the payload.
 */
typedef struct {
    z_moved_encoding_t *encoding;
} z_query_reply_err_options_t;

/**
 * Represents the configuration used to configure a put operation sent via :c:func:`z_put`.
 *
 * Members:
 *   z_moved_encoding_t* encoding: The encoding of the payload.
 *   z_congestion_control_t congestion_control: The congestion control to apply when routing this message.
 *   z_priority_t priority: The priority of this message when routed.
 *   z_timestamp_t *timestamp: The API level timestamp (e.g. of the data when it was created).
 *   bool is_express: If ``true``, Zenoh will not wait to batch this operation with others to reduce the bandwidth.
 *   z_moved_bytes_t* attachment: An optional attachment to the publication.
 *   z_reliability_t reliability: The reliability that should be used to transmit the data (unstable).
 *   z_source_info_t* source_info: The source info for the message (unstable).
 */
typedef struct {
    z_moved_encoding_t *encoding;
    z_congestion_control_t congestion_control;
    z_priority_t priority;
    z_timestamp_t *timestamp;
    bool is_express;
    z_moved_bytes_t *attachment;
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    z_locality_t allowed_destination;
#endif
#ifdef Z_FEATURE_UNSTABLE_API
    z_reliability_t reliability;
    z_source_info_t *source_info;
#endif
} z_put_options_t;

/**
 * Represents the configuration used to configure a delete operation sent via :c:func:`z_delete`.
 *
 * Members:
 *   z_congestion_control_t congestion_control: The congestion control to apply when routing this message.
 *   z_priority_t priority: The priority of this message when router.
 *   bool is_express: If ``true``, Zenoh will not wait to batch this operation with others to reduce the bandwidth.
 *   z_timestamp_t *timestamp: The API level timestamp (e.g. of the data when it was created).
 *   z_reliability_t reliability: The reliability that should be used to transmit the data (unstable).
 *   z_source_info_t* source_info: The source info for the message (unstable).
 */
typedef struct {
    z_congestion_control_t congestion_control;
    z_priority_t priority;
    bool is_express;
    z_timestamp_t *timestamp;
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    z_locality_t allowed_destination;
#endif
#ifdef Z_FEATURE_UNSTABLE_API
    z_reliability_t reliability;
    z_source_info_t *source_info;
#endif
} z_delete_options_t;

/**
 * Represents the configuration used to configure a put operation by a previously declared publisher,
 * sent via :c:func:`z_publisher_put`.
 *
 * Members:
 *   z_moved_encoding_t* encoding: The encoding of the payload.
 *   z_timestamp_t *timestamp: The API level timestamp (e.g. of the data when it was created).
 *   z_moved_bytes_t* attachment: An optional attachment to the publication.
 *   z_source_info_t* source_info: The source info for the message (unstable).
 */
typedef struct {
    z_moved_encoding_t *encoding;
    z_timestamp_t *timestamp;
    z_moved_bytes_t *attachment;
#ifdef Z_FEATURE_UNSTABLE_API
    z_source_info_t *source_info;
#endif
} z_publisher_put_options_t;

/**
 * Represents the configuration used to configure a delete operation by a previously declared publisher,
 * sent via :c:func:`z_publisher_delete`.
 *
 * Members:
 *   z_timestamp_t *timestamp: The API level timestamp (e.g. of the data when it was created).
 *   z_source_info_t* source_info: The source info for the message (unstable).
 */
typedef struct {
    z_timestamp_t *timestamp;
#ifdef Z_FEATURE_UNSTABLE_API
    z_source_info_t *source_info;
#endif
} z_publisher_delete_options_t;

/**
 * Represents the configuration used to configure a get operation sent via :c:func:`z_get`.
 *
 * Members:
 *   z_moved_bytes_t* payload: The payload to include in the query.
 *   z_moved_encoding_t* encoding: Payload encoding.
 *   z_query_consolidation_t consolidation: The replies consolidation strategy to apply on replies.
 *   z_congestion_control_t congestion_control: The congestion control to apply when routing the query.
 *   z_priority_t priority: The priority of the query.
 *   bool is_express: If ``true``, Zenoh will not wait to batch this operation with others to reduce the bandwidth.
 *   z_query_target_t target: The queryables that should be targeted by this get.
 *   uint64_t timeout_ms: Query timeout in milliseconds. 0 means default timeout. 0 corresponds to default get request
 *     timeout.
 *   z_moved_bytes_t* attachment: An optional attachment to the query.
 *   z_source_info_t* source_info: The source info for the request (unstable).
 *   z_moved_cancellation_token_t *cancellation_token: Token to allow cancelling get operation (unstable).
 *   z_reply_keyexpr_t accept_replies: The type of accepted replies for the query.
 */
typedef struct {
    z_moved_bytes_t *payload;
    z_moved_encoding_t *encoding;
    z_query_consolidation_t consolidation;
    z_congestion_control_t congestion_control;
    z_priority_t priority;
    bool is_express;
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    z_locality_t allowed_destination;
#endif
    z_query_target_t target;
    uint64_t timeout_ms;
    z_moved_bytes_t *attachment;
#ifdef Z_FEATURE_UNSTABLE_API
    z_source_info_t *source_info;
    z_moved_cancellation_token_t *cancellation_token;
#endif
    z_reply_keyexpr_t accept_replies;
} z_get_options_t;

#if Z_FEATURE_MULTI_THREAD == 1 || defined(SPHINX_DOCS)
/**
 * Represents the configuration used to configure a read task started via :c:func:`zp_start_read_task`.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 */
typedef struct {
    z_task_attr_t *task_attributes;
} zp_task_read_options_t;

/**
 * Represents the configuration used to configure a lease task started via :c:func:`zp_start_lease_task`.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 */
typedef struct {
    z_task_attr_t *task_attributes;
} zp_task_lease_options_t;
#endif
#if Z_FEATURE_MULTI_THREAD == 0 || defined(SPHINX_DOCS)
/**
 * Represents the configuration used to configure a read operation started via :c:func:`zp_read`.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 */
typedef struct {
    bool single_read;  // Read a single packet instead of the whole buffer
} zp_read_options_t;

/**
 * Represents the configuration used to configure a send keep alive operation started via :c:func:`zp_send_keep_alive`.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 */
typedef struct {
    uint8_t __dummy;  // Just to avoid empty structures that might cause undefined behavior
} zp_send_keep_alive_options_t;

/**
 * Represents the configuration used to configure a send join operation started via :c:func:`zp_send_join`.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 */
typedef struct {
    uint8_t __dummy;  // Just to avoid empty structures that might cause undefined behavior
} zp_send_join_options_t;
#endif
/**
 * Represents the configuration used to configure a publisher upon declaration with :c:func:`z_declare_publisher`.
 *
 * Members:
 *   uint64_t timeout_ms: The maximum duration in ms the scouting can take.
 *   z_what_t what: Type of entities to scout for.
 */
typedef struct {
    uint32_t timeout_ms;
    z_what_t what;
} z_scout_options_t;

/**
 * Represents missed samples.
 *
 * Members:
 *   source: The source of missed samples.
 *   nb: The number of missed samples.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef struct {
    z_entity_global_id_t source;
    uint32_t nb;
} ze_miss_t;

/**
 * Represents a data sample.
 */
_Z_OWNED_TYPE_VALUE(_z_sample_t, sample)

/**
 * Represents the content of a ``hello`` message returned by a zenoh entity as a reply to a `scout` message.
 */
_Z_OWNED_TYPE_VALUE(_z_hello_t, hello)

/**
 * Represents the reply to a query.
 */
_Z_OWNED_TYPE_VALUE(_z_reply_t, reply)

/**
 * Represents an array of non null-terminated string.
 */
_Z_OWNED_TYPE_VALUE(_z_string_svec_t, string_array)

#if Z_FEATURE_CONNECTIVITY == 1
/**
 * Represents a transport connected to the current session.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct _z_info_transport_t {
    z_id_t _zid;
    z_whatami_t _whatami;
    bool _is_qos;
    bool _is_multicast;
    bool _is_shm;
} _z_info_transport_t;
_Z_OWNED_TYPE_VALUE(_z_info_transport_t, transport)

/**
 * Represents a link connected to the current session.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct _z_info_link_t {
    z_id_t _zid;
    _z_string_t _src;
    _z_string_t _dst;
    uint16_t _mtu;
    bool _is_streamed;
    bool _is_reliable;
} _z_info_link_t;
_Z_OWNED_TYPE_VALUE(_z_info_link_t, link)

/**
 * Represents a transport connectivity event.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct _z_info_transport_event_t {
    z_sample_kind_t kind;
    _z_info_transport_t transport;
} _z_info_transport_event_t;
_Z_OWNED_TYPE_VALUE(_z_info_transport_event_t, transport_event)

/**
 * Represents a link connectivity event.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct _z_info_link_event_t {
    z_sample_kind_t kind;
    _z_info_link_t link;
} _z_info_link_event_t;
_Z_OWNED_TYPE_VALUE(_z_info_link_event_t, link_event)

/**
 * Represents a transport events listener entity.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct _z_transport_events_listener_t {
    size_t _id;
    _z_session_weak_t _session;
    _z_sync_group_t _callback_drop_sync_group;
} _z_transport_events_listener_t;
_Z_OWNED_TYPE_VALUE(_z_transport_events_listener_t, transport_events_listener)

/**
 * Represents a link events listener entity.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct _z_link_events_listener_t {
    size_t _id;
    _z_session_weak_t _session;
    _z_sync_group_t _callback_drop_sync_group;
} _z_link_events_listener_t;
_Z_OWNED_TYPE_VALUE(_z_link_events_listener_t, link_events_listener)

/**
 * Options passed to the :c:func:`z_declare_transport_events_listener()` function.
 *
 * Members:
 *   bool history: If set, the listener receives current transports as ``PUT`` events before future events.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct z_transport_events_listener_options_t {
    bool history;
} z_transport_events_listener_options_t;

/**
 * Options passed to the :c:func:`z_declare_link_events_listener()` function.
 *
 * Members:
 *   bool history: If set, the listener receives current links as ``PUT`` events before future events.
 *   z_moved_transport_t *transport: Optional transport filter. If set, only events for this transport are delivered.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct z_link_events_listener_options_t {
    bool history;
    z_moved_transport_t *transport;
} z_link_events_listener_options_t;

/**
 * Options passed to the :c:func:`z_info_links()` function.
 *
 * Members:
 *   z_moved_transport_t *transport: Optional transport filter. If set, only links for this transport are returned.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
typedef struct z_info_links_options_t {
    z_moved_transport_t *transport;
} z_info_links_options_t;
#endif

typedef _z_drop_handler_t z_closure_drop_callback_t;
typedef _z_closure_sample_callback_t z_closure_sample_callback_t;

typedef struct {
    void *context;
    z_closure_sample_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_sample_t;

/**
 * Represents the sample closure.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_sample_t, closure_sample)

typedef _z_closure_query_callback_t z_closure_query_callback_t;

typedef struct {
    void *context;
    z_closure_query_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_query_t;

/**
 * Represents the query callback closure.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_query_t, closure_query)

typedef _z_closure_reply_callback_t z_closure_reply_callback_t;

typedef struct {
    void *context;
    z_closure_reply_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_reply_t;

/**
 * Represents the query reply callback closure.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_reply_t, closure_reply)

typedef void (*z_closure_hello_callback_t)(z_loaned_hello_t *hello, void *arg);

typedef struct {
    void *context;
    z_closure_hello_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_hello_t;

/**
 * Represents the Zenoh ID callback closure.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_hello_t, closure_hello)

typedef void (*z_closure_zid_callback_t)(const z_id_t *id, void *arg);

typedef struct {
    void *context;
    z_closure_zid_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_zid_t;

/**
 * Represents the Zenoh ID callback closure.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_zid_t, closure_zid)

#if Z_FEATURE_CONNECTIVITY == 1
typedef void (*z_closure_transport_callback_t)(z_loaned_transport_t *transport, void *arg);

typedef struct {
    void *context;
    z_closure_transport_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_transport_t;

/**
 * Represents the transport callback closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_transport_t, closure_transport)

typedef void (*z_closure_link_callback_t)(z_loaned_link_t *link, void *arg);

typedef struct {
    void *context;
    z_closure_link_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_link_t;

/**
 * Represents the link callback closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_link_t, closure_link)

typedef void (*z_closure_transport_event_callback_t)(z_loaned_transport_event_t *event, void *arg);

typedef struct {
    void *context;
    z_closure_transport_event_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_transport_event_t;

/**
 * Represents the transport event callback closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_transport_event_t, closure_transport_event)

typedef void (*z_closure_link_event_callback_t)(z_loaned_link_event_t *event, void *arg);

typedef struct {
    void *context;
    z_closure_link_event_callback_t call;
    z_closure_drop_callback_t drop;
} _z_closure_link_event_t;

/**
 * Represents the link event callback closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_link_event_t, closure_link_event)
#endif

typedef _z_closure_matching_status_callback_t z_closure_matching_status_callback_t;
typedef _z_closure_matching_status_t z_closure_matching_status_t;
/**
 * Represents the matching status callback closure.
 */
_Z_OWNED_TYPE_VALUE(_z_closure_matching_status_t, closure_matching_status)

typedef void (*ze_closure_miss_callback_t)(const ze_miss_t *miss, void *arg);

typedef struct {
    void *context;
    ze_closure_miss_callback_t call;
    z_closure_drop_callback_t drop;
} _ze_closure_miss_t;

/**
 * Represents the sample miss callback closure.
 */
_Z_OWNED_TYPE_VALUE_PREFIX(ze, _ze_closure_miss_t, closure_miss)

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_API_TYPES_H */
