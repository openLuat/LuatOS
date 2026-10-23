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

#ifndef ZENOH_PICO_LINK_MANAGER_H
#define ZENOH_PICO_LINK_MANAGER_H

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/link/link.h"
#include "zenoh-pico/utils/config.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_endpoint_tcp_valid(_z_endpoint_t *ep);
z_result_t _z_new_peer_tcp(_z_endpoint_t *endpoint, _z_sys_net_socket_t *socket);
z_result_t _z_new_link_tcp(_z_link_t *zl, _z_endpoint_t *ep);

#if Z_FEATURE_LINK_UDP_UNICAST == 1
z_result_t _z_endpoint_udp_unicast_valid(_z_endpoint_t *ep);
z_result_t _z_new_link_udp_unicast(_z_link_t *zl, _z_endpoint_t ep);
#endif
#if Z_FEATURE_LINK_UDP_MULTICAST == 1
z_result_t _z_endpoint_udp_multicast_valid(_z_endpoint_t *ep);
z_result_t _z_new_link_udp_multicast(_z_link_t *zl, _z_endpoint_t ep);
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
z_result_t _z_endpoint_bt_valid(_z_endpoint_t *ep);
z_result_t _z_new_link_bt(_z_link_t *zl, _z_endpoint_t ep);
#endif
#if Z_FEATURE_LINK_SERIAL == 1
z_result_t _z_endpoint_serial_valid(_z_endpoint_t *ep);
z_result_t _z_new_link_serial(_z_link_t *zl, _z_endpoint_t ep);
#endif
#if Z_FEATURE_LINK_WS == 1
z_result_t _z_endpoint_ws_valid(_z_endpoint_t *ep);
z_result_t _z_new_link_ws(_z_link_t *zl, _z_endpoint_t *ep);
#endif
#if Z_FEATURE_LINK_TLS == 1
z_result_t _z_endpoint_tls_valid(_z_endpoint_t *ep);
z_result_t _z_new_peer_tls(_z_endpoint_t *endpoint, _z_sys_net_socket_t *socket, const _z_config_t *session_cfg);
z_result_t _z_new_link_tls(_z_link_t *zl, _z_endpoint_t *ep, const _z_config_t *session_cfg);
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_LINK_MANAGER_H */
