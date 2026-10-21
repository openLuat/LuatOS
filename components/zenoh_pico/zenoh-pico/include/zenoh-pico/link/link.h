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

#ifndef ZENOH_PICO_LINK_H
#define ZENOH_PICO_LINK_H

#include "zenoh-pico/config.h"
#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/config.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_LINK_TCP == 1
#include "zenoh-pico/system/link/tcp.h"
#endif

#if Z_FEATURE_LINK_UDP_UNICAST == 1 || Z_FEATURE_LINK_UDP_MULTICAST == 1
#include "zenoh-pico/system/link/udp.h"
#endif

#if Z_FEATURE_RAWETH_TRANSPORT == 1
#include "zenoh-pico/system/link/raweth.h"
#endif

#if Z_FEATURE_LINK_BLUETOOTH == 1
#include "zenoh-pico/system/link/bt.h"
#endif

#if Z_FEATURE_LINK_SERIAL == 1
#include "zenoh-pico/system/link/serial.h"
#endif

#if Z_FEATURE_LINK_WS == 1
#include "zenoh-pico/system/link/ws.h"
#endif

#if Z_FEATURE_LINK_TLS == 1
#include "zenoh-pico/system/link/tls.h"
#endif

#include "zenoh-pico/utils/result.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Link transport capability enum.
 *
 * Enumerators:
 *     Z_LINK_CAP_TRANSPORT_UNICAST: Link has unicast capabilities.
 *     Z_LINK_CAP_TRANSPORT_MULTICAST: Link has multicast capabilities.
 */
typedef enum {
    Z_LINK_CAP_TRANSPORT_UNICAST = 0,
    Z_LINK_CAP_TRANSPORT_MULTICAST = 1,
    Z_LINK_CAP_TRANSPORT_RAWETH = 2,
} _z_link_cap_transport_t;

/**
 * Link flow capability enum.
 *
 * Enumerators:
 *     Z_LINK_CAP_FLOW_STREAM: Link use datagrams.
 *     Z_LINK_CAP_FLOW_DATAGRAM: Link use byte stream.
 */
typedef enum {
    Z_LINK_CAP_FLOW_DATAGRAM = 0,
    Z_LINK_CAP_FLOW_STREAM = 1,
} _z_link_cap_flow_t;

/**
 * Link capabilities, stored as a register-like object.
 *
 * Fields:
 *     transport: 2 bits, see _z_link_cap_transport_t enum.
 *     flow: 1 bit, see _z_link_cap_flow_t enum.
 *     reliable: 1 bit, 1 if the link is reliable (network definition)
 *     reserved: 4 bits, reserved for future use
 */
typedef struct _z_link_capabilities_t {
    uint8_t _transport : 2;
    uint8_t _flow : 1;
    uint8_t _is_reliable : 1;
    uint8_t _reserved : 4;
} _z_link_capabilities_t;

struct _z_link_t;  // Forward declaration to be used in _z_f_link_*

typedef z_result_t (*_z_f_link_open)(struct _z_link_t *self);
typedef z_result_t (*_z_f_link_listen)(struct _z_link_t *self);
typedef void (*_z_f_link_close)(struct _z_link_t *self);
typedef size_t (*_z_f_link_write)(const struct _z_link_t *self, const uint8_t *ptr, size_t len,
                                  _z_sys_net_socket_t *socket);
typedef size_t (*_z_f_link_write_all)(const struct _z_link_t *self, const uint8_t *ptr, size_t len);
typedef size_t (*_z_f_link_read)(const struct _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr);
typedef size_t (*_z_f_link_read_exact)(const struct _z_link_t *self, uint8_t *ptr, size_t len, _z_slice_t *addr,
                                       _z_sys_net_socket_t *socket);
typedef size_t (*_z_f_link_read_socket)(const _z_sys_net_socket_t socket, uint8_t *ptr, size_t len);
typedef void (*_z_f_link_free)(struct _z_link_t *self);

static inline size_t _z_noop_link_read_socket(const _z_sys_net_socket_t socket, uint8_t *ptr, size_t len) {
    _ZP_UNUSED(socket);
    _ZP_UNUSED(ptr);
    _ZP_UNUSED(len);
    _Z_ERROR("Function not implemented");
    return 0;
}

enum _z_link_type_e {
    _Z_LINK_TYPE_TCP,
    _Z_LINK_TYPE_UDP,
    _Z_LINK_TYPE_BT,
    _Z_LINK_TYPE_SERIAL,
    _Z_LINK_TYPE_WS,
    _Z_LINK_TYPE_TLS,
    _Z_LINK_TYPE_RAWETH,
};

typedef struct _z_link_t {
    _z_endpoint_t _endpoint;
    int _type;
    union {
#if Z_FEATURE_LINK_TCP == 1
        _z_tcp_socket_t _tcp;
#endif
#if Z_FEATURE_LINK_UDP_UNICAST == 1 || Z_FEATURE_LINK_UDP_MULTICAST == 1
        _z_udp_socket_t _udp;
#endif
#if Z_FEATURE_LINK_BLUETOOTH == 1
        _z_bt_socket_t _bt;
#endif
#if Z_FEATURE_LINK_SERIAL == 1
        _z_serial_socket_t _serial;
#endif
#if Z_FEATURE_LINK_WS == 1
        _z_ws_socket_t _ws;
#endif
#if Z_FEATURE_LINK_TLS == 1
        _z_tls_socket_t _tls;
#endif
#if Z_FEATURE_RAWETH_TRANSPORT == 1
        _z_raweth_socket_t _raweth;
#endif
    } _socket;

    _z_f_link_open _open_f;
    _z_f_link_listen _listen_f;
    _z_f_link_close _close_f;
    _z_f_link_write _write_f;
    _z_f_link_write_all _write_all_f;
    _z_f_link_read _read_f;
    _z_f_link_read_exact _read_exact_f;
    _z_f_link_read_socket _read_socket_f;
    _z_f_link_free _free_f;

    uint16_t _mtu;
    _z_link_capabilities_t _cap;
} _z_link_t;

void _z_link_clear(_z_link_t *zl);
void _z_link_free(_z_link_t **zl);
z_result_t _z_open_socket(const _z_string_t *locator, const _z_config_t *session_cfg, _z_sys_net_socket_t *socket);
z_result_t _z_open_link(_z_link_t *zl, const _z_string_t *locator, const _z_config_t *session_cfg);
z_result_t _z_listen_link(_z_link_t *zl, const _z_string_t *locator, const _z_config_t *session_cfg);

z_result_t _z_link_send_wbuf(const _z_link_t *zl, const _z_wbuf_t *wbf, _z_sys_net_socket_t *socket);
size_t _z_link_recv_zbuf(const _z_link_t *zl, _z_zbuf_t *zbf, _z_slice_t *addr);
size_t _z_link_recv_exact_zbuf(const _z_link_t *zl, _z_zbuf_t *zbf, size_t len, _z_slice_t *addr,
                               _z_sys_net_socket_t *socket);
size_t _z_link_socket_recv_zbuf(const _z_link_t *link, _z_zbuf_t *zbf, const _z_sys_net_socket_t socket);
const _z_sys_net_socket_t *_z_link_get_socket(const _z_link_t *link);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_LINK_H */
