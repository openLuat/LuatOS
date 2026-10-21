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

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/protocol/core.h"

#ifndef ZENOH_PICO_UTILS_UUID_H
#define ZENOH_PICO_UTILS_UUID_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Converts an UUID in string format to a byte array.
 *
 * Parameters:
 *   bytes: Pointer to an already allocated byte array of size (at least) 16 bytes.
 *   uuid_str: A valid UUID string.
 */
void _z_uuid_to_bytes(uint8_t *bytes, const char *uuid_str);

/**
 * Converts an Zenoh ID to string.
 *
 * Parameters:
 *   id: Zenoh ID.
 *
 * Returns:
 *   ID string representation
 */
_z_string_t _z_id_to_string(const _z_id_t *id);

/**
 * Parses a string to a Zenoh ID.
 *
 * Parameters:
 *   str - Pointer to the string to parse.
 *
 * Returns:
 *   The parsed Zenoh ID if successful, or an empty ID on failure.
 */
_z_id_t _z_id_from_string(const _z_string_t *str);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_UUID_H */
