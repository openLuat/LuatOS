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

#ifndef ZENOH_PICO_SYSTEM_LINK_WS_H
#define ZENOH_PICO_SYSTEM_LINK_WS_H

#include <stdint.h>

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_LINK_WS == 1

typedef struct {
    _z_sys_net_socket_t _sock;
    _z_sys_net_endpoint_t _rep;
} _z_ws_socket_t;

z_result_t _z_create_endpoint_ws(_z_sys_net_endpoint_t *ep, const char *s_addr, const char *s_port);
void _z_free_endpoint_ws(_z_sys_net_endpoint_t *ep);

z_result_t _z_open_ws(_z_sys_net_socket_t *sock, const _z_sys_net_endpoint_t rep, uint32_t tout);
z_result_t _z_listen_ws(_z_sys_net_socket_t *sock, const _z_sys_net_endpoint_t rep);
void _z_close_ws(_z_sys_net_socket_t *sock);
size_t _z_read_exact_ws(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len);
size_t _z_read_ws(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len);
size_t _z_send_ws(const _z_sys_net_socket_t sock, const uint8_t *ptr, size_t len);
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SYSTEM_LINK_WS_H */
