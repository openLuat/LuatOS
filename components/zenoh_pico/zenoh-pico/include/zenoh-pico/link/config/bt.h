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

#ifndef ZENOH_PICO_LINK_CONFIG_BT_H
#define ZENOH_PICO_LINK_CONFIG_BT_H

#include "zenoh-pico/collections/intmap.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_LINK_BLUETOOTH == 1

#define BT_CONFIG_ARGC 3

#define BT_CONFIG_MODE_KEY 0x01
#define BT_CONFIG_MODE_STR "mode"

#define BT_CONFIG_PROFILE_KEY 0x02
#define BT_CONFIG_PROFILE_STR "profile"

#define BT_CONFIG_TOUT_KEY 0x03
#define BT_CONFIG_TOUT_STR "tout"

#define BT_CONFIG_MAPPING_BUILD                   \
    _z_str_intmapping_t args[BT_CONFIG_ARGC];     \
    args[0]._key = BT_CONFIG_MODE_KEY;            \
    args[0]._str = (char *)BT_CONFIG_MODE_STR;    \
    args[1]._key = BT_CONFIG_PROFILE_KEY;         \
    args[1]._str = (char *)BT_CONFIG_PROFILE_STR; \
    args[2]._key = BT_CONFIG_TOUT_KEY;            \
    args[2]._str = (char *)BT_CONFIG_TOUT_STR;

size_t _z_bt_config_strlen(const _z_str_intmap_t *s);

void _z_bt_config_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s);
char *_z_bt_config_to_str(const _z_str_intmap_t *s);

z_result_t _z_bt_config_from_str(_z_str_intmap_t *strint, const char *s);
z_result_t _z_bt_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n);
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_LINK_CONFIG_BT_H */
