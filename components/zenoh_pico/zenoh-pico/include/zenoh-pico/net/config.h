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

#ifndef ZENOH_PICO_CONFIG_NETAPI_H
#define ZENOH_PICO_CONFIG_NETAPI_H

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/utils/config.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Create an empty set of properties for zenoh-net session configuration.
 *
 * Returns:
 *     A :c:type:`_z_config_t` containing an empty configuration.
 */
_z_config_t _z_config_empty(void);

/**
 * Create a default set of properties for zenoh-net session configuration.
 *
 * Parameters:
 *   config:  A :c:type:`_z_config_t` where a default configuration for client mode will be constructed.
 *
 * Returns:
 *   `0`` in case of success, or a ``negative value`` otherwise.
 */
z_result_t _z_config_default(_z_config_t *config);

/**
 * Create a default set of properties for client mode zenoh-net session configuration.
 * If peer is not null, it is added to the configuration as remote peer.
 *
 * Parameters:
 *   config:  A :c:type:`_z_config_t` where a default configuration for client mode will be constructed.
 *   locator: An optional peer locator. The caller keeps its ownership.
 *
 * Returns:
 *     `0`` in case of success, or a ``negative value`` otherwise.
 */
z_result_t _z_config_client(_z_config_t *config, const char *locator);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_CONFIG_NETAPI_H */
