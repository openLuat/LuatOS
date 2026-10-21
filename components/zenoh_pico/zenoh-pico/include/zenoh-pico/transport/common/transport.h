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

#ifndef ZENOH_PICO_COMMON_TRANSPORT_H
#define ZENOH_PICO_COMMON_TRANSPORT_H

#include "zenoh-pico/transport/transport.h"

#ifdef __cplusplus
extern "C" {
#endif

void _z_transport_common_clear(_z_transport_common_t *ztc);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COMMON_TRANSPORT_H*/
