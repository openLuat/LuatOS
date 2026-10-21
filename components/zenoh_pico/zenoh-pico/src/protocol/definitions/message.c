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

#include "zenoh-pico/protocol/definitions/message.h"

#include <stdbool.h>

#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/network.h"

void _z_msg_reply_clear(_z_msg_reply_t *msg) { _z_push_body_clear(&msg->_body); }

void _z_msg_put_clear(_z_msg_put_t *msg) {
    _z_bytes_drop(&msg->_payload);
    _z_bytes_drop(&msg->_attachment);
    _z_encoding_clear(&msg->_encoding);
    _z_timestamp_clear(&msg->_commons._timestamp);
}

_z_msg_query_reqexts_t _z_msg_query_required_extensions(const _z_msg_query_t *msg) {
    return (_z_msg_query_reqexts_t){
        .body = _z_bytes_check(&msg->_ext_value.payload) || _z_encoding_check(&msg->_ext_value.encoding),
        .info = _z_id_check(msg->_ext_info._source_id.zid) || msg->_ext_info._source_id.eid != 0 ||
                msg->_ext_info._source_sn != 0,
        .attachment = _z_bytes_check(&msg->_ext_attachment),
    };
}

void _z_msg_query_clear(_z_msg_query_t *msg) {
    _z_slice_clear(&msg->_parameters);
    _z_bytes_drop(&msg->_ext_attachment);
    _z_value_clear(&msg->_ext_value);
    msg->_implicit_anyke = false;
}

void _z_msg_err_clear(_z_msg_err_t *err) {
    _z_encoding_clear(&err->_encoding);
    _z_bytes_drop(&err->_payload);
}
