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

#ifndef ZENOH_PICO_LINK_CONFIG_RAWETH_H
#define ZENOH_PICO_LINK_CONFIG_RAWETH_H

#include "zenoh-pico/collections/intmap.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/link/link.h"

#ifdef __cplusplus
extern "C" {
#endif

#define RAWETH_SCHEMA "reth"

z_result_t _z_endpoint_raweth_valid(_z_endpoint_t *endpoint);
z_result_t _z_new_link_raweth(_z_link_t *zl, _z_endpoint_t endpoint);
size_t _z_raweth_config_strlen(const _z_str_intmap_t *s);
char *_z_raweth_config_to_str(const _z_str_intmap_t *s);
z_result_t _z_raweth_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n);
z_result_t _z_raweth_config_from_str(_z_str_intmap_t *strint, const char *s);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_LINK_CONFIG_RAWETH_H */
