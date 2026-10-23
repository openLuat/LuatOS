//
// Copyright (c) 2025 ZettaScale Technology
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

#ifndef ZENOH_PICO_SESSION_LOOPBACK_H
#define ZENOH_PICO_SESSION_LOOPBACK_H

#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/net/query.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_session_deliver_push_locally(_z_session_t *zn, const _z_keyexpr_t *keyexpr, _z_bytes_t *payload,
                                           _z_encoding_t *encoding, z_sample_kind_t kind, _z_n_qos_t qos,
                                           const _z_timestamp_t *timestamp, _z_bytes_t *attachment,
                                           z_reliability_t reliability, const _z_source_info_t *source_info);

z_result_t _z_session_deliver_query_locally(_z_session_t *zn, const _z_keyexpr_t *keyexpr, const _z_slice_t *parameters,
                                            z_consolidation_mode_t consolidation, _z_bytes_t *payload,
                                            _z_encoding_t *encoding, _z_bytes_t *attachment,
                                            const _z_source_info_t *source_info, _z_zint_t qid, uint64_t timeout_ms,
                                            _z_n_qos_t qos, bool implicit_anyke);

z_result_t _z_session_deliver_reply_locally(const _z_query_t *query, const _z_session_rc_t *zn,
                                            const _z_declared_keyexpr_t *keyexpr, _z_bytes_t *payload,
                                            _z_encoding_t *encoding, z_sample_kind_t kind, _z_n_qos_t qos,
                                            const _z_timestamp_t *timestamp, _z_bytes_t *attachment,
                                            const _z_source_info_t *source_info);

z_result_t _z_session_deliver_reply_err_locally(const _z_query_t *query, const _z_session_rc_t *zn, _z_bytes_t *payload,
                                                _z_encoding_t *encoding, _z_n_qos_t qos);

z_result_t _z_session_deliver_reply_final_locally(_z_session_t *zn, _z_zint_t rid);

#if defined(Z_LOOPBACK_TESTING)
typedef _z_transport_common_t *(*_z_session_transport_override_fn)(_z_session_t *);
void _z_session_set_transport_common_override(_z_session_transport_override_fn fn);

typedef z_result_t (*_z_session_send_override_fn)(_z_session_t *zn, const _z_network_message_t *n_msg,
                                                  z_reliability_t reliability, z_congestion_control_t cong_ctrl,
                                                  void *peer, bool *handled);
void _z_transport_set_send_n_msg_override(_z_session_send_override_fn fn);
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SESSION_LOOPBACK_H */
