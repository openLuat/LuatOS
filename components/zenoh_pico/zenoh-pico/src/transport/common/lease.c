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

#include "zenoh-pico/transport/common/lease.h"

#include <stddef.h>

#include "zenoh-pico/transport/multicast/lease.h"
#include "zenoh-pico/transport/unicast/lease.h"

z_result_t _z_send_keep_alive(_z_transport_t *zt) {
    z_result_t ret = _Z_RES_OK;
    switch (zt->_type) {
#if Z_FEATURE_UNICAST_TRANSPORT == 1
        case _Z_TRANSPORT_UNICAST_TYPE:
            ret = _zp_unicast_send_keep_alive(&zt->_transport._unicast);
            break;
#endif
#if Z_FEATURE_MULTICAST_TRANSPORT == 1
        case _Z_TRANSPORT_MULTICAST_TYPE:
            ret = _zp_multicast_send_keep_alive(&zt->_transport._multicast);
            break;
#endif
#if Z_FEATURE_RAWETH_TRANSPORT == 1
        case _Z_TRANSPORT_RAWETH_TYPE:
            ret = _zp_multicast_send_keep_alive(&zt->_transport._raweth);
            break;
#endif
        default:
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
            ret = _Z_ERR_TRANSPORT_NOT_AVAILABLE;
            break;
    }
    return ret;
}

z_result_t _z_send_join(_z_transport_t *zt) {
    z_result_t ret = _Z_RES_OK;
    // Join task only applies to multicast transports
    switch (zt->_type) {
#if Z_FEATURE_MULTICAST_TRANSPORT == 1
        case _Z_TRANSPORT_MULTICAST_TYPE:
            ret = _zp_multicast_send_join(&zt->_transport._multicast);
            break;
#endif
#if Z_FEATURE_RAWETH_TRANSPORT == 1
        case _Z_TRANSPORT_RAWETH_TYPE:
            ret = _zp_multicast_send_join(&zt->_transport._raweth);
            break;
#endif
        default:
            _ZP_UNUSED(zt);
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
            ret = _Z_ERR_TRANSPORT_NOT_AVAILABLE;
            break;
    }
    return ret;
}
