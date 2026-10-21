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

#ifndef INCLUDE_ZENOH_PICO_TRANSPORT_MANAGER_H
#define INCLUDE_ZENOH_PICO_TRANSPORT_MANAGER_H

#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/link/manager.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

enum _z_peer_op_e {
    _Z_PEER_OP_OPEN = 0,
    _Z_PEER_OP_LISTEN = 1,
};

z_result_t _z_new_transport(_z_transport_t *zt, const _z_id_t *bs, const _z_string_t *locator, z_whatami_t mode,
                            int peer_op, const _z_config_t *session_cfg, _z_runtime_t *runtime);
z_result_t _z_new_peer(_z_transport_t *zt, const _z_id_t *session_id, const _z_string_t *locator,
                       const _z_config_t *session_cfg);
void _z_free_transport(_z_transport_t **zt);

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_TRANSPORT_MANAGER_H */
