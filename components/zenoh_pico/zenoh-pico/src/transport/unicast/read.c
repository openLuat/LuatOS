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

#include "zenoh-pico/transport/unicast/read.h"

#include <stddef.h>

#include "zenoh-pico/api/types.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/protocol/codec/transport.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/session/interest.h"
#include "zenoh-pico/transport/common/rx.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast/lease.h"
#include "zenoh-pico/transport/unicast/rx.h"
#include "zenoh-pico/utils/logging.h"

#define _Z_UNICAST_PEER_READ_STATUS_OK 0
#define _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA -1
#define _Z_UNICAST_PEER_READ_STATUS_SOCKET_CLOSED -2
#define _Z_UNICAST_PEER_READ_STATUS_CRITICAL_ERROR -3

#if Z_FEATURE_UNICAST_TRANSPORT == 1

static z_result_t _z_unicast_process_messages(_z_transport_unicast_t *ztu, _z_transport_peer_unicast_t *peer,
                                              size_t to_read) {
    // Wrap the main buffer to_read bytes
    _z_zbuf_t zbuf;
    if (peer->flow_state == _Z_FLOW_STATE_READY) {
        zbuf = _z_zbuf_view(&peer->flow_buff, to_read);
    } else {
        zbuf = _z_zbuf_view(&ztu->_common._zbuf, to_read);
    }

    peer->common._received = true;
    while (_z_zbuf_len(&zbuf) > 0) {
        // Decode one session message
        _z_transport_message_t t_msg;
        z_result_t ret = _z_transport_message_decode(&t_msg, &zbuf);

        if (ret != _Z_RES_OK) {
            _Z_INFO("Connection compromised due to malformed message: %d", ret);
            return ret;
        }
        ret = _z_unicast_handle_transport_message(ztu, &t_msg, peer);
        if (ret != _Z_RES_OK) {
            if (ret != _Z_ERR_CONNECTION_CLOSED) {
                _Z_WARN("Connection compromised due to message processing error: %d", ret);
            }
            return ret;
        }
    }
    // Move the read position of the read buffer
    if (peer->flow_state == _Z_FLOW_STATE_READY) {
        _z_zbuf_set_rpos(&peer->flow_buff, _z_zbuf_get_rpos(&peer->flow_buff) + to_read);
    } else {
        _z_zbuf_set_rpos(&ztu->_common._zbuf, _z_zbuf_get_rpos(&ztu->_common._zbuf) + to_read);
    }

    if (_z_unicast_update_rx_buffer(ztu) != _Z_RES_OK) {
        _Z_ERROR("Connection closed due to lack of memory to allocate rx buffer");
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    return _Z_RES_OK;
}

static bool _z_unicast_client_read(_z_transport_unicast_t *ztu, _z_transport_peer_unicast_t *peer, size_t *to_read) {
    switch (ztu->_common._link->_cap._flow) {
        case Z_LINK_CAP_FLOW_STREAM:
            if (_z_zbuf_len(&ztu->_common._zbuf) < _Z_MSG_LEN_ENC_SIZE) {
                _z_link_socket_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, peer->_socket);
                if (_z_zbuf_len(&ztu->_common._zbuf) < _Z_MSG_LEN_ENC_SIZE) {
                    _z_zbuf_compact(&ztu->_common._zbuf);
                    return false;
                }
            }
            // Get stream size
            *to_read = _z_read_stream_size(&ztu->_common._zbuf);
            // Read data
            if (_z_zbuf_len(&ztu->_common._zbuf) < *to_read) {
                _z_link_socket_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, peer->_socket);
                if (_z_zbuf_len(&ztu->_common._zbuf) < *to_read) {
                    _z_zbuf_set_rpos(&ztu->_common._zbuf, _z_zbuf_get_rpos(&ztu->_common._zbuf) - _Z_MSG_LEN_ENC_SIZE);
                    _z_zbuf_compact(&ztu->_common._zbuf);
                    return false;
                }
            }
            break;
        case Z_LINK_CAP_FLOW_DATAGRAM:
            _z_zbuf_compact(&ztu->_common._zbuf);
            *to_read = _z_link_socket_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, peer->_socket);
            if (*to_read == SIZE_MAX) {
                return false;
            }
            break;
        default:
            break;
    }
    return true;
}

z_result_t _zp_unicast_read(_z_transport_unicast_t *ztu, bool single_read) {
    _z_transport_peer_unicast_t *curr_peer = _z_transport_peer_unicast_slist_value(ztu->_peers);
    if (curr_peer == NULL) {
        _Z_ERROR("Invalid router endpoint\n");
        _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_RX_FAILED);
    }
    // Read & process a single message
    if (single_read) {
        _z_transport_message_t t_msg;
        _Z_RETURN_IF_ERR(_z_unicast_recv_t_msg(ztu, &t_msg));
        _Z_CLEAN_RETURN_IF_ERR(_z_unicast_handle_transport_message(ztu, &t_msg, curr_peer), _z_t_msg_clear(&t_msg));
        _z_t_msg_clear(&t_msg);
        // Update buffer
        _Z_RETURN_IF_ERR(_z_unicast_update_rx_buffer(ztu));
    } else {
        // Prepare buffer
        _z_zbuf_reset(&ztu->_common._zbuf);
        size_t to_read = 0;
        // Retrieve data if any
        if (_z_unicast_client_read(ztu, curr_peer, &to_read)) {
            // Process data
            _Z_RETURN_IF_ERR(_z_unicast_process_messages(ztu, curr_peer, to_read))
        } else {
            return _Z_NO_DATA_PROCESSED;
        }
    }
    return _Z_RES_OK;
}

#if Z_FEATURE_UNICAST_PEER == 1
static z_result_t _z_unicast_handle_remaining_data(_z_transport_unicast_t *ztu, _z_transport_peer_unicast_t *peer,
                                                   size_t extra_size, size_t *to_read, bool *message_to_process) {
    *message_to_process = false;
    if (extra_size < _Z_MSG_LEN_ENC_SIZE) {
        peer->flow_state = _Z_FLOW_STATE_PENDING_SIZE;
        peer->flow_curr_size = _z_zbuf_read(&ztu->_common._zbuf);
        return _Z_RES_OK;
    }
    // Get stream size
    *to_read = _z_read_stream_size(&ztu->_common._zbuf);
    if (_z_zbuf_len(&ztu->_common._zbuf) < *to_read) {
        peer->flow_state = _Z_FLOW_STATE_PENDING_DATA;
        peer->flow_curr_size = (uint16_t)*to_read;
        peer->flow_buff = _z_zbuf_make(peer->flow_curr_size);
        if (_z_zbuf_capacity(&peer->flow_buff) != peer->flow_curr_size) {
            _Z_ERROR("Not enough memory to allocate flow state buffer");
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        _z_zbuf_copy_bytes(&peer->flow_buff, &ztu->_common._zbuf);
        return _Z_RES_OK;
    }
    *message_to_process = true;
    return _Z_RES_OK;
}

static int _z_unicast_peer_read(_z_transport_unicast_t *ztu, _z_transport_peer_unicast_t *peer, size_t *to_read) {
    // If we receive fragmented data we have to store it on a separate buffer
    size_t read_size = 0;
    switch (ztu->_common._link->_cap._flow) {
        case Z_LINK_CAP_FLOW_STREAM:
            switch (peer->flow_state) {
                case _Z_FLOW_STATE_READY:
                    peer->flow_state = _Z_FLOW_STATE_INACTIVE;
                    peer->flow_curr_size = 0;
                    _z_zbuf_clear(&peer->flow_buff);  // fall through
                default:                              // fall through
                case _Z_FLOW_STATE_INACTIVE:
                    read_size = _z_link_socket_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, peer->_socket);
                    if (read_size == 0) {
                        _Z_DEBUG("Socket closed");
                        return _Z_UNICAST_PEER_READ_STATUS_SOCKET_CLOSED;
                    } else if (read_size == SIZE_MAX) {
                        return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
                    }
                    if (_z_zbuf_len(&ztu->_common._zbuf) < _Z_MSG_LEN_ENC_SIZE) {
                        peer->flow_state = _Z_FLOW_STATE_PENDING_SIZE;
                        peer->flow_curr_size = _z_zbuf_read(&ztu->_common._zbuf);
                        return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
                    }
                    // Get stream size
                    *to_read = _z_read_stream_size(&ztu->_common._zbuf);
                    // Read data if needed
                    read_size = _z_zbuf_len(&ztu->_common._zbuf);
                    if (read_size < *to_read) {
                        peer->flow_state = _Z_FLOW_STATE_PENDING_DATA;
                        peer->flow_curr_size = (uint16_t)*to_read;
                        peer->flow_buff = _z_zbuf_make(peer->flow_curr_size);
                        if (_z_zbuf_capacity(&peer->flow_buff) != peer->flow_curr_size) {
                            _Z_ERROR("Not enough memory to allocate flow state buffer");
                            return _Z_UNICAST_PEER_READ_STATUS_CRITICAL_ERROR;
                        }
                        _z_zbuf_copy_bytes(&peer->flow_buff, &ztu->_common._zbuf);
                        return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
                    }
                    break;
                case _Z_FLOW_STATE_PENDING_SIZE:
                    read_size = _z_link_socket_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, peer->_socket);
                    if (read_size == 0) {
                        _Z_DEBUG("Socket closed");
                        return _Z_UNICAST_PEER_READ_STATUS_SOCKET_CLOSED;
                    } else if (read_size == SIZE_MAX) {
                        return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
                    }
                    peer->flow_curr_size += (uint16_t)(_z_zbuf_read(&ztu->_common._zbuf) << 8);
                    *to_read = peer->flow_curr_size;
                    if (_z_zbuf_len(&ztu->_common._zbuf) < *to_read) {
                        peer->flow_state = _Z_FLOW_STATE_PENDING_DATA;
                        peer->flow_buff = _z_zbuf_make(peer->flow_curr_size);
                        if (_z_zbuf_capacity(&peer->flow_buff) != peer->flow_curr_size) {
                            _Z_ERROR("Not enough memory to allocate flow state buffer");
                            return _Z_UNICAST_PEER_READ_STATUS_CRITICAL_ERROR;
                        }
                        _z_zbuf_copy_bytes(&peer->flow_buff, &ztu->_common._zbuf);
                        return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
                    }
                    break;
                case _Z_FLOW_STATE_PENDING_DATA:
                    read_size = _z_link_socket_recv_zbuf(ztu->_common._link, &peer->flow_buff, peer->_socket);
                    if (read_size == 0) {
                        _Z_DEBUG("Socket closed");
                        return _Z_UNICAST_PEER_READ_STATUS_SOCKET_CLOSED;
                    } else if (read_size == SIZE_MAX) {
                        return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
                    }
                    *to_read = peer->flow_curr_size;
                    if (_z_zbuf_len(&peer->flow_buff) < *to_read) {
                        return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
                    } else {
                        peer->flow_state = _Z_FLOW_STATE_READY;
                    }
                    break;
            }

            break;
        case Z_LINK_CAP_FLOW_DATAGRAM:
            *to_read = _z_link_socket_recv_zbuf(ztu->_common._link, &ztu->_common._zbuf, peer->_socket);
            if (*to_read == SIZE_MAX) {
                return _Z_UNICAST_PEER_READ_STATUS_PENDING_DATA;
            }
            break;
        default:
            break;
    }
    return _Z_UNICAST_PEER_READ_STATUS_OK;
}

static z_result_t _zp_unicast_process_peer_event(_z_transport_unicast_t *ztu) {
    _z_transport_peer_mutex_lock(&ztu->_common);
    _z_transport_peer_unicast_slist_t *curr_list = ztu->_peers;
    _z_transport_peer_unicast_slist_t *prev = NULL;
    _z_transport_peer_unicast_slist_t *prev_drop = NULL;
    size_t to_read = 0;
    while (curr_list != NULL) {
        bool drop_peer = false;
        _z_transport_peer_unicast_t *curr_peer = _z_transport_peer_unicast_slist_value(curr_list);
        if (curr_peer->_pending) {
            curr_peer->_pending = false;
            // Read data from socket
            int res = _z_unicast_peer_read(ztu, curr_peer, &to_read);
            if (res == _Z_UNICAST_PEER_READ_STATUS_OK) {  // Messages to process
                bool message_to_process = false;
                do {
                    message_to_process = false;
                    // Process one message
                    if (_z_unicast_process_messages(ztu, curr_peer, to_read) != _Z_RES_OK) {
                        // Failed to process, drop peer
                        _Z_ERROR("Dropping peer due to processing error");
                        drop_peer = true;
                        prev_drop = prev;
                        break;
                    } else if (curr_peer->flow_state != _Z_FLOW_STATE_READY) {
                        // Process remaining data
                        size_t extra_data = _z_zbuf_len(&ztu->_common._zbuf);
                        if (extra_data > 0) {
                            _Z_RETURN_IF_ERR(_z_unicast_handle_remaining_data(ztu, curr_peer, extra_data, &to_read,
                                                                              &message_to_process));
                        }
                    }
                } while (message_to_process);
            } else if (res == _Z_UNICAST_PEER_READ_STATUS_SOCKET_CLOSED) {
                drop_peer = true;
                prev_drop = prev;
            } else if (res == _Z_UNICAST_PEER_READ_STATUS_CRITICAL_ERROR) {
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
        }
        // Update previous only if current node is not dropped
        if (!drop_peer) {
            prev = curr_list;
        }
        // Progress list
        curr_list = _z_transport_peer_unicast_slist_next(curr_list);
        // Drop peer if needed
        if (drop_peer) {
            _Z_DEBUG("Dropping peer");
            _z_session_t *zs = _z_transport_common_get_session(&ztu->_common);
#if Z_FEATURE_CONNECTIVITY == 1
            _z_connectivity_peer_event_data_t disconnected_peer = {0};
            uint16_t mtu = 0;
            bool is_streamed = false;
            bool is_reliable = false;
            _z_transport_get_link_properties(&ztu->_common, &mtu, &is_streamed, &is_reliable);
            _z_connectivity_peer_event_data_copy_from_common(&disconnected_peer, &curr_peer->common);
#endif
            _z_interest_peer_disconnected(zs, &curr_peer->common);
            ztu->_peers = _z_transport_peer_unicast_slist_drop_element(ztu->_peers, prev_drop);
#if Z_FEATURE_CONNECTIVITY == 1
            _z_transport_peer_mutex_unlock(&ztu->_common);
            _z_connectivity_peer_disconnected(zs, &disconnected_peer, false, mtu, is_streamed, is_reliable);
            _z_connectivity_peer_event_data_clear(&disconnected_peer);
            _z_transport_peer_mutex_lock(&ztu->_common);
            curr_list = ztu->_peers;
            prev = NULL;
            prev_drop = NULL;
            _z_zbuf_reset(&ztu->_common._zbuf);
            continue;
#endif
        }
        _z_zbuf_reset(&ztu->_common._zbuf);
    }
    _z_transport_peer_mutex_unlock(&ztu->_common);
    return _Z_RES_OK;
}
#endif

_z_fut_fn_result_t _zp_unicast_read_task_fn(void *ztu_arg, _z_executor_t *executor) {
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
        size_t to_read = 0;
        // Retrieve data
        if (_z_unicast_client_read(ztu, curr_peer, &to_read) &&
            _z_unicast_process_messages(ztu, curr_peer, to_read) != _Z_RES_OK) {
            _Z_INFO("Read task failed, closing session\n");
            return _zp_unicast_failed_result(ztu, executor);
        }
    }
#if Z_FEATURE_UNICAST_PEER == 1
    if (mode == Z_WHATAMI_PEER) {
        _z_transport_peer_mutex_lock(&ztu->_common);
        bool has_peers = !_z_transport_peer_unicast_slist_is_empty(ztu->_peers);
        _z_transport_peer_mutex_unlock(&ztu->_common);
        if (!has_peers) {
            // TODO: suspend or finish the task and restart it when a new connection is established.
            return _z_fut_fn_result_wake_up_after(100);
        } else {
#if Z_FEATURE_MULTI_THREAD == 1
            z_result_t wait_res = _z_socket_wait_event(&ztu->_peers, &ztu->_common._mutex_peer);
#else
            z_result_t wait_res = _z_socket_wait_event(&ztu->_peers, NULL);
#endif
            if (wait_res == _Z_RES_OK && _zp_unicast_process_peer_event(ztu) != _Z_RES_OK) {
                // TODO: Close transport on error. Probably we should just close the failed peer and
                // initiate reconnection task
                return _z_fut_fn_result_ready();
            }
        }
    }
#endif
    return _z_fut_fn_result_continue();
}
#endif  // Z_FEATURE_UNICAST_TRANSPORT == 1
