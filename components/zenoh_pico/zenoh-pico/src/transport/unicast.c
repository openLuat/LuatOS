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

#include "zenoh-pico/transport/unicast.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/link/link.h"
#include "zenoh-pico/transport/common/rx.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/multicast/rx.h"
#include "zenoh-pico/transport/unicast/lease.h"
#include "zenoh-pico/transport/unicast/read.h"
#include "zenoh-pico/transport/unicast/rx.h"
#include "zenoh-pico/transport/utils.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/uuid.h"

#if Z_FEATURE_UNICAST_TRANSPORT == 1
void _zp_unicast_fetch_zid(const _z_transport_t *zt, _z_closure_zid_t *callback) {
    void *ctx = callback->context;
    _z_transport_peer_unicast_slist_t *l = zt->_transport._unicast._peers;
    for (; l != NULL; l = _z_transport_peer_unicast_slist_next(l)) {
        _z_transport_peer_unicast_t *val = _z_transport_peer_unicast_slist_value(l);
        z_id_t id = val->common._remote_zid;
        callback->call(&id, ctx);
    }
}

void _zp_unicast_info_session(const _z_transport_t *zt, _z_config_t *ps, int mode) {
    uint_fast8_t config_entry = (mode == Z_WHATAMI_CLIENT) ? Z_INFO_ROUTER_PID_KEY : Z_INFO_PEER_PID_KEY;
    _z_transport_peer_unicast_slist_t *xs = zt->_transport._unicast._peers;
    while (xs != NULL) {
        _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(xs);
        _z_string_t remote_zid_str = _z_id_to_string(&peer->common._remote_zid);
        _zp_config_insert_string(ps, config_entry, &remote_zid_str);
        _z_string_clear(&remote_zid_str);
        xs = _z_transport_peer_unicast_slist_next(xs);
    }
}

#else
void _zp_unicast_fetch_zid(const _z_transport_t *zt, _z_closure_zid_t *callback) {
    _ZP_UNUSED(zt);
    _ZP_UNUSED(callback);
}

void _zp_unicast_info_session(const _z_transport_t *zt, _z_config_t *ps, int mode) {
    _ZP_UNUSED(zt);
    _ZP_UNUSED(ps);
    _ZP_UNUSED(mode);
}
#endif  // Z_FEATURE_UNICAST_TRANSPORT == 1
