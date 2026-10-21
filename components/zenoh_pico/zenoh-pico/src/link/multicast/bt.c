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

#include "zenoh-pico/link/config/bt.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/link/manager.h"
#include "zenoh-pico/system/link/bt.h"

#if Z_FEATURE_LINK_BLUETOOTH == 1

#define SPP_MAXIMUM_PAYLOAD 128

z_result_t _z_endpoint_bt_valid(_z_endpoint_t *ep) {
    z_result_t ret = _Z_RES_OK;

    _z_string_t bt_str = _z_string_alias_str(BT_SCHEMA);
    if (!_z_string_equals(&ep->_locator._protocol, &bt_str)) {
        _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
    }

    if (ret == _Z_RES_OK) {
        if (_z_string_len(&ep->_locator._address) == (size_t)0) {
            _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
            ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
        }
    }

    return ret;
}

static char *__z_convert_address_bt(_z_string_t *address) {
    char *ret = NULL;
    ret = (char *)z_malloc(_z_string_len(address) + 1);
    if (ret != NULL) {
        _z_str_n_copy(ret, _z_string_data(address), _z_string_len(address) + 1);
    }
    return ret;
}

z_result_t _z_f_link_open_bt(_z_link_t *self) {
    z_result_t ret = _Z_RES_OK;

    const char *mode_str = _z_str_intmap_get(&self->_endpoint._config, BT_CONFIG_MODE_KEY);
    uint8_t mode = (strcmp(mode_str, "master") == 0) ? _Z_BT_MODE_MASTER : _Z_BT_MODE_SLAVE;
    const char *profile_str = _z_str_intmap_get(&self->_endpoint._config, BT_CONFIG_PROFILE_KEY);
    uint8_t profile = (strcmp(profile_str, "spp") == 0) ? _Z_BT_PROFILE_SPP : _Z_BT_PROFILE_UNSUPPORTED;
    uint32_t tout = Z_CONFIG_SOCKET_TIMEOUT;
    char *tout_as_str = _z_str_intmap_get(&self->_endpoint._config, BT_CONFIG_TOUT_KEY);
    if (tout_as_str != NULL) {
        tout = (uint32_t)strtoul(tout_as_str, NULL, 10);
    }

    self->_socket._bt._gname = __z_convert_address_bt(&self->_endpoint._locator._address);
    ret = _z_open_bt(&self->_socket._bt._sock, self->_socket._bt._gname, mode, profile, tout);

    return ret;
}

z_result_t _z_f_link_listen_bt(_z_link_t *self) {
    z_result_t ret = _Z_RES_OK;

    const char *mode_str = _z_str_intmap_get(&self->_endpoint._config, BT_CONFIG_MODE_KEY);
    uint8_t mode = (strcmp(mode_str, "master") == 0) ? _Z_BT_MODE_MASTER : _Z_BT_MODE_SLAVE;
    const char *profile_str = _z_str_intmap_get(&self->_endpoint._config, BT_CONFIG_PROFILE_KEY);
    uint8_t profile = (strcmp(profile_str, "spp") == 0) ? _Z_BT_PROFILE_SPP : _Z_BT_PROFILE_UNSUPPORTED;
    uint32_t tout = Z_CONFIG_SOCKET_TIMEOUT;
    char *tout_as_str = _z_str_intmap_get(&self->_endpoint._config, BT_CONFIG_TOUT_KEY);
    if (tout_as_str != NULL) {
        tout = (uint32_t)strtoul(tout_as_str, NULL, 10);
    }

    self->_socket._bt._gname = __z_convert_address_bt(&self->_endpoint._locator._address);
    ret = _z_listen_bt(&self->_socket._bt._sock, self->_socket._bt._gname, mode, profile, tout);

    return ret;
}

void _z_f_link_close_bt(_z_link_t *self) { _z_close_bt(&self->_socket._bt._sock); }

void _z_f_link_free_bt(_z_link_t *self) { _ZP_UNUSED(self); }

size_t _z_f_link_write_bt(const _z_link_t *self, const uint8_t *ptr, size_t len, _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(socket);
    return _z_send_bt(self->_socket._bt._sock, ptr, len);
}

size_t _z_f_link_write_all_bt(const _z_link_t *self, const uint8_t *ptr, size_t len) {
    return _z_send_bt(self->_socket._bt._sock, ptr, len);
}

size_t _z_f_link_read_bt(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr) {
    size_t rb = _z_read_bt(self->_socket._bt._sock, ptr, len);
    if ((rb > (size_t)0) && (addr != NULL)) {
        addr->len = strlen(self->_socket._bt._gname);
        (void)memcpy((uint8_t *)addr->start, self->_socket._bt._gname, strlen(self->_socket._bt._gname));
    }

    return rb;
}

size_t _z_f_link_read_exact_bt(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr,
                               _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(socket);
    size_t rb = _z_read_exact_bt(self->_socket._bt._sock, ptr, len);
    if ((rb == len) && (addr != NULL)) {
        addr->len = strlen(self->_socket._bt._gname);
        (void)memcpy((uint8_t *)addr->start, self->_socket._bt._gname, strlen(self->_socket._bt._gname));
    }

    return rb;
}

uint16_t _z_get_link_mtu_bt(void) { return SPP_MAXIMUM_PAYLOAD; }

z_result_t _z_new_link_bt(_z_link_t *zl, _z_endpoint_t endpoint) {
    z_result_t ret = _Z_RES_OK;
    zl->_type = _Z_LINK_TYPE_BT;
    zl->_cap._transport = Z_LINK_CAP_TRANSPORT_MULTICAST;
    zl->_cap._flow = Z_LINK_CAP_FLOW_STREAM;
    zl->_cap._is_reliable = false;

    zl->_mtu = _z_get_link_mtu_bt();

    zl->_endpoint = endpoint;

    zl->_open_f = _z_f_link_open_bt;
    zl->_listen_f = _z_f_link_listen_bt;
    zl->_close_f = _z_f_link_close_bt;
    zl->_free_f = _z_f_link_free_bt;

    zl->_write_f = _z_f_link_write_bt;
    zl->_write_all_f = _z_f_link_write_all_bt;
    zl->_read_f = _z_f_link_read_bt;
    zl->_read_exact_f = _z_f_link_read_exact_bt;
    zl->_read_socket_f = _z_noop_link_read_socket;

    return ret;
}
#endif
