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

#ifndef ZENOH_PICO_MULTICAST_RX_H
#define ZENOH_PICO_MULTICAST_RX_H

#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_multicast_recv_t_msg(_z_transport_multicast_t *ztm, _z_transport_message_t *t_msg, _z_slice_t *addr);
z_result_t _z_multicast_handle_transport_message(_z_transport_multicast_t *ztm, _z_transport_message_t *t_msg,
                                                 _z_slice_t *addr);
z_result_t _z_multicast_update_rx_buffer(_z_transport_multicast_t *ztm);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_TRANSPORT_LINK_RX_H */
