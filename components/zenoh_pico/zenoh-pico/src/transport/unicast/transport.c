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

#include "zenoh-pico/transport/common/transport.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "zenoh-pico/link/link.h"
#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/transport/common/rx.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast/transport.h"
#include "zenoh-pico/transport/utils.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_UNICAST_TRANSPORT == 1
static z_result_t _z_unicast_transport_create_inner(_z_transport_unicast_t *ztu, _z_link_t *zl,
                                                    _z_transport_unicast_establish_param_t *param) {
// Initialize batching data
#if Z_FEATURE_BATCHING == 1
    ztu->_common._batch_state = _Z_BATCHING_IDLE;
    ztu->_common._batch_count = 0;
#endif

#if Z_FEATURE_MULTI_THREAD == 1
    // Initialize the mutexes
    _Z_RETURN_IF_ERR(_z_mutex_init(&ztu->_common._mutex_tx));
    _Z_RETURN_IF_ERR(_z_mutex_rec_init(&ztu->_common._mutex_peer));
#endif  // Z_FEATURE_MULTI_THREAD == 1

    // Initialize the read and write buffers
    uint16_t mtu = (zl->_mtu < param->_batch_size) ? zl->_mtu : param->_batch_size;
    size_t wbuf_size = mtu;
    size_t zbuf_size = param->_batch_size;
    // Initialize tx rx buffers
    ztu->_common._wbuf = _z_wbuf_make(wbuf_size, false);
    ztu->_common._zbuf = _z_zbuf_make(zbuf_size);

    // Check if a buffer failed to allocate
    if ((_z_wbuf_capacity(&ztu->_common._wbuf) != wbuf_size) || (_z_zbuf_capacity(&ztu->_common._zbuf) != zbuf_size)) {
        _Z_ERROR("Not enough memory to allocate transport buffers!");
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    // Set default SN resolution
    ztu->_common._sn_res = _z_sn_max(param->_seq_num_res);
    // The initial SN at TX side
    ztu->_common._sn_tx_reliable = param->_initial_sn_tx;
    ztu->_common._sn_tx_best_effort = param->_initial_sn_tx;
    // Notifiers
    ztu->_common._transmitted = 0;
    // Transport lease
    ztu->_common._lease = param->_lease;
    // Transport link for unicast
    ztu->_common._link = zl;

    ztu->_peers = _z_transport_peer_unicast_slist_new();
    return _Z_RES_OK;
}

z_result_t _z_unicast_transport_create(_z_transport_t *zt, _z_link_t *zl,
                                       _z_transport_unicast_establish_param_t *param) {
    zt->_type = _Z_TRANSPORT_UNICAST_TYPE;
    _z_transport_unicast_t *ztu = &zt->_transport._unicast;
    memset(ztu, 0, sizeof(_z_transport_unicast_t));

    z_result_t ret = _z_unicast_transport_create_inner(ztu, zl, param);
    if (ret != _Z_RES_OK) {
        // Clear alloc data
#if Z_FEATURE_MULTI_THREAD == 1
        _z_mutex_drop(&ztu->_common._mutex_tx);
        _z_mutex_rec_drop(&ztu->_common._mutex_peer);
#endif
        _z_wbuf_clear(&ztu->_common._wbuf);
        _z_zbuf_clear(&ztu->_common._zbuf);
    }
    return ret;
}

static z_result_t _z_unicast_handshake_open(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                            const _z_id_t *local_zid, z_whatami_t mode, _z_sys_net_socket_t *socket) {
    z_clock_t recv_deadline = z_clock_now();
    z_clock_advance_ms(&recv_deadline, Z_TRANSPORT_CONNECT_TIMEOUT);

    _z_transport_message_t ism = _z_t_msg_make_init_syn(mode, *local_zid);
    param->_seq_num_res = ism._body._init._seq_num_res;  // The announced sn resolution
    param->_req_id_res = ism._body._init._req_id_res;    // The announced req id resolution
    param->_batch_size = ism._body._init._batch_size;    // The announced batch size

    // Encode and send the message
    _Z_DEBUG("Sending Z_INIT(Syn)");
    z_result_t ret = _z_link_send_t_msg(zl, &ism, socket);
    _z_t_msg_clear(&ism);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    // Try to receive response
    _z_transport_message_t iam = {0};
    _Z_RETURN_IF_ERR(_z_link_recv_t_msg(&iam, zl, socket, recv_deadline));
    if ((_Z_MID(iam._header) != _Z_MID_T_INIT) || !_Z_HAS_FLAG(iam._header, _Z_FLAG_T_INIT_A)) {
        _z_t_msg_clear(&iam);
        _Z_ERROR_RETURN(_Z_ERR_MESSAGE_UNEXPECTED);
    }
    param->_remote_whatami = iam._body._init._whatami;
    _Z_DEBUG("Received Z_INIT(Ack)");
    // Any of the size parameters in the InitAck must be less or equal than the one in the InitSyn,
    // otherwise the InitAck message is considered invalid and it should be treated as a
    // CLOSE message with L==0 by the Initiating Peer -- the recipient of the InitAck message.
    if (iam._body._init._seq_num_res <= param->_seq_num_res) {
        param->_seq_num_res = iam._body._init._seq_num_res;
    } else {
        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_OPEN_SN_RESOLUTION);
        ret = _Z_ERR_TRANSPORT_OPEN_SN_RESOLUTION;
    }
    if (iam._body._init._req_id_res <= param->_req_id_res) {
        param->_req_id_res = iam._body._init._req_id_res;
    } else {
        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_OPEN_SN_RESOLUTION);
        ret = _Z_ERR_TRANSPORT_OPEN_SN_RESOLUTION;
    }
    if (iam._body._init._batch_size <= param->_batch_size) {
        param->_batch_size = iam._body._init._batch_size;
    } else {
        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_OPEN_SN_RESOLUTION);
        ret = _Z_ERR_TRANSPORT_OPEN_SN_RESOLUTION;
    }
#if Z_FEATURE_FRAGMENTATION == 1
    if (iam._body._init._patch <= ism._body._init._patch) {
        param->_patch = iam._body._init._patch;
    } else {
        // TODO: Use a better error code?
        _Z_ERROR_LOG(_Z_ERR_GENERIC);
        ret = _Z_ERR_GENERIC;
    }
#endif
    if (ret != _Z_RES_OK) {
        _z_t_msg_clear(&iam);
        return ret;
    }
    param->_key_id_res = 0x08 << param->_key_id_res;
    param->_req_id_res = 0x08 << param->_req_id_res;

    if (mode == Z_WHATAMI_CLIENT) {
        // The initial SN at TX side
        z_random_fill(&param->_initial_sn_tx, sizeof(param->_initial_sn_tx));
        param->_initial_sn_tx = param->_initial_sn_tx & !_z_sn_modulo_mask(param->_seq_num_res);
    }
    // Should be pre-initialized in peer mode

    // Initialize the Local and Remote Peer IDs
    param->_remote_zid = iam._body._init._zid;

    // Create the OpenSyn message
    _z_zint_t lease = Z_TRANSPORT_LEASE;
    _z_zint_t initial_sn = param->_initial_sn_tx;
    _z_slice_t cookie = _z_slice_null();
    if (!_z_slice_is_empty(&iam._body._init._cookie)) {
        _z_slice_copy(&cookie, &iam._body._init._cookie);
    }
    _z_transport_message_t osm = _z_t_msg_make_open_syn(lease, initial_sn, cookie);
    _z_t_msg_clear(&iam);
    // Encode and send the message
    _Z_DEBUG("Sending Z_OPEN(Syn)");
    ret = _z_link_send_t_msg(zl, &osm, socket);
    _z_t_msg_clear(&osm);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    // Try to receive response
    _z_transport_message_t oam = {0};
    _Z_RETURN_IF_ERR(_z_link_recv_t_msg(&oam, zl, socket, recv_deadline));
    if ((_Z_MID(oam._header) != _Z_MID_T_OPEN) || !_Z_HAS_FLAG(oam._header, _Z_FLAG_T_OPEN_A)) {
        _z_t_msg_clear(&oam);
        _Z_ERROR_LOG(_Z_ERR_MESSAGE_UNEXPECTED);
        ret = _Z_ERR_MESSAGE_UNEXPECTED;
    }
    // THIS LOG STRING USED IN TEST, change with caution
    _Z_DEBUG("Received Z_OPEN(Ack)");
    param->_lease = (oam._body._open._lease < Z_TRANSPORT_LEASE) ? oam._body._open._lease : Z_TRANSPORT_LEASE;
    // The initial SN at RX side. Initialize the session as we had already received
    // a message with a SN equal to initial_sn - 1.
    param->_initial_sn_rx = oam._body._open._initial_sn;
    _z_t_msg_clear(&oam);
    return _Z_RES_OK;
}

z_result_t _z_unicast_handshake_listen(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                       const _z_id_t *local_zid, z_whatami_t mode, _z_sys_net_socket_t *socket) {
    z_clock_t recv_deadline = z_clock_now();
    z_clock_advance_ms(&recv_deadline, Z_TRANSPORT_ACCEPT_TIMEOUT);
    assert(mode == Z_WHATAMI_PEER);
    // Read t message from link
    _z_transport_message_t tmsg = {0};
    z_result_t ret = _z_link_recv_t_msg(&tmsg, zl, socket, recv_deadline);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    // Receive InitSyn
    if (_Z_MID(tmsg._header) != _Z_MID_T_INIT || _Z_HAS_FLAG(tmsg._header, _Z_FLAG_T_INIT_A)) {
        _z_t_msg_clear(&tmsg);
        _Z_ERROR_RETURN(_Z_ERR_MESSAGE_UNEXPECTED);
    }
    _Z_DEBUG("Received Z_INIT(Syn)");
    // Encode InitAck
    _z_slice_t cookie = _z_slice_null();
    _z_transport_message_t iam = _z_t_msg_make_init_ack(mode, *local_zid, cookie);

    // If the new node has less representing capabilities adjust settings
    if (tmsg._body._init._seq_num_res < iam._body._init._seq_num_res) {
        _Z_DEBUG("Adjusting SN resolution from %u to %u", iam._body._init._seq_num_res, tmsg._body._init._seq_num_res);
        iam._body._init._seq_num_res = tmsg._body._init._seq_num_res;
    }
    if (tmsg._body._init._req_id_res < iam._body._init._req_id_res) {
        _Z_DEBUG("Adjusting Req ID resolution from %u to %u", iam._body._init._req_id_res,
                 tmsg._body._init._req_id_res);
        iam._body._init._req_id_res = tmsg._body._init._req_id_res;
    }
    if (tmsg._body._init._batch_size < iam._body._init._batch_size) {
        _Z_DEBUG("Adjusting Batch Size from %u to %u", iam._body._init._batch_size, tmsg._body._init._batch_size);
        iam._body._init._batch_size = tmsg._body._init._batch_size;
    }

#if Z_FEATURE_FRAGMENTATION == 1
    if (iam._body._init._patch > tmsg._body._init._patch) {
        iam._body._init._patch = tmsg._body._init._patch;
    }
#endif
    param->_seq_num_res = iam._body._init._seq_num_res;
    param->_req_id_res = iam._body._init._req_id_res;
    param->_batch_size = iam._body._init._batch_size;
    param->_remote_zid = tmsg._body._init._zid;
    param->_remote_whatami = tmsg._body._init._whatami;
    param->_key_id_res = 0x08 << param->_key_id_res;
    param->_req_id_res = 0x08 << param->_req_id_res;
    _z_t_msg_clear(&tmsg);
    // Send InitAck
    _Z_DEBUG("Sending Z_INIT(Ack)");
    ret = _z_link_send_t_msg(zl, &iam, socket);
    _z_t_msg_clear(&iam);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    // Read t message from link
    ret = _z_link_recv_t_msg(&tmsg, zl, socket, recv_deadline);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    // Receive OpenSyn
    if (_Z_MID(tmsg._header) != _Z_MID_T_OPEN || _Z_HAS_FLAG(tmsg._header, _Z_FLAG_T_INIT_A)) {
        _z_t_msg_clear(&tmsg);
        _Z_ERROR_RETURN(_Z_ERR_MESSAGE_UNEXPECTED);
    }
    _Z_DEBUG("Received Z_OPEN(Syn)");
    // Process message
    param->_lease = (tmsg._body._open._lease < Z_TRANSPORT_LEASE) ? tmsg._body._open._lease : Z_TRANSPORT_LEASE;
    param->_initial_sn_rx = tmsg._body._open._initial_sn;
    _z_t_msg_clear(&tmsg);

    // Encode OpenAck
    _z_zint_t lease = Z_TRANSPORT_LEASE;
    _z_zint_t initial_sn = param->_initial_sn_tx;
    _z_transport_message_t oam = _z_t_msg_make_open_ack(lease, initial_sn);

    // Encode and send the message
    _Z_DEBUG("Sending Z_OPEN(Ack)");
    ret = _z_link_send_t_msg(zl, &oam, socket);
    _z_t_msg_clear(&oam);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    // Handshake finished
    return _Z_RES_OK;
}

z_result_t _z_unicast_open_client(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                  const _z_id_t *local_zid) {
    return _z_unicast_handshake_open(param, zl, local_zid, Z_WHATAMI_CLIENT, NULL);
}

z_result_t _z_unicast_open_peer(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                const _z_id_t *local_zid, int peer_op, _z_sys_net_socket_t *socket) {
    z_result_t ret = _Z_RES_OK;

    // Init sn tx
    z_random_fill(&param->_initial_sn_tx, sizeof(param->_initial_sn_tx));
    param->_initial_sn_tx = param->_initial_sn_tx & !_z_sn_modulo_mask(param->_seq_num_res);

    if (peer_op == _Z_PEER_OP_OPEN) {
        ret = _z_unicast_handshake_open(param, zl, local_zid, Z_WHATAMI_PEER, socket);
    } else {
        // Initialize common parameters
        param->_lease = Z_TRANSPORT_LEASE;
        param->_batch_size = Z_BATCH_UNICAST_SIZE;
        param->_seq_num_res = Z_SN_RESOLUTION;
    }
    return ret;
}

z_result_t _z_unicast_send_close(_z_transport_unicast_t *ztu, uint8_t reason, bool link_only) {
    z_result_t ret = _Z_RES_OK;
    // Send and clear message
    _z_transport_message_t cm = _z_t_msg_make_close(reason, link_only);
    ret = _z_transport_tx_send_t_msg(&ztu->_common, &cm, NULL);
    _z_t_msg_clear(&cm);
    return ret;
}

z_result_t _z_unicast_transport_close(_z_transport_unicast_t *ztu, uint8_t reason) {
    return _z_unicast_send_close(ztu, reason, false);
}

void _z_unicast_transport_clear(_z_transport_unicast_t *ztu) {
    _z_transport_peer_unicast_slist_free(&ztu->_peers);
    _z_transport_common_clear(
        &ztu->_common);  // free common in the very end, as peers might access the link data in common while being freed
}

#else

z_result_t _z_unicast_transport_create(_z_transport_t *zt, _z_link_t *zl,
                                       _z_transport_unicast_establish_param_t *param) {
    _ZP_UNUSED(zt);
    _ZP_UNUSED(zl);
    _ZP_UNUSED(param);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_unicast_open_client(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                  const _z_id_t *local_zid) {
    _ZP_UNUSED(param);
    _ZP_UNUSED(zl);
    _ZP_UNUSED(local_zid);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_unicast_open_peer(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                const _z_id_t *local_zid, int peer_op, _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(param);
    _ZP_UNUSED(zl);
    _ZP_UNUSED(local_zid);
    _ZP_UNUSED(peer_op);
    _ZP_UNUSED(socket);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_unicast_send_close(_z_transport_unicast_t *ztu, uint8_t reason, bool link_only) {
    _ZP_UNUSED(ztu);
    _ZP_UNUSED(reason);
    _ZP_UNUSED(link_only);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_unicast_transport_close(_z_transport_unicast_t *ztu, uint8_t reason) {
    _ZP_UNUSED(ztu);
    _ZP_UNUSED(reason);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

void _z_unicast_transport_clear(_z_transport_unicast_t *ztu) { _ZP_UNUSED(ztu); }

#endif  // Z_FEATURE_UNICAST_TRANSPORT == 1
