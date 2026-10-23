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

#include "zenoh-pico/transport/raweth/read.h"

#include <stddef.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/codec/transport.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/transport/multicast/rx.h"
#include "zenoh-pico/transport/raweth/rx.h"
#include "zenoh-pico/transport/unicast/rx.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_RAWETH_TRANSPORT == 1

z_result_t _zp_raweth_read(_z_transport_multicast_t *ztm, bool single_read) {
    z_result_t ret = _Z_RES_OK;
    _ZP_UNUSED(single_read);

    _z_slice_t addr;
    _z_transport_message_t t_msg;
    ret = _z_raweth_recv_t_msg(ztm, &t_msg, &addr);
    if (ret == _Z_RES_OK) {
        ret = _z_multicast_handle_transport_message(ztm, &t_msg, &addr);
        _z_t_msg_clear(&t_msg);
    }
    _z_slice_clear(&addr);
    ret = _z_raweth_update_rx_buff(ztm);
    if (ret != _Z_RES_OK) {
        _Z_ERROR("Failed to allocate rx buffer");
    }
    return ret;
}

_z_fut_fn_result_t _zp_raweth_read_task_fn(void *ztm_arg, _z_executor_t *executor) {
    _ZP_UNUSED(executor);
    _z_transport_multicast_t *ztm = (_z_transport_multicast_t *)ztm_arg;

    if (ztm->_common._state == _Z_TRANSPORT_STATE_CLOSED) {
        return _z_fut_fn_result_ready();
    } else if (ztm->_common._state == _Z_TRANSPORT_STATE_RECONNECTING) {
        return _z_fut_fn_result_suspend();
    }

    _z_transport_message_t t_msg;
    _z_slice_t addr = _z_slice_alias_buf(NULL, 0);

    // Read message from link
    z_result_t ret = _z_raweth_recv_t_msg(ztm, &t_msg, &addr);
    switch (ret) {
        case _Z_RES_OK:
            // Process message
            break;
        case _Z_ERR_TRANSPORT_RX_FAILED:
            // Drop message
            _z_slice_clear(&addr);
            return _z_fut_fn_result_continue();
        default:
            // Drop message & stop task
            _Z_ERROR("Connection closed due to malformed message: %d", ret);
            _z_slice_clear(&addr);
            return _z_fut_fn_result_ready();
    }
    // Process message
    ret = _z_multicast_handle_transport_message(ztm, &t_msg, &addr);
    if (ret != _Z_RES_OK) {
        _Z_ERROR("Connection closed due to message processing error: %d", ret);
        _z_slice_clear(&addr);
        return _z_fut_fn_result_ready();
    }
    _z_t_msg_clear(&t_msg);
    _z_slice_clear(&addr);
    if (_z_raweth_update_rx_buff(ztm) != _Z_RES_OK) {
        _Z_ERROR("Connection closed due to lack of memory to allocate rx buffer");
        return _z_fut_fn_result_ready();
    }
    return _z_fut_fn_result_continue();
}
#endif
