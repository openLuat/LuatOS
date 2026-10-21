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

#include "zenoh-pico/link/config/udp.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/link/manager.h"
#include "zenoh-pico/system/link/udp.h"

#if Z_FEATURE_LINK_UDP_UNICAST == 1

z_result_t _z_endpoint_udp_unicast_valid(_z_endpoint_t *endpoint) {
    z_result_t ret = _Z_RES_OK;

    _z_string_t udp_str = _z_string_alias_str(UDP_SCHEMA);
    if (!_z_string_equals(&endpoint->_locator._protocol, &udp_str)) {
        _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
    }

    if (ret == _Z_RES_OK) {
        char *s_address = _z_endpoint_parse_host(&endpoint->_locator._address);
        if (s_address == NULL) {
            _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
            ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
        }
        z_free(s_address);
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

z_result_t _z_f_link_open_udp_unicast(_z_link_t *self) {
    z_result_t ret = _Z_RES_OK;

    uint32_t tout = Z_CONFIG_SOCKET_TIMEOUT;
    char *tout_as_str = _z_str_intmap_get(&self->_endpoint._config, UDP_CONFIG_TOUT_KEY);
    if (tout_as_str != NULL) {
        tout = (uint32_t)strtoul(tout_as_str, NULL, 10);
    }

    ret = _z_open_udp_unicast(&self->_socket._udp._sock, self->_socket._udp._rep, tout);

    return ret;
}

z_result_t _z_f_link_listen_udp_unicast(_z_link_t *self) {
    z_result_t ret = _Z_RES_OK;

    uint32_t tout = Z_CONFIG_SOCKET_TIMEOUT;
    char *tout_as_str = _z_str_intmap_get(&self->_endpoint._config, UDP_CONFIG_TOUT_KEY);
    if (tout_as_str != NULL) {
        tout = (uint32_t)strtoul(tout_as_str, NULL, 10);
    }

    ret = _z_listen_udp_unicast(&self->_socket._udp._sock, self->_socket._udp._rep, tout);

    return ret;
}

void _z_f_link_close_udp_unicast(_z_link_t *self) { _z_close_udp_unicast(&self->_socket._udp._sock); }

void _z_f_link_free_udp_unicast(_z_link_t *self) { _z_free_endpoint_udp(&self->_socket._udp._rep); }

size_t _z_f_link_write_udp_unicast(const _z_link_t *self, const uint8_t *ptr, size_t len, _z_sys_net_socket_t *socket) {
    if (socket != NULL) {
        return _z_send_udp_unicast(*socket, ptr, len, self->_socket._udp._rep);
    } else {
        return _z_send_udp_unicast(self->_socket._udp._sock, ptr, len, self->_socket._udp._rep);
    }
}

size_t _z_f_link_write_all_udp_unicast(const _z_link_t *self, const uint8_t *ptr, size_t len) {
    return _z_send_udp_unicast(self->_socket._udp._sock, ptr, len, self->_socket._udp._rep);
}

size_t _z_f_link_read_udp_unicast(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr) {
    _ZP_UNUSED(addr);
    return _z_read_udp_unicast(self->_socket._udp._sock, ptr, len);
}

size_t _z_f_link_read_exact_udp_unicast(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr,
                                        _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(addr);
    if (socket != NULL) {
        return _z_read_exact_udp_unicast(*socket, ptr, len);
    } else {
        return _z_read_exact_udp_unicast(self->_socket._udp._sock, ptr, len);
    }
}

size_t _z_f_link_udp_read_socket(const _z_sys_net_socket_t socket, uint8_t *ptr, size_t len) {
    return _z_read_udp_unicast(socket, ptr, len);
}

uint16_t _z_get_link_mtu_udp_unicast(void) {
    // @TODO: the return value should change depending on the target platform.
    return 1450;
}

z_result_t _z_new_link_udp_unicast(_z_link_t *zl, _z_endpoint_t endpoint) {
    z_result_t ret = _Z_RES_OK;
    zl->_type = _Z_LINK_TYPE_UDP;
    zl->_cap._transport = Z_LINK_CAP_TRANSPORT_UNICAST;
    zl->_cap._flow = Z_LINK_CAP_FLOW_DATAGRAM;
    zl->_cap._is_reliable = false;

    zl->_mtu = _z_get_link_mtu_udp_unicast();

    zl->_endpoint = endpoint;
    char *s_address = _z_endpoint_parse_host(&endpoint._locator._address);
    char *s_port = _z_endpoint_parse_port(&endpoint._locator._address);
    if ((s_address == NULL) || (s_port == NULL)) {
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
    } else {
        ret = _z_create_endpoint_udp(&zl->_socket._udp._rep, s_address, s_port);
    }
    z_free(s_address);
    z_free(s_port);

    zl->_open_f = _z_f_link_open_udp_unicast;
    zl->_listen_f = _z_f_link_listen_udp_unicast;
    zl->_close_f = _z_f_link_close_udp_unicast;
    zl->_free_f = _z_f_link_free_udp_unicast;

    zl->_write_f = _z_f_link_write_udp_unicast;
    zl->_write_all_f = _z_f_link_write_all_udp_unicast;
    zl->_read_f = _z_f_link_read_udp_unicast;
    zl->_read_exact_f = _z_f_link_read_exact_udp_unicast;
    zl->_read_socket_f = _z_f_link_udp_read_socket;

    return ret;
}
#endif
