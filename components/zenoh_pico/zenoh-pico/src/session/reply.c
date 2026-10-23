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

#include "zenoh-pico/session/reply.h"

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/utils/logging.h"

z_result_t _z_trigger_reply_partial(_z_session_t *zn, _z_zint_t id, _z_wireexpr_t *key, _z_msg_reply_t *reply,
                                    _z_entity_global_id_t *replier_id, _z_transport_peer_common_t *peer) {
    z_result_t ret = _Z_RES_OK;

#if Z_FEATURE_QUERY == 1
    ret = _z_trigger_query_reply_partial(zn, id, key, &reply->_body._body._put,
                                         (reply->_body._is_put ? Z_SAMPLE_KIND_PUT : Z_SAMPLE_KIND_DELETE), replier_id,
                                         peer);
#else
    _ZP_UNUSED(zn);
    _ZP_UNUSED(id);
    _ZP_UNUSED(key);
    _ZP_UNUSED(reply);
    _ZP_UNUSED(replier_id);
    _ZP_UNUSED(peer);
#endif
    return ret;
}

z_result_t _z_trigger_reply_err(_z_session_t *zn, _z_zint_t id, _z_msg_err_t *error,
                                _z_entity_global_id_t *replier_id) {
    z_result_t ret = _Z_RES_OK;

#if Z_FEATURE_QUERY == 1
    ret = _z_trigger_query_reply_err(zn, id, error, replier_id);
#else
    _ZP_UNUSED(zn);
    _ZP_UNUSED(id);
    _ZP_UNUSED(error);
    _ZP_UNUSED(replier_id);
#endif
    return ret;
}

z_result_t _z_trigger_reply_final(_z_session_t *zn, _z_n_msg_response_final_t *final) {
    z_result_t ret = _Z_RES_OK;

#if Z_FEATURE_QUERY == 1
    // TODO check id to know where to dispatch
    _z_zint_t id = final->_request_id;
    _z_trigger_query_reply_final(zn, id);
#else
    _ZP_UNUSED(zn);
    _ZP_UNUSED(final);
#endif
    return ret;
}
