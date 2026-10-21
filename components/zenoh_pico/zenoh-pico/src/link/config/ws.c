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

#include "zenoh-pico/link/config/ws.h"

#include <string.h>

#include "zenoh-pico/config.h"

#if Z_FEATURE_LINK_WS == 1

size_t _z_ws_config_strlen(const _z_str_intmap_t *s) {
    WS_CONFIG_MAPPING_BUILD

    return _z_str_intmap_strlen(s, argc, args);
}

void _z_ws_config_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s) {
    WS_CONFIG_MAPPING_BUILD
    _z_str_intmap_onto_str(dst, dst_len, s, argc, args);
}

char *_z_ws_config_to_str(const _z_str_intmap_t *s) {
    WS_CONFIG_MAPPING_BUILD

    return _z_str_intmap_to_str(s, argc, args);
}

z_result_t _z_ws_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n) {
    WS_CONFIG_MAPPING_BUILD

    return _z_str_intmap_from_strn(strint, s, argc, args, n);
}

z_result_t _z_ws_config_from_str(_z_str_intmap_t *strint, const char *s) {
    return _z_ws_config_from_strn(strint, s, strlen(s));
}
#endif
