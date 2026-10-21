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

#ifndef INCLUDE_ZENOH_PICO_NET_SESSION_H
#define INCLUDE_ZENOH_PICO_NET_SESSION_H

#include <stdint.h>

#include "zenoh-pico/collections/atomic.h"
#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/list.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/session/liveliness.h"
#include "zenoh-pico/session/matching.h"
#include "zenoh-pico/session/queryable.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/subscription.h"
#include "zenoh-pico/utils/config.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * A zenoh-net session.
 */
struct _z_write_filter_registration_t;

#if Z_FEATURE_CONNECTIVITY == 1
typedef struct {
    _z_void_rc_t _callback;
} _z_connectivity_transport_listener_t;

static inline size_t _z_connectivity_transport_listener_size(const _z_connectivity_transport_listener_t *listener) {
    _ZP_UNUSED(listener);
    return sizeof(_z_connectivity_transport_listener_t);
}

static inline void _z_connectivity_transport_listener_clear(_z_connectivity_transport_listener_t *listener) {
    _z_void_rc_drop(&listener->_callback);
    listener->_callback = _z_void_rc_null();
}

static inline void _z_connectivity_transport_listener_copy(_z_connectivity_transport_listener_t *dst,
                                                           const _z_connectivity_transport_listener_t *src) {
    dst->_callback = _z_void_rc_clone(&src->_callback);
}

static inline void _z_connectivity_transport_listener_move(_z_connectivity_transport_listener_t *dst,
                                                           _z_connectivity_transport_listener_t *src) {
    dst->_callback = src->_callback;
    src->_callback = _z_void_rc_null();
}

_Z_ELEM_DEFINE(_z_connectivity_transport_listener, _z_connectivity_transport_listener_t,
               _z_connectivity_transport_listener_size, _z_connectivity_transport_listener_clear,
               _z_connectivity_transport_listener_copy, _z_connectivity_transport_listener_move, _z_noop_eq,
               _z_noop_cmp, _z_noop_hash)
_Z_INT_MAP_DEFINE(_z_connectivity_transport_listener, _z_connectivity_transport_listener_t)

typedef struct {
    _z_void_rc_t _callback;
    bool _has_transport_filter;
    _z_id_t _transport_zid;
    bool _transport_is_multicast;
} _z_connectivity_link_listener_t;

static inline size_t _z_connectivity_link_listener_size(const _z_connectivity_link_listener_t *listener) {
    _ZP_UNUSED(listener);
    return sizeof(_z_connectivity_link_listener_t);
}

static inline void _z_connectivity_link_listener_clear(_z_connectivity_link_listener_t *listener) {
    _z_void_rc_drop(&listener->_callback);
    listener->_callback = _z_void_rc_null();
    listener->_has_transport_filter = false;
    listener->_transport_zid = (_z_id_t){0};
    listener->_transport_is_multicast = false;
}

static inline void _z_connectivity_link_listener_copy(_z_connectivity_link_listener_t *dst,
                                                      const _z_connectivity_link_listener_t *src) {
    dst->_callback = _z_void_rc_clone(&src->_callback);
    dst->_has_transport_filter = src->_has_transport_filter;
    dst->_transport_zid = src->_transport_zid;
    dst->_transport_is_multicast = src->_transport_is_multicast;
}

static inline void _z_connectivity_link_listener_move(_z_connectivity_link_listener_t *dst,
                                                      _z_connectivity_link_listener_t *src) {
    dst->_callback = src->_callback;
    dst->_has_transport_filter = src->_has_transport_filter;
    dst->_transport_zid = src->_transport_zid;
    dst->_transport_is_multicast = src->_transport_is_multicast;
    src->_callback = _z_void_rc_null();
    src->_has_transport_filter = false;
    src->_transport_zid = (_z_id_t){0};
    src->_transport_is_multicast = false;
}

_Z_ELEM_DEFINE(_z_connectivity_link_listener, _z_connectivity_link_listener_t, _z_connectivity_link_listener_size,
               _z_connectivity_link_listener_clear, _z_connectivity_link_listener_copy,
               _z_connectivity_link_listener_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_INT_MAP_DEFINE(_z_connectivity_link_listener, _z_connectivity_link_listener_t)
#endif

typedef struct _z_session_t {
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_t _mutex_inner;
    _z_mutex_rec_t _mutex_transport;
#if Z_FEATURE_ADMIN_SPACE == 1
    _z_mutex_t _mutex_admin_space;
#endif
#endif  // Z_FEATURE_MULTI_THREAD == 1

    // Zenoh-pico is considering a single transport per session.
    z_whatami_t _mode;
    _z_transport_t _tp;

    // Zenoh PID
    _z_id_t _local_zid;

    // Session counters
    uint16_t _resource_id;
    uint32_t _entity_id;
    _z_zint_t _query_id;
    _z_zint_t _interest_id;

    // Session declarations
    _z_resource_slist_t *_local_resources;

#if Z_FEATURE_AUTO_RECONNECT == 1
    // Information for session restoring
    _z_config_t _config;
    _z_network_message_slist_t *_declaration_cache;
#endif

    // Session subscriptions
#if Z_FEATURE_SUBSCRIPTION == 1
    _z_subscription_rc_slist_t *_subscriptions;
    _z_subscription_rc_slist_t *_liveliness_subscriptions;
#if Z_FEATURE_RX_CACHE == 1
    _z_subscription_lru_cache_t _subscription_cache;
#endif
#endif

#if Z_FEATURE_LIVELINESS == 1
    _z_declared_keyexpr_intmap_t _local_tokens;
    _z_keyexpr_intmap_t _remote_tokens;
#if Z_FEATURE_QUERY == 1
    uint32_t _liveliness_query_id;
    _z_liveliness_pending_query_intmap_t _liveliness_pending_queries;
#endif
#endif

    // Session queryables
#if Z_FEATURE_QUERYABLE == 1
    _z_session_queryable_rc_slist_t *_local_queryable;
#if Z_FEATURE_RX_CACHE == 1
    _z_queryable_lru_cache_t _queryable_cache;
#endif
#endif
#if Z_FEATURE_QUERY == 1
    _z_pending_query_slist_t *_pending_queries;
#endif

    // Session interests
#if Z_FEATURE_INTEREST == 1
    _z_session_interest_rc_slist_t *_local_interests;
    _z_declare_data_slist_t *_remote_declares;
    struct _z_write_filter_registration_t *_write_filters;
#endif

#if Z_FEATURE_ADMIN_SPACE == 1
    // entity Id for admin space queryable (0 if not started)
    uint32_t _admin_space_queryable_id;
#if Z_FEATURE_CONNECTIVITY == 1
    // entity Id for session connectivity queryable (0 if not started)
    uint32_t _admin_space_session_queryable_id;
#if Z_FEATURE_PUBLICATION == 1
    // listener ids for admin-space connectivity event bridge (0 if not started)
    size_t _admin_space_transport_listener_id;
    size_t _admin_space_link_listener_id;
#endif
#endif
#endif
#if Z_FEATURE_CONNECTIVITY == 1
    size_t _connectivity_next_listener_id;
    _z_connectivity_transport_listener_intmap_t _connectivity_transport_event_listeners;
    _z_connectivity_link_listener_intmap_t _connectivity_link_event_listeners;
#endif
    _z_sync_group_t _callback_drop_sync_group;
    _z_atomic_bool_t _is_closed;
    _z_runtime_t _runtime;
} _z_session_t;

/**
 * Open a zenoh-net session
 *
 * Parameters:
 *     zn: A pointer of A :c:type:`_z_session_t` used as a return value.
 *     config: A set of properties. The caller keeps its ownership.
 *     zid: A pointer to Zenoh ID.
 *
 * Returns:
 *     ``0`` in case of success, or a ``negative value`` in case of failure.
 */
z_result_t _z_open(_z_session_rc_t *zn, _z_config_t *config, const _z_id_t *zid);

#if Z_FEATURE_AUTO_RECONNECT == 1
void _z_client_reopen_task_drop(void *ztc_arg);
_z_fut_fn_result_t _z_client_reopen_task_fn(void *ztc_arg, _z_executor_t *executor);
#endif

/**
 * Store declaration network message to cache for resend it after session restore
 *
 * Parameters:
 *     zs: A zenoh-net session.
 *     z_msg: Network message with declaration
 */
void _z_cache_declaration(_z_session_t *zs, const _z_network_message_t *n_msg);

/**
 * Remove corresponding declaration from the cache
 *
 * Parameters:
 *     zs: A zenoh-net session.
 *     z_msg: Network message with undeclaration
 */
void _z_prune_declaration(_z_session_t *zs, const _z_network_message_t *n_msg);

/**
 * Return true is session and all associated transports were closed.
 */
bool _z_session_is_closed(const _z_session_t *session);

/**
 * Return true if session is connected to at least one router peer.
 */
bool _z_session_has_router_peer(const _z_session_t *session);

/**
 * Upgrade a weak session reference to a strong one if the session is open, otherwise return null.
 */
_z_session_rc_t _z_session_weak_upgrade_if_open(const _z_session_weak_t *weak);
/**
 * Get informations about an zenoh-net session.
 *
 * Parameters:
 *     session: A zenoh-net session. The caller keeps its ownership.
 *
 * Returns:
 *     A :c:type:`_z_config_t` map containing informations on the given zenoh-net session.
 */
_z_config_t *_z_info(const _z_session_t *session);

/*------------------ Zenoh-Pico Session Management Auxiliary ------------------*/
/**
 * Read from the network. This function should be called manually called when
 * the read loop has not been started, e.g., when running in a single thread.
 *
 * Parameters:
 *     session: The zenoh-net session. The caller keeps its ownership.
 *     single_read: Read a single packet from the buffer instead of the whole buffer
 * Returns:
 *     ``0`` in case of success, ``-1`` in case of failure.
 */
z_result_t _zp_read(_z_session_t *z, bool single_read);

/**
 * Send a KeepAlive message.
 *
 * Parameters:
 *     session: The zenoh-net session. The caller keeps its ownership.
 * Returns:
 *     ``0`` in case of success, ``-1`` in case of failure.
 */
z_result_t _zp_send_keep_alive(_z_session_t *z);

/**
 * Send a Join message.
 *
 * Parameters:
 *     session: The zenoh-net session. The caller keeps its ownership.
 * Returns:
 *     ``0`` in case of success, ``-1`` in case of failure.
 */
z_result_t _zp_send_join(_z_session_t *z);

z_result_t _zp_start_transport_tasks(_z_session_t *z);
#if Z_FEATURE_CONNECTIVITY == 1
void _z_connectivity_peer_connected(_z_session_t *session, const _z_connectivity_peer_event_data_t *peer,
                                    bool is_multicast, uint16_t mtu, bool is_streamed, bool is_reliable);
void _z_connectivity_peer_disconnected(_z_session_t *session, const _z_connectivity_peer_event_data_t *peer,
                                       bool is_multicast, uint16_t mtu, bool is_streamed, bool is_reliable);
void _z_connectivity_peer_disconnected_from_transport(_z_session_t *session, const _z_transport_common_t *transport,
                                                      const _z_connectivity_peer_event_data_t *peer, bool is_multicast);
#endif

static inline _z_session_t *_z_transport_common_get_session(_z_transport_common_t *transport) {
    // the session should always outlive the transport, so it should be safe
    // to access pointer directly without upgrade
    return _z_session_weak_as_unsafe_ptr(&transport->_session);
}

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_NET_SESSION_H */
