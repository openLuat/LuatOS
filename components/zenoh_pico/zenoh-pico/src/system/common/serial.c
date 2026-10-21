//
// Copyright (c) 2024 ZettaScale Technology
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

#include "zenoh-pico/protocol/definitions/serial.h"

#include <stdint.h>

#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/system/common/serial.h"
#include "zenoh-pico/system/link/serial.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_LINK_SERIAL == 1

#define SERIAL_CONNECT_THROTTLE_TIME_MS 250

z_result_t _z_connect_serial(const _z_sys_net_socket_t sock) {
    while (true) {
        uint8_t header = _Z_FLAG_SERIAL_INIT;

        _z_send_serial_internal(sock, header, NULL, 0);
        uint8_t tmp;
        size_t ret = _z_read_serial_internal(sock, &header, &tmp, sizeof(tmp));
        if (ret == SIZE_MAX) {
            _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_RX_FAILED);
        }

        if (_Z_HAS_FLAG(header, _Z_FLAG_SERIAL_ACK) && _Z_HAS_FLAG(header, _Z_FLAG_SERIAL_INIT)) {
            _Z_DEBUG("connected");
            break;
        } else if (_Z_HAS_FLAG(header, _Z_FLAG_SERIAL_RESET)) {
            z_sleep_ms(SERIAL_CONNECT_THROTTLE_TIME_MS);
            _Z_DEBUG("reset");
            continue;
        } else {
            _Z_ERROR("unknown header received: %02X", header);
            _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_RX_FAILED);
        }
    }

    return _Z_RES_OK;
}

size_t _z_read_serial(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len) {
    uint8_t header;
    return _z_read_serial_internal(sock, &header, ptr, len);
}

size_t _z_send_serial(const _z_sys_net_socket_t sock, const uint8_t *ptr, size_t len) {
    return _z_send_serial_internal(sock, 0, ptr, len);
}

size_t _z_read_exact_serial(const _z_sys_net_socket_t sock, uint8_t *ptr, size_t len) {
    size_t n = 0;
    uint8_t *pos = &ptr[0];

    do {
        size_t rb = _z_read_serial(sock, ptr, len - n);
        if (rb == SIZE_MAX) {
            n = rb;
            break;
        }

        n += rb;
        pos = _z_ptr_u8_offset(pos, rb);
    } while (n != len);

    return n;
}
#endif  // Z_FEATURE_LINK_SERIAL == 1
