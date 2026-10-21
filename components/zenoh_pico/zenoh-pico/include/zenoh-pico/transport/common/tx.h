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

#ifndef ZENOH_PICO_TRANSPORT_TX_H
#define ZENOH_PICO_TRANSPORT_TX_H

#include "zenoh-pico/link/link.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

void __unsafe_z_prepare_wbuf(_z_wbuf_t *buf, uint8_t link_flow_capability);
void __unsafe_z_finalize_wbuf(_z_wbuf_t *buf, uint8_t link_flow_capability);
/*This function is unsafe because it operates in potentially concurrent
        data.*Make sure that the following mutexes are locked before calling this function : *-ztu->mutex_tx */
z_result_t __unsafe_z_serialize_zenoh_fragment(_z_wbuf_t *dst, _z_wbuf_t *src, z_reliability_t reliability, size_t sn,
                                               bool first);

/*------------------ Transmission and Reception helpers ------------------*/
z_result_t _z_transport_tx_send_t_msg(_z_transport_common_t *ztc, const _z_transport_message_t *t_msg,
                                      _z_transport_peer_unicast_slist_t *peers);
z_result_t _z_transport_tx_send_t_msg_wrapper(_z_transport_common_t *ztc, const _z_transport_message_t *t_msg);
z_result_t _z_send_t_msg(_z_transport_t *zt, const _z_transport_message_t *t_msg);
z_result_t _z_link_send_t_msg(const _z_link_t *zl, const _z_transport_message_t *t_msg, _z_sys_net_socket_t *socket);
z_result_t _z_send_n_msg(_z_session_t *zn, const _z_network_message_t *n_msg, z_reliability_t reliability,
                         z_congestion_control_t cong_ctrl, void *peer);
z_result_t _z_send_n_batch(_z_session_t *zn, z_congestion_control_t cong_ctrl);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_TRANSPORT_TX_H */
