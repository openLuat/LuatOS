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

#ifndef ZENOH_PICO_TRANSPORT_RX_H
#define ZENOH_PICO_TRANSPORT_RX_H

#include "zenoh-pico/link/link.h"
#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

/*------------------ Transmission and Reception helpers ------------------*/
size_t _z_read_stream_size(_z_zbuf_t *zbuf);
// Socket is assumed to be in blocking mode with a finite timeout.
z_result_t _z_link_recv_t_msg(_z_transport_message_t *t_msg, const _z_link_t *zl, _z_sys_net_socket_t *socket,
                              z_clock_t recv_deadline);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_TRANSPORT_RX_H */
