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

#include "zenoh-pico/link/link.h"

#include <stddef.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/link/config/raweth.h"
#include "zenoh-pico/link/manager.h"
#include "zenoh-pico/utils/logging.h"

z_result_t _z_open_socket(const _z_string_t *locator, const _z_config_t *session_cfg, _z_sys_net_socket_t *socket) {
#if Z_FEATURE_LINK_TLS != 1
    _ZP_UNUSED(session_cfg);
#endif
    _z_endpoint_t ep;
    z_result_t ret = _Z_RES_OK;
    _Z_RETURN_IF_ERR(_z_endpoint_from_string(&ep, locator));
    if (_z_endpoint_tcp_valid(&ep) == _Z_RES_OK) {
        ret = _z_new_peer_tcp(&ep, socket);
#if Z_FEATURE_LINK_TLS == 1
    } else if (_z_endpoint_tls_valid(&ep) == _Z_RES_OK) {
        ret = _z_new_peer_tls(&ep, socket, session_cfg);
#endif
    } else {
        _Z_ERROR_LOG(_Z_ERR_GENERIC);
        ret = _Z_ERR_GENERIC;
    }
    _z_endpoint_clear(&ep);
    return ret;
}

z_result_t _z_open_link(_z_link_t *zl, const _z_string_t *locator, const _z_config_t *session_cfg) {
#if Z_FEATURE_LINK_TLS != 1
    _ZP_UNUSED(session_cfg);
#endif
    z_result_t ret = _Z_RES_OK;

    _z_endpoint_t ep;
    ret = _z_endpoint_from_string(&ep, locator);
    if (ret == _Z_RES_OK) {
        // Create transport link
        if (_z_endpoint_tcp_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_tcp(zl, &ep);
        } else
#if Z_FEATURE_LINK_UDP_UNICAST == 1
            if (_z_endpoint_udp_unicast_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_udp_unicast(zl, ep);
        } else
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
            if (_z_endpoint_bt_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_bt(zl, ep);
        } else
#endif
#if Z_FEATURE_LINK_SERIAL == 1
            if (_z_endpoint_serial_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_serial(zl, ep);
        } else
#endif
#if Z_FEATURE_LINK_WS == 1
            if (_z_endpoint_ws_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_ws(zl, &ep);
        } else
#endif
#if Z_FEATURE_LINK_TLS == 1
            if (_z_endpoint_tls_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_tls(zl, &ep, session_cfg);
        } else
#endif
        {
            _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_SCHEMA_UNKNOWN);
            ret = _Z_ERR_CONFIG_LOCATOR_SCHEMA_UNKNOWN;
        }
        if (ret == _Z_RES_OK) {
            // Open transport link for communication
            if (zl->_open_f(zl) != _Z_RES_OK) {
                _Z_ERROR_LOG(_Z_ERR_TRANSPORT_OPEN_FAILED);
                ret = _Z_ERR_TRANSPORT_OPEN_FAILED;
                _z_link_clear(zl);
            }
        } else {
            _z_endpoint_clear(&ep);
        }
    } else {
        _z_endpoint_clear(&ep);
        _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
    }

    return ret;
}

z_result_t _z_listen_link(_z_link_t *zl, const _z_string_t *locator, const _z_config_t *session_cfg) {
#if Z_FEATURE_LINK_TLS != 1
    _ZP_UNUSED(session_cfg);
#endif
    z_result_t ret = _Z_RES_OK;

    _z_endpoint_t ep;
    ret = _z_endpoint_from_string(&ep, locator);
    if (ret == _Z_RES_OK) {
        // Create transport link
        if (_z_endpoint_tcp_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_tcp(zl, &ep);
        } else
#if Z_FEATURE_LINK_TLS == 1
            if (_z_endpoint_tls_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_tls(zl, &ep, session_cfg);
        } else
#endif
#if Z_FEATURE_LINK_UDP_MULTICAST == 1
            if (_z_endpoint_udp_multicast_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_udp_multicast(zl, ep);
        } else
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
            if (_z_endpoint_bt_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_bt(zl, ep);
        } else
#endif
            if (_z_endpoint_raweth_valid(&ep) == _Z_RES_OK) {
            ret = _z_new_link_raweth(zl, ep);
        } else {
            _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_SCHEMA_UNKNOWN);
            ret = _Z_ERR_CONFIG_LOCATOR_SCHEMA_UNKNOWN;
        }
        if (ret == _Z_RES_OK) {
            // Open transport link for listening
            if (zl->_listen_f(zl) != _Z_RES_OK) {
                _Z_ERROR_LOG(_Z_ERR_TRANSPORT_OPEN_FAILED);
                ret = _Z_ERR_TRANSPORT_OPEN_FAILED;
                _z_link_clear(zl);
            }
        } else {
            _z_endpoint_clear(&ep);
        }
    } else {
        _z_endpoint_clear(&ep);
        _Z_ERROR_LOG(_Z_ERR_CONFIG_LOCATOR_INVALID);
        ret = _Z_ERR_CONFIG_LOCATOR_INVALID;
    }

    return ret;
}

void _z_link_clear(_z_link_t *l) {
    if (l->_close_f != NULL) {
        l->_close_f(l);
    }
    if (l->_free_f != NULL) {
        l->_free_f(l);
    }
    _z_endpoint_clear(&l->_endpoint);
}

void _z_link_free(_z_link_t **l) {
    _z_link_t *ptr = *l;

    if (ptr != NULL) {
        _z_link_clear(ptr);

        z_free(ptr);
        *l = NULL;
    }
}

size_t _z_link_recv_zbuf(const _z_link_t *link, _z_zbuf_t *zbf, _z_slice_t *addr) {
    size_t rb = link->_read_f(link, _z_zbuf_get_wptr(zbf), _z_zbuf_space_left(zbf), addr);
    if (rb != SIZE_MAX) {
        _z_zbuf_set_wpos(zbf, _z_zbuf_get_wpos(zbf) + rb);
    }
    return rb;
}

size_t _z_link_recv_exact_zbuf(const _z_link_t *link, _z_zbuf_t *zbf, size_t len, _z_slice_t *addr,
                               _z_sys_net_socket_t *socket) {
    size_t rb = link->_read_exact_f(link, _z_zbuf_get_wptr(zbf), len, addr, socket);
    if (rb != SIZE_MAX) {
        _z_zbuf_set_wpos(zbf, _z_zbuf_get_wpos(zbf) + rb);
    }
    return rb;
}

size_t _z_link_socket_recv_zbuf(const _z_link_t *link, _z_zbuf_t *zbf, const _z_sys_net_socket_t socket) {
    size_t rb = link->_read_socket_f(socket, _z_zbuf_get_wptr(zbf), _z_zbuf_space_left(zbf));
    if (rb != SIZE_MAX) {
        _z_zbuf_set_wpos(zbf, _z_zbuf_get_wpos(zbf) + rb);
    }
    return rb;
}

z_result_t _z_link_send_wbuf(const _z_link_t *link, const _z_wbuf_t *wbf, _z_sys_net_socket_t *socket) {
    z_result_t ret = _Z_RES_OK;
    bool link_is_streamed = link->_cap._flow == Z_LINK_CAP_FLOW_STREAM;

    for (size_t i = 0; (i < _z_wbuf_len_iosli(wbf)) && (ret == _Z_RES_OK); i++) {
        _z_slice_t bs = _z_iosli_to_bytes(_z_wbuf_get_iosli(wbf, i));
        size_t n = bs.len;
        do {
            size_t wb = link->_write_f(link, bs.start, n, socket);
            if ((wb == SIZE_MAX) || (wb > n)) {
                _Z_ERROR_LOG(_Z_ERR_TRANSPORT_TX_FAILED);
                ret = _Z_ERR_TRANSPORT_TX_FAILED;
                break;
            }
            if (link_is_streamed && wb != n) {
                _Z_ERROR_LOG(_Z_ERR_TRANSPORT_TX_FAILED);
                ret = _Z_ERR_TRANSPORT_TX_FAILED;
                break;
            }
            n = n - wb;
            bs.start = bs.start + (bs.len - n);
        } while (n > (size_t)0);
    }

    return ret;
}

const _z_sys_net_socket_t *_z_link_get_socket(const _z_link_t *link) {
    switch (link->_type) {
#if Z_FEATURE_LINK_TCP == 1
        case _Z_LINK_TYPE_TCP:
            return &link->_socket._tcp._sock;
#endif
#if Z_FEATURE_LINK_UDP_UNICAST == 1 || Z_FEATURE_LINK_UDP_MULTICAST == 1
        case _Z_LINK_TYPE_UDP:
            return &link->_socket._udp._sock;
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
        case _Z_LINK_TYPE_BT:
            return &link->_socket._bt._sock;
#endif
#if Z_FEATURE_LINK_SERIAL == 1
        case _Z_LINK_TYPE_SERIAL:
            return &link->_socket._serial._sock;
#endif
#if Z_FEATURE_LINK_WS == 1
        case _Z_LINK_TYPE_WS:
            return &link->_socket._ws._sock;
#endif
#if Z_FEATURE_LINK_TLS == 1
        case _Z_LINK_TYPE_TLS:
            return &link->_socket._tls._sock;
#endif
#if Z_FEATURE_RAWETH_TRANSPORT == 1
        case _Z_LINK_TYPE_RAWETH:
            return &link->_socket._raweth._sock;
#endif
        default:
            _Z_INFO("Unknown link type");
            return NULL;
    }
}
