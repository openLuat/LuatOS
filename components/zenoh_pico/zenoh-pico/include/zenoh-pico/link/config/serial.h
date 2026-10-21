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

#ifndef ZENOH_PICO_LINK_CONFIG_SERIAL_H
#define ZENOH_PICO_LINK_CONFIG_SERIAL_H

#include "zenoh-pico/collections/intmap.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_LINK_SERIAL == 1

#define SERIAL_CONFIG_ARGC 1

#define SERIAL_CONFIG_BAUDRATE_KEY 0x01
#define SERIAL_CONFIG_BAUDRATE_STR "baudrate"

// #define SERIAL_CONFIG_DATABITS_KEY     0x02
// #define SERIAL_CONFIG_DATABITS_STR     "data_bits"

// #define SERIAL_CONFIG_FLOWCONTROL_KEY  0x03
// #define SERIAL_CONFIG_FLOWCONTROL_STR  "flow_control"

// #define SERIAL_CONFIG_PARITY_KEY       0x04
// #define SERIAL_CONFIG_PARITY_STR       "parity"

// #define SERIAL_CONFIG_STOPBITS_KEY     0x05
// #define SERIAL_CONFIG_STOPBITS_STR     "stop_bits"

// #define SERIAL_CONFIG_TOUT_KEY         0x06
// #define SERIAL_CONFIG_TOUT_STR         "tout"

#define SERIAL_CONFIG_MAPPING_BUILD               \
    _z_str_intmapping_t args[SERIAL_CONFIG_ARGC]; \
    args[0]._key = SERIAL_CONFIG_BAUDRATE_KEY;    \
    args[0]._str = (char *)SERIAL_CONFIG_BAUDRATE_STR;
// args[1]._key = SERIAL_CONFIG_DATABITS_KEY;
// args[1]._str = SERIAL_CONFIG_DATABITS_STR;
// args[2]._key = SERIAL_CONFIG_FLOWCONTROL_KEY;
// args[2]._str = SERIAL_CONFIG_FLOWCONTROL_STR;
// args[3]._key = SERIAL_CONFIG_PARITY_KEY;
// args[3]._str = SERIAL_CONFIG_PARITY_STR;
// args[4]._key = SERIAL_CONFIG_STOPBITS_KEY;
// args[4]._str = SERIAL_CONFIG_STOPBITS_STR;
// args[5]._key = SERIAL_CONFIG_TOUT_KEY;
// args[5]._str = SERIAL_CONFIG_TOUT_STR;

size_t _z_serial_config_strlen(const _z_str_intmap_t *s);

void _z_serial_config_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s);
char *_z_serial_config_to_str(const _z_str_intmap_t *s);

z_result_t _z_serial_config_from_str(_z_str_intmap_t *strint, const char *s);
z_result_t _z_serial_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n);
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_LINK_CONFIG_SERIAL_H */
