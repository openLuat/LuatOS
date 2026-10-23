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

#ifndef ZENOH_PICO_UTILS_PROPERTY_H
#define ZENOH_PICO_UTILS_PROPERTY_H

#include <stdint.h>

#include "zenoh-pico/collections/intmap.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

// Properties returned by _z_info()
#define Z_INFO_PID_KEY 0x00
#define Z_INFO_PEER_PID_KEY 0x01
#define Z_INFO_ROUTER_PID_KEY 0x02

/**
 * Zenoh-net properties are represented as int-string map.
 */
typedef _z_str_intmap_t _z_config_t;

/**
 * Initialize a new empty map of properties.
 */
z_result_t _z_config_init(_z_config_t *ps);

/**
 * Insert a property with a given key to a properties map.
 * If a property with the same key already exists in the properties map, it is replaced.
 *
 * Parameters:
 *   ps: A pointer to the properties map.
 *   key: The key of the property to add.
 *   value: The value of the property to add.
 */
z_result_t _zp_config_insert(_z_config_t *ps, uint8_t key, const char *value);
z_result_t _zp_config_insert_string(_z_config_t *ps, uint8_t key, const _z_string_t *value);

/**
 * Get the property with the given key from a properties map.
 *
 * Parameters:
 *     ps: A pointer to properties map.
 *     key: The key of the property.
 *
 * Returns:
 *     The value of the property with key ``key`` in properties map ``ps``.
 */
char *_z_config_get(const _z_config_t *ps, uint8_t key);
z_result_t _z_config_get_all(const _z_config_t *ps, _z_string_svec_t *locators, uint8_t key);

/**
 * Get the length of the given properties map.
 *
 * Parameters:
 *     ps: A pointer to the properties map.
 *
 * Returns:
 *     The length of the given properties map.
 */
#define _z_config_len _z_str_intmap_len

/**
 * Clone a config.
 *
 * Parameters:
 *     m: A pointer to the config to clone.
 *
 * Returns:
 *     The clone of the config.
 */
#define _z_config_clone _z_str_intmap_clone

/**
 * Get the length of the given properties map.
 *
 * Parameters:
 *     ps: A pointer to the properties map.
 *
 * Returns:
 *     A boolean to indicate if properties are present.
 */
#define _z_config_is_empty _z_str_intmap_is_empty

/**
 * Clear a set of properties.
 *
 * Parameters:
 *   ps: A pointer to the properties map.
 */
#define _z_config_clear _z_str_intmap_clear

/**
 * Free a set of properties.
 *
 * Parameters:
 *   ps: A pointer to a pointer of properties.
 *
 */
#define _z_config_free _z_str_intmap_free

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_PROPERTY_H */
