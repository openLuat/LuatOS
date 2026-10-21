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

#include "zenoh-pico/transport/common/read.h"

#include <stddef.h>

#include "zenoh-pico/transport/multicast/read.h"
#include "zenoh-pico/transport/raweth/read.h"
#include "zenoh-pico/transport/unicast/read.h"

z_result_t _z_read(_z_transport_t *zt, bool single_read) {
    z_result_t ret = _Z_RES_OK;
    switch (zt->_type) {
#if Z_FEATURE_UNICAST_TRANSPORT == 1
        case _Z_TRANSPORT_UNICAST_TYPE:
            ret = _zp_unicast_read(&zt->_transport._unicast, single_read);
            break;
#endif
#if Z_FEATURE_MULTICAST_TRANSPORT == 1
        case _Z_TRANSPORT_MULTICAST_TYPE:
            ret = _zp_multicast_read(&zt->_transport._multicast, single_read);
            break;
#endif
#if Z_FEATURE_RAWETH_TRANSPORT == 1
        case _Z_TRANSPORT_RAWETH_TYPE:
            ret = _zp_raweth_read(&zt->_transport._raweth, single_read);
            break;
#endif
        default:
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
            ret = _Z_ERR_TRANSPORT_NOT_AVAILABLE;
            break;
    }
    return ret;
}
