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

#include "zenoh-pico/link/endpoint.h"

#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"
#if Z_FEATURE_LINK_TCP == 1
#include "zenoh-pico/link/config/tcp.h"
#endif
#if Z_FEATURE_LINK_UDP_UNICAST == 1 || Z_FEATURE_LINK_UDP_MULTICAST == 1
#include "zenoh-pico/link/config/udp.h"
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
#include "zenoh-pico/link/config/bt.h"
#endif
#if Z_FEATURE_LINK_SERIAL == 1
#include "zenoh-pico/link/config/serial.h"
#endif
#if Z_FEATURE_LINK_WS == 1
#include "zenoh-pico/link/config/ws.h"
#endif
#if Z_FEATURE_LINK_TLS == 1
#include "zenoh-pico/link/config/tls.h"
#endif
#include "zenoh-pico/link/config/raweth.h"

/*------------------ Locator ------------------*/
void _z_locator_init(_z_locator_t *locator) {
    locator->_protocol = _z_string_null();
    locator->_address = _z_string_null();
    locator->_metadata = _z_str_intmap_make();
}

void _z_locator_clear(_z_locator_t *lc) {
    _z_string_clear(&lc->_protocol);
    _z_string_clear(&lc->_address);
    _z_str_intmap_clear(&lc->_metadata);
}

void _z_locator_free(_z_locator_t **lc) {
    _z_locator_t *ptr = *lc;

    if (ptr != NULL) {
        _z_locator_clear(ptr);

        z_free(ptr);
        *lc = NULL;
    }
}

z_result_t _z_locator_copy(_z_locator_t *dst, const _z_locator_t *src) {
    _Z_RETURN_IF_ERR(_z_string_copy(&dst->_protocol, &src->_protocol));
    _Z_RETURN_IF_ERR(_z_string_copy(&dst->_address, &src->_address));

    // @TODO: implement copy for metadata
    dst->_metadata = _z_str_intmap_make();
    return _Z_RES_OK;
}

bool _z_locator_eq(const _z_locator_t *left, const _z_locator_t *right) {
    bool res = false;

    res = _z_string_equals(&left->_protocol, &right->_protocol);
    if (res == true) {
        res = _z_string_equals(&left->_address, &right->_address);
        // if (res == true) {
        //     // @TODO: implement eq for metadata
        // }
    }

    return res;
}

static z_result_t _z_locator_protocol_from_string(_z_string_t *protocol, const _z_string_t *str) {
    *protocol = _z_string_null();

    const char *p_start = _z_string_data(str);
    const char *p_end = (char *)memchr(p_start, (int)LOCATOR_PROTOCOL_SEPARATOR, _z_string_len(str));
    if ((p_end == NULL) || (p_start == p_end)) {
        _Z_ERROR_RETURN(_Z_ERR_CONFIG_LOCATOR_INVALID);
    }
    size_t p_len = _z_ptr_char_diff(p_end, p_start);
    return _z_string_copy_substring(protocol, str, 0, p_len);
}

static z_result_t _z_locator_address_from_string(_z_string_t *address, const _z_string_t *str) {
    *address = _z_string_null();

    // Find protocol separator
    const char *p_start = (char *)memchr(_z_string_data(str), (int)LOCATOR_PROTOCOL_SEPARATOR, _z_string_len(str));
    if (p_start == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_CONFIG_LOCATOR_INVALID);
    }
    // Skip protocol separator
    p_start = _z_cptr_char_offset(p_start, 1);
    size_t start_offset = _z_ptr_char_diff(p_start, _z_string_data(str));
    if (start_offset >= _z_string_len(str)) {
        _Z_ERROR_RETURN(_Z_ERR_CONFIG_LOCATOR_INVALID);
    }
    // Find metadata separator
    size_t curr_len = _z_string_len(str) - start_offset;
    const char *p_end = (char *)memchr(p_start, (int)LOCATOR_METADATA_SEPARATOR, curr_len);
    // There is no metadata separator, then look for config separator
    if (p_end == NULL) {
        p_end = memchr(p_start, (int)ENDPOINT_CONFIG_SEPARATOR, curr_len);
    }
    // There is no config separator, then address goes to the end of string
    if (p_end == NULL) {
        p_end = _z_cptr_char_offset(_z_string_data(str), (ptrdiff_t)_z_string_len(str));
    }
    if (p_start >= p_end) {
        _Z_ERROR_RETURN(_Z_ERR_CONFIG_LOCATOR_INVALID);
    }
    // Copy data
    size_t addr_len = _z_ptr_char_diff(p_end, p_start);
    return _z_string_copy_substring(address, str, start_offset, addr_len);
}

z_result_t _z_locator_metadata_from_string(_z_str_intmap_t *strint, const _z_string_t *str) {
    *strint = _z_str_intmap_make();

    // Find metadata separator
    const char *p_start = (char *)memchr(_z_string_data(str), LOCATOR_METADATA_SEPARATOR, _z_string_len(str));
    if (p_start == NULL) {
        return _Z_RES_OK;
    }
    p_start = _z_cptr_char_offset(p_start, 1);
    size_t start_offset = _z_ptr_char_diff(p_start, _z_string_data(str));
    if (start_offset > _z_string_len(str)) {
        _Z_ERROR_RETURN(_Z_ERR_CONFIG_LOCATOR_INVALID);
    }
    if (start_offset == _z_string_len(str)) {
        return _Z_RES_OK;
    }

    const char *p_end = (char *)memchr(_z_string_data(str), ENDPOINT_CONFIG_SEPARATOR, _z_string_len(str));
    if (p_end == NULL) {
        p_end = _z_cptr_char_offset(_z_string_data(str), (ptrdiff_t)_z_string_len(str) + 1);
    }

    if (p_start != p_end) {
        size_t p_len = _z_ptr_char_diff(p_end, p_start);
        return _z_str_intmap_from_strn(strint, p_start, 0, NULL, p_len);
    }
    return _Z_RES_OK;
}

size_t _z_locator_metadata_strlen(const _z_str_intmap_t *s) {
    // @TODO: define protocol-level metadata
    return _z_str_intmap_strlen(s, 0, NULL);
}

void _z_locator_metadata_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s) {
    // @TODO: define protocol-level metadata
    _z_str_intmap_onto_str(dst, dst_len, s, 0, NULL);
}

z_result_t _z_locator_from_string(_z_locator_t *lc, const _z_string_t *str) {
    if (str == NULL || !_z_string_check(str)) {
        _Z_ERROR_RETURN(_Z_ERR_CONFIG_LOCATOR_INVALID);
    }
    // Parse protocol
    _Z_RETURN_IF_ERR(_z_locator_protocol_from_string(&lc->_protocol, str));
    // Parse address
    _Z_CLEAN_RETURN_IF_ERR(_z_locator_address_from_string(&lc->_address, str), _z_locator_clear(lc));
    // Parse metadata
    _Z_CLEAN_RETURN_IF_ERR(_z_locator_metadata_from_string(&lc->_metadata, str), _z_locator_clear(lc));
    return _Z_RES_OK;
}

size_t _z_locator_strlen(const _z_locator_t *l) {
    size_t ret = 0;

    if (l != NULL) {
        // Calculate the string length to allocate
        ret = _z_string_len(&l->_protocol) + _z_string_len(&l->_address) + 1;

        // @TODO: define protocol-level metadata
        size_t md_len = _z_locator_metadata_strlen(&l->_metadata);
        if (md_len > (size_t)0) {
            ret = ret + (size_t)1;  // Locator metadata separator
            ret = ret + md_len;     // Locator metadata content
        }
    }
    return ret;
}

/**
 * Converts a :c:type:`_z_locator_t` into its string format.
 *
 * Parameters:
 *   dst: Pointer to the destination string. It MUST be already allocated with enough space to store the locator in
 * its string format. loc: :c:type:`_z_locator_t` to be converted into its string format.
 */
static void __z_locator_onto_string(_z_string_t *dst, const _z_locator_t *loc) {
    char *curr_dst = (char *)_z_string_data(dst);
    const char psep = LOCATOR_PROTOCOL_SEPARATOR;
    const char msep = LOCATOR_METADATA_SEPARATOR;

    size_t prot_len = _z_string_len(&loc->_protocol);
    size_t addr_len = _z_string_len(&loc->_address);

    if ((prot_len + addr_len + 1) > _z_string_len(dst)) {
        _Z_ERROR("Buffer too small to write locator");
        return;
    }
    // Locator protocol
    memcpy(curr_dst, _z_string_data(&loc->_protocol), prot_len);
    curr_dst = _z_ptr_char_offset(curr_dst, (ptrdiff_t)prot_len);
    // Locator protocol separator
    memcpy(curr_dst, &psep, 1);
    curr_dst = _z_ptr_char_offset(curr_dst, 1);
    // Locator address
    memcpy(curr_dst, _z_string_data(&loc->_address), addr_len);
    curr_dst = _z_ptr_char_offset(curr_dst, (ptrdiff_t)addr_len);
    // @TODO: define protocol-level metadata
    size_t md_len = _z_locator_metadata_strlen(&loc->_metadata);
    if (md_len > (size_t)0) {
        size_t curr_len = _z_string_len(dst) - _z_ptr_char_diff(curr_dst, _z_string_data(dst));
        if (curr_len == 0) {
            _Z_ERROR("Buffer too small to write metadata");
            return;
        }
        // Locator metadata separator
        memcpy(curr_dst, &msep, 1);
        curr_dst = _z_ptr_char_offset(curr_dst, 1);
        // Locator metadata
        _z_locator_metadata_onto_str(curr_dst, curr_len, &loc->_metadata);
    }
}

/**
 * Converts a :c:type:`_z_locator_t` into its _z_string format.
 *
 * Parameters:
 *   loc: :c:type:`_z_locator_t` to be converted into its _z_string format.
 *
 * Returns:
 *   The z_stringified :c:type:`_z_locator_t`.
 */
_z_string_t _z_locator_to_string(const _z_locator_t *loc) {
    _z_string_t s = _z_string_preallocate(_z_locator_strlen(loc));
    if (!_z_string_check(&s)) {
        return s;
    }
    __z_locator_onto_string(&s, loc);
    return s;
}

char *_z_endpoint_parse_host(_z_string_t *addr) {
    if (addr == NULL) {
        return NULL;
    }

    const char *addr_data = _z_string_data(addr);
    const size_t addr_len = _z_string_len(addr);
    if (addr_data == NULL || addr_len == 0) {
        return NULL;
    }

    const char *colon = _z_string_rchr(addr, ':');
    if (colon == NULL) {
        return NULL;
    }

    // IPv6
    const char *host_start = addr_data;
    const char *host_end = colon;
    if ((host_end > host_start) && (host_start[0] == '[') && (host_end[-1] == ']')) {
        host_start = _z_cptr_char_offset(host_start, 1);
        host_end = _z_cptr_char_offset(host_end, -1);
    }

    if (host_end <= host_start) {
        return NULL;
    }

    const size_t host_len = _z_ptr_char_diff(host_end, host_start);
    char *host_copy = (char *)z_malloc(host_len + 1);
    if (host_copy == NULL) {
        return NULL;
    }

    _z_str_n_copy(host_copy, host_start, host_len + 1);
    return host_copy;
}

char *_z_endpoint_parse_port(_z_string_t *addr) {
    if (addr == NULL) {
        return NULL;
    }

    const char *addr_data = _z_string_data(addr);
    const size_t addr_len = _z_string_len(addr);
    if (addr_data == NULL || addr_len == 0) {
        return NULL;
    }

    const char *colon = _z_string_rchr(addr, ':');
    if (colon == NULL) {
        return NULL;
    }

    const char *addr_end = _z_cptr_char_offset(addr_data, (ptrdiff_t)addr_len);
    const char *port_start = _z_cptr_char_offset(colon, 1);
    if (port_start >= addr_end) {
        return NULL;
    }

    const size_t port_len = _z_ptr_char_diff(addr_end, port_start);
    char *port = (char *)z_malloc(port_len + 1);
    if (port == NULL) {
        return NULL;
    }

    _z_str_n_copy(port, port_start, port_len + 1);

    char *endptr = NULL;
    errno = 0;
    unsigned long port_val = strtoul(port, &endptr, 10);
    if ((errno != 0) || (endptr == port) || (*endptr != '\0') || (port_val == 0) || (port_val > 65535)) {
        z_free(port);
        return NULL;
    }

    return port;
}

/*------------------ Endpoint ------------------*/
void _z_endpoint_init(_z_endpoint_t *endpoint) {
    _z_locator_init(&endpoint->_locator);
    endpoint->_config = _z_str_intmap_make();
}

void _z_endpoint_clear(_z_endpoint_t *ep) {
    _z_locator_clear(&ep->_locator);
    _z_str_intmap_clear(&ep->_config);
}

void _z_endpoint_free(_z_endpoint_t **ep) {
    _z_endpoint_t *ptr = *ep;

    if (ptr != NULL) {
        _z_locator_clear(&ptr->_locator);
        _z_str_intmap_clear(&ptr->_config);

        z_free(ptr);
        *ep = NULL;
    }
}

z_result_t _z_endpoint_config_from_string(_z_str_intmap_t *strint, const _z_string_t *str, _z_string_t *proto) {
    char *p_start = (char *)memchr(_z_string_data(str), ENDPOINT_CONFIG_SEPARATOR, _z_string_len(str));
    if (p_start != NULL) {
        p_start = _z_ptr_char_offset(p_start, 1);
        size_t cfg_size = _z_string_len(str) - _z_ptr_char_diff(p_start, _z_string_data(str));

        // Call the right configuration parser depending on the protocol
        _z_string_t cmp_str = _z_string_null();
#if Z_FEATURE_LINK_TCP == 1
        cmp_str = _z_string_alias_str(TCP_SCHEMA);
        if (_z_string_equals(proto, &cmp_str)) {
            return _z_tcp_config_from_strn(strint, p_start, cfg_size);
        }
#endif
#if Z_FEATURE_LINK_UDP_UNICAST == 1 || Z_FEATURE_LINK_UDP_MULTICAST == 1
        cmp_str = _z_string_alias_str(UDP_SCHEMA);
        if (_z_string_equals(proto, &cmp_str)) {
            return _z_udp_config_from_strn(strint, p_start, cfg_size);
        }
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
        cmp_str = _z_string_alias_str(BT_SCHEMA);
        if (_z_string_equals(proto, &cmp_str)) {
            return _z_bt_config_from_strn(strint, p_start, cfg_size);
        }
#endif
#if Z_FEATURE_LINK_SERIAL == 1
        cmp_str = _z_string_alias_str(SERIAL_SCHEMA);
        if (_z_string_equals(proto, &cmp_str)) {
            return _z_serial_config_from_strn(strint, p_start, cfg_size);
        }
#endif
#if Z_FEATURE_LINK_WS == 1
        cmp_str = _z_string_alias_str(WS_SCHEMA);
        if (_z_string_equals(proto, &cmp_str)) {
            return _z_ws_config_from_strn(strint, p_start, cfg_size);
        }
#endif
#if Z_FEATURE_LINK_TLS == 1
        cmp_str = _z_string_alias_str(TLS_SCHEMA);
        if (_z_string_equals(proto, &cmp_str)) {
            return _z_tls_config_from_strn(strint, p_start, cfg_size);
        }
#endif
        cmp_str = _z_string_alias_str(RAWETH_SCHEMA);
        if (_z_string_equals(proto, &cmp_str)) {
            return _z_raweth_config_from_strn(strint, p_start, cfg_size);
        }
    }
    return _Z_RES_OK;
}

size_t _z_endpoint_config_strlen(const _z_str_intmap_t *s, _z_string_t *proto) {
    // Call the right configuration parser depending on the protocol
    _z_string_t cmp_str = _z_string_null();
#if Z_FEATURE_LINK_TCP == 1
    cmp_str = _z_string_alias_str(TCP_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_tcp_config_strlen(s);
    }
#endif
#if Z_FEATURE_LINK_UDP_UNICAST == 1 || Z_FEATURE_LINK_UDP_MULTICAST == 1
    cmp_str = _z_string_alias_str(UDP_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_udp_config_strlen(s);
    }
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
    cmp_str = _z_string_alias_str(BT_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_bt_config_strlen(s);
    }
#endif
#if Z_FEATURE_LINK_SERIAL == 1
    cmp_str = _z_string_alias_str(SERIAL_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_serial_config_strlen(s);
    }
#endif
#if Z_FEATURE_LINK_WS == 1
    cmp_str = _z_string_alias_str(WS_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_ws_config_strlen(s);
    }
#endif
#if Z_FEATURE_LINK_TLS == 1
    cmp_str = _z_string_alias_str(TLS_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_tls_config_strlen(s);
    }
#endif
    cmp_str = _z_string_alias_str(RAWETH_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_raweth_config_strlen(s);
    }
    return 0;
}

char *_z_endpoint_config_to_string(const _z_str_intmap_t *s, const _z_string_t *proto) {
    // Call the right configuration parser depending on the protocol
    _z_string_t cmp_str = _z_string_null();

#if Z_FEATURE_LINK_TCP == 1
    cmp_str = _z_string_alias_str(TCP_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_tcp_config_to_str(s);
    }
#endif
#if Z_FEATURE_LINK_UDP_UNICAST == 1 || Z_FEATURE_LINK_UDP_MULTICAST == 1
    cmp_str = _z_string_alias_str(UDP_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_udp_config_to_str(s);
    }
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
    cmp_str = _z_string_alias_str(BT_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_bt_config_to_str(s);
    }
#endif
#if Z_FEATURE_LINK_SERIAL == 1
    cmp_str = _z_string_alias_str(SERIAL_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_serial_config_to_str(s);
    }
#endif
#if Z_FEATURE_LINK_WS == 1
    cmp_str = _z_string_alias_str(WS_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_ws_config_to_str(s);
    }
#endif
#if Z_FEATURE_LINK_TLS == 1
    cmp_str = _z_string_alias_str(TLS_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_tls_config_to_str(s);
    }
#endif
    cmp_str = _z_string_alias_str(RAWETH_SCHEMA);
    if (_z_string_equals(proto, &cmp_str)) {
        return _z_raweth_config_to_str(s);
    }
    return NULL;
}

z_result_t _z_endpoint_from_string(_z_endpoint_t *ep, const _z_string_t *str) {
    _z_endpoint_init(ep);
    _Z_CLEAN_RETURN_IF_ERR(_z_locator_from_string(&ep->_locator, str), _z_endpoint_clear(ep));
    _Z_CLEAN_RETURN_IF_ERR(_z_endpoint_config_from_string(&ep->_config, str, &ep->_locator._protocol),
                           _z_endpoint_clear(ep));
    return _Z_RES_OK;
}

_z_string_t _z_endpoint_to_string(const _z_endpoint_t *endpoint) {
    _z_string_t ret = _z_string_null();
    // Retrieve locator
    _z_string_t locator = _z_locator_to_string(&endpoint->_locator);
    if (!_z_string_check(&locator)) {
        return _z_string_null();
    }
    size_t curr_len = _z_string_len(&locator);
    // Retrieve config
    char *config = _z_endpoint_config_to_string(&endpoint->_config, &endpoint->_locator._protocol);
    size_t config_len = 0;
    if (config != NULL) {
        config_len = strlen(config);
        curr_len += config_len;
    }
    // Reconstruct the endpoint as a string
    ret = _z_string_preallocate(curr_len);
    if (!_z_string_check(&ret)) {
        // cppcheck-suppress misra-c2012-17.3
        _z_string_clear(&locator);
        if (config != NULL) {
            // cppcheck-suppress misra-c2012-17.3
            z_free(config);
        }
        return ret;
    }
    // Copy locator
    char *curr_dst = (char *)_z_string_data(&ret);
    memcpy(curr_dst, _z_string_data(&locator), _z_string_len(&locator));
    curr_dst = _z_ptr_char_offset(curr_dst, (ptrdiff_t)_z_string_len(&locator));
    // Copy config
    if (config != NULL) {
        memcpy(curr_dst, config, config_len);
        // cppcheck-suppress misra-c2012-17.3
        z_free(config);
    }
    // Clean up
    _z_string_clear(&locator);
    return ret;
}
