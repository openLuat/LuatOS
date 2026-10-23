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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_MESSAGE_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_MESSAGE_H

#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/protocol/iobuf.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_push_body_encode(_z_wbuf_t *wbf, const _z_push_body_t *pshb);
z_result_t _z_push_body_decode(_z_push_body_t *body, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs);

z_result_t _z_query_encode(_z_wbuf_t *wbf, const _z_msg_query_t *query);
z_result_t _z_query_decode(_z_msg_query_t *query, _z_zbuf_t *zbf, uint8_t header);
z_result_t _z_reply_encode(_z_wbuf_t *wbf, const _z_msg_reply_t *reply);
z_result_t _z_reply_decode(_z_msg_reply_t *reply, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs);

z_result_t _z_err_encode(_z_wbuf_t *wbf, const _z_msg_err_t *err);
z_result_t _z_err_decode(_z_msg_err_t *err, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs);

z_result_t _z_put_encode(_z_wbuf_t *wbf, const _z_msg_put_t *put);
z_result_t _z_put_decode(_z_msg_put_t *put, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs);

z_result_t _z_del_encode(_z_wbuf_t *wbf, const _z_msg_del_t *del);
z_result_t _z_del_decode(_z_msg_del_t *del, _z_zbuf_t *zbf, uint8_t header);

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_MESSAGE_H */
