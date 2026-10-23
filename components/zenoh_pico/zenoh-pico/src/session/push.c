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

#include "zenoh-pico/session/push.h"

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/session/subscription.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_SUBSCRIPTION == 1
z_result_t _z_trigger_push(_z_session_t *zn, _z_n_msg_push_t *push, z_reliability_t reliability,
                           _z_transport_peer_common_t *peer) {
    z_result_t ret = _Z_RES_OK;

    // Memory cleaning must be done in the feature layer
    if (push->_body._is_put) {
        _z_msg_put_t *put = &push->_body._body._put;
        ret =
            _z_trigger_subscriptions_put(zn, &push->_key, &put->_payload, &put->_encoding, &put->_commons._timestamp,
                                         push->_qos, &put->_attachment, reliability, &put->_commons._source_info, peer);
    } else {
        _z_msg_del_t *del = &push->_body._body._del;
        ret = _z_trigger_subscriptions_del(zn, &push->_key, &del->_commons._timestamp, push->_qos, &del->_attachment,
                                           reliability, &del->_commons._source_info, peer);
    }
    return ret;
}
#else
z_result_t _z_trigger_push(_z_session_t *zn, _z_n_msg_push_t *push, z_reliability_t reliability,
                           _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(push);
    _ZP_UNUSED(reliability);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}
#endif
