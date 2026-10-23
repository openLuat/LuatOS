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

#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/utils.h"

#if Z_FEATURE_CONNECTIVITY == 1
static z_result_t _z_transport_make_endpoint(const _z_string_t *protocol, const char *address, _z_string_t *out) {
    _z_locator_t locator;

    *out = _z_string_null();
    if (address == NULL || address[0] == '\0') {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }

    _z_locator_init(&locator);
    if (protocol != NULL && _z_string_check(protocol)) {
        locator._protocol = _z_string_alias(*protocol);
    } else {
        locator._protocol = _z_string_alias_str("tcp");
    }
    locator._address = _z_string_alias_str(address);

    *out = _z_locator_to_string(&locator);
    _z_locator_clear(&locator);
    if (!_z_string_check(out)) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    return _Z_RES_OK;
}
#endif

void _z_transport_peer_common_clear(_z_transport_peer_common_t *src) {
#if Z_FEATURE_CONNECTIVITY == 1
    _z_string_clear(&src->_link_src);
    _z_string_clear(&src->_link_dst);
#endif
#if Z_FEATURE_FRAGMENTATION == 1
    _z_wbuf_clear(&src->_dbuf_reliable);
    _z_wbuf_clear(&src->_dbuf_best_effort);
#endif
    src->_remote_zid = _z_id_empty();
    _z_resource_slist_free(&src->_remote_resources);
}
void _z_transport_peer_common_copy(_z_transport_peer_common_t *dst, const _z_transport_peer_common_t *src) {
#if Z_FEATURE_CONNECTIVITY == 1
    dst->_link_src = _z_string_null();
    dst->_link_dst = _z_string_null();
    (void)_z_string_copy(&dst->_link_src, &src->_link_src);
    if (_z_string_copy(&dst->_link_dst, &src->_link_dst) != _Z_RES_OK) {
        _z_string_clear(&dst->_link_src);
    }
#endif
#if Z_FEATURE_FRAGMENTATION == 1
    dst->_state_reliable = src->_state_reliable;
    dst->_state_best_effort = src->_state_best_effort;
    _z_wbuf_copy(&dst->_dbuf_reliable, &src->_dbuf_reliable);
    _z_wbuf_copy(&dst->_dbuf_best_effort, &src->_dbuf_best_effort);
    dst->_patch = src->_patch;
#endif
    dst->_remote_resources = NULL;
    dst->_received = src->_received;
    dst->_remote_zid = src->_remote_zid;
    dst->_remote_whatami = src->_remote_whatami;
}

#if Z_FEATURE_CONNECTIVITY == 1
void _z_connectivity_peer_event_data_clear(_z_connectivity_peer_event_data_t *event_data) {
    if (event_data == NULL) {
        return;
    }
    if (event_data->_owns_endpoints) {
        _z_string_clear(&event_data->_link_src);
        _z_string_clear(&event_data->_link_dst);
    }
    *event_data = (_z_connectivity_peer_event_data_t){0};
}

void _z_connectivity_peer_event_data_copy_from_common(_z_connectivity_peer_event_data_t *dst,
                                                      const _z_transport_peer_common_t *src) {
    *dst = (_z_connectivity_peer_event_data_t){0};
    dst->_link_src = _z_string_null();
    dst->_link_dst = _z_string_null();
    dst->_remote_zid = src->_remote_zid;
    dst->_remote_whatami = src->_remote_whatami;
    dst->_owns_endpoints = true;

    (void)_z_string_copy(&dst->_link_src, &src->_link_src);
    if (_z_string_copy(&dst->_link_dst, &src->_link_dst) != _Z_RES_OK) {
        _z_string_clear(&dst->_link_src);
    }
}

void _z_connectivity_peer_event_data_alias_from_common(_z_connectivity_peer_event_data_t *dst,
                                                       const _z_transport_peer_common_t *src) {
    *dst = (_z_connectivity_peer_event_data_t){
        ._remote_zid = src->_remote_zid,
        ._remote_whatami = src->_remote_whatami,
        ._link_src = src->_link_src,
        ._link_dst = src->_link_dst,
        ._owns_endpoints = false,
    };
}
#endif

bool _z_transport_peer_common_eq(const _z_transport_peer_common_t *left, const _z_transport_peer_common_t *right) {
    return _z_id_eq(&left->_remote_zid, &right->_remote_zid);
}

void _z_transport_peer_multicast_clear(_z_transport_peer_multicast_t *src) {
    _z_slice_clear(&src->_remote_addr);
    _z_transport_peer_common_clear(&src->common);
}

void _z_transport_peer_multicast_copy(_z_transport_peer_multicast_t *dst, const _z_transport_peer_multicast_t *src) {
    dst->_sn_res = src->_sn_res;
    _z_conduit_sn_list_copy(&dst->_sn_rx_sns, &src->_sn_rx_sns);
    dst->_lease = src->_lease;
    _z_slice_copy(&dst->_remote_addr, &src->_remote_addr);
    _z_transport_peer_common_copy(&dst->common, &src->common);
}

size_t _z_transport_peer_multicast_size(const _z_transport_peer_multicast_t *src) {
    _ZP_UNUSED(src);
    return sizeof(_z_transport_peer_multicast_t);
}

bool _z_transport_peer_multicast_eq(const _z_transport_peer_multicast_t *left,
                                    const _z_transport_peer_multicast_t *right) {
    return _z_transport_peer_common_eq(&left->common, &right->common);
}

void _z_transport_peer_unicast_clear(_z_transport_peer_unicast_t *src) {
    _z_zbuf_clear(&src->flow_buff);
    if (src->_owns_socket) {
        _z_socket_close(&src->_socket);
    }
    _z_transport_peer_common_clear(&src->common);
}

void _z_transport_peer_unicast_copy(_z_transport_peer_unicast_t *dst, const _z_transport_peer_unicast_t *src) {
    dst->_sn_rx_reliable = src->_sn_rx_reliable;
    dst->_sn_rx_best_effort = src->_sn_rx_best_effort;
    dst->_socket = src->_socket;
    dst->_owns_socket = false;  // Ownership is not copied
    dst->_pending = false;
    dst->flow_state = _Z_FLOW_STATE_INACTIVE;
    dst->flow_curr_size = 0;
    dst->flow_buff = _z_zbuf_null();
    _z_transport_peer_common_copy(&dst->common, &src->common);
}

size_t _z_transport_peer_unicast_size(const _z_transport_peer_unicast_t *src) {
    _ZP_UNUSED(src);
    return sizeof(_z_transport_peer_unicast_t);
}

bool _z_transport_peer_unicast_eq(const _z_transport_peer_unicast_t *left, const _z_transport_peer_unicast_t *right) {
    return _z_transport_peer_common_eq(&left->common, &right->common);
}

z_result_t _z_transport_peer_unicast_add(_z_transport_unicast_t *ztu, _z_transport_unicast_establish_param_t *param,
                                         _z_sys_net_socket_t socket, bool owns_socket,
                                         _z_transport_peer_unicast_t **output_peer) {
#if Z_FEATURE_CONNECTIVITY == 1
    bool dispatch_connected_event = output_peer == NULL;
    _z_session_t *session = _z_transport_common_get_session(&ztu->_common);
    _z_connectivity_peer_event_data_t peer_event_data = {0};
    char local_addr[160] = {0};
    char remote_addr[160] = {0};
    uint16_t mtu = 0;
    bool is_streamed = false;
    bool is_reliable = false;
#endif

    _z_transport_peer_mutex_lock(&ztu->_common);
    // Create peer
    ztu->_peers = _z_transport_peer_unicast_slist_push_empty(ztu->_peers);
    if (ztu->_peers == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    // Fill peer data
    _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(ztu->_peers);
    peer->flow_state = _Z_FLOW_STATE_INACTIVE;
    peer->flow_curr_size = 0;
    peer->flow_buff = _z_zbuf_null();
    peer->_pending = false;
    peer->_socket = socket;
    peer->_owns_socket = owns_socket;
    _z_zint_t initial_sn_rx = _z_sn_decrement(ztu->_common._sn_res, param->_initial_sn_rx);
    peer->_sn_rx_reliable = initial_sn_rx;
    peer->_sn_rx_best_effort = initial_sn_rx;

    peer->common._remote_zid = param->_remote_zid;
    peer->common._remote_whatami = param->_remote_whatami;
    peer->common._received = true;
    peer->common._remote_resources = NULL;
#if Z_FEATURE_CONNECTIVITY == 1
    peer->common._link_src = _z_string_null();
    peer->common._link_dst = _z_string_null();
#endif
#if Z_FEATURE_FRAGMENTATION == 1
    peer->common._patch = param->_patch < _Z_CURRENT_PATCH ? param->_patch : _Z_CURRENT_PATCH;
    peer->common._state_reliable = _Z_DBUF_STATE_NULL;
    peer->common._state_best_effort = _Z_DBUF_STATE_NULL;
    peer->common._dbuf_reliable = _z_wbuf_null();
    peer->common._dbuf_best_effort = _z_wbuf_null();
#endif
#if Z_FEATURE_CONNECTIVITY == 1
    if (ztu->_common._link != NULL) {
        mtu = ztu->_common._link->_mtu;
        is_streamed = ztu->_common._link->_cap._flow == Z_LINK_CAP_FLOW_STREAM;
        is_reliable = ztu->_common._link->_cap._is_reliable;
        if (_z_socket_get_endpoints(&peer->_socket, local_addr, sizeof(local_addr), remote_addr, sizeof(remote_addr)) ==
            _Z_RES_OK) {
            (void)_z_transport_make_endpoint(&ztu->_common._link->_endpoint._locator._protocol, local_addr,
                                             &peer->common._link_src);
            (void)_z_transport_make_endpoint(&ztu->_common._link->_endpoint._locator._protocol, remote_addr,
                                             &peer->common._link_dst);
        }
    }
    if (dispatch_connected_event) {
        _z_connectivity_peer_event_data_copy_from_common(&peer_event_data, &peer->common);
    }
#endif
    _z_transport_peer_mutex_unlock(&ztu->_common);

    if (output_peer != NULL) {
        *output_peer = peer;
    }

#if Z_FEATURE_CONNECTIVITY == 1
    if (dispatch_connected_event) {
        _z_connectivity_peer_connected(session, &peer_event_data, false, mtu, is_streamed, is_reliable);
    }
    _z_connectivity_peer_event_data_clear(&peer_event_data);
#endif

    return _Z_RES_OK;
}
