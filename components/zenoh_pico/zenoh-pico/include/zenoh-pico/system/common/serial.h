//
// Copyright (c) 2024 ZettaScale Technology
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

#ifndef ZENOH_PICO_SYSTEM_COMMON_SERIAL_H
#define ZENOH_PICO_SYSTEM_COMMON_SERIAL_H

#include <stdint.h>

#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_connect_serial(const _z_sys_net_socket_t sock);
size_t _z_read_serial(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len);
size_t _z_send_serial(const _z_sys_net_socket_t sock, const uint8_t *ptr, size_t len);
size_t _z_read_exact_serial(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SYSTEM_COMMON_SERIAL_H */
