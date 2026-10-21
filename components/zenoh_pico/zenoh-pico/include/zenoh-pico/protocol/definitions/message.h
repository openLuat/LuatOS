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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_MESSAGE_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_MESSAGE_H

#include "zenoh-pico/net/encoding.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Zenoh Messages */
#define _Z_MID_Z_OAM 0x00
#define _Z_MID_Z_PUT 0x01
#define _Z_MID_Z_DEL 0x02
#define _Z_MID_Z_QUERY 0x03
#define _Z_MID_Z_REPLY 0x04
#define _Z_MID_Z_ERR 0x05

/* Zenoh message flags */
#define _Z_FLAG_Z_Z 0x80
#define _Z_FLAG_Z_D 0x20  // 1 << 5 | Dropping          if D==1 then the message can be dropped
#define _Z_FLAG_Z_K 0x80  // 1 << 7 | ResourceKey       if K==1 then keyexpr is string
#define _Z_FLAG_Z_R \
    0x20  // 1 << 5 | Reliable          if R==1 then it concerns the reliable channel, best-effort otherwise
#define _Z_FLAG_Z_X 0x00  // Unused flags are set to zero

#define _Z_FRAG_BUFF_BASE_SIZE 128  // Arbitrary base size of the buffer to encode a fragment message header

// Flags:
// - X: Reserved
// - E: Encoding       If E==1 then the encoding is present
// - Z: Extension      If Z==1 then at least one extension is present
//
//   7 6 5 4 3 2 1 0
//  +-+-+-+-+-+-+-+-+
//  |Z|E|X|   ERR   |
//  +-+-+-+---------+
//  %   encoding    %
//  +---------------+
//  ~  [err_exts]   ~  if Z==1
//  +---------------+
///  ~ pl: <u8;z32>  ~ Payload
///  +---------------+
#define _Z_FLAG_Z_E_E 0x40
typedef struct {
    _z_encoding_t _encoding;
    _z_source_info_t _ext_source_info;
    _z_bytes_t _payload;
} _z_msg_err_t;
void _z_msg_err_clear(_z_msg_err_t *err);

typedef struct {
    _z_timestamp_t _timestamp;
    _z_source_info_t _source_info;
} _z_m_push_commons_t;

typedef struct {
    _z_m_push_commons_t _commons;
    _z_bytes_t _attachment;
} _z_msg_del_t;
static inline void _z_msg_del_clear(_z_msg_del_t *del) { (void)del; }
#define _Z_M_DEL_ID 0x02
#define _Z_FLAG_Z_D_T 0x20

typedef struct {
    _z_m_push_commons_t _commons;
    _z_bytes_t _payload;
    _z_encoding_t _encoding;
    _z_bytes_t _attachment;
} _z_msg_put_t;
void _z_msg_put_clear(_z_msg_put_t *);
#define _Z_M_PUT_ID 0x01
#define _Z_FLAG_Z_P_E 0x40
#define _Z_FLAG_Z_P_T 0x20

/*------------------ Query Message ------------------*/
//   7 6 5 4 3 2 1 0
//  +-+-+-+-+-+-+-+-+
//  |Z|P|C|  QUERY  |
//  +-+-+-+---------+
//  ~ consolidation ~  if C==1 -- u8
//  +---------------+
//  ~ params        ~  if P==1 -- <utf8;z16>
//  +---------------+
//  ~ [qry_exts]    ~  if Z==1
//  +---------------+
#define _Z_FLAG_Z_Q_C 0x20  // 1 << 5 | Consolidation if C==1 then consolidation is present
#define _Z_FLAG_Z_Q_P 0x40  // 1 << 6 | Params        if P==1 then parameters are present
typedef struct {
    _z_slice_t _parameters;
    _z_source_info_t _ext_info;
    _z_value_t _ext_value;
    z_consolidation_mode_t _consolidation;
    _z_bytes_t _ext_attachment;
    bool _implicit_anyke;  // implicit _anyke parameter (i.e it is not listed in _parameters, but is still present)
} _z_msg_query_t;
typedef struct {
    bool info;
    bool body;
    bool attachment;
} _z_msg_query_reqexts_t;
_z_msg_query_reqexts_t _z_msg_query_required_extensions(const _z_msg_query_t *msg);
void _z_msg_query_clear(_z_msg_query_t *msg);

typedef struct {
    bool _is_put;
    union {
        _z_msg_del_t _del;
        _z_msg_put_t _put;
    } _body;
} _z_reply_body_t;
// Flags:
// - C: Consolidation  If C==1 then consolidation is present
// - X: Reserved
// - Z: Extension      If Z==1 then at least one extension is present
//
//   7 6 5 4 3 2 1 0
//  +-+-+-+-+-+-+-+-+
//  |Z|X|C|  REPLY  |
//  +-+-+-+---------+
//  ~ consolidation ~  if C==1
//  +---------------+
//  ~  [repl_exts]  ~  if Z==1
//  +---------------+
//  ~  ReplyBody    ~  -- Payload
//  +---------------+
typedef struct {
    z_consolidation_mode_t _consolidation;
    _z_reply_body_t _body;
} _z_msg_reply_t;
void _z_msg_reply_clear(_z_msg_reply_t *msg);
#define _Z_FLAG_Z_R_C 0x20

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_MESSAGE_H */
