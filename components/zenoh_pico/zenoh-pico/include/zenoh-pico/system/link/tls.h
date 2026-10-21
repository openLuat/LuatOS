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

#ifndef ZENOH_PICO_SYSTEM_LINK_TLS_H
#define ZENOH_PICO_SYSTEM_LINK_TLS_H

#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

#if Z_FEATURE_LINK_TLS == 1

#include "mbedtls/entropy.h"
#include "mbedtls/error.h"
#include "mbedtls/hmac_drbg.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"

typedef struct {
    mbedtls_ssl_context _ssl;
    mbedtls_ssl_config _ssl_config;
    mbedtls_entropy_context _entropy;
    mbedtls_hmac_drbg_context _hmac_drbg;
    mbedtls_x509_crt _ca_cert;
    mbedtls_pk_context _listen_key;
    mbedtls_x509_crt _listen_cert;
    mbedtls_pk_context _client_key;
    mbedtls_x509_crt _client_cert;
    bool _enable_mtls;
} _z_tls_context_t;

typedef struct {
    _z_sys_net_socket_t _sock;
    _z_tls_context_t *_tls_ctx;
    bool _is_peer_socket;  // a peer socket allocated in heap, needs to be freed in _z_close_tls
} _z_tls_socket_t;

z_result_t _z_open_tls(_z_tls_socket_t *sock, const _z_sys_net_endpoint_t *rep, const char *hostname,
                       const _z_str_intmap_t *config, bool peer_socket);
z_result_t _z_listen_tls(_z_tls_socket_t *sock, const char *host, const char *port, const _z_str_intmap_t *config);
z_result_t _z_tls_accept(_z_sys_net_socket_t *socket, const _z_sys_net_socket_t *listen_sock);
void _z_close_tls(_z_tls_socket_t *sock);
size_t _z_read_tls(const _z_tls_socket_t *sock, uint8_t *ptr, size_t len);
size_t _z_write_tls(const _z_tls_socket_t *sock, const uint8_t *ptr, size_t len);
size_t _z_write_all_tls(const _z_tls_socket_t *sock, const uint8_t *ptr, size_t len);

_z_tls_context_t *_z_tls_context_new(void);
void _z_tls_context_free(_z_tls_context_t **ctx);

#endif  // Z_FEATURE_LINK_TLS == 1

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SYSTEM_LINK_TLS_H */
