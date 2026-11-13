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

#include "zenoh-pico/net/query.h"

#include "zenoh-pico/net/session.h"
#include "zenoh-pico/session/loopback.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/utils/locality.h"
#include "zenoh-pico/utils/logging.h"

static void _z_query_clear_inner(_z_query_t *q) {
    _z_declared_keyexpr_clear(&q->_key);
    _z_value_clear(&q->_value);
    _z_bytes_drop(&q->_attachment);
    _z_string_clear(&q->_parameters);
    _z_session_weak_drop(&q->_zn);
}

z_result_t _z_session_send_reply_final(_z_session_t *session, uint32_t query_id, bool is_local) {
    if (is_local) {
        return _z_session_deliver_reply_final_locally(session, query_id);
    } else {
        _z_zenoh_message_t z_msg;
        _z_n_msg_make_response_final(&z_msg, query_id);
        z_result_t ret = _z_send_n_msg(session, &z_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL);
        _z_msg_clear(&z_msg);
        return ret;
    }
}

z_result_t _z_query_send_reply_final(_z_query_t *q) {
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&q->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
    }

    z_result_t ret = _z_session_send_reply_final(_Z_RC_IN_VAL(&sess_rc), q->_request_id, q->_is_local);
    _z_session_rc_drop(&sess_rc);
    return ret;
}

void _z_query_clear(_z_query_t *q) {
    // Send REPLY_FINAL message
    if (!_Z_RC_IS_NULL(&q->_zn) && _z_query_send_reply_final(q) != _Z_RES_OK) {
        _Z_ERROR("Query send REPLY_FINAL transport failure !");
    }
    // Clean up memory
    _z_query_clear_inner(q);
}

void _z_query_free(_z_query_t **query) {
    _z_query_t *ptr = *query;
    if (ptr != NULL) {
        _z_query_clear(ptr);
        z_free(ptr);
        *query = NULL;
    }
}

#if Z_FEATURE_QUERYABLE == 1
void _z_queryable_clear(_z_queryable_t *qbl) {
    _z_session_weak_drop(&qbl->_zn);
    _z_sync_group_drop(&qbl->_callback_drop_sync_group);
    *qbl = _z_queryable_null();
}

void _z_queryable_free(_z_queryable_t **qbl) {
    _z_queryable_t *ptr = *qbl;

    if (ptr != NULL) {
        _z_queryable_clear(ptr);

        z_free(ptr);
        *qbl = NULL;
    }
}
#endif
