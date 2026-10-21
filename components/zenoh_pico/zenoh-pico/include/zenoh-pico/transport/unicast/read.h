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

#ifndef ZENOH_PICO_UNICAST_READ_H
#define ZENOH_PICO_UNICAST_READ_H

#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_UNICAST_TRANSPORT == 1
z_result_t _zp_unicast_read(_z_transport_unicast_t *ztu, bool single_read);
_z_fut_fn_result_t _zp_unicast_read_task_fn(void *ztu_arg, _z_executor_t *executor);
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UNICAST_READ_H */
