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

// #include "zenoh-pico/transport/link/tx.h"

#include "zenoh-pico/transport/common/tx.h"

#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/protocol/codec/network.h"
#include "zenoh-pico/protocol/codec/transport.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/system/link/raweth.h"
#include "zenoh-pico/transport/multicast/transport.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/utils.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_RAWETH_TRANSPORT == 1

static int _zp_raweth_find_map_entry(const _z_keyexpr_t *keyexpr, _z_raweth_socket_t *sock) {
    for (size_t i = 0; i < _zp_raweth_mapping_array_len(&sock->_mapping); i++) {
        // Find matching keyexpr
        const _zp_raweth_mapping_entry_t *entry = _zp_raweth_mapping_array_get(&sock->_mapping, i);
        _z_keyexpr_t entry_ke = _z_keyexpr_alias_from_string(&entry->_keyexpr);
        if (!z_keyexpr_intersects(keyexpr, &entry_ke)) {
            continue;
        }
        return (int)i;
    }
    return -1;
}

static z_result_t _zp_raweth_set_socket(const _z_keyexpr_t *keyexpr, _z_raweth_socket_t *sock) {
    z_result_t ret = _Z_RES_OK;

    if (_zp_raweth_mapping_array_len(&sock->_mapping) < 1) {
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
    if (keyexpr == NULL) {
        // Store default value into socket
        const _zp_raweth_mapping_entry_t *entry = _zp_raweth_mapping_array_get(&sock->_mapping, 0);
        memcpy(&sock->_dmac, &entry->_dmac, _ZP_MAC_ADDR_LENGTH);
        uint16_t vlan = entry->_vlan;
        sock->_has_vlan = entry->_has_vlan;
        if (sock->_has_vlan) {
            memcpy(&sock->_vlan, &vlan, sizeof(vlan));
        }
    } else {
        // Find config entry (linear)
        int idx = _zp_raweth_find_map_entry(keyexpr, sock);
        // Key not found case
        if (idx < 0) {
            idx = 0;  // Set to default entry
            _Z_DEBUG("Key '%.*s' wasn't found in config mapping, sending to default address",
                     (int)_z_string_len(&keyexpr), _z_string_data(&keyexpr));
        }
        // Store data into socket
        const _zp_raweth_mapping_entry_t *entry = _zp_raweth_mapping_array_get(&sock->_mapping, (size_t)idx);
        memcpy(&sock->_dmac, &entry->_dmac, _ZP_MAC_ADDR_LENGTH);
        uint16_t vlan = entry->_vlan;
        sock->_has_vlan = entry->_has_vlan;
        if (sock->_has_vlan) {
            memcpy(&sock->_vlan, &vlan, sizeof(vlan));
        }
    }
    return ret;
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - ztm->_mutex_inner
 */
static _z_zint_t __unsafe_z_raweth_get_sn(_z_transport_multicast_t *ztm, z_reliability_t reliability) {
    _z_zint_t sn;
    if (reliability == Z_RELIABILITY_RELIABLE) {
        sn = ztm->_common._sn_tx_reliable;
        ztm->_common._sn_tx_reliable = _z_sn_increment(ztm->_common._sn_res, ztm->_common._sn_tx_reliable);
    } else {
        sn = ztm->_common._sn_tx_best_effort;
        ztm->_common._sn_tx_best_effort = _z_sn_increment(ztm->_common._sn_res, ztm->_common._sn_tx_best_effort);
    }
    return sn;
}

static void __unsafe_z_raweth_prepare_header(_z_link_t *zl, _z_wbuf_t *wbf) {
    _z_raweth_socket_t *resocket = &zl->_socket._raweth;
    // Reserve eth header in buffer
    if (resocket->_has_vlan) {
        _z_wbuf_set_wpos(wbf, sizeof(_zp_eth_vlan_header_t));
    } else {
        _z_wbuf_set_wpos(wbf, sizeof(_zp_eth_header_t));
    }
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - ztm->_mutex_inner
 */
static z_result_t __unsafe_z_raweth_write_header(_z_link_t *zl, _z_wbuf_t *wbf) {
    _z_raweth_socket_t *resocket = &zl->_socket._raweth;
    // Save and reset buffer position
    size_t wpos = _z_wbuf_len(wbf);
    _z_wbuf_set_wpos(wbf, 0);
    // Write eth header in buffer
    if (resocket->_has_vlan) {
        _zp_eth_vlan_header_t header;
        // Set header
        memset(&header, 0, sizeof(header));
        memcpy(&header.dmac, &resocket->_dmac, _ZP_MAC_ADDR_LENGTH);
        memcpy(&header.smac, &resocket->_smac, _ZP_MAC_ADDR_LENGTH);
        header.vlan_type = _ZP_ETH_TYPE_VLAN;
        header.tag = resocket->_vlan;
        header.ethtype = resocket->_ethtype;
        header.data_length = _z_raweth_htons((uint16_t)(wpos - sizeof(header)));
        // Write header
        _Z_RETURN_IF_ERR(_z_wbuf_write_bytes(wbf, (uint8_t *)&header, 0, sizeof(header)));
    } else {
        _zp_eth_header_t header;
        // Set header
        memcpy(&header.dmac, &resocket->_dmac, _ZP_MAC_ADDR_LENGTH);
        memcpy(&header.smac, &resocket->_smac, _ZP_MAC_ADDR_LENGTH);
        header.ethtype = resocket->_ethtype;
        header.data_length = _z_raweth_htons((uint16_t)(wpos - sizeof(header)));
        // Write header
        _Z_RETURN_IF_ERR(_z_wbuf_write_bytes(wbf, (uint8_t *)&header, 0, sizeof(header)));
    }
    // Restore wpos
    _z_wbuf_set_wpos(wbf, wpos);
    return _Z_RES_OK;
}

static z_result_t _z_raweth_link_send_wbuf(const _z_link_t *zl, const _z_wbuf_t *wbf) {
    z_result_t ret = _Z_RES_OK;
    for (size_t i = 0; (i < _z_wbuf_len_iosli(wbf)) && (ret == _Z_RES_OK); i++) {
        _z_slice_t bs = _z_iosli_to_bytes(_z_wbuf_get_iosli(wbf, i));
        size_t n = bs.len;

        do {
            // Retrieve addr from config + vlan tag above (locator)
            size_t wb = _z_send_raweth(&zl->_socket._raweth._sock, bs.start, n);  // Unix
            if (wb == SIZE_MAX) {
                _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
            }
            n = n - wb;
            bs.start = bs.start + (bs.len - n);
        } while (n > (size_t)0);
    }
    return ret;
}

z_result_t _z_raweth_link_send_t_msg(const _z_link_t *zl, const _z_transport_message_t *t_msg) {
    z_result_t ret = _Z_RES_OK;

    // Create and prepare the buffer to serialize the message on
    uint16_t mtu = (zl->_mtu < Z_BATCH_UNICAST_SIZE) ? zl->_mtu : Z_BATCH_UNICAST_SIZE;
    _z_wbuf_t wbf = _z_wbuf_make(mtu, false);
    if (_z_wbuf_capacity(&wbf) != mtu) {
        _Z_ERROR_LOG(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }

    // Discard const qualifier
    _z_link_t *mzl = (_z_link_t *)zl;
    // Set socket info
    _Z_RETURN_IF_ERR(_zp_raweth_set_socket(NULL, &mzl->_socket._raweth));
    // Prepare buff
    __unsafe_z_raweth_prepare_header(mzl, &wbf);
    // Encode the session message
    _Z_RETURN_IF_ERR(_z_transport_message_encode(&wbf, t_msg));
    // Write the message header
    _Z_RETURN_IF_ERR(__unsafe_z_raweth_write_header(mzl, &wbf));
    // Send the wbuf on the socket
    ret = _z_raweth_link_send_wbuf(zl, &wbf);
    _z_wbuf_clear(&wbf);

    return ret;
}

z_result_t _z_raweth_send_t_msg(_z_transport_common_t *ztc, const _z_transport_message_t *t_msg) {
    z_result_t ret = _Z_RES_OK;
    _Z_DEBUG(">> send session message");

    _z_transport_tx_mutex_lock(ztc, true);
    // Reset wbuf
    _z_wbuf_reset(&ztc->_wbuf);
    // Set socket info
    _Z_CLEAN_RETURN_IF_ERR(_zp_raweth_set_socket(NULL, &ztc->_link->_socket._raweth),
                           _z_transport_tx_mutex_unlock(ztc));
    // Prepare buff
    __unsafe_z_raweth_prepare_header(ztc->_link, &ztc->_wbuf);
    // Encode the session message
    _Z_CLEAN_RETURN_IF_ERR(_z_transport_message_encode(&ztc->_wbuf, t_msg), _z_transport_tx_mutex_unlock(ztc));
    // Write the message header
    _Z_CLEAN_RETURN_IF_ERR(__unsafe_z_raweth_write_header(ztc->_link, &ztc->_wbuf), _z_transport_tx_mutex_unlock(ztc));
    // Send the wbuf on the socket
    _Z_CLEAN_RETURN_IF_ERR(_z_raweth_link_send_wbuf(ztc->_link, &ztc->_wbuf), _z_transport_tx_mutex_unlock(ztc));
    // Mark the session that we have transmitted data
    ztc->_transmitted = true;
    _z_transport_tx_mutex_unlock(ztc);
    return ret;
}

z_result_t _z_raweth_send_n_msg(_z_session_t *zn, const _z_network_message_t *n_msg, z_reliability_t reliability,
                                z_congestion_control_t cong_ctrl) {
    z_result_t ret = _Z_RES_OK;
    _z_transport_multicast_t *ztm = &zn->_tp._transport._raweth;
    _Z_DEBUG(">> send network message");

    // Acquire the lock and drop the message if needed
    ret = _z_transport_tx_mutex_lock(&ztm->_common, cong_ctrl == Z_CONGESTION_CONTROL_BLOCK);
    if (ret != _Z_RES_OK) {
        _Z_INFO("Dropping zenoh message because of congestion control");
        return ret;
    }
    const _z_keyexpr_t *keyexpr = NULL;
    switch (n_msg->_tag) {
        case _Z_N_PUSH:
            keyexpr = &n_msg->_body._push._key;
            break;
        case _Z_N_REQUEST:
            keyexpr = &n_msg->_body._request._key;
            break;
        case _Z_N_RESPONSE:
            keyexpr = &n_msg->_body._response._key;
            break;
        case _Z_N_RESPONSE_FINAL:
        case _Z_N_DECLARE:
        default:
            break;
    }
    // Reset wbuf
    _z_wbuf_reset(&ztm->_common._wbuf);
    // Set socket info
    _Z_CLEAN_RETURN_IF_ERR(_zp_raweth_set_socket(keyexpr, &ztm->_common._link->_socket._raweth),
                           _z_transport_tx_mutex_unlock(&ztm->_common));
    // Prepare buff
    __unsafe_z_raweth_prepare_header(ztm->_common._link, &ztm->_common._wbuf);
    // Set the frame header
    _z_zint_t sn = __unsafe_z_raweth_get_sn(ztm, reliability);
    _z_transport_message_t t_msg = _z_t_msg_make_frame_header(sn, reliability);
    // Encode the frame header
    _Z_CLEAN_RETURN_IF_ERR(_z_transport_message_encode(&ztm->_common._wbuf, &t_msg),
                           _z_transport_tx_mutex_unlock(&ztm->_common));
    // Encode the network message
    if (_z_network_message_encode(&ztm->_common._wbuf, n_msg) == _Z_RES_OK) {
        // Write the eth header
        _Z_CLEAN_RETURN_IF_ERR(__unsafe_z_raweth_write_header(ztm->_common._link, &ztm->_common._wbuf),
                               _z_transport_tx_mutex_unlock(&ztm->_common));
        // Send the wbuf on the socket
        _Z_CLEAN_RETURN_IF_ERR(_z_raweth_link_send_wbuf(ztm->_common._link, &ztm->_common._wbuf),
                               _z_transport_tx_mutex_unlock(&ztm->_common));
        // Mark the session that we have transmitted data
        ztm->_common._transmitted = true;
    } else {  // The message does not fit in the current batch, let's fragment it
#if Z_FEATURE_FRAGMENTATION == 1
        // Create an expandable wbuf for fragmentation
        _z_wbuf_t fbf = _z_wbuf_make(_Z_FRAG_BUFF_BASE_SIZE, true);
        if (_z_wbuf_capacity(&fbf) != _Z_FRAG_BUFF_BASE_SIZE) {
            _Z_ERROR_LOG(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            _z_transport_tx_mutex_unlock(&ztm->_common);
            return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        }
        // Encode the message on the expandable wbuf
        _Z_CLEAN_RETURN_IF_ERR(_z_network_message_encode(&fbf, n_msg), _z_transport_tx_mutex_unlock(&ztm->_common));
        // Fragment and send the message
        bool is_first = true;
        while (_z_wbuf_len(&fbf) > 0) {
            if (is_first) {
                // Get the fragment sequence number
                sn = __unsafe_z_raweth_get_sn(ztm, reliability);
            }
            // Reset wbuf
            _z_wbuf_reset(&ztm->_common._wbuf);
            // Prepare buff
            __unsafe_z_raweth_prepare_header(ztm->_common._link, &ztm->_common._wbuf);
            // Serialize one fragment
            _Z_CLEAN_RETURN_IF_ERR(
                __unsafe_z_serialize_zenoh_fragment(&ztm->_common._wbuf, &fbf, reliability, sn, is_first),
                _z_transport_tx_mutex_unlock(&ztm->_common));
            // Write the eth header
            _Z_CLEAN_RETURN_IF_ERR(__unsafe_z_raweth_write_header(ztm->_common._link, &ztm->_common._wbuf),
                                   _z_transport_tx_mutex_unlock(&ztm->_common));
            // Send the wbuf on the socket
            _Z_CLEAN_RETURN_IF_ERR(_z_raweth_link_send_wbuf(ztm->_common._link, &ztm->_common._wbuf),
                                   _z_transport_tx_mutex_unlock(&ztm->_common));
            // Mark the session that we have transmitted data
            ztm->_common._transmitted = true;
            is_first = false;
        }
        // Clear the expandable buffer
        _z_wbuf_clear(&fbf);
#else
        _Z_INFO("Sending the message required fragmentation feature that is deactivated.");
#endif
    }
    _z_transport_tx_mutex_unlock(&ztm->_common);
    return ret;
}

#else
z_result_t _z_raweth_link_send_t_msg(const _z_link_t *zl, const _z_transport_message_t *t_msg) {
    _ZP_UNUSED(zl);
    _ZP_UNUSED(t_msg);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}
z_result_t _z_raweth_send_t_msg(_z_transport_common_t *ztc, const _z_transport_message_t *t_msg) {
    _ZP_UNUSED(ztc);
    _ZP_UNUSED(t_msg);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_raweth_send_n_msg(_z_session_t *zn, const _z_network_message_t *n_msg, z_reliability_t reliability,
                                z_congestion_control_t cong_ctrl) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(n_msg);
    _ZP_UNUSED(reliability);
    _ZP_UNUSED(cong_ctrl);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}
#endif  // Z_FEATURE_RAWETH_TRANSPORT == 1
