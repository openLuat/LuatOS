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

#ifndef ZENOH_PICO_MULTICAST_READ_H
#define ZENOH_PICO_MULTICAST_READ_H

#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _zp_multicast_read(_z_transport_multicast_t *ztm, bool single_read);
_z_fut_fn_result_t _zp_multicast_read_task_fn(void *ztm_arg, _z_executor_t *executor);
#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_MULTICAST_READ_H */
