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
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/multicast/transport.h"
#include "zenoh-pico/transport/raweth/tx.h"
#include "zenoh-pico/transport/utils.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_MULTICAST_TRANSPORT == 1 || Z_FEATURE_RAWETH_TRANSPORT == 1

z_result_t _z_multicast_transport_create(_z_transport_t *zt, _z_link_t *zl,
                                         _z_transport_multicast_establish_param_t *param) {
    z_result_t ret = _Z_RES_OK;
    // Transport specific information
    _z_transport_multicast_t *ztm = NULL;
    switch (zl->_cap._transport) {
        case Z_LINK_CAP_TRANSPORT_MULTICAST:
            zt->_type = _Z_TRANSPORT_MULTICAST_TYPE;
            ztm = &zt->_transport._multicast;
            ztm->_send_f = _z_transport_tx_send_t_msg_wrapper;
            break;
        case Z_LINK_CAP_TRANSPORT_RAWETH:
            zt->_type = _Z_TRANSPORT_RAWETH_TYPE;
            ztm = &zt->_transport._raweth;
            ztm->_send_f = _z_raweth_send_t_msg;
            break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }

// Initialize batching data
#if Z_FEATURE_BATCHING == 1
    ztm->_common._batch_state = _Z_BATCHING_IDLE;
    ztm->_common._batch_count = 0;
#endif

#if Z_FEATURE_MULTI_THREAD == 1
    // Initialize the mutexes
    ret = _z_mutex_init(&ztm->_common._mutex_tx);
    if (ret == _Z_RES_OK) {
        ret = _z_mutex_rec_init(&ztm->_common._mutex_peer);
        if (ret != _Z_RES_OK) {
            _z_mutex_drop(&ztm->_common._mutex_tx);
        }
    }
#endif  // Z_FEATURE_MULTI_THREAD == 1

    // Initialize the read and write buffers
    if (ret == _Z_RES_OK) {
        uint16_t mtu = (zl->_mtu < Z_BATCH_MULTICAST_SIZE) ? zl->_mtu : Z_BATCH_MULTICAST_SIZE;
        ztm->_common._wbuf = _z_wbuf_make(mtu, false);
        ztm->_common._zbuf = _z_zbuf_make(Z_BATCH_MULTICAST_SIZE);

        // Clean up the buffers if one of them failed to be allocated
        if ((_z_wbuf_capacity(&ztm->_common._wbuf) != mtu) ||
            (_z_zbuf_capacity(&ztm->_common._zbuf) != Z_BATCH_MULTICAST_SIZE)) {
            _Z_ERROR_LOG(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            _Z_ERROR("Not enough memory to allocate transport tx rx buffers!");

#if Z_FEATURE_MULTI_THREAD == 1
            _z_mutex_drop(&ztm->_common._mutex_tx);
            _z_mutex_rec_drop(&ztm->_common._mutex_peer);
#endif  // Z_FEATURE_MULTI_THREAD == 1

            _z_wbuf_clear(&ztm->_common._wbuf);
            _z_zbuf_clear(&ztm->_common._zbuf);
        }
    }

    if (ret == _Z_RES_OK) {
        // Set default SN resolution
        ztm->_common._sn_res = _z_sn_max(param->_seq_num_res);

        // The initial SN at TX side
        ztm->_common._sn_tx_reliable = param->_initial_sn_tx._val._plain._reliable;
        ztm->_common._sn_tx_best_effort = param->_initial_sn_tx._val._plain._best_effort;

        // Initialize peer list
        ztm->_peers = _z_transport_peer_multicast_slist_new();

        ztm->_common._lease = Z_TRANSPORT_LEASE;

        // Notifiers
        ztm->_common._transmitted = false;

        // Transport link for multicast
        ztm->_common._link = zl;
    }
    return ret;
}

z_result_t _z_multicast_open_peer(_z_transport_multicast_establish_param_t *param, const _z_link_t *zl,
                                  const _z_id_t *local_zid) {
    z_result_t ret = _Z_RES_OK;

    _z_zint_t initial_sn_tx = 0;
    z_random_fill(&initial_sn_tx, sizeof(initial_sn_tx));
    initial_sn_tx = initial_sn_tx & !_z_sn_modulo_mask(Z_SN_RESOLUTION);

    _z_conduit_sn_list_t next_sn;
    next_sn._is_qos = false;
    next_sn._val._plain._best_effort = initial_sn_tx;
    next_sn._val._plain._reliable = initial_sn_tx;

    _z_id_t zid = *local_zid;
    _z_transport_message_t jsm = _z_t_msg_make_join(Z_WHATAMI_PEER, Z_TRANSPORT_LEASE, zid, next_sn);

    // Encode and send the message
    _Z_DEBUG("Sending Z_JOIN message");
    switch (zl->_cap._transport) {
        case Z_LINK_CAP_TRANSPORT_MULTICAST:
            ret = _z_link_send_t_msg(zl, &jsm, NULL);
            break;
        case Z_LINK_CAP_TRANSPORT_RAWETH:
            ret = _z_raweth_link_send_t_msg(zl, &jsm);
            break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
    _z_t_msg_clear(&jsm);

    if (ret == _Z_RES_OK) {
        param->_seq_num_res = jsm._body._join._seq_num_res;
        param->_initial_sn_tx = next_sn;
    }
    return ret;
}

z_result_t _z_multicast_open_client(_z_transport_multicast_establish_param_t *param, const _z_link_t *zl,
                                    const _z_id_t *local_zid) {
    _ZP_UNUSED(param);
    _ZP_UNUSED(zl);
    _ZP_UNUSED(local_zid);
    _Z_ERROR_LOG(_Z_ERR_CONFIG_UNSUPPORTED_CLIENT_MULTICAST);
    z_result_t ret = _Z_ERR_CONFIG_UNSUPPORTED_CLIENT_MULTICAST;
    // @TODO: not implemented
    return ret;
}

z_result_t _z_multicast_send_close(_z_transport_multicast_t *ztm, uint8_t reason, bool link_only) {
    z_result_t ret = _Z_RES_OK;
    // Send and clear message
    _z_transport_message_t cm = _z_t_msg_make_close(reason, link_only);
    ret = ztm->_send_f(&ztm->_common, &cm);
    _z_t_msg_clear(&cm);
    return ret;
}

z_result_t _z_multicast_transport_close(_z_transport_multicast_t *ztm, uint8_t reason) {
    return _z_multicast_send_close(ztm, reason, false);
}

void _z_multicast_transport_clear(_z_transport_multicast_t *ztm) {
    _z_transport_peer_multicast_slist_free(&ztm->_peers);
    _z_transport_common_clear(
        &ztm->_common);  // free common in the very end, as peers might access the link data in common while being freed
}

#else

z_result_t _z_multicast_transport_create(_z_transport_t *zt, _z_link_t *zl,
                                         _z_transport_multicast_establish_param_t *param) {
    _ZP_UNUSED(zt);
    _ZP_UNUSED(zl);
    _ZP_UNUSED(param);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_multicast_open_peer(_z_transport_multicast_establish_param_t *param, const _z_link_t *zl,
                                  const _z_id_t *local_zid) {
    _ZP_UNUSED(param);
    _ZP_UNUSED(zl);
    _ZP_UNUSED(local_zid);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_multicast_open_client(_z_transport_multicast_establish_param_t *param, const _z_link_t *zl,
                                    const _z_id_t *local_zid) {
    _ZP_UNUSED(param);
    _ZP_UNUSED(zl);
    _ZP_UNUSED(local_zid);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_multicast_send_close(_z_transport_multicast_t *ztm, uint8_t reason, bool link_only) {
    _ZP_UNUSED(ztm);
    _ZP_UNUSED(reason);
    _ZP_UNUSED(link_only);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_multicast_transport_close(_z_transport_multicast_t *ztm, uint8_t reason) {
    _ZP_UNUSED(ztm);
    _ZP_UNUSED(reason);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

void _z_multicast_transport_clear(_z_transport_multicast_t *ztm) { _ZP_UNUSED(ztm); }
#endif  // Z_FEATURE_MULTICAST_TRANSPORT == 1 || Z_FEATURE_RAWETH_TRANSPORT == 1
