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

#ifndef ZENOH_PICO_UNICAST_H
#define ZENOH_PICO_UNICAST_H

#include "zenoh-pico/api/types.h"

#ifdef __cplusplus
extern "C" {
#endif

void _zp_unicast_fetch_zid(const _z_transport_t *zt, _z_closure_zid_t *callback);
void _zp_unicast_info_session(const _z_transport_t *zt, _z_config_t *ps, int mode);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UNICAST_H */
