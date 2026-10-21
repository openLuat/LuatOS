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

#include "zenoh-pico/config.h"

#include <stddef.h>

#include "zenoh-pico/net/config.h"

_z_config_t _z_config_empty(void) {
    _z_config_t config;
    _z_config_init(&config);
    return config;
}

z_result_t _z_config_default(_z_config_t *config) { return _z_config_client(config, NULL); }

z_result_t _z_config_client(_z_config_t *ps, const char *locator) {
    *ps = _z_config_empty();
    _Z_RETURN_IF_ERR(_zp_config_insert(ps, Z_CONFIG_MODE_KEY, Z_CONFIG_MODE_CLIENT));
    if (locator != NULL) {
        // Connect only to the provided locator
        _Z_CLEAN_RETURN_IF_ERR(_zp_config_insert(ps, Z_CONFIG_CONNECT_KEY, locator), _z_config_clear(ps));
    } else {
        // The locator is not provided, we should perform scouting
        _Z_CLEAN_RETURN_IF_ERR(
            _zp_config_insert(ps, Z_CONFIG_MULTICAST_SCOUTING_KEY, Z_CONFIG_MULTICAST_SCOUTING_DEFAULT),
            _z_config_clear(ps));
        _Z_CLEAN_RETURN_IF_ERR(
            _zp_config_insert(ps, Z_CONFIG_MULTICAST_LOCATOR_KEY, Z_CONFIG_MULTICAST_LOCATOR_DEFAULT),
            _z_config_clear(ps));
        _Z_CLEAN_RETURN_IF_ERR(_zp_config_insert(ps, Z_CONFIG_SCOUTING_TIMEOUT_KEY, Z_CONFIG_SCOUTING_TIMEOUT_DEFAULT),
                               _z_config_clear(ps));
    }
    return _Z_RES_OK;
}
