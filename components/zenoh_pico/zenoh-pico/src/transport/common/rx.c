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

#include "zenoh-pico/protocol/codec/transport.h"
#include "zenoh-pico/transport/multicast/rx.h"
#include "zenoh-pico/transport/unicast/rx.h"
#include "zenoh-pico/utils/endianness.h"
#include "zenoh-pico/utils/logging.h"

/*------------------ Reception helper ------------------*/
size_t _z_read_stream_size(_z_zbuf_t *zbuf) {
    uint8_t stream_size[_Z_MSG_LEN_ENC_SIZE];
    // Read the bytes from stream
    for (uint8_t i = 0; i < _Z_MSG_LEN_ENC_SIZE; i++) {
        stream_size[i] = _z_zbuf_read(zbuf);
    }
    return _z_host_le_load16(stream_size);
}

z_result_t _z_link_recv_t_msg_cap_flow_stream(const _z_link_t *zl, _z_zbuf_t *zbf, _z_sys_net_socket_t *socket) {
    // Read the message length
    size_t read = _z_link_recv_exact_zbuf(zl, zbf, _Z_MSG_LEN_ENC_SIZE, NULL, socket);
    if (read == _Z_MSG_LEN_ENC_SIZE) {
        size_t len = 0;
        for (uint8_t i = 0; i < _Z_MSG_LEN_ENC_SIZE; i++) {
            len |= (size_t)(_z_zbuf_read(zbf) << (i * (uint8_t)8));
        }

        size_t writable = _z_zbuf_capacity(zbf) - _z_zbuf_len(zbf);
        if (writable >= len) {
            // Read enough bytes to decode the message
            if (_z_link_recv_exact_zbuf(zl, zbf, len, NULL, socket) != len) {
                _Z_ERROR_LOG(_Z_ERR_TRANSPORT_RX_FAILED);
                return _Z_ERR_TRANSPORT_RX_FAILED;
            }
        } else {
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NO_SPACE);
            return _Z_ERR_TRANSPORT_NO_SPACE;
        }
    } else if (read == SIZE_MAX) {
        return Z_ETIMEDOUT;
    } else {
        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_RX_FAILED);
        return _Z_ERR_TRANSPORT_RX_FAILED;
    }
    return _Z_RES_OK;
}

z_result_t _z_link_recv_t_msg_cap_flow_datagram(const _z_link_t *zl, _z_zbuf_t *zbf, _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(socket);
    if (_z_link_recv_zbuf(zl, zbf, NULL) == SIZE_MAX) {
        return Z_ETIMEDOUT;
    } else {
        return _Z_RES_OK;
    }
}

z_result_t _z_link_recv_t_msg(_z_transport_message_t *t_msg, const _z_link_t *zl, _z_sys_net_socket_t *socket,
                              z_clock_t recv_deadline) {
    // Create and prepare the buffer
    _z_zbuf_t zbf = _z_zbuf_make(Z_BATCH_UNICAST_SIZE);
    _z_zbuf_reset(&zbf);

    z_result_t ret = Z_ETIMEDOUT;
    while (ret == Z_ETIMEDOUT) {
        switch (zl->_cap._flow) {
            case Z_LINK_CAP_FLOW_STREAM:
                ret = _z_link_recv_t_msg_cap_flow_stream(zl, &zbf, socket);
                break;
            case Z_LINK_CAP_FLOW_DATAGRAM:
                ret = _z_link_recv_t_msg_cap_flow_datagram(zl, &zbf, socket);
                break;
            default:
                _Z_ERROR_LOG(_Z_ERR_GENERIC);
                ret = _Z_ERR_GENERIC;
                break;
        }
        if (ret == Z_ETIMEDOUT) {
            z_clock_t now = z_clock_now();
            if (zp_clock_elapsed_ms_since(&recv_deadline, &now) == 0) {
                ret = _Z_ERR_TRANSPORT_RX_DURATION_EXPIRED;
            }
        }
    }

    if (ret == _Z_RES_OK) {
        _z_transport_message_t l_t_msg;
        ret = _z_transport_message_decode(&l_t_msg, &zbf);
        if (ret == _Z_RES_OK) {
            _z_t_msg_copy(t_msg, &l_t_msg);
        }
    } else {
        _Z_ERROR_LOG(ret);
    }
    _z_zbuf_clear(&zbf);

    return ret;
}
