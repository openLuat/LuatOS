/* SPDX-License-Identifier: MIT */
/* AI-MANAGED: true */
/* 调用真实SDK分片序列化/解码，核首、续、末片可靠性和全部二进制。 */
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/protocol/codec/transport.h"
#include <stdio.h>
#include <string.h>

static int check_fragments(z_reliability_t reliability) {
    uint8_t data[8192];
    for (size_t i = 0; i < sizeof(data); ++i) data[i] = (uint8_t)i;
    _z_wbuf_t src = _z_wbuf_make(sizeof(data), false);
    _z_wbuf_t dst = _z_wbuf_make(2048, false);
    size_t offset = 0, fragments = 0;
    int failed = 0;
    for (size_t i = 0; i < sizeof(data); ++i) {
        if (_z_wbuf_write(&src, data[i]) != _Z_RES_OK) { failed = 1; break; }
    }
    while (!failed && _z_wbuf_len(&src)) {
        _z_wbuf_reset(&dst);
        if (__unsafe_z_serialize_zenoh_fragment(&dst, &src, reliability, fragments + 1,
                                               fragments == 0) != _Z_RES_OK) {
            failed = 1; break;
        }
        _z_zbuf_t wire = _z_wbuf_to_zbuf(&dst);
        _z_transport_message_t msg = {0};
        if (_z_transport_message_decode(&msg, &wire) != _Z_RES_OK) failed = 1;
        else {
            _z_t_msg_fragment_t *f = &msg._body._fragment;
            if ((msg._header & 0x1f) != _Z_MID_T_FRAGMENT ||
                _z_t_msg_get_reliability(&msg) != reliability ||
                f->first != (fragments == 0) || f->drop || f->_sn != fragments + 1 ||
                ((msg._header & _Z_FLAG_T_FRAGMENT_M) != 0) != (_z_wbuf_len(&src) != 0) ||
                !f->_payload.len || f->_payload.len > sizeof(data) - offset ||
                memcmp(f->_payload.start, data + offset, f->_payload.len)) failed = 1;
            else offset += f->_payload.len;
        }
        _z_t_msg_clear(&msg); _z_zbuf_clear(&wire); ++fragments;
    }
    _z_wbuf_clear(&src); _z_wbuf_clear(&dst);
    if (offset != sizeof(data) || fragments < 3) failed = 1;
    printf("FRAGMENT_%s reliability=%d fragments=%zu bytes=%zu\n",
           failed ? "FAIL" : "PASS", reliability, fragments, offset);
    return failed;
}
int main(void) {
    int reliable = check_fragments(Z_RELIABILITY_RELIABLE);
    int best_effort = check_fragments(Z_RELIABILITY_BEST_EFFORT);
    return reliable || best_effort;
}
