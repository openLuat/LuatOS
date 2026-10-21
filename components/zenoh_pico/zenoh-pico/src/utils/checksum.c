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

#include "zenoh-pico/utils/checksum.h"

#define __CRC_POLYNOMIAL 0x04C11DB7

uint32_t _z_crc32(const uint8_t *message, size_t len) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc = crc ^ (uint32_t)message[i];
        for (uint8_t j = 0; j < (uint8_t)8; j++) {
            crc = (crc >> 1) ^ ((uint32_t)__CRC_POLYNOMIAL & (uint32_t)(-(int32_t)(crc & (uint32_t)1)));
        }
    }
    return ~crc;
}
