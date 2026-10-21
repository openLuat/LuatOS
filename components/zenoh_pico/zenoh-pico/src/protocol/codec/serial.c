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

#include <inttypes.h>
#include <stdint.h>
#include <string.h>

#include "zenoh-pico/utils/checksum.h"
#include "zenoh-pico/utils/encoding.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"

#define KIND_FIELD_LEN 1u
#define LEN_FIELD_LEN 2u
#define CRC32_LEN 4u

size_t _z_serial_msg_serialize(uint8_t *dest, size_t dest_len, const uint8_t *src, size_t src_len, uint8_t header,
                               uint8_t *tmp_buf, size_t tmp_buf_len) {
    size_t expected_size = src_len + KIND_FIELD_LEN + LEN_FIELD_LEN + CRC32_LEN;
    if (tmp_buf_len < expected_size) {
        _Z_DEBUG("tmp buffer too small: %zu < %zu", tmp_buf_len, expected_size);
        return SIZE_MAX;
    }

    uint32_t crc32 = _z_crc32(src, src_len);
    uint8_t crc_bytes[CRC32_LEN] = {(uint8_t)(crc32 & 0xFF), (uint8_t)((crc32 >> 8) & 0xFF),
                                    (uint8_t)((crc32 >> 16) & 0xFF), (uint8_t)((crc32 >> 24) & 0xFF)};

    uint16_t wire_size = (uint16_t)src_len;
    uint8_t size_bytes[LEN_FIELD_LEN] = {(uint8_t)(wire_size & 0xFF), (uint8_t)((wire_size >> 8) & 0xFF)};

    uint8_t *tmp_buf_ptr = tmp_buf;

    tmp_buf_ptr[0] = header;
    tmp_buf_ptr += sizeof(header);

    memcpy(tmp_buf_ptr, size_bytes, sizeof(size_bytes));
    tmp_buf_ptr += sizeof(size_bytes);

    memcpy(tmp_buf_ptr, src, src_len);
    tmp_buf_ptr += src_len;

    memcpy(tmp_buf_ptr, crc_bytes, sizeof(crc_bytes));
    tmp_buf_ptr += sizeof(crc_bytes);

    size_t total_len = _z_ptr_u8_diff(tmp_buf_ptr, tmp_buf);

    size_t ret = _z_cobs_encode(tmp_buf, total_len, dest);
    if (ret + 1 > dest_len) {
        _Z_DEBUG("destination buffer too small");
        return SIZE_MAX;
    }

    dest[ret] = 0x00;

    return ret + 1u;
}

size_t _z_serial_msg_deserialize(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len, uint8_t *header,
                                 uint8_t *tmp_buf, size_t tmp_buf_len) {
    if (tmp_buf_len < src_len) {
        _Z_DEBUG("tmp_buf too small");
        return SIZE_MAX;
    }

    size_t decoded_size = _z_cobs_decode(src, src_len, tmp_buf);

    if (decoded_size < KIND_FIELD_LEN + LEN_FIELD_LEN + CRC32_LEN) {
        _Z_DEBUG("decoded frame too small");
        return SIZE_MAX;
    }

    uint8_t *tmp_buf_ptr = tmp_buf;

    *header = tmp_buf_ptr[0];
    tmp_buf_ptr += sizeof(uint8_t);

    uint16_t wire_size = (uint16_t)(tmp_buf_ptr[0] | (tmp_buf_ptr[1] << 8));
    tmp_buf_ptr += sizeof(uint16_t);

    size_t expected_size = wire_size + KIND_FIELD_LEN + LEN_FIELD_LEN + CRC32_LEN;
    if (expected_size != decoded_size) {
        _Z_DEBUG("wire size mismatch: %zu != %zu", expected_size, decoded_size);
        return SIZE_MAX;
    }

    if (dst_len < wire_size) {
        _Z_DEBUG("destination buffer too small: %zu < %u", dst_len, wire_size);
        return SIZE_MAX;
    }

    if (wire_size != 0) {
        memcpy(dst, tmp_buf_ptr, wire_size);
        tmp_buf_ptr += wire_size;
    }

    uint32_t received_crc =
        (uint32_t)(tmp_buf_ptr[0] | (tmp_buf_ptr[1] << 8) | (tmp_buf_ptr[2] << 16) | (tmp_buf_ptr[3] << 24));

    uint32_t computed_crc = _z_crc32(dst, wire_size);
    if (received_crc != computed_crc) {
        _Z_DEBUG("CRC mismatch. Received: 0x%08" PRIu32 ", Computed: 0x%08" PRIu32, received_crc, computed_crc);
        return SIZE_MAX;
    }

    return wire_size;
}
