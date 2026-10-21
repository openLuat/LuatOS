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

#ifndef ZENOH_PICO_SYSTEM_LINK_BT_H
#define ZENOH_PICO_SYSTEM_LINK_BT_H

#include <stdint.h>

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"

#if Z_FEATURE_LINK_BLUETOOTH == 1

#ifdef __cplusplus
extern "C" {
#endif

#define _Z_BT_MODE_MASTER 0
#define _Z_BT_MODE_SLAVE 1

#define _Z_BT_PROFILE_UNSUPPORTED 255
#define _Z_BT_PROFILE_SPP 0

typedef struct {
    _z_sys_net_socket_t _sock;
    char *_gname;
} _z_bt_socket_t;

z_result_t _z_open_bt(_z_sys_net_socket_t *sock, const char *gname, uint8_t mode, uint8_t profile, uint32_t tout);
z_result_t _z_listen_bt(_z_sys_net_socket_t *sock, const char *gname, uint8_t mode, uint8_t profile, uint32_t tout);
void _z_close_bt(_z_sys_net_socket_t *sock);
size_t _z_read_exact_bt(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len);
size_t _z_read_bt(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len);
size_t _z_send_bt(const _z_sys_net_socket_t sock, const uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif

#endif /* ZENOH_PICO_SYSTEM_LINK_BT_H */
