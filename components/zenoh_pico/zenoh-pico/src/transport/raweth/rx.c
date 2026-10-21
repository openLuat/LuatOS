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

// #include "zenoh-pico/transport/link/rx.h"

#include <stddef.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/codec/network.h"
#include "zenoh-pico/protocol/codec/transport.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/transport/multicast/transport.h"
#include "zenoh-pico/transport/utils.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_RAWETH_TRANSPORT == 1

static size_t _z_raweth_link_recv_zbuf(const _z_link_t *link, _z_zbuf_t *zbf, _z_slice_t *addr) {
    uint8_t *buff = _z_zbuf_get_wptr(zbf);
    size_t rb = _z_receive_raweth(&link->_socket._raweth._sock, buff, _z_zbuf_space_left(zbf), addr,
                                  &link->_socket._raweth._whitelist);
    // Check validity
    if ((rb == SIZE_MAX) || (rb < sizeof(_zp_eth_header_t))) {
        return SIZE_MAX;
    }
    // Check if header has vlan
    bool has_vlan = false;
    _zp_eth_header_t *header = (_zp_eth_header_t *)buff;
    if (header->ethtype == _ZP_ETH_TYPE_VLAN) {
        has_vlan = true;
    }
    // Check validity
    if (has_vlan && (rb < sizeof(_zp_eth_vlan_header_t))) {
        return SIZE_MAX;
    }
    size_t data_length = 0;
    if (has_vlan) {
        _zp_eth_vlan_header_t *vlan_header = (_zp_eth_vlan_header_t *)buff;
        // Retrieve data length
        data_length = _z_raweth_ntohs(vlan_header->data_length);
        if (rb < (data_length + sizeof(_zp_eth_vlan_header_t))) {
            // Invalid data_length
            return SIZE_MAX;
        }
        // Skip header
        _z_zbuf_set_wpos(zbf, _z_zbuf_get_wpos(zbf) + sizeof(_zp_eth_vlan_header_t) + data_length);
        _z_zbuf_set_rpos(zbf, _z_zbuf_get_rpos(zbf) + sizeof(_zp_eth_vlan_header_t));
    } else {
        header = (_zp_eth_header_t *)buff;
        // Retrieve data length
        data_length = _z_raweth_ntohs(header->data_length);
        if (rb < (data_length + sizeof(_zp_eth_header_t))) {
            // Invalid data_length
            return SIZE_MAX;
        }
        // Skip header
        _z_zbuf_set_wpos(zbf, _z_zbuf_get_wpos(zbf) + sizeof(_zp_eth_header_t) + data_length);
        _z_zbuf_set_rpos(zbf, _z_zbuf_get_rpos(zbf) + sizeof(_zp_eth_header_t));
    }
    return data_length;
}

/*------------------ Reception helper ------------------*/
z_result_t _z_raweth_recv_t_msg_na(_z_transport_multicast_t *ztm, _z_transport_message_t *t_msg, _z_slice_t *addr) {
    _Z_DEBUG(">> recv session msg");
    z_result_t ret = _Z_RES_OK;

    // Prepare the buffer
    _z_zbuf_reset(&ztm->_common._zbuf);

    switch (ztm->_common._link->_cap._flow) {
        // Datagram capable links
        case Z_LINK_CAP_FLOW_DATAGRAM: {
            _z_zbuf_compact(&ztm->_common._zbuf);
            // Read from link
            size_t to_read = _z_raweth_link_recv_zbuf(ztm->_common._link, &ztm->_common._zbuf, addr);
            if (to_read == SIZE_MAX) {
                _Z_ERROR_LOG(_Z_ERR_TRANSPORT_RX_FAILED);
                ret = _Z_ERR_TRANSPORT_RX_FAILED;
            }
            break;
        }
        default:
            _Z_ERROR_LOG(_Z_ERR_GENERIC);
            ret = _Z_ERR_GENERIC;
            break;
    }
    // Decode message
    if (ret == _Z_RES_OK) {
        _Z_DEBUG(">> \t transport_message_decode: %ju", (uintmax_t)_z_zbuf_len(&ztm->_common._zbuf));
        ret = _z_transport_message_decode(t_msg, &ztm->_common._zbuf);
    }
    return ret;
}

z_result_t _z_raweth_recv_t_msg(_z_transport_multicast_t *ztm, _z_transport_message_t *t_msg, _z_slice_t *addr) {
    return _z_raweth_recv_t_msg_na(ztm, t_msg, addr);
}

z_result_t _z_raweth_update_rx_buff(_z_transport_multicast_t *ztm) {
    // Check if user or defragment buffer took ownership of buffer
    if (_z_zbuf_get_ref_count(&ztm->_common._zbuf) != 1) {
        // Allocate a new buffer
        _z_zbuf_t new_zbuf = _z_zbuf_make(Z_BATCH_MULTICAST_SIZE);
        if (_z_zbuf_capacity(&new_zbuf) != Z_BATCH_MULTICAST_SIZE) {
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        // Recopy leftover bytes
        size_t leftovers = _z_zbuf_len(&ztm->_common._zbuf);
        if (leftovers > 0) {
            _z_zbuf_copy_bytes(&new_zbuf, &ztm->_common._zbuf);
        }
        // Drop buffer & update
        _z_zbuf_clear(&ztm->_common._zbuf);
        ztm->_common._zbuf = new_zbuf;
    }
    return _Z_RES_OK;
}

#else
z_result_t _z_raweth_recv_t_msg(_z_transport_multicast_t *ztm, _z_transport_message_t *t_msg, _z_slice_t *addr) {
    _ZP_UNUSED(ztm);
    _ZP_UNUSED(t_msg);
    _ZP_UNUSED(addr);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}
#endif  // Z_FEATURE_RAWETH_TRANSPORT == 1
