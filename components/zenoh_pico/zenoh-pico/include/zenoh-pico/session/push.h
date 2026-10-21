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

#include <stdint.h>

#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/message.h"

#ifndef ZENOH_PICO_SESSION_PUSH_H
#define ZENOH_PICO_SESSION_PUSH_H

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_trigger_push(_z_session_t *zn, _z_n_msg_push_t *push, z_reliability_t reliability,
                           _z_transport_peer_common_t *peer);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SESSION_PUSH_H */
