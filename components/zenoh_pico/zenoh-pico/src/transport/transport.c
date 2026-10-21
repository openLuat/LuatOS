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

#include "zenoh-pico/transport/multicast/transport.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast/transport.h"
#include "zenoh-pico/utils/logging.h"

_z_transport_common_t *_z_transport_get_common(_z_transport_t *zt) {
    switch (zt->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            return &zt->_transport._unicast._common;
        case _Z_TRANSPORT_MULTICAST_TYPE:
            return &zt->_transport._multicast._common;
        case _Z_TRANSPORT_RAWETH_TYPE:
            return &zt->_transport._raweth._common;
        default:
            _Z_DEBUG("None transport, it should never happens");
            return NULL;
    }
}

z_result_t _z_send_close(_z_transport_t *zt, uint8_t reason, bool link_only) {
    z_result_t ret = _Z_RES_OK;
    // Call transport function
    switch (zt->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            ret = _z_unicast_send_close(&zt->_transport._unicast, reason, link_only);
            break;
        case _Z_TRANSPORT_MULTICAST_TYPE:
        case _Z_TRANSPORT_RAWETH_TYPE:
            ret = _z_multicast_send_close(&zt->_transport._multicast, reason, link_only);
            break;
        default:
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
            ret = _Z_ERR_TRANSPORT_NOT_AVAILABLE;
            break;
    }
    return ret;
}

z_result_t _z_transport_close(_z_transport_t *zt, uint8_t reason) { return _z_send_close(zt, reason, false); }

void _z_transport_clear(_z_transport_t *zt) {
    switch (zt->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            _z_unicast_transport_clear(&zt->_transport._unicast);
            break;
        case _Z_TRANSPORT_MULTICAST_TYPE:
        case _Z_TRANSPORT_RAWETH_TYPE:
            _z_multicast_transport_clear(&zt->_transport._multicast);
            break;
        default:
            return;
    }
    _z_transport_get_common(zt)->_state = _Z_TRANSPORT_STATE_CLOSED;
    zt->_type = _Z_TRANSPORT_NONE;
}

void _z_transport_free(_z_transport_t **zt) {
    _z_transport_t *ptr = *zt;
    if (ptr == NULL) {
        return;
    }
    // Clear and free transport
    _z_transport_clear(ptr);
    z_free(ptr);
    *zt = NULL;
}

#if Z_FEATURE_BATCHING == 1
bool _z_transport_start_batching(_z_transport_t *zt) {
    _z_transport_common_t *ztc = _z_transport_get_common(zt);
    if (ztc->_batch_state == _Z_BATCHING_ACTIVE) {
        return false;
    }
    ztc->_batch_count = 0;
    ztc->_batch_state = _Z_BATCHING_ACTIVE;

#if Z_FEATURE_BATCH_TX_MUTEX == 1
    _z_transport_tx_mutex_lock(ztc, true);
#endif
#if Z_FEATURE_BATCH_PEER_MUTEX == 1
    _z_transport_peer_mutex_lock(ztc);
#endif
    return true;
}

void _z_transport_stop_batching(_z_transport_t *zt) {
    _z_transport_common_t *ztc = _z_transport_get_common(zt);

#if Z_FEATURE_BATCH_TX_MUTEX == 1
    _z_transport_tx_mutex_unlock(ztc);
#endif
#if Z_FEATURE_BATCH_PEER_MUTEX == 1
    _z_transport_peer_mutex_unlock(ztc);
#endif
    ztc->_batch_state = _Z_BATCHING_IDLE;
}
#endif
