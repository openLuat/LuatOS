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

#include "zenoh-pico/transport/common/rx.h"

#include <stddef.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/codec/network.h"
#include "zenoh-pico/protocol/codec/transport.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/transport/unicast/rx.h"
#include "zenoh-pico/transport/unicast/transport.h"
#include "zenoh-pico/transport/utils.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_UNICAST_TRANSPORT == 1

z_result_t _z_unicast_recv_t_msg(_z_transport_unicast_t *ztu, _z_transport_message_t *t_msg) {
    _Z_DEBUG(">> recv session msg");
    z_result_t ret = _Z_RES_OK;
    size_t to_read = 0;
    _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(ztu->_peers);
    do {
        switch (ztu->_common._link->_cap._flow) {
            // Stream capable links
            case Z_LINK_CAP_FLOW_STREAM:
                if (_z_zbuf_len(&ztu->_common._zbuf) < _Z_MSG_LEN_ENC_SIZE) {
                    _z_link_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, NULL);
                    if (_z_zbuf_len(&ztu->_common._zbuf) < _Z_MSG_LEN_ENC_SIZE) {
                        _z_zbuf_compact(&ztu->_common._zbuf);
                        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NOT_ENOUGH_BYTES);
                        ret = _Z_ERR_TRANSPORT_NOT_ENOUGH_BYTES;
                        continue;
                    }
                }
                // Get stream size
                to_read = _z_read_stream_size(&ztu->_common._zbuf);
                // Read data
                if (_z_zbuf_len(&ztu->_common._zbuf) < to_read) {
                    _z_link_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, NULL);
                    if (_z_zbuf_len(&ztu->_common._zbuf) < to_read) {
                        _z_zbuf_set_rpos(&ztu->_common._zbuf,
                                         _z_zbuf_get_rpos(&ztu->_common._zbuf) - _Z_MSG_LEN_ENC_SIZE);
                        _z_zbuf_compact(&ztu->_common._zbuf);
                        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NOT_ENOUGH_BYTES);
                        ret = _Z_ERR_TRANSPORT_NOT_ENOUGH_BYTES;
                        continue;
                    }
                }
                break;
            // Datagram capable links
            case Z_LINK_CAP_FLOW_DATAGRAM:
                _z_zbuf_compact(&ztu->_common._zbuf);
                to_read = _z_link_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, NULL);
                if (to_read == SIZE_MAX) {
                    _Z_ERROR_LOG(_Z_ERR_TRANSPORT_RX_FAILED);
                    ret = _Z_ERR_TRANSPORT_RX_FAILED;
                }
                break;
            default:
                break;
        }
    } while (false);  // The 1-iteration loop to use continue to break the entire loop on error

    if (ret == _Z_RES_OK) {
        _Z_DEBUG(">> \t transport_message_decode");
        ret = _z_transport_message_decode(t_msg, &ztu->_common._zbuf);

        // Mark the session that we have received data
        if (ret == _Z_RES_OK) {
            peer->common._received = true;
        }
    }
    return ret;
}

static z_result_t _z_unicast_handle_frame(_z_transport_unicast_t *ztu, uint8_t header, _z_t_msg_frame_t *msg,
                                          _z_transport_peer_unicast_t *peer) {
    z_reliability_t tmsg_reliability;
    // Check if the SN is correct
    if (_Z_HAS_FLAG(header, _Z_FLAG_T_FRAME_R)) {
        tmsg_reliability = Z_RELIABILITY_RELIABLE;
        // @TODO: amend once reliability is in place. For the time being only
        //        monotonic SNs are ensured
        if (_z_sn_precedes(ztu->_common._sn_res, peer->_sn_rx_reliable, msg->_sn)) {
            peer->_sn_rx_reliable = msg->_sn;
        } else {
#if Z_FEATURE_FRAGMENTATION == 1
            _z_wbuf_clear(&peer->common._dbuf_reliable);
            peer->common._state_reliable = _Z_DBUF_STATE_NULL;
#endif
            _Z_INFO("Reliable message dropped because it is out of order");
            _z_t_msg_frame_clear(msg);
            return _Z_RES_OK;
        }
    } else {
        tmsg_reliability = Z_RELIABILITY_BEST_EFFORT;
        if (_z_sn_precedes(ztu->_common._sn_res, peer->_sn_rx_best_effort, msg->_sn)) {
            peer->_sn_rx_best_effort = msg->_sn;
        } else {
#if Z_FEATURE_FRAGMENTATION == 1
            _z_wbuf_clear(&peer->common._dbuf_best_effort);
            peer->common._state_best_effort = _Z_DBUF_STATE_NULL;
#endif
            _Z_INFO("Best effort message dropped because it is out of order");
            _z_t_msg_frame_clear(msg);
            return _Z_RES_OK;
        }
    }
    // Handle all the zenoh message, one by one
    // From this point, memory cleaning must be handled by the network message layer
    _z_network_message_t curr_nmsg = {0};
    _z_arc_slice_t arcs = _z_arc_slice_empty();
    while (_z_zbuf_len(msg->_payload) > 0) {
        _Z_RETURN_IF_ERR(_z_network_message_decode(&curr_nmsg, msg->_payload, &arcs, (uintptr_t)&peer->common));
        curr_nmsg._reliability = tmsg_reliability;
        _Z_RETURN_IF_ERR(_z_handle_network_message(&ztu->_common, &curr_nmsg, &peer->common));
    }
    return _Z_RES_OK;
}

static z_result_t _z_unicast_handle_fragment_inner(_z_transport_unicast_t *ztu, uint8_t header,
                                                   _z_t_msg_fragment_t *msg, _z_transport_peer_unicast_t *peer) {
    z_result_t ret = _Z_RES_OK;
#if Z_FEATURE_FRAGMENTATION == 1
    _z_wbuf_t *dbuf;
    uint8_t *dbuf_state;
    z_reliability_t tmsg_reliability;
    bool consecutive;

    // Select the right defragmentation buffer
    if (_Z_HAS_FLAG(header, _Z_FLAG_T_FRAGMENT_R)) {
        tmsg_reliability = Z_RELIABILITY_RELIABLE;
        // Check SN
        // @TODO: amend once reliability is in place. For the time being only
        //        monotonic SNs are ensured
        if (_z_sn_precedes(ztu->_common._sn_res, peer->_sn_rx_reliable, msg->_sn)) {
            consecutive = _z_sn_consecutive(ztu->_common._sn_res, peer->_sn_rx_reliable, msg->_sn);
            peer->_sn_rx_reliable = msg->_sn;
            dbuf = &peer->common._dbuf_reliable;
            dbuf_state = &peer->common._state_reliable;
        } else {
            _z_wbuf_clear(&peer->common._dbuf_reliable);
            peer->common._state_reliable = _Z_DBUF_STATE_NULL;
            _Z_INFO("Reliable message dropped because it is out of order");
            return _Z_RES_OK;
        }
    } else {
        tmsg_reliability = Z_RELIABILITY_BEST_EFFORT;
        // Check SN
        if (_z_sn_precedes(ztu->_common._sn_res, peer->_sn_rx_best_effort, msg->_sn)) {
            consecutive = _z_sn_consecutive(ztu->_common._sn_res, peer->_sn_rx_best_effort, msg->_sn);
            peer->_sn_rx_best_effort = msg->_sn;
            dbuf = &peer->common._dbuf_best_effort;
            dbuf_state = &peer->common._state_best_effort;
        } else {
            _z_wbuf_clear(&peer->common._dbuf_best_effort);
            peer->common._state_best_effort = _Z_DBUF_STATE_NULL;
            _Z_INFO("Best effort message dropped because it is out of order");
            return _Z_RES_OK;
        }
    }
    // Check consecutive SN
    if (!consecutive && _z_wbuf_len(dbuf) > 0) {
        _z_wbuf_clear(dbuf);
        *dbuf_state = _Z_DBUF_STATE_NULL;
        _Z_INFO("Defragmentation buffer dropped because non-consecutive fragments received");
        return _Z_RES_OK;
    }
    // Handle fragment markers
    if (_Z_PATCH_HAS_FRAGMENT_MARKERS(peer->common._patch)) {
        if (msg->first) {
            _z_wbuf_reset(dbuf);
        } else if (_z_wbuf_len(dbuf) == 0) {
            _Z_INFO("First fragment received without the start marker");
            return _Z_RES_OK;
        }
        if (msg->drop) {
            _z_wbuf_reset(dbuf);
            return _Z_RES_OK;
        }
    }
    // Allocate buffer if needed
    if (*dbuf_state == _Z_DBUF_STATE_NULL) {
        *dbuf = _z_wbuf_make(Z_FRAG_MAX_SIZE, false);
        if (_z_wbuf_capacity(dbuf) != Z_FRAG_MAX_SIZE) {
            _Z_ERROR("Not enough memory to allocate transport defragmentation buffer");
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        *dbuf_state = _Z_DBUF_STATE_INIT;
    }
    // Process fragment data
    if (*dbuf_state == _Z_DBUF_STATE_INIT) {
        // Check overflow
        if ((_z_wbuf_len(dbuf) + msg->_payload.len) > Z_FRAG_MAX_SIZE) {
            *dbuf_state = _Z_DBUF_STATE_OVERFLOW;
        } else {
            // Fill buffer
            _z_wbuf_write_bytes(dbuf, msg->_payload.start, 0, msg->_payload.len);
        }
    }
    // Process final fragment
    if (!_Z_HAS_FLAG(header, _Z_FLAG_T_FRAGMENT_M)) {
        // Drop message if it exceeds the fragmentation size
        if (*dbuf_state == _Z_DBUF_STATE_OVERFLOW) {
            _Z_INFO("Fragment dropped because defragmentation buffer has overflown");
            _z_wbuf_clear(dbuf);
            *dbuf_state = _Z_DBUF_STATE_NULL;
            return _Z_RES_OK;
        }
        // Convert the defragmentation buffer into a decoding buffer
        _z_zbuf_t zbf = _z_wbuf_moved_as_zbuf(dbuf);
        if (_z_zbuf_capacity(&zbf) == 0) {
            _Z_ERROR("Failed to convert defragmentation buffer into a decoding buffer!");
            _z_wbuf_clear(dbuf);
            *dbuf_state = _Z_DBUF_STATE_NULL;
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        // Decode message
        _z_zenoh_message_t zm = {0};
        _z_arc_slice_t arcs = _z_arc_slice_empty();
        ret = _z_network_message_decode(&zm, &zbf, &arcs, (uintptr_t)&peer->common);
        zm._reliability = tmsg_reliability;
        if (ret == _Z_RES_OK) {
            // Memory clear of the network message data must be handled by the network message layer
            _z_handle_network_message(&ztu->_common, &zm, &peer->common);
        } else {
            _Z_INFO("Failed to decode defragmented message");
            _Z_ERROR_LOG(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
            ret = _Z_ERR_MESSAGE_DESERIALIZATION_FAILED;
        }
        // Free the decoding buffer
        _z_zbuf_clear(&zbf);
        *dbuf_state = _Z_DBUF_STATE_NULL;
    }
#else
    _ZP_UNUSED(ztu);
    _ZP_UNUSED(header);
    _ZP_UNUSED(msg);
    _ZP_UNUSED(peer);
    _Z_INFO("Fragment dropped because fragmentation feature is deactivated");
#endif
    return ret;
}

static z_result_t _z_unicast_handle_fragment(_z_transport_unicast_t *ztu, uint8_t header, _z_t_msg_fragment_t *msg,
                                             _z_transport_peer_unicast_t *peer) {
    z_result_t ret = _z_unicast_handle_fragment_inner(ztu, header, msg, peer);
    _z_t_msg_fragment_clear(msg);
    return ret;
}

z_result_t _z_unicast_handle_transport_message(_z_transport_unicast_t *ztu, _z_transport_message_t *t_msg,
                                               _z_transport_peer_unicast_t *peer) {
    z_result_t ret = _Z_RES_OK;

    switch (_Z_MID(t_msg->_header)) {
        case _Z_MID_T_FRAME:
            _Z_DEBUG("Received Z_FRAME message");
            ret = _z_unicast_handle_frame(ztu, t_msg->_header, &t_msg->_body._frame, peer);
            break;

        case _Z_MID_T_FRAGMENT:
            _Z_DEBUG("Received Z_FRAGMENT message");
            ret = _z_unicast_handle_fragment(ztu, t_msg->_header, &t_msg->_body._fragment, peer);
            break;

        case _Z_MID_T_KEEP_ALIVE: {
            _Z_DEBUG("Received Z_KEEP_ALIVE message");
            _z_t_msg_keep_alive_clear(&t_msg->_body._keep_alive);
            break;
        }

        case _Z_MID_T_INIT: {
            // Do nothing, zenoh clients are not expected to handle accept messages on established sessions
            _z_t_msg_init_clear(&t_msg->_body._init);
            break;
        }

        case _Z_MID_T_OPEN: {
            // Do nothing, zenoh clients are not expected to handle accept messages on established sessions
            _z_t_msg_open_clear(&t_msg->_body._open);
            break;
        }

        case _Z_MID_T_CLOSE: {
            _Z_INFO("Closing session as requested by the remote peer");
            // Peer will be dropped thanks to the error
            _Z_ERROR_LOG(_Z_ERR_CONNECTION_CLOSED);
            ret = _Z_ERR_CONNECTION_CLOSED;
            _z_t_msg_close_clear(&t_msg->_body._close);
            break;
        }

        default: {
            _Z_INFO("WARNING: Unknown transport message ID");
            _z_t_msg_clear(t_msg);
            break;
        }
    }
    return ret;
}

z_result_t _z_unicast_update_rx_buffer(_z_transport_unicast_t *ztu) {
    // Check if user or defragment buffer took ownership of buffer
    if (_z_zbuf_get_ref_count(&ztu->_common._zbuf) != 1) {
        // Allocate a new buffer
        size_t buff_capacity = _z_zbuf_capacity(&ztu->_common._zbuf);
        _z_zbuf_t new_zbuf = _z_zbuf_make(buff_capacity);
        if (_z_zbuf_capacity(&new_zbuf) != buff_capacity) {
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        // Recopy leftover bytes
        size_t leftovers = _z_zbuf_len(&ztu->_common._zbuf);
        if (leftovers > 0) {
            _z_zbuf_copy_bytes(&new_zbuf, &ztu->_common._zbuf);
        }
        // Drop buffer & update
        _z_zbuf_clear(&ztu->_common._zbuf);
        ztu->_common._zbuf = new_zbuf;
    }
    return _Z_RES_OK;
}

#else
z_result_t _z_unicast_recv_t_msg(_z_transport_unicast_t *ztu, _z_transport_message_t *t_msg) {
    _ZP_UNUSED(ztu);
    _ZP_UNUSED(t_msg);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_unicast_handle_transport_message(_z_transport_unicast_t *ztu, _z_transport_message_t *t_msg,
                                               _z_transport_peer_unicast_t *peer) {
    _ZP_UNUSED(ztu);
    _ZP_UNUSED(t_msg);
    _ZP_UNUSED(peer);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}
#endif  // Z_FEATURE_UNICAST_TRANSPORT == 1
