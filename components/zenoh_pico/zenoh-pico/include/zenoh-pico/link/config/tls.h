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

#ifndef ZENOH_PICO_LINK_CONFIG_TLS_H
#define ZENOH_PICO_LINK_CONFIG_TLS_H

#include "zenoh-pico/collections/intmap.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_LINK_TLS == 1

#define TLS_CONFIG_ARGC 12

#define TLS_CONFIG_ROOT_CA_CERTIFICATE_KEY 0x01
#define TLS_CONFIG_ROOT_CA_CERTIFICATE_STR "root_ca_certificate"

#define TLS_CONFIG_ROOT_CA_CERTIFICATE_BASE64_KEY 0x02
#define TLS_CONFIG_ROOT_CA_CERTIFICATE_BASE64_STR "root_ca_certificate_base64"

#define TLS_CONFIG_LISTEN_PRIVATE_KEY_KEY 0x03
#define TLS_CONFIG_LISTEN_PRIVATE_KEY_STR "listen_private_key"

#define TLS_CONFIG_LISTEN_PRIVATE_KEY_BASE64_KEY 0x04
#define TLS_CONFIG_LISTEN_PRIVATE_KEY_BASE64_STR "listen_private_key_base64"

#define TLS_CONFIG_LISTEN_CERTIFICATE_KEY 0x05
#define TLS_CONFIG_LISTEN_CERTIFICATE_STR "listen_certificate"

#define TLS_CONFIG_LISTEN_CERTIFICATE_BASE64_KEY 0x06
#define TLS_CONFIG_LISTEN_CERTIFICATE_BASE64_STR "listen_certificate_base64"

#define TLS_CONFIG_ENABLE_MTLS_KEY 0x07
#define TLS_CONFIG_ENABLE_MTLS_STR "enable_mtls"

#define TLS_CONFIG_CONNECT_PRIVATE_KEY_KEY 0x08
#define TLS_CONFIG_CONNECT_PRIVATE_KEY_STR "connect_private_key"

#define TLS_CONFIG_CONNECT_PRIVATE_KEY_BASE64_KEY 0x09
#define TLS_CONFIG_CONNECT_PRIVATE_KEY_BASE64_STR "connect_private_key_base64"

#define TLS_CONFIG_CONNECT_CERTIFICATE_KEY 0x0A
#define TLS_CONFIG_CONNECT_CERTIFICATE_STR "connect_certificate"

#define TLS_CONFIG_CONNECT_CERTIFICATE_BASE64_KEY 0x0B
#define TLS_CONFIG_CONNECT_CERTIFICATE_BASE64_STR "connect_certificate_base64"

#define TLS_CONFIG_VERIFY_NAME_ON_CONNECT_KEY 0x0C
#define TLS_CONFIG_VERIFY_NAME_ON_CONNECT_STR "verify_name_on_connect"

#define TLS_CONFIG_MAPPING_BUILD                                       \
    _z_str_intmapping_t args[TLS_CONFIG_ARGC];                         \
    args[0]._key = TLS_CONFIG_ROOT_CA_CERTIFICATE_KEY;                 \
    args[0]._str = (char *)TLS_CONFIG_ROOT_CA_CERTIFICATE_STR;         \
    args[1]._key = TLS_CONFIG_ROOT_CA_CERTIFICATE_BASE64_KEY;          \
    args[1]._str = (char *)TLS_CONFIG_ROOT_CA_CERTIFICATE_BASE64_STR;  \
    args[2]._key = TLS_CONFIG_LISTEN_PRIVATE_KEY_KEY;                  \
    args[2]._str = (char *)TLS_CONFIG_LISTEN_PRIVATE_KEY_STR;          \
    args[3]._key = TLS_CONFIG_LISTEN_PRIVATE_KEY_BASE64_KEY;           \
    args[3]._str = (char *)TLS_CONFIG_LISTEN_PRIVATE_KEY_BASE64_STR;   \
    args[4]._key = TLS_CONFIG_LISTEN_CERTIFICATE_KEY;                  \
    args[4]._str = (char *)TLS_CONFIG_LISTEN_CERTIFICATE_STR;          \
    args[5]._key = TLS_CONFIG_LISTEN_CERTIFICATE_BASE64_KEY;           \
    args[5]._str = (char *)TLS_CONFIG_LISTEN_CERTIFICATE_BASE64_STR;   \
    args[6]._key = TLS_CONFIG_ENABLE_MTLS_KEY;                         \
    args[6]._str = (char *)TLS_CONFIG_ENABLE_MTLS_STR;                 \
    args[7]._key = TLS_CONFIG_CONNECT_PRIVATE_KEY_KEY;                 \
    args[7]._str = (char *)TLS_CONFIG_CONNECT_PRIVATE_KEY_STR;         \
    args[8]._key = TLS_CONFIG_CONNECT_PRIVATE_KEY_BASE64_KEY;          \
    args[8]._str = (char *)TLS_CONFIG_CONNECT_PRIVATE_KEY_BASE64_STR;  \
    args[9]._key = TLS_CONFIG_CONNECT_CERTIFICATE_KEY;                 \
    args[9]._str = (char *)TLS_CONFIG_CONNECT_CERTIFICATE_STR;         \
    args[10]._key = TLS_CONFIG_CONNECT_CERTIFICATE_BASE64_KEY;         \
    args[10]._str = (char *)TLS_CONFIG_CONNECT_CERTIFICATE_BASE64_STR; \
    args[11]._key = TLS_CONFIG_VERIFY_NAME_ON_CONNECT_KEY;             \
    args[11]._str = (char *)TLS_CONFIG_VERIFY_NAME_ON_CONNECT_STR;

size_t _z_tls_config_strlen(const _z_str_intmap_t *s);

void _z_tls_config_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s);
char *_z_tls_config_to_str(const _z_str_intmap_t *s);

z_result_t _z_tls_config_from_str(_z_str_intmap_t *strint, const char *s);
z_result_t _z_tls_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n);
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_LINK_CONFIG_TLS_H */
