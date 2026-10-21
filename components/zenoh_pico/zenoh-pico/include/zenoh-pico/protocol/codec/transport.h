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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_TRANSPORT_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_TRANSPORT_H

#include "zenoh-pico/protocol/definitions/transport.h"
#include "zenoh-pico/protocol/iobuf.h"

#ifdef __cplusplus
extern "C" {
#endif

z_result_t _z_scouting_message_encode(_z_wbuf_t *buf, const _z_scouting_message_t *msg);
z_result_t _z_scouting_message_decode(_z_scouting_message_t *msg, _z_zbuf_t *buf);

z_result_t _z_transport_message_encode(_z_wbuf_t *buf, const _z_transport_message_t *msg);
z_result_t _z_transport_message_decode(_z_transport_message_t *msg, _z_zbuf_t *buf);

z_result_t _z_join_encode(_z_wbuf_t *wbf, uint8_t header, const _z_t_msg_join_t *msg);
z_result_t _z_join_decode(_z_t_msg_join_t *msg, _z_zbuf_t *zbf, uint8_t header);

z_result_t _z_init_encode(_z_wbuf_t *wbf, uint8_t header, const _z_t_msg_init_t *msg);
z_result_t _z_init_decode(_z_t_msg_init_t *msg, _z_zbuf_t *zbf, uint8_t header);

z_result_t _z_open_encode(_z_wbuf_t *wbf, uint8_t header, const _z_t_msg_open_t *msg);
z_result_t _z_open_decode(_z_t_msg_open_t *msg, _z_zbuf_t *zbf, uint8_t header);

z_result_t _z_close_encode(_z_wbuf_t *wbf, uint8_t header, const _z_t_msg_close_t *msg);
z_result_t _z_close_decode(_z_t_msg_close_t *msg, _z_zbuf_t *zbf, uint8_t header);

z_result_t _z_keep_alive_encode(_z_wbuf_t *wbf, uint8_t header, const _z_t_msg_keep_alive_t *msg);
z_result_t _z_keep_alive_decode(_z_t_msg_keep_alive_t *msg, _z_zbuf_t *zbf, uint8_t header);

z_result_t _z_frame_encode(_z_wbuf_t *wbf, uint8_t header, const _z_t_msg_frame_t *msg);
z_result_t _z_frame_decode(_z_t_msg_frame_t *msg, _z_zbuf_t *zbf, uint8_t header);

z_result_t _z_fragment_encode(_z_wbuf_t *wbf, uint8_t header, const _z_t_msg_fragment_t *msg);
z_result_t _z_fragment_decode(_z_t_msg_fragment_t *msg, _z_zbuf_t *zbf, uint8_t header);

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_TRANSPORT_H */
