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

#include "zenoh-pico/transport/unicast/lease.h"

#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/session/interest.h"
#include "zenoh-pico/session/liveliness.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast/transport.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_UNICAST_TRANSPORT == 1
#if Z_FEATURE_UNICAST_PEER == 1
static bool _zp_unicast_peer_is_expired(const _z_transport_peer_unicast_t *target,
                                        const _z_transport_peer_unicast_t *peer) {
    _ZP_UNUSED(target);
    return !peer->common._received;
}

static void _zp_unicast_report_disconnected_peers(_z_transport_unicast_t *ztu,
                                                  _z_transport_peer_unicast_slist_t **dropped_peers) {
    if (dropped_peers == NULL || *dropped_peers == NULL) {
        return;
    }

#if Z_FEATURE_CONNECTIVITY == 1
    uint16_t mtu = 0;
    bool is_streamed = false;
    bool is_reliable = false;
    _z_transport_get_link_properties(&ztu->_common, &mtu, &is_streamed, &is_reliable);
#endif

    _z_session_t *zs = _z_transport_common_get_session(&ztu->_common);
    _z_transport_peer_unicast_slist_t *it = *dropped_peers;
    while (it != NULL) {
        _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(it);
        _Z_INFO("Deleting peer because it has expired after %zums", ztu->_common._lease);
        _z_interest_peer_disconnected(zs, &peer->common);
#if Z_FEATURE_CONNECTIVITY == 1
        _z_connectivity_peer_event_data_t disconnected_peer = {0};
        _z_connectivity_peer_event_data_alias_from_common(&disconnected_peer, &peer->common);
        _z_connectivity_peer_disconnected(zs, &disconnected_peer, false, mtu, is_streamed, is_reliable);
#endif
        it = _z_transport_peer_unicast_slist_next(it);
    }
    _z_transport_peer_unicast_slist_free(dropped_peers);
}
#endif

z_result_t _zp_unicast_send_keep_alive(_z_transport_unicast_t *ztu) {
    z_result_t ret = _Z_RES_OK;

    _z_transport_message_t t_msg = _z_t_msg_make_keep_alive();
    ret = _z_transport_tx_send_t_msg(&ztu->_common, &t_msg, NULL);

    return ret;
}

_z_fut_fn_result_t _zp_unicast_failed_result(_z_transport_unicast_t *ztu, _z_executor_t *executor) {
    _z_session_t *zs = _z_transport_common_get_session(&ztu->_common);
#if Z_FEATURE_LIVELINESS == 1 && Z_FEATURE_SUBSCRIPTION == 1
    _z_liveliness_subscription_undeclare_all(zs);
#endif
#if Z_FEATURE_CONNECTIVITY == 1
    _z_connectivity_peer_event_data_t disconnected_peer = {0};
    uint16_t mtu = 0;
    bool is_streamed = false;
    bool is_reliable = false;
    bool has_disconnected_peer = false;
    _z_transport_peer_mutex_lock(&ztu->_common);
    if (!_z_transport_peer_unicast_slist_is_empty(ztu->_peers)) {
        _z_transport_peer_unicast_t *curr_peer = _z_transport_peer_unicast_slist_value(ztu->_peers);
        _z_transport_get_link_properties(&ztu->_common, &mtu, &is_streamed, &is_reliable);
        _z_connectivity_peer_event_data_copy_from_common(&disconnected_peer, &curr_peer->common);
        has_disconnected_peer = true;
    }
    _z_transport_peer_mutex_unlock(&ztu->_common);
    if (has_disconnected_peer) {
        _z_connectivity_peer_disconnected(zs, &disconnected_peer, false, mtu, is_streamed, is_reliable);
        _z_connectivity_peer_event_data_clear(&disconnected_peer);
    }
#endif
    _z_unicast_transport_close(ztu, _Z_CLOSE_EXPIRED);
    _z_session_transport_mutex_lock(zs);
#if Z_FEATURE_AUTO_RECONNECT == 1
    // Store weak session to reuse for reconnection.
    _z_session_weak_t weak_session_clone = _z_session_weak_clone(&ztu->_common._session);
#endif
    _z_transport_clear(&zs->_tp);
    _z_session_transport_mutex_unlock(zs);

#if Z_FEATURE_AUTO_RECONNECT == 1
    ztu->_common._state = _Z_TRANSPORT_STATE_RECONNECTING;
    ztu->_common._session = weak_session_clone;
    _z_fut_t f = _z_fut_null();
    f._fut_arg = &ztu->_common;
    f._fut_fn = _z_client_reopen_task_fn;
    f._destroy_fn = _z_client_reopen_task_drop;
    if (_z_fut_handle_is_null(_z_executor_spawn(executor, &f))) {
        _Z_ERROR("Failed to spawn client reopen task after transport failure.");
        ztu->_common._state = _Z_TRANSPORT_STATE_CLOSED;
        _z_session_weak_drop(&ztu->_common._session);
        return _z_fut_fn_result_ready();
    } else {
        return _z_fut_fn_result_suspend();
    }
#else
    return _z_fut_fn_result_ready();
#endif
}

_z_fut_fn_result_t _zp_unicast_lease_task_fn(void *ztu_arg, _z_executor_t *executor) {
    _z_transport_unicast_t *ztu = (_z_transport_unicast_t *)ztu_arg;
    if (ztu->_common._state == _Z_TRANSPORT_STATE_CLOSED) {
        return _z_fut_fn_result_ready();
    } else if (ztu->_common._state == _Z_TRANSPORT_STATE_RECONNECTING) {
        return _z_fut_fn_result_suspend();
    }

    z_whatami_t mode = _z_transport_common_get_session(&ztu->_common)->_mode;

    if (mode == Z_WHATAMI_CLIENT) {
        _z_transport_peer_unicast_t *curr_peer = _z_transport_peer_unicast_slist_value(ztu->_peers);
        assert(curr_peer != NULL);
        if (curr_peer->common._received) {
            // Reset the lease parameters
            curr_peer->common._received = false;
            return _z_fut_fn_result_wake_up_after((unsigned long)ztu->_common._lease);
        } else {
            // THIS LOG STRING USED IN TEST, change with caution
            _Z_INFO("Closing session because it has expired after %zums", ztu->_common._lease);
            return _zp_unicast_failed_result(ztu, executor);
        }
    }
// TODO: Should we have a task per peer ?
#if Z_FEATURE_UNICAST_PEER == 1
    if (mode == Z_WHATAMI_PEER) {
        _z_transport_peer_unicast_slist_t *dropped_peers = _z_transport_peer_unicast_slist_new();
        _z_transport_peer_mutex_lock(&ztu->_common);
        ztu->_peers = _z_transport_peer_unicast_slist_extract_all_filter(ztu->_peers, &dropped_peers,
                                                                         _zp_unicast_peer_is_expired, NULL);
        _z_transport_peer_unicast_slist_t *curr_list = ztu->_peers;
        while (curr_list != NULL) {
            _z_transport_peer_unicast_t *curr_peer = _z_transport_peer_unicast_slist_value(curr_list);
            curr_peer->common._received = false;
            curr_list = _z_transport_peer_unicast_slist_next(curr_list);
        }
        _z_transport_peer_mutex_unlock(&ztu->_common);
        _zp_unicast_report_disconnected_peers(ztu, &dropped_peers);
        return _z_fut_fn_result_wake_up_after((unsigned long)ztu->_common._lease);
    }
#endif
    return _z_fut_fn_result_ready();
}

_z_fut_fn_result_t _zp_unicast_keep_alive_task_fn(void *ztu_arg, _z_executor_t *executor) {
    _z_transport_unicast_t *ztu = (_z_transport_unicast_t *)ztu_arg;
    if (ztu->_common._state == _Z_TRANSPORT_STATE_CLOSED) {
        return _z_fut_fn_result_ready();
    } else if (ztu->_common._state == _Z_TRANSPORT_STATE_RECONNECTING) {
        return _z_fut_fn_result_suspend();
    }

    z_whatami_t mode = _z_transport_common_get_session(&ztu->_common)->_mode;
    if (mode == Z_WHATAMI_CLIENT) {
        assert(_z_transport_peer_unicast_slist_value(ztu->_peers) != NULL);
        if (!ztu->_common._transmitted) {
            if (_zp_unicast_send_keep_alive(ztu) < 0) {
                // THIS LOG STRING USED IN TEST, change with caution
                _Z_INFO("Send keep alive failed.");
                return _zp_unicast_failed_result(ztu, executor);
            }
        }
        ztu->_common._transmitted = false;
        return _z_fut_fn_result_wake_up_after((unsigned long)ztu->_common._lease / Z_TRANSPORT_LEASE_EXPIRE_FACTOR);
    }
// TODO: Should we have a task per peer ?
#if Z_FEATURE_UNICAST_PEER == 1
    if (mode == Z_WHATAMI_PEER) {
        if (!ztu->_common._transmitted) {
            _Z_DEBUG("Sending keep alive");
            // Send keep alive to all peers
            _z_transport_message_t t_msg = _z_t_msg_make_keep_alive();
            _z_transport_peer_mutex_lock(&ztu->_common);
            if (!_z_transport_peer_unicast_slist_is_empty(ztu->_peers)) {
                if (_z_transport_tx_send_t_msg(&ztu->_common, &t_msg, ztu->_peers) != _Z_RES_OK) {
                    _Z_INFO("Send keep alive failed.");
                    // TODO: report failed peers and close them ?
                }
            }
            _z_transport_peer_mutex_unlock(&ztu->_common);
        }
        ztu->_common._transmitted = false;
        return _z_fut_fn_result_wake_up_after((unsigned long)ztu->_common._lease / Z_TRANSPORT_LEASE_EXPIRE_FACTOR);
    }
#endif
    return _z_fut_fn_result_ready();
}
#endif  // Z_FEATURE_UNICAST_TRANSPORT == 1
