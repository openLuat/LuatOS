//
// Copyright (c) 2025 ZettaScale Technology
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

#include "zenoh-pico/link/config/tls.h"

#include <string.h>

#if Z_FEATURE_LINK_TLS == 1

size_t _z_tls_config_strlen(const _z_str_intmap_t *s) {
    TLS_CONFIG_MAPPING_BUILD

    return _z_str_intmap_strlen(s, TLS_CONFIG_ARGC, args);
}

void _z_tls_config_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s) {
    TLS_CONFIG_MAPPING_BUILD

    _z_str_intmap_onto_str(dst, dst_len, s, TLS_CONFIG_ARGC, args);
}

char *_z_tls_config_to_str(const _z_str_intmap_t *s) {
    TLS_CONFIG_MAPPING_BUILD

    return _z_str_intmap_to_str(s, TLS_CONFIG_ARGC, args);
}

z_result_t _z_tls_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n) {
    TLS_CONFIG_MAPPING_BUILD

    return _z_str_intmap_from_strn(strint, s, TLS_CONFIG_ARGC, args, n);
}

z_result_t _z_tls_config_from_str(_z_str_intmap_t *strint, const char *s) {
    TLS_CONFIG_MAPPING_BUILD

    return _z_str_intmap_from_str(strint, s, TLS_CONFIG_ARGC, args);
}

#endif
