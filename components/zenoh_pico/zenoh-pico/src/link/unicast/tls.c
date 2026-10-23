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

#include <stddef.h>
#include <string.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/link/link.h"
#include "zenoh-pico/link/manager.h"
#include "zenoh-pico/system/link/tls.h"
#include "zenoh-pico/utils/config.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/string.h"

#if Z_FEATURE_LINK_TLS == 1

uint16_t _z_get_link_mtu_tls(void) { return 65535; }

z_result_t _z_endpoint_tls_valid(_z_endpoint_t *endpoint) {
    z_result_t ret = _Z_RES_OK;

    _z_string_t tls_str = _z_string_alias_str(TLS_SCHEMA);
    if (!_z_string_equals(&endpoint->_locator._protocol, &tls_str)) {
        _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
    }

    if (ret == _Z_RES_OK) {
        char *s_addr = _z_endpoint_parse_host(&endpoint->_locator._address);
        if (s_addr == NULL) {
            _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
            ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
        }
        z_free(s_addr);
    }

    if (ret == _Z_RES_OK) {
        char *s_port = _z_endpoint_parse_port(&endpoint->_locator._address);
        if (s_port == NULL) {
            _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
            ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
        }
        z_free(s_port);
    }

    return ret;
}

static _z_config_t _z_tls_merge_config(_z_str_intmap_t *endpoint_cfg, const _z_config_t *session_cfg) {
    _z_config_t cfg;
    if (endpoint_cfg != NULL) {
        _z_str_intmap_move(&cfg, endpoint_cfg);
    } else {
        cfg = _z_str_intmap_make();
    }
    if (session_cfg == NULL) {
        return cfg;
    }
    static const struct {
        uint8_t locator_key;
        uint8_t session_key;
    } mapping[] = {{TLS_CONFIG_ROOT_CA_CERTIFICATE_KEY, Z_CONFIG_TLS_ROOT_CA_CERTIFICATE_KEY},
                   {TLS_CONFIG_ROOT_CA_CERTIFICATE_BASE64_KEY, Z_CONFIG_TLS_ROOT_CA_CERTIFICATE_BASE64_KEY},
                   {TLS_CONFIG_LISTEN_PRIVATE_KEY_KEY, Z_CONFIG_TLS_LISTEN_PRIVATE_KEY_KEY},
                   {TLS_CONFIG_LISTEN_PRIVATE_KEY_BASE64_KEY, Z_CONFIG_TLS_LISTEN_PRIVATE_KEY_BASE64_KEY},
                   {TLS_CONFIG_LISTEN_CERTIFICATE_KEY, Z_CONFIG_TLS_LISTEN_CERTIFICATE_KEY},
                   {TLS_CONFIG_LISTEN_CERTIFICATE_BASE64_KEY, Z_CONFIG_TLS_LISTEN_CERTIFICATE_BASE64_KEY},
                   {TLS_CONFIG_ENABLE_MTLS_KEY, Z_CONFIG_TLS_ENABLE_MTLS_KEY},
                   {TLS_CONFIG_CONNECT_PRIVATE_KEY_KEY, Z_CONFIG_TLS_CONNECT_PRIVATE_KEY_KEY},
                   {TLS_CONFIG_CONNECT_PRIVATE_KEY_BASE64_KEY, Z_CONFIG_TLS_CONNECT_PRIVATE_KEY_BASE64_KEY},
                   {TLS_CONFIG_CONNECT_CERTIFICATE_KEY, Z_CONFIG_TLS_CONNECT_CERTIFICATE_KEY},
                   {TLS_CONFIG_CONNECT_CERTIFICATE_BASE64_KEY, Z_CONFIG_TLS_CONNECT_CERTIFICATE_BASE64_KEY},
                   {TLS_CONFIG_VERIFY_NAME_ON_CONNECT_KEY, Z_CONFIG_TLS_VERIFY_NAME_ON_CONNECT_KEY}};

    for (size_t i = 0; i < sizeof(mapping) / sizeof(mapping[0]); i++) {
        if (_z_config_get(&cfg, mapping[i].locator_key) != NULL) {
            continue;
        }
        const char *value = _z_config_get(session_cfg, mapping[i].session_key);
        if (value != NULL) {
            _zp_config_insert(&cfg, mapping[i].locator_key, value);
        }
    }
    return cfg;
}

static z_result_t _z_f_link_open_tls(_z_link_t *self) {
    z_result_t ret = _Z_RES_OK;

    char *hostname = _z_endpoint_parse_host(&self->_endpoint._locator._address);
    char *port = _z_endpoint_parse_port(&self->_endpoint._locator._address);
    if ((hostname == NULL) || (port == NULL)) {
        _Z_ERROR("Failed to parse TLS endpoint address");
        z_free(hostname);
        z_free(port);
        return _Z_ERR_GENERIC;
    }

    _z_sys_net_endpoint_t rep = {0};
    ret = _z_create_endpoint_tcp(&rep, hostname, port);
    if (ret == _Z_RES_OK) {
        ret = _z_open_tls(&self->_socket._tls, &rep, hostname, &self->_endpoint._config, false);
    }
    _z_free_endpoint_tcp(&rep);
    z_free(hostname);
    z_free(port);
    if (ret != _Z_RES_OK) {
        _Z_ERROR("TLS open failed");
    }
    return ret;
}

static z_result_t _z_f_link_listen_tls(_z_link_t *self) {
    z_result_t ret = _Z_RES_OK;

    char *host = _z_endpoint_parse_host(&self->_endpoint._locator._address);
    char *port = _z_endpoint_parse_port(&self->_endpoint._locator._address);
    if ((host == NULL) || (port == NULL)) {
        _Z_ERROR("Invalid TLS endpoint");
        z_free(host);
        z_free(port);
        return _Z_ERR_GENERIC;
    }

    ret = _z_listen_tls(&self->_socket._tls, host, port, &self->_endpoint._config);
    if (ret != _Z_RES_OK) {
        _Z_ERROR("TLS listen failed");
    }

    z_free(host);
    z_free(port);
    return ret;
}

static void _z_f_link_close_tls(_z_link_t *self) { _z_close_tls(&self->_socket._tls); }

static size_t _z_f_link_write_tls(const _z_link_t *self, const uint8_t *ptr, size_t len, _z_sys_net_socket_t *socket) {
    // Use provided socket if available, otherwise fall back to link socket
    if (socket != NULL && socket->_tls_sock != NULL) {
        return _z_write_tls((_z_tls_socket_t *)socket->_tls_sock, ptr, len);
    } else {
        return _z_write_tls(&self->_socket._tls, ptr, len);
    }
}

static size_t _z_f_link_write_all_tls(const _z_link_t *self, const uint8_t *ptr, size_t len) {
    return _z_write_all_tls(&self->_socket._tls, ptr, len);
}

static size_t _z_f_link_read_tls(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr) {
    _ZP_UNUSED(addr);
    return _z_read_tls(&self->_socket._tls, ptr, len);
}

static size_t _z_f_link_read_exact_tls(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr,
                                       _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(addr);

    size_t n = (size_t)0;
    do {
        size_t rb;
        if (socket != NULL && socket->_tls_sock != NULL) {
            rb = _z_read_tls((_z_tls_socket_t *)socket->_tls_sock, &ptr[n], len - n);
        } else {
            rb = _z_read_tls(&self->_socket._tls, &ptr[n], len - n);
        }

        if (rb == SIZE_MAX) {
            n = rb;
            break;
        }
        n += rb;
    } while (n != len);

    return n;
}

static size_t _z_f_link_tls_read_socket(const _z_sys_net_socket_t socket, uint8_t *ptr, size_t len) {
    if (socket._tls_sock == NULL) {
        _Z_ERROR("TLS context not found in socket");
        return SIZE_MAX;
    }
    return _z_read_tls((_z_tls_socket_t *)socket._tls_sock, ptr, len);
}

static void _z_f_link_free_tls(_z_link_t *self) { _ZP_UNUSED(self); }

z_result_t _z_new_link_tls(_z_link_t *zl, _z_endpoint_t *endpoint, const _z_config_t *session_cfg) {
    z_result_t ret = _Z_RES_OK;

    zl->_type = _Z_LINK_TYPE_TLS;
    zl->_cap._transport = Z_LINK_CAP_TRANSPORT_UNICAST;
    zl->_cap._flow = Z_LINK_CAP_FLOW_STREAM;
    zl->_cap._is_reliable = true;

    zl->_mtu = _z_get_link_mtu_tls();

    _z_config_t cfg = _z_tls_merge_config(&endpoint->_config, session_cfg);
    zl->_endpoint = *endpoint;
    zl->_endpoint._config = cfg;
    _z_str_intmap_clear(&endpoint->_config);
    _Z_DEBUG("TLS locator: '%.*s'", (int)_z_string_len(&endpoint->_locator._address),
             _z_string_data(&endpoint->_locator._address));

    zl->_open_f = _z_f_link_open_tls;
    zl->_listen_f = _z_f_link_listen_tls;
    zl->_close_f = _z_f_link_close_tls;
    zl->_write_f = _z_f_link_write_tls;
    zl->_write_all_f = _z_f_link_write_all_tls;
    zl->_read_f = _z_f_link_read_tls;
    zl->_read_exact_f = _z_f_link_read_exact_tls;
    zl->_read_socket_f = _z_f_link_tls_read_socket;
    zl->_free_f = _z_f_link_free_tls;

    return ret;
}

z_result_t _z_new_peer_tls(_z_endpoint_t *endpoint, _z_sys_net_socket_t *socket, const _z_config_t *session_cfg) {
    _z_sys_net_endpoint_t sys_endpoint = {0};
    char *s_address = _z_endpoint_parse_host(&endpoint->_locator._address);
    char *s_port = _z_endpoint_parse_port(&endpoint->_locator._address);
    z_result_t ret = _Z_RES_OK;
    if ((s_address == NULL) || (s_port == NULL)) {
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
        goto cleanup;
    }

    ret = _z_create_endpoint_tcp(&sys_endpoint, s_address, s_port);
    if (ret != _Z_RES_OK) {
        goto cleanup;
    }

    socket->_tls_sock = z_malloc(sizeof(_z_tls_socket_t));
    if (socket->_tls_sock == NULL) {
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto cleanup;
    }

    _z_config_t cfg = _z_tls_merge_config(&endpoint->_config, session_cfg);
    ret = _z_open_tls((_z_tls_socket_t *)socket->_tls_sock, &sys_endpoint, s_address, &cfg, true);
    if (ret != _Z_RES_OK) {
        z_free(socket->_tls_sock);
        socket->_tls_sock = NULL;
        _z_config_clear(&cfg);
        _z_str_intmap_clear(&endpoint->_config);
        goto cleanup;
    }

    socket->_fd = ((_z_tls_socket_t *)socket->_tls_sock)->_sock._fd;
    _z_config_clear(&cfg);
    _z_str_intmap_clear(&endpoint->_config);

cleanup:
    z_free(s_address);
    z_free(s_port);
    _z_free_endpoint_tcp(&sys_endpoint);
    return ret;
}

#endif  // Z_FEATURE_LINK_TLS == 1
