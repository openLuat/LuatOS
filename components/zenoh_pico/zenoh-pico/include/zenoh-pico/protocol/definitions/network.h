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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_NETWORK_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_NETWORK_H

#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/declarations.h"
#include "zenoh-pico/protocol/definitions/interest.h"
#include "zenoh-pico/protocol/definitions/message.h"
#include "zenoh-pico/protocol/ext.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Network Messages */
#define _Z_MID_N_OAM 0x1f
#define _Z_MID_N_DECLARE 0x1e
#define _Z_MID_N_PUSH 0x1d
#define _Z_MID_N_REQUEST 0x1c
#define _Z_MID_N_RESPONSE 0x1b
#define _Z_MID_N_RESPONSE_FINAL 0x1a
#define _Z_MID_N_INTEREST 0x19

/*=============================*/
/*        Network flags        */
/*=============================*/
#define _Z_FLAG_N_Z 0x80  // 1 << 7

// DECLARE message flags:
// - I: Interest       If I==1 then the declare is in a response to an Interest with future==false
// - X: Reserved
// - Z: Extension      If Z==1 then Zenoh extensions are present
#define _Z_FLAG_N_DECLARE_I 0x20  // 1 << 5

// INTEREST message flags:
// - C: Current       If C==1 then interest concerns current declarations
// - F: Future        If F==1 then interest concerns future declarations
// - Z: Extension     If Z==1 then Zenoh extensions are present
#define _Z_FLAG_N_INTEREST_CURRENT 0x20  // 1 << 5
#define _Z_FLAG_N_INTEREST_FUTURE 0x40   // 1 << 6

// PUSH message flags:
//      N Named            if N==1 then the key expr has name/suffix
//      M Mapping          if M==1 then keyexpr mapping is the one declared by the sender, otherwise by the receiver
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_N_PUSH_N 0x20  // 1 << 5
#define _Z_FLAG_N_PUSH_M 0x40  // 1 << 6

// REQUEST message flags:
//      N Named            if N==1 then the key expr has name/suffix
//      M Mapping          if M==1 then keyexpr mapping is the one declared by the sender, otherwise by the receiver
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_N_REQUEST_N 0x20  // 1 << 5
#define _Z_FLAG_N_REQUEST_M 0x40  // 1 << 6

// RESPONSE message flags:
//      N Named            if N==1 then the key expr has name/suffix
//      M Mapping          if M==1 then keyexpr mapping is the one declared by the sender, otherwise by the receiver
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_N_RESPONSE_N 0x20  // 1 << 5
#define _Z_FLAG_N_RESPONSE_M 0x40  // 1 << 6

typedef _z_qos_t _z_n_qos_t;

#define _Z_N_QOS_IS_EXPRESS_FLAG (1 << 4)

static inline _z_qos_t _z_n_qos_create(bool express, z_congestion_control_t congestion_control, z_priority_t priority) {
    _z_n_qos_t ret;
    bool nodrop = congestion_control == Z_CONGESTION_CONTROL_DROP ? 0 : 1;
    ret._val = (uint8_t)((express << 4) | (nodrop << 3) | (uint8_t)priority);
    return ret;
}
static inline z_priority_t _z_n_qos_get_priority(_z_n_qos_t n_qos) {
    z_priority_t ret = (z_priority_t)(n_qos._val & 0x07);  // 0b0111
    return ret;
}
static inline z_congestion_control_t _z_n_qos_get_congestion_control(_z_n_qos_t n_qos) {
    z_congestion_control_t ret =
        (n_qos._val & 0x08) ? Z_CONGESTION_CONTROL_BLOCK : Z_CONGESTION_CONTROL_DROP;  // 0b1000
    return ret;
}
static inline bool _z_n_qos_get_express(_z_n_qos_t n_qos) {
    bool ret = (n_qos._val & 0x10) != 0;  // 0b10000
    return ret;
}
#define _z_n_qos_make(express, nodrop, priority)                                                    \
    _z_n_qos_create((bool)express, nodrop ? Z_CONGESTION_CONTROL_BLOCK : Z_CONGESTION_CONTROL_DROP, \
                    (z_priority_t)priority)

extern const _z_qos_t _Z_N_QOS_DEFAULT;

// RESPONSE FINAL message flags:
//      Z Extensions       if Z==1 then Zenoh extensions are present
// #define _Z_FLAG_N_RESPONSE_X 0x20  // 1 << 5
// #define _Z_FLAG_N_RESPONSE_X 0x40  // 1 << 6

// Flags:
// - N: Named          if N==1 then the keyexpr has name/suffix
// - M: Mapping        if M==1 then keyexpr mapping is the one declared by the sender, otherwise by the receiver
// - Z: Extension      if Z==1 then at least one extension is present
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|M|N| REQUEST |
// +-+-+-+---------+
// ~ request_id:z32~
// +---------------+
// ~ key_scope:z16 ~
// +---------------+
// ~  key_suffix   ~  if N==1 -- <u8;z16>
// +---------------+
// ~   [req_exts]  ~  if Z==1
// +---------------+
// ~ ZenohMessage  ~
// +---------------+
//
typedef struct {
    _z_zint_t _rid;
    _z_wireexpr_t _key;
    _z_timestamp_t _ext_timestamp;
    _z_n_qos_t _ext_qos;
    z_query_target_t _ext_target;
    uint32_t _ext_budget;
    uint64_t _ext_timeout_ms;
    enum {
        _Z_REQUEST_QUERY,
        _Z_REQUEST_PUT,
        _Z_REQUEST_DEL,
    } _tag;
    union {
        _z_msg_query_t _query;
        _z_msg_put_t _put;
        _z_msg_del_t _del;
    } _body;
} _z_n_msg_request_t;
typedef struct {
    bool ext_qos;
    bool ext_tstamp;
    bool ext_target;
    bool ext_budget;
    bool ext_timeout_ms;
    uint8_t n;
} _z_n_msg_request_exts_t;
_z_n_msg_request_exts_t _z_n_msg_request_needed_exts(const _z_n_msg_request_t *msg);
void _z_n_msg_request_clear(_z_n_msg_request_t *msg);

typedef _z_reply_body_t _z_push_body_t;
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_push_body_t _z_push_body_null(void) { return (_z_push_body_t){0}; }

_z_push_body_t _z_push_body_steal(_z_push_body_t *msg);
void _z_push_body_clear(_z_push_body_t *msg);

/*------------------ Response Final Message ------------------*/
// Flags:
// - Z: Extension      if Z==1 then at least one extension is present
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|M|N| ResFinal|
// +-+-+-+---------+
// ~ request_id:z32~
// +---------------+
// ~  [reply_exts] ~  if Z==1
// +---------------+
//
typedef struct {
    _z_zint_t _request_id;
} _z_n_msg_response_final_t;
void _z_n_msg_response_final_clear(_z_n_msg_response_final_t *msg);

// Flags:
// - N: Named          if N==1 then the keyexpr has name/suffix
// - M: Mapping        if M==1 then keyexpr mapping is the one declared by the sender, otherwise by the receiver
// - Z: Extension      if Z==1 then at least one extension is present
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|M|N|  PUSH   |
// +-+-+-+---------+
// ~ key_scope:z?  ~
// +---------------+
// ~  key_suffix   ~  if N==1 -- <u8;z16>
// +---------------+
// ~  [push_exts]  ~  if Z==1
// +---------------+
// ~ ZenohMessage  ~
// +---------------+
//
typedef struct {
    _z_wireexpr_t _key;
    _z_timestamp_t _timestamp;
    _z_n_qos_t _qos;
    _z_push_body_t _body;
} _z_n_msg_push_t;
void _z_n_msg_push_clear(_z_n_msg_push_t *msg);

/*------------------ Response Message ------------------*/
typedef struct {
    _z_timestamp_t _ext_timestamp;
    _z_zint_t _request_id;
    _z_wireexpr_t _key;
    _z_n_qos_t _ext_qos;
    struct {
        _z_id_t _zid;
        uint32_t _eid;
    } _ext_responder;
    enum {
        _Z_RESPONSE_BODY_REPLY,
        _Z_RESPONSE_BODY_ERR,
    } _tag;
    union {
        _z_msg_reply_t _reply;
        _z_msg_err_t _err;
    } _body;
} _z_n_msg_response_t;
void _z_n_msg_response_clear(_z_n_msg_response_t *msg);

/*------------------ Declare Message ------------------*/
typedef struct {
    uint32_t value;
    bool has_value;
} _z_optional_id_t;
static inline _z_optional_id_t _z_optional_id_make_some(uint32_t value) {
    _z_optional_id_t id;
    id.value = value;
    id.has_value = true;
    return id;
}
static inline _z_optional_id_t _z_optional_id_make_none(void) {
    _z_optional_id_t id = {0};
    return id;
}

typedef struct {
    _z_declaration_t _decl;
    _z_timestamp_t _ext_timestamp;
    _z_n_qos_t _ext_qos;
    _z_optional_id_t _interest_id;
} _z_n_msg_declare_t;
static inline void _z_n_msg_declare_clear(_z_n_msg_declare_t *msg) { _z_declaration_clear(&msg->_decl); }

/*------------------ Interest Message ------------------*/

/// Flags:
/// - C: Current       If C==1 then interest concerns current declarations
/// - F: Future        If F==1 then interest concerns future declarations
/// - Z: Extension     If Z==1 then Zenoh extensions are present
/// If C==0 and F==0, then interest is final
///
/// 7 6 5 4 3 2 1 0
/// +-+-+-+-+-+-+-+-+
/// |Z|F|C|INTEREST |
/// +-+-+-+---------+
/// ~    id:z32     ~
/// +---------------+
/// |A|M|N|R|T|Q|S|K|  (*) if interest is not final
/// +---------------+
/// ~ key_scope:z16 ~  if interest is not final && R==1
/// +---------------+
/// ~  key_suffix   ~  if interest is not final && R==1 && N==1 -- <u8;z16>
/// +---------------+
/// ~  [int_exts]   ~  if Z==1
/// +---------------+
///
/// (*) - if K==1 then the interest refers to key expressions
///     - if S==1 then the interest refers to subscribers
///     - if Q==1 then the interest refers to queryables
///     - if T==1 then the interest refers to tokens
///     - if R==1 then the interest is restricted to the matching key expression, else it is for all key expressions.
///     - if N==1 then the key expr has name/suffix. If R==0 then N should be set to 0.
///     - if M==1 then key expr mapping is the one declared by the sender, else it is the one declared by the receiver.
///               If R==0 then M should be set to 0.
///     - if A==1 then the replies SHOULD be aggregated
/// ```

typedef struct {
    _z_interest_t _interest;
} _z_n_msg_interest_t;
static inline void _z_n_msg_interest_clear(_z_n_msg_interest_t *msg) { _z_interest_clear(&msg->_interest); }

/*------------------ OAM Message ------------------*/

/// Flags:
/// - E |: Encoding     The encoding of the extension
/// - E/
/// - Z: Extension      If Z==1 then at least one extension is present
///
///  7 6 5 4 3 2 1 0
/// +-+-+-+-+-+-+-+-+
/// |Z|ENC|  OAM    |
/// +-+-+-+---------+
/// ~    id:z16     ~
/// +---------------+
/// ~  [oam_exts]   ~  if Z==1
/// +---------------+
/// %    length     %  If ENC == Z64 || ENC == ZBuf (z32)
/// +---------------+
/// ~     [u8]      ~  If ENC == ZBuf
/// +---------------+
///
/// Encoding:
/// - 0b00: Unit
/// - 0b01: Z64
/// - 0b10: ZBuf
/// - 0b11: Reserved
typedef struct {
    uint16_t _id;
    _z_timestamp_t _ext_timestamp;
    _z_n_qos_t _ext_qos;
    enum { _Z_OAM_BODY_UNIT, _Z_OAM_BODY_ZINT, _Z_OAM_BODY_ZBUF } _enc;
    _z_msg_ext_body_t _body;
} _z_n_msg_oam_t;
void _z_n_msg_oam_clear(_z_n_msg_oam_t *msg);

/*------------------ Zenoh Message ------------------*/
typedef union {
    _z_n_msg_declare_t _declare;
    _z_n_msg_push_t _push;
    _z_n_msg_request_t _request;
    _z_n_msg_response_t _response;
    _z_n_msg_response_final_t _response_final;
    _z_n_msg_interest_t _interest;
    _z_n_msg_oam_t _oam;
} _z_network_body_t;
typedef struct {
    enum { _Z_N_DECLARE, _Z_N_PUSH, _Z_N_REQUEST, _Z_N_RESPONSE, _Z_N_RESPONSE_FINAL, _Z_N_INTEREST, _Z_N_OAM } _tag;
    _z_network_body_t _body;
    z_reliability_t _reliability;
} _z_network_message_t;
typedef _z_network_message_t _z_zenoh_message_t;
void _z_n_msg_clear(_z_network_message_t *m);
void _z_n_msg_free(_z_network_message_t **m);
inline static void _z_msg_clear(_z_zenoh_message_t *msg) { _z_n_msg_clear(msg); }
inline static void _z_msg_free(_z_zenoh_message_t **msg) { _z_n_msg_free(msg); }
z_result_t _z_n_msg_copy(_z_network_message_t *dst, const _z_network_message_t *src);
_z_network_message_t *_z_n_msg_clone(const _z_network_message_t *src);

_Z_ELEM_DEFINE(_z_network_message, _z_network_message_t, _z_noop_size, _z_n_msg_clear, _z_n_msg_copy, _z_noop_move,
               _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_SVEC_DEFINE(_z_network_message, _z_network_message_t)
_Z_SLIST_DEFINE(_z_network_message, _z_network_message_t, true)

void _z_n_msg_make_response_final(_z_network_message_t *msg, _z_zint_t rid);
void _z_n_msg_make_declare(_z_network_message_t *msg, _z_declaration_t declaration, _z_optional_id_t interest_id);
void _z_n_msg_make_query(_z_zenoh_message_t *msg, const _z_wireexpr_t *key, const _z_slice_t *parameters, _z_zint_t qid,
                         z_reliability_t reliability, z_consolidation_mode_t consolidation, const _z_bytes_t *payload,
                         const _z_encoding_t *encoding, uint64_t timeout_ms, const _z_bytes_t *attachment,
                         _z_n_qos_t qos, const _z_source_info_t *source_info, bool implicit_anyke);
void _z_n_msg_make_push_put(_z_network_message_t *dst, const _z_wireexpr_t *key, const _z_bytes_t *payload,
                            const _z_encoding_t *encoding, _z_n_qos_t qos, const _z_timestamp_t *timestamp,
                            const _z_bytes_t *attachment, z_reliability_t reliability,
                            const _z_source_info_t *source_info);
void _z_n_msg_make_push_del(_z_network_message_t *dst, const _z_wireexpr_t *key, _z_n_qos_t qos,
                            const _z_timestamp_t *timestamp, z_reliability_t reliability,
                            const _z_source_info_t *source_info);
void _z_n_msg_make_reply_ok_put(_z_network_message_t *dst, const _z_id_t *zid, _z_zint_t rid, const _z_wireexpr_t *key,
                                z_reliability_t reliability, z_consolidation_mode_t consolidation, _z_n_qos_t qos,
                                const _z_timestamp_t *timestamp, const _z_source_info_t *source_info,
                                const _z_bytes_t *payload, const _z_encoding_t *encoding, const _z_bytes_t *attachment);
void _z_n_msg_make_reply_ok_del(_z_network_message_t *dst, const _z_id_t *zid, _z_zint_t rid, const _z_wireexpr_t *key,
                                z_reliability_t reliability, z_consolidation_mode_t consolidation, _z_n_qos_t qos,
                                const _z_timestamp_t *timestamp, const _z_source_info_t *source_info,
                                const _z_bytes_t *attachment);
void _z_n_msg_make_reply_err(_z_network_message_t *dst, const _z_id_t *zid, _z_zint_t rid, z_reliability_t reliability,
                             _z_n_qos_t qos, const _z_bytes_t *payload, const _z_encoding_t *encoding,
                             const _z_source_info_t *source_info);
void _z_n_msg_make_interest(_z_network_message_t *msg, _z_interest_t interest);

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_NETWORK_H */
