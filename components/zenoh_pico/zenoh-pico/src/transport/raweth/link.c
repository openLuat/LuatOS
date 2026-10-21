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

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/link/config/raweth.h"
#include "zenoh-pico/link/manager.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/system/link/raweth.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"

#if Z_FEATURE_RAWETH_TRANSPORT == 1

#define RAWETH_CFG_TUPLE_SEPARATOR '#'
#define RAWETH_CFG_LIST_SEPARATOR ","

#define RAWETH_CONFIG_ARGC 4

#define RAWETH_CONFIG_IFACE_KEY 0x01
#define RAWETH_CONFIG_IFACE_STR "iface"

#define RAWETH_CONFIG_ETHTYPE_KEY 0x02
#define RAWETH_CONFIG_ETHTYPE_STR "ethtype"

#define RAWETH_CONFIG_MAPPING_KEY 0x03
#define RAWETH_CONFIG_MAPPING_STR "mapping"

#define RAWETH_CONFIG_WHITELIST_KEY 0x04
#define RAWETH_CONFIG_WHITELIST_STR "whitelist"

// Ethtype must be at least 0x600 in network order
#define RAWETH_ETHTYPE_MIN_VALUE 0x600U

#define RAWETH_CONFIG_MAPPING_BUILD               \
    _z_str_intmapping_t args[RAWETH_CONFIG_ARGC]; \
    args[0]._key = RAWETH_CONFIG_IFACE_KEY;       \
    args[0]._str = RAWETH_CONFIG_IFACE_STR;       \
    args[1]._key = RAWETH_CONFIG_ETHTYPE_KEY;     \
    args[1]._str = RAWETH_CONFIG_ETHTYPE_STR;     \
    args[2]._key = RAWETH_CONFIG_MAPPING_KEY;     \
    args[2]._str = RAWETH_CONFIG_MAPPING_STR;     \
    args[3]._key = RAWETH_CONFIG_WHITELIST_KEY;   \
    args[3]._str = RAWETH_CONFIG_WHITELIST_STR;

const uint16_t _ZP_RAWETH_DEFAULT_ETHTYPE = 0x72e0;
const char *_ZP_RAWETH_DEFAULT_INTERFACE = "lo";
const uint8_t _ZP_RAWETH_DEFAULT_SMAC[_ZP_MAC_ADDR_LENGTH] = {0x30, 0x03, 0xc8, 0x37, 0x25, 0xa1};
const _zp_raweth_mapping_entry_t _ZP_RAWETH_DEFAULT_MAPPING = {
    ._keyexpr = {0}, ._vlan = 0x0000, ._dmac = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff}, ._has_vlan = false};

static bool _z_valid_iface_raweth(_z_str_intmap_t *config);
static const char *_z_get_iface_raweth(_z_str_intmap_t *config);
static bool _z_valid_ethtype_raweth(_z_str_intmap_t *config);
static long _z_get_ethtype_raweth(_z_str_intmap_t *config);
static size_t _z_valid_mapping_raweth(_z_str_intmap_t *config);
static z_result_t _z_get_mapping_raweth(_z_str_intmap_t *config, _zp_raweth_mapping_array_t *array, size_t size);
static size_t _z_valid_whitelist_raweth(_z_str_intmap_t *config);
static z_result_t _z_get_whitelist_raweth(_z_str_intmap_t *config, _zp_raweth_whitelist_array_t *array, size_t size);
static z_result_t _z_get_mapping_entry(char *entry, _zp_raweth_mapping_entry_t *storage);
static bool _z_valid_mapping_entry(char *entry);
static bool _z_valid_address_raweth_inner(const _z_string_t *address);
static bool _z_valid_address_raweth(const char *address);
static uint8_t *_z_parse_address_raweth(const char *address);
static z_result_t _z_f_link_open_raweth(_z_link_t *self);
static z_result_t _z_f_link_listen_raweth(_z_link_t *self);
static void _z_f_link_close_raweth(_z_link_t *self);
static void _z_f_link_free_raweth(_z_link_t *self);
static size_t _z_f_link_write_raweth(const _z_link_t *self, const uint8_t *ptr, size_t len,
                                     _z_sys_net_socket_t *socket);
static size_t _z_f_link_write_all_raweth(const _z_link_t *self, const uint8_t *ptr, size_t len);
static size_t _z_f_link_read_raweth(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr);
static size_t _z_f_link_read_exact_raweth(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr,
                                          _z_sys_net_socket_t *socket);
static uint16_t _z_get_link_mtu_raweth(void);

static bool _z_valid_iface_raweth(_z_str_intmap_t *config) {
    const char *iface = _z_str_intmap_get(config, RAWETH_CONFIG_IFACE_KEY);
    return (iface != NULL);
}

static const char *_z_get_iface_raweth(_z_str_intmap_t *config) {
    return _z_str_intmap_get(config, RAWETH_CONFIG_IFACE_KEY);
}

static bool _z_valid_ethtype_raweth(_z_str_intmap_t *config) {
    const char *s_ethtype = _z_str_intmap_get(config, RAWETH_CONFIG_ETHTYPE_KEY);
    if (s_ethtype == NULL) {
        return false;
    }
    long ethtype = strtol(s_ethtype, NULL, 16);
    return (_z_raweth_htons((uint16_t)ethtype) > RAWETH_ETHTYPE_MIN_VALUE);
}

static long _z_get_ethtype_raweth(_z_str_intmap_t *config) {
    const char *s_ethtype = _z_str_intmap_get(config, RAWETH_CONFIG_ETHTYPE_KEY);
    return strtol(s_ethtype, NULL, 16);
}

static size_t _z_valid_mapping_raweth(_z_str_intmap_t *config) {
    // Retrieve list
    const char *cfg_str = _z_str_intmap_get(config, RAWETH_CONFIG_MAPPING_KEY);
    if (cfg_str == NULL) {
        return 0;
    }
    char *s_mapping = (char *)z_malloc(strlen(cfg_str));
    if (s_mapping == NULL) {
        return 0;
    }
    size_t size = 0;
    strcpy(s_mapping, cfg_str);
    // Parse list
    const char *delim = RAWETH_CFG_LIST_SEPARATOR;
    char *entry = strtok(s_mapping, delim);
    while (entry != NULL) {
        // Check entry
        if (!_z_valid_mapping_entry(entry)) {
            z_free(s_mapping);
            return 0;
        }
        size++;
        entry = strtok(NULL, delim);
    }
    // Clean up
    z_free(s_mapping);
    return size;
}

static z_result_t _z_get_mapping_raweth(_z_str_intmap_t *config, _zp_raweth_mapping_array_t *array, size_t size) {
    // Retrieve data
    const char *cfg_str = _z_str_intmap_get(config, RAWETH_CONFIG_MAPPING_KEY);
    if (cfg_str == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
    // Copy data
    char *s_mapping = (char *)z_malloc(strlen(cfg_str));
    if (s_mapping == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    strcpy(s_mapping, cfg_str);
    // Allocate array
    *array = _zp_raweth_mapping_array_make(size);
    if (_zp_raweth_mapping_array_len(array) == 0) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    size_t idx = 0;
    // Parse list
    const char *delim = RAWETH_CFG_LIST_SEPARATOR;
    char *entry = strtok(s_mapping, delim);
    while ((entry != NULL) && (idx < _zp_raweth_mapping_array_len(array))) {
        // Copy data into array
        _Z_CLEAN_RETURN_IF_ERR(_z_get_mapping_entry(entry, _zp_raweth_mapping_array_get(array, idx)),
                               z_free(s_mapping));
        // Next iteration
        idx++;
        entry = strtok(NULL, delim);
    }
    // Clean up
    z_free(s_mapping);
    return _Z_RES_OK;
}

static size_t _z_valid_whitelist_raweth(_z_str_intmap_t *config) {
    // Retrieve data
    const char *cfg_str = _z_str_intmap_get(config, RAWETH_CONFIG_WHITELIST_KEY);
    if (cfg_str == NULL) {
        return 0;
    }
    // Copy data
    char *s_whitelist = (char *)z_malloc(strlen(cfg_str));
    if (s_whitelist == NULL) {
        return 0;
    }
    strcpy(s_whitelist, cfg_str);
    // Parse list
    size_t size = 0;
    const char *delim = RAWETH_CFG_LIST_SEPARATOR;
    char *entry = strtok(s_whitelist, delim);
    while (entry != NULL) {
        // Check entry
        if (!_z_valid_address_raweth(entry)) {
            z_free(s_whitelist);
            return 0;
        }
        size++;
        entry = strtok(NULL, delim);
    }
    // Parse last entry

    // Clean up
    z_free(s_whitelist);
    return size;
}

static z_result_t _z_get_whitelist_raweth(_z_str_intmap_t *config, _zp_raweth_whitelist_array_t *array, size_t size) {
    // Retrieve data
    const char *cfg_str = _z_str_intmap_get(config, RAWETH_CONFIG_WHITELIST_KEY);
    if (cfg_str == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
    // Copy data
    char *s_whitelist = (char *)z_malloc(strlen(cfg_str));
    if (s_whitelist == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    strcpy(s_whitelist, cfg_str);
    // Allocate array
    *array = _zp_raweth_whitelist_array_make(size);
    if (_zp_raweth_whitelist_array_len(array) == 0) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    size_t idx = 0;
    // Parse list
    const char *delim = RAWETH_CFG_LIST_SEPARATOR;
    char *entry = strtok(s_whitelist, delim);
    while ((entry != NULL) && (idx < _zp_raweth_whitelist_array_len(array))) {
        // Convert address from string to int array
        uint8_t *addr = _z_parse_address_raweth(entry);
        if (addr == NULL) {
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        // Copy address to entry
        _zp_raweth_whitelist_entry_t *elem = _zp_raweth_whitelist_array_get(array, idx);
        memcpy(elem->_mac, addr, _ZP_MAC_ADDR_LENGTH);
        z_free(addr);
        // Next iteration
        idx++;
        entry = strtok(NULL, delim);
    }
    // Clean up
    z_free(s_whitelist);
    return _Z_RES_OK;
}

static z_result_t _z_get_mapping_entry(char *entry, _zp_raweth_mapping_entry_t *storage) {
    size_t len = strlen(entry);
    const char *entry_end = &entry[len - (size_t)1];

    // Get first tuple member (keyexpr)
    char *p_start = &entry[0];
    char *p_end = strchr(p_start, RAWETH_CFG_TUPLE_SEPARATOR);
    size_t ke_len = (uintptr_t)p_end - (uintptr_t)p_start;
    storage->_keyexpr = _z_string_copy_from_substr(p_start, ke_len);
    if (!_z_string_check(&storage->_keyexpr)) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }

    // Check second entry (address)
    p_start = p_end;
    p_start++;
    p_end = strchr(p_start, RAWETH_CFG_TUPLE_SEPARATOR);
    *p_end = '\0';
    uint8_t *addr = _z_parse_address_raweth(p_start);
    memcpy(storage->_dmac, addr, _ZP_MAC_ADDR_LENGTH);
    z_free(addr);
    *p_end = RAWETH_CFG_TUPLE_SEPARATOR;

    // Check optional third entry (vlan id)
    p_start = p_end;
    p_start++;
    if (p_start >= entry_end) {  // No entry
        storage->_has_vlan = false;
    } else {
        storage->_has_vlan = true;
        storage->_vlan = (uint16_t)strtol(p_start, NULL, 16);
    }
    return _Z_RES_OK;
}
static bool _z_valid_mapping_entry(char *entry) {
    size_t len = strlen(entry);
    const char *entry_end = &entry[len - (size_t)1];

    // Check first tuple member (keyexpr)
    char *p_start = &entry[0];
    char *p_end = strchr(p_start, RAWETH_CFG_TUPLE_SEPARATOR);
    if (p_end == NULL) {
        return false;
    }
    // Check second entry (address)
    p_start = p_end;
    p_start++;
    if (p_start > entry_end) {
        return false;
    }
    p_end = strchr(p_start, RAWETH_CFG_TUPLE_SEPARATOR);
    if (p_end == NULL) {
        return false;
    }
    *p_end = '\0';
    if (!_z_valid_address_raweth(p_start)) {
        *p_end = RAWETH_CFG_TUPLE_SEPARATOR;
        return false;
    }
    *p_end = RAWETH_CFG_TUPLE_SEPARATOR;
    return true;
}

static bool _z_valid_address_raweth_inner(const _z_string_t *address) {
    // Check if the string has the correct length
    size_t len = _z_string_len(address);
    const char *str_data = _z_string_data(address);
    if (len != 17) {  // 6 pairs of hexadecimal digits and 5 colons
        return false;
    }
    // Check if the colons are at the correct positions
    for (size_t i = 2; i < len; i += 3) {
        if (str_data[i] != ':') {
            return false;
        }
    }
    // Check if each character is a valid hexadecimal digit
    for (size_t i = 0; i < len; ++i) {
        if (i % 3 != 2) {
            char c = str_data[i];
            if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))) {
                return false;
            }
        }
    }
    return true;
}

static bool _z_valid_address_raweth(const char *address) {
    _z_string_t addr_str = _z_string_alias_str(address);
    return _z_valid_address_raweth_inner(&addr_str);
}

static uint8_t *_z_parse_address_raweth(const char *address) {
    // Allocate data
    uint8_t *ret = (uint8_t *)z_malloc(_ZP_MAC_ADDR_LENGTH);
    if (ret == NULL) {
        return ret;
    }
    for (int i = 0; i < _ZP_MAC_ADDR_LENGTH; ++i) {
        // Extract a pair of hexadecimal digits from the MAC address string
        char byteString[3];
        strncpy(byteString, address + i * 3, 2);
        byteString[2] = '\0';
        // Convert the hexadecimal string to an integer
        ret[i] = (unsigned char)strtol(byteString, NULL, 16);
    }
    return ret;
}

static z_result_t _z_f_link_open_raweth(_z_link_t *self) {
    // Init arrays
    self->_socket._raweth._mapping = _zp_raweth_mapping_array_empty();
    self->_socket._raweth._whitelist = _zp_raweth_whitelist_array_empty();
    // Init socket smac
    if (_z_valid_address_raweth_inner(&self->_endpoint._locator._address)) {
        uint8_t *addr = _z_parse_address_raweth(_z_string_data(&self->_endpoint._locator._address));
        memcpy(&self->_socket._raweth._smac, addr, _ZP_MAC_ADDR_LENGTH);
        z_free(addr);
    } else {
        _Z_DEBUG("Invalid locator source mac addr, using default value.");
        memcpy(&self->_socket._raweth._smac, _ZP_RAWETH_DEFAULT_SMAC, _ZP_MAC_ADDR_LENGTH);
    }
    // Init socket interface
    if (_z_valid_iface_raweth(&self->_endpoint._config)) {
        self->_socket._raweth._interface = _z_get_iface_raweth(&self->_endpoint._config);
    } else {
        _Z_DEBUG("Invalid locator interface, using default value %s", _ZP_RAWETH_DEFAULT_INTERFACE);
        self->_socket._raweth._interface = _ZP_RAWETH_DEFAULT_INTERFACE;
    }
    // Init socket ethtype
    if (_z_valid_ethtype_raweth(&self->_endpoint._config)) {
        self->_socket._raweth._ethtype = (uint16_t)_z_get_ethtype_raweth(&self->_endpoint._config);
    } else {
        _Z_DEBUG("Invalid locator ethtype, using default value 0x%04x", _ZP_RAWETH_DEFAULT_ETHTYPE);
        self->_socket._raweth._ethtype = _ZP_RAWETH_DEFAULT_ETHTYPE;
    }
    // Init socket mapping
    size_t size = _z_valid_mapping_raweth(&self->_endpoint._config);
    if (size != (size_t)0) {
        _Z_RETURN_IF_ERR(_z_get_mapping_raweth(&self->_endpoint._config, &self->_socket._raweth._mapping, size));
    } else {
        _Z_DEBUG("Invalid locator mapping, using default value.");
        self->_socket._raweth._mapping = _zp_raweth_mapping_array_make(1);
        if (_zp_raweth_mapping_array_len(&self->_socket._raweth._mapping) == 0) {
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        _zp_raweth_mapping_entry_t *entry = _zp_raweth_mapping_array_get(&self->_socket._raweth._mapping, 0);
        *entry = _ZP_RAWETH_DEFAULT_MAPPING;
    }
    // Init socket whitelist
    size = _z_valid_whitelist_raweth(&self->_endpoint._config);
    if (size != (size_t)0) {
        _Z_RETURN_IF_ERR(_z_get_whitelist_raweth(&self->_endpoint._config, &self->_socket._raweth._whitelist, size));
    } else {
        _Z_DEBUG("Invalid locator whitelist, filtering deactivated.");
    }
    // Open raweth link
    return _z_open_raweth(&self->_socket._raweth._sock, self->_socket._raweth._interface);
}

static z_result_t _z_f_link_listen_raweth(_z_link_t *self) { return _z_f_link_open_raweth(self); }

static void _z_f_link_close_raweth(_z_link_t *self) {
    // Close connection
    _z_close_raweth(&self->_socket._raweth._sock);
    // Clear config
    _zp_raweth_mapping_array_clear(&self->_socket._raweth._mapping);
    if (_zp_raweth_whitelist_array_len(&self->_socket._raweth._whitelist) != 0) {
        _zp_raweth_whitelist_array_clear(&self->_socket._raweth._whitelist);
    }
}

static void _z_f_link_free_raweth(_z_link_t *self) { _ZP_UNUSED(self); }

static size_t _z_f_link_write_raweth(const _z_link_t *self, const uint8_t *ptr, size_t len,
                                     _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(self);
    _ZP_UNUSED(ptr);
    _ZP_UNUSED(len);
    _ZP_UNUSED(socket);
    return SIZE_MAX;
}

static size_t _z_f_link_write_all_raweth(const _z_link_t *self, const uint8_t *ptr, size_t len) {
    _ZP_UNUSED(self);
    _ZP_UNUSED(ptr);
    _ZP_UNUSED(len);
    return SIZE_MAX;
}

static size_t _z_f_link_read_raweth(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr) {
    _ZP_UNUSED(self);
    _ZP_UNUSED(ptr);
    _ZP_UNUSED(len);
    _ZP_UNUSED(addr);
    return SIZE_MAX;
}

static size_t _z_f_link_read_exact_raweth(const _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr,
                                          _z_sys_net_socket_t *socket) {
    _ZP_UNUSED(self);
    _ZP_UNUSED(ptr);
    _ZP_UNUSED(len);
    _ZP_UNUSED(addr);
    _ZP_UNUSED(socket);
    return SIZE_MAX;
}

static uint16_t _z_get_link_mtu_raweth(void) { return _ZP_MAX_ETH_FRAME_SIZE; }

z_result_t _z_endpoint_raweth_valid(_z_endpoint_t *endpoint) {
    z_result_t ret = _Z_RES_OK;

    // Check the root
    _z_string_t str_cmp = _z_string_alias_str(RAWETH_SCHEMA);
    if (!_z_string_equals(&endpoint->_locator._protocol, &str_cmp)) {
        _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
    }
    return ret;
}

z_result_t _z_new_link_raweth(_z_link_t *zl, _z_endpoint_t endpoint) {
    z_result_t ret = _Z_RES_OK;
    zl->_type = _Z_LINK_TYPE_RAWETH;
    zl->_cap._transport = Z_LINK_CAP_TRANSPORT_RAWETH;
    zl->_cap._is_reliable = false;
    zl->_mtu = _z_get_link_mtu_raweth();

    zl->_endpoint = endpoint;

    // Init socket
    memset(&zl->_socket._raweth, 0, sizeof(zl->_socket._raweth));

    zl->_open_f = _z_f_link_open_raweth;
    zl->_listen_f = _z_f_link_listen_raweth;
    zl->_close_f = _z_f_link_close_raweth;
    zl->_free_f = _z_f_link_free_raweth;

    zl->_write_f = _z_f_link_write_raweth;
    zl->_write_all_f = _z_f_link_write_all_raweth;
    zl->_read_f = _z_f_link_read_raweth;
    zl->_read_exact_f = _z_f_link_read_exact_raweth;
    zl->_read_socket_f = _z_noop_link_read_socket;

    return ret;
}

size_t _z_raweth_config_strlen(const _z_str_intmap_t *s) {
    RAWETH_CONFIG_MAPPING_BUILD
    return _z_str_intmap_strlen(s, RAWETH_CONFIG_ARGC, args);
}
char *_z_raweth_config_to_str(const _z_str_intmap_t *s) {
    RAWETH_CONFIG_MAPPING_BUILD
    return _z_str_intmap_to_str(s, RAWETH_CONFIG_ARGC, args);
}

z_result_t _z_raweth_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n) {
    RAWETH_CONFIG_MAPPING_BUILD
    return _z_str_intmap_from_strn(strint, s, RAWETH_CONFIG_ARGC, args, n);
}

z_result_t _z_raweth_config_from_str(_z_str_intmap_t *strint, const char *s) {
    return _z_raweth_config_from_strn(strint, s, strlen(s));
}

#else
z_result_t _z_endpoint_raweth_valid(_z_endpoint_t *endpoint) {
    _ZP_UNUSED(endpoint);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_new_link_raweth(_z_link_t *zl, _z_endpoint_t endpoint) {
    _ZP_UNUSED(zl);
    _ZP_UNUSED(endpoint);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

size_t _z_raweth_config_strlen(const _z_str_intmap_t *s) {
    _ZP_UNUSED(s);
    return 0;
}

char *_z_raweth_config_to_str(const _z_str_intmap_t *s) {
    _ZP_UNUSED(s);
    return NULL;
}

z_result_t _z_raweth_config_from_strn(_z_str_intmap_t *strint, const char *s, size_t n) {
    _ZP_UNUSED(strint);
    _ZP_UNUSED(s);
    _ZP_UNUSED(n);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}

z_result_t _z_raweth_config_from_str(_z_str_intmap_t *strint, const char *s) {
    _ZP_UNUSED(strint);
    _ZP_UNUSED(s);
    _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
}
#endif
