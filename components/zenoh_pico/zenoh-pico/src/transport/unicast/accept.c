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

#include "zenoh-pico/session/interest.h"
#include "zenoh-pico/session/liveliness.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast/lease.h"
#include "zenoh-pico/transport/unicast/transport.h"
#include "zenoh-pico/utils/logging.h"
#if Z_FEATURE_LINK_TLS == 1
#include "zenoh-pico/system/link/tls.h"
#endif
#include "zenoh-pico/runtime/runtime.h"

#if Z_FEATURE_UNICAST_TRANSPORT == 1 && Z_FEATURE_UNICAST_PEER == 1
#if Z_FEATURE_CONNECTIVITY == 1
static void _zp_unicast_dispatch_connected_event(_z_transport_unicast_t *ztu, const _z_transport_peer_unicast_t *peer) {
    if (ztu == NULL || peer == NULL) {
        return;
    }

    _z_connectivity_peer_event_data_t connected_peer = {0};
    uint16_t mtu = 0;
    bool is_streamed = false;
    bool is_reliable = false;
    bool has_event_data = false;

    _z_transport_peer_mutex_lock(&ztu->_common);
    _z_transport_peer_unicast_slist_t *it = ztu->_peers;
    while (it != NULL) {
        _z_transport_peer_unicast_t *current_peer = _z_transport_peer_unicast_slist_value(it);
        if (current_peer == peer) {
            _z_transport_get_link_properties(&ztu->_common, &mtu, &is_streamed, &is_reliable);
            _z_connectivity_peer_event_data_copy_from_common(&connected_peer, &current_peer->common);
            has_event_data = true;
            break;
        }
        it = _z_transport_peer_unicast_slist_next(it);
    }
    _z_transport_peer_mutex_unlock(&ztu->_common);

    if (has_event_data) {
        _z_connectivity_peer_connected(_z_transport_common_get_session(&ztu->_common), &connected_peer, false, mtu,
                                       is_streamed, is_reliable);
        _z_connectivity_peer_event_data_clear(&connected_peer);
    }
}
#endif

_z_fut_fn_result_t _zp_unicast_accept_task_fn(void *ctx, _z_executor_t *executor) {
    _ZP_UNUSED(executor);
    _z_transport_unicast_t *ztu = (_z_transport_unicast_t *)ctx;
    const _z_sys_net_socket_t *socket_ptr = _z_link_get_socket(ztu->_common._link);
    if (socket_ptr == NULL) {
        _Z_ERROR_LOG(_Z_ERR_INVALID);
        return _z_fut_fn_result_ready();
    }
    _z_sys_net_socket_t listen_socket = *socket_ptr;
    _z_sys_net_socket_t con_socket = {0};
    z_result_t ret = _z_socket_accept(&listen_socket, &con_socket);
    if (ret != _Z_RES_OK) {
        if (ret == _Z_ERR_INVALID) {
            _Z_INFO("Accept socket was closed");
            return _z_fut_fn_result_ready();
        } else {  // wait for a while before retry
            return _z_fut_fn_result_wake_up_after(1000);
        }
    }
    if (_z_transport_peer_unicast_slist_len(ztu->_peers) >= Z_LISTEN_MAX_CONNECTION_NB) {
        // TODO: Send a connection refusal message before closing the socket
        // TODO: Suspend task and only wake it up when a peer is removed and a new connection can be accepted.
        _Z_INFO("Refusing connection as max connections currently reached");
        _z_socket_close(&con_socket);
        return _z_fut_fn_result_wake_up_after(1000);
    }
    ret = _z_socket_set_blocking(&con_socket, true);
    if (ret != _Z_RES_OK) {
        _Z_INFO("Failed to set socket blocking with error %d", ret);
        _z_socket_close(&con_socket);
        return _z_fut_fn_result_continue();
    }
#if Z_FEATURE_LINK_TLS == 1
    // Perform TLS handshake if this is a TLS link
    if (ztu->_common._link->_type == _Z_LINK_TYPE_TLS) {
        ret = _z_tls_accept(&con_socket, &listen_socket);
        if (ret != _Z_RES_OK) {
            _Z_INFO("TLS handshake failed with error %d", ret);
            _z_socket_close(&con_socket);
            return _z_fut_fn_result_continue();
        }
    }
#endif
    _z_transport_unicast_establish_param_t param = {0};
    // Start handshake in blocking mode
    ret = _z_unicast_handshake_listen(&param, ztu->_common._link,
                                      &_z_transport_common_get_session(&ztu->_common)->_local_zid, Z_WHATAMI_PEER,
                                      &con_socket);
    if (ret != _Z_RES_OK) {
        _Z_INFO("Connection accept handshake failed with error %d", ret);
        _z_socket_close(&con_socket);
        return _z_fut_fn_result_continue();
    }
    // Set socket as non blocking
    if (_z_socket_set_blocking(&con_socket, false) != _Z_RES_OK) {
        _Z_INFO("Failed to set socket non blocking");
        _z_socket_close(&con_socket);
        return _z_fut_fn_result_continue();
    }
    // Add peer
    _z_transport_peer_unicast_t *new_peer = NULL;
    ret = _z_transport_peer_unicast_add(ztu, &param, con_socket, true, &new_peer);
    if (ret != _Z_RES_OK) {
        _z_socket_close(&con_socket);
        return _z_fut_fn_result_continue();
    }
    if (new_peer != NULL) {
        (void)_z_interest_push_declarations_to_peer(_z_transport_common_get_session(&ztu->_common), (void *)new_peer);
#if Z_FEATURE_CONNECTIVITY == 1
        _zp_unicast_dispatch_connected_event(ztu, new_peer);
#endif
    }
    return _z_fut_fn_result_continue();
}
#endif
