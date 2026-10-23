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

#ifndef ZENOH_PICO_UNICAST_TRANSPORT_H
#define ZENOH_PICO_UNICAST_TRANSPORT_H

#include "zenoh-pico/api/types.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_unicast_transport_create(_z_transport_t *zt, _z_link_t *zl,
                                       _z_transport_unicast_establish_param_t *param);
z_result_t _z_unicast_handshake_listen(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                       const _z_id_t *local_zid, z_whatami_t mode, _z_sys_net_socket_t *socket);
z_result_t _z_unicast_open_client(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                  const _z_id_t *local_zid);
z_result_t _z_unicast_open_peer(_z_transport_unicast_establish_param_t *param, const _z_link_t *zl,
                                const _z_id_t *local_zid, int peer_op, _z_sys_net_socket_t *socket);
z_result_t _z_unicast_send_close(_z_transport_unicast_t *ztu, uint8_t reason, bool link_only);
z_result_t _z_unicast_transport_close(_z_transport_unicast_t *ztu, uint8_t reason);
void _z_unicast_transport_clear(_z_transport_unicast_t *ztu);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UNICAST_TRANSPORT_H */
