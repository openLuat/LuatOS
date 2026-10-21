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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_TRANSPORT_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_TRANSPORT_H

/* Scouting Messages */
#include <stdint.h>

#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/protocol/definitions/network.h"

#ifdef __cplusplus
extern "C" {
#endif

#define _Z_MID_SCOUT 0x01
#define _Z_MID_HELLO 0x02

/* Transport Messages */
#define _Z_MID_T_OAM 0x00
#define _Z_MID_T_INIT 0x01
#define _Z_MID_T_OPEN 0x02
#define _Z_MID_T_CLOSE 0x03
#define _Z_MID_T_KEEP_ALIVE 0x04
#define _Z_MID_T_FRAME 0x05
#define _Z_MID_T_FRAGMENT 0x06
#define _Z_MID_T_JOIN 0x07

/*=============================*/
/*        Message flags        */
/*=============================*/
#define _Z_FLAG_T_Z 0x80  // 1 << 7

// Scout message flags:
//      I ZenohID          if I==1 then the ZenohID is present
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_SCOUT_I 0x08  // 1 << 3

// Hello message flags:
//      L Locators         if L==1 then Locators are present
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_HELLO_L 0x20  // 1 << 5

// Join message flags:
//      T Lease period     if T==1 then the lease period is in seconds else in milliseconds
//      S Size params      if S==1 then size parameters are exchanged
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_JOIN_T 0x20  // 1 << 5
#define _Z_FLAG_T_JOIN_S 0x40  // 1 << 6

// Init message flags:
//      A Ack              if A==1 then the message is an acknowledgment (aka InitAck), otherwise InitSyn
//      S Size params      if S==1 then size parameters are exchanged
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_INIT_A 0x20  // 1 << 5
#define _Z_FLAG_T_INIT_S 0x40  // 1 << 6

// Open message flags:
//      A Ack              if A==1 then the message is an acknowledgment (aka OpenAck), otherwise OpenSyn
//      T Lease period     if T==1 then the lease period is in seconds else in milliseconds
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_OPEN_A 0x20  // 1 << 5
#define _Z_FLAG_T_OPEN_T 0x40  // 1 << 6

// Frame message flags:
//      R Reliable         if R==1 it concerns the reliable channel, else the best-effort channel
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_FRAME_R 0x20  // 1 << 5

// Frame message flags:
//      R Reliable         if R==1 it concerns the reliable channel, else the best-effort channel
//      M More             if M==1 then other fragments will follow
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_FRAGMENT_R 0x20  // 1 << 5
#define _Z_FLAG_T_FRAGMENT_M 0x40  // 1 << 6

// Close message flags:
//      S Session Close    if S==1 Session close or S==0 Link close
//      Z Extensions       if Z==1 then Zenoh extensions are present
#define _Z_FLAG_T_CLOSE_S 0x20  // 1 << 5

/*=============================*/
/*            Patch            */
/*=============================*/
/// Used to negotiate the patch version of the protocol
/// if not present (or 0), then protocol as released with 1.0.0
/// if >= 1, then fragmentation start/stop marker
#define _Z_NO_PATCH 0x00
#define _Z_CURRENT_PATCH 0x01
#define _Z_PATCH_HAS_FRAGMENT_MARKERS(patch) (patch >= 1)

/*=============================*/
/*     Transport Messages      */
/*=============================*/
/*------------------ Scout Message ------------------*/
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// The SCOUT message can be sent at any point in time to solicit HELLO messages from matching parties.
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|X|X|  SCOUT  |
// +-+-+-+---------+
// |    version    |
// +---------------+
// |zid_len|I| what| (#)(*)
// +-+-+-+-+-+-+-+-+
// ~      [u8]     ~ if Flag(I)==1 -- ZenohID
// +---------------+
//
// (#) ZID length. If Flag(I)==1 it indicates how many bytes are used for the ZenohID bytes.
//     A ZenohID is minimum 1 byte and maximum 16 bytes. Therefore, the actual length is computed as:
//         real_zid_len := 1 + zid_len
//
// (*) What. It indicates a bitmap of WhatAmI interests.
//    The valid bitflags are:
//    - 0b001: Router
//    - 0b010: Peer
//    - 0b100: Client
//
typedef struct {
    _z_id_t _zid;
    z_what_t _what;
    uint8_t _version;
} _z_s_msg_scout_t;
void _z_s_msg_scout_clear(_z_s_msg_scout_t *msg);

/*------------------ Hello Message ------------------*/
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// The HELLO message is sent in any of the following three cases:
//     1) in response to a SCOUT message;
//     2) to (periodically) advertise (e.g., on multicast) the Peer and the locators it is reachable at;
//     3) in a already established session to update the corresponding peer on the new capabilities
//        (i.e., whatami) and/or new set of locators (i.e., added or deleted).
// Locators are expressed as:
// <code>
//  udp/192.168.0.2:1234
//  tcp/192.168.0.2:1234
//  udp/239.255.255.123:5555
// <code>
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|X|L|  HELLO  |
// +-+-+-+---------+
// |    version    |
// +---------------+
// |zid_len|X|X|wai| (*)
// +-+-+-+-+-+-+-+-+
// ~     [u8]      ~ -- ZenohID
// +---------------+
// ~   <utf8;z8>   ~ if Flag(L)==1 -- List of locators
// +---------------+
//
// (*) WhatAmI. It indicates the role of the zenoh node sending the HELLO message.
//    The valid WhatAmI values are:
//    - 0b00: Router
//    - 0b01: Peer
//    - 0b10: Client
//    - 0b11: Reserved
//
typedef struct {
    _z_id_t _zid;
    _z_locator_array_t _locators;
    z_whatami_t _whatami;
    uint8_t _version;
} _z_s_msg_hello_t;
void _z_s_msg_hello_clear(_z_s_msg_hello_t *msg);

/*------------------ Join Message ------------------*/
// # Join message
//
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// The JOIN message is sent on a multicast Locator to advertise the transport parameters.
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |O|S|T|   JOIN  |
// +-+-+-+-+-------+
// ~             |Q~ if O==1
// +---------------+
// | v_maj | v_min | -- Protocol Version VMaj.VMin
// +-------+-------+
// ~    whatami    ~ -- Router, Peer or a combination of them
// +---------------+
// ~   zenoh_id    ~ -- PID of the sender of the JOIN message
// +---------------+
// ~     lease     ~ -- Lease period of the sender of the JOIN message(*)
// +---------------+
// ~ seq_num_res ~ if S==1(*) -- Otherwise 2^28 is assumed(**)
// +---------------+
// ~   [next_sn]   ~ (***)
// +---------------+
//
// - if Q==1 then the sender supports QoS.
//
// (*)   if T==1 then the lease period is expressed in seconds, otherwise in milliseconds
// (**)  if S==0 then 2^28 is assumed.
// (***) if Q==1 then 8 sequence numbers are present: one for each priority.
//       if Q==0 then only one sequence number is present.
//
typedef struct {
    _z_zint_t _reliable;
    _z_zint_t _best_effort;
} _z_coundit_sn_t;
typedef struct {
    union {
        _z_coundit_sn_t _plain;
        _z_coundit_sn_t _qos[Z_PRIORITIES_NUM];
    } _val;
    bool _is_qos;
} _z_conduit_sn_list_t;
typedef struct {
    _z_id_t _zid;
    _z_zint_t _lease;
    _z_conduit_sn_list_t _next_sn;
    uint16_t _batch_size;
    z_whatami_t _whatami;
    uint8_t _req_id_res;
    uint8_t _seq_num_res;
    uint8_t _version;
#if Z_FEATURE_FRAGMENTATION == 1
    uint8_t _patch;
#endif
} _z_t_msg_join_t;
void _z_t_msg_join_clear(_z_t_msg_join_t *msg);

/*------------------ Init Message ------------------*/
// # Init message
//
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// The INIT message is sent on a specific Locator to initiate a session with the peer associated
// with that Locator. The initiator MUST send an INIT message with the A flag set to 0.  If the
// corresponding peer deems appropriate to initialize a session with the initiator, the corresponding
// peer MUST reply with an INIT message with the A flag set to 1.
//
// Flags:
// - A: Ack          if A==0 then the message is an InitSyn else it is an InitAck
// - S: Size params  if S==1 then size parameters are exchanged
// - Z: Extensions   if Z==1 then zenoh extensions will follow.
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|S|A|   INIT  |
// +-+-+-+---------+
// |    version    |
// +---------------+
// |zid_len|x|x|wai| (#)(*)
// +-------+-+-+---+
// ~      [u8]     ~ -- ZenohID of the sender of the INIT message
// +---------------+
// |x|x|kid|rid|fsn| \                -- SN/ID resolution (+)
// +---------------+  | if Flag(S)==1
// |      u16      |  |               -- Batch Size ($)
// |               | /
// +---------------+
// ~    <u8;z16>   ~ -- if Flag(A)==1 -- Cookie
// +---------------+
// ~   [InitExts]  ~ -- if Flag(Z)==1
// +---------------+
//
// If A==1 and S==0 then size parameters are (ie. S flag) are accepted.
//
// (*) WhatAmI. It indicates the role of the zenoh node sending the INIT
// message.
//    The valid WhatAmI values are:
//    - 0b00: Router
//    - 0b01: Peer
//    - 0b10: Client
//    - 0b11: Reserved
//
// (#) ZID length. It indicates how many bytes are used for the ZenohID bytes.
//     A ZenohID is minimum 1 byte and maximum 16 bytes. Therefore, the actual
//     length is computed as:
//         real_zid_len := 1 + zid_len
//
// (+) Sequence Number/ID resolution. It indicates the resolution and
// consequently the wire overhead
//     of various SN and ID in Zenoh.
//     - fsn: frame/fragment sequence number resolution. Used in Frame/Fragment
//     messages.
//     - rid: request ID resolution. Used in Request/Response messages.
//     - kid: key expression ID resolution. Used in Push/Request/Response
//     messages. The valid SN/ID resolution values are:
//     - 0b00: 8 bits
//     - 0b01: 16 bits
//     - 0b10: 32 bits
//     - 0b11: 64 bits
//
// ($) Batch Size. It indicates the maximum size of a batch the sender of the
//
typedef struct {
    _z_id_t _zid;
    _z_slice_t _cookie;
    uint16_t _batch_size;
    z_whatami_t _whatami;
    uint8_t _req_id_res;
    uint8_t _seq_num_res;
    uint8_t _version;
#if Z_FEATURE_FRAGMENTATION == 1
    uint8_t _patch;
#endif
} _z_t_msg_init_t;
void _z_t_msg_init_clear(_z_t_msg_init_t *msg);

/*------------------ Open Message ------------------*/
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// The OPEN message is sent on a link to finally open an initialized session with the peer.
//
// Flags:
// - A Ack           if A==1 then the message is an acknowledgment (aka OpenAck), otherwise OpenSyn
// - T Lease period  if T==1 then the lease period is in seconds else in milliseconds
// - Z Extensions    if Z==1 then Zenoh extensions are present
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|T|A|   OPEN  |
// +-+-+-+---------+
// %     lease     % -- Lease period of the sender of the OPEN message
// +---------------+
// %  initial_sn   % -- Initial SN proposed by the sender of the OPEN(*)
// +---------------+
// ~    <u8;z16>   ~ if Flag(A)==0 (**) -- Cookie
// +---------------+
// ~   [OpenExts]  ~ if Flag(Z)==1
// +---------------+
//
// (*)     The initial sequence number MUST be compatible with the sequence number resolution agreed in the
//         [`super::InitSyn`]-[`super::InitAck`] message exchange
// (**)    The cookie MUST be the same received in the [`super::InitAck`]from the corresponding zenoh node
//
typedef struct {
    _z_zint_t _lease;
    _z_zint_t _initial_sn;
    _z_slice_t _cookie;
} _z_t_msg_open_t;
void _z_t_msg_open_clear(_z_t_msg_open_t *msg);

/*------------------ Close Message ------------------*/
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// The CLOSE message is sent in any of the following two cases:
//     1) in response to an OPEN message which is not accepted;
//     2) at any time to arbitrarily close the session with the corresponding peer.
//
// Flags:
// - S: Session Close  if S==1 Session close or S==0 Link close
// - X: Reserved
// - Z: Extensions     if Z==1 then zenoh extensions will follow.
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|X|S|  CLOSE  |
// +-+-+-+---------+
// |    Reason     |
// +---------------+
// ~  [CloseExts]  ~ if Flag(Z)==1
// +---------------+
//
typedef struct {
    uint8_t _reason;
} _z_t_msg_close_t;
void _z_t_msg_close_clear(_z_t_msg_close_t *msg);
/*=============================*/
/*        Close reasons        */
/*=============================*/
#define _Z_CLOSE_GENERIC 0x00
#define _Z_CLOSE_UNSUPPORTED 0x01
#define _Z_CLOSE_INVALID 0x02
#define _Z_CLOSE_MAX_TRANSPORTS 0x03
#define _Z_CLOSE_MAX_LINKS 0x04
#define _Z_CLOSE_EXPIRED 0x05

/*------------------ Keep Alive Message ------------------*/
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// The KEEP_ALIVE message can be sent periodically to avoid the expiration of the session lease
// period in case there are no messages to be sent.
//
// Flags:
// - X: Reserved
// - X: Reserved
// - Z: Extensions     If Z==1 then Zenoh extensions will follow.
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|X|X| KALIVE  |
// +-+-+-+---------+
// ~  [KAliveExts] ~ if Flag(Z)==1
// +---------------+
//
typedef struct {
    uint8_t __dummy;  // Just to avoid empty structures that might cause undefined behavior
} _z_t_msg_keep_alive_t;
void _z_t_msg_keep_alive_clear(_z_t_msg_keep_alive_t *msg);

/*------------------ Frame Message ------------------*/
// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
//
// Flags:
// - R: Reliable       If R==1 it concerns the reliable channel, else the best-effort channel
// - X: Reserved
// - Z: Extensions     If Z==1 then zenoh extensions will follow.
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|X|R|  FRAME  |
// +-+-+-+---------+
// %    seq num    %
// +---------------+
// ~  [FrameExts]  ~ if Flag(Z)==1
// +---------------+
// ~  [NetworkMsg] ~
// +---------------+
//
// - if R==1 then the FRAME is sent on the reliable channel, best-effort otherwise.
//
typedef struct {
    _z_zbuf_t *_payload;
    _z_zint_t _sn;
} _z_t_msg_frame_t;
void _z_t_msg_frame_clear(_z_t_msg_frame_t *msg);

/*------------------ Fragment Message ------------------*/
// The Fragment message is used to transmit on the wire large Zenoh Message that require fragmentation
// because they are larger than the maximum batch size (i.e. 2^16-1) and/or the link MTU.
//
// The [`Fragment`] message flow is the following:
//
// Flags:
// - R: Reliable       if R==1 it concerns the reliable channel, else the best-effort channel
// - M: More           if M==1 then other fragments will follow
// - Z: Extensions     if Z==1 then zenoh extensions will follow.
//
//  7 6 5 4 3 2 1 0
// +-+-+-+-+-+-+-+-+
// |Z|M|R| FRAGMENT|
// +-+-+-+---------+
// %    seq num    %
// +---------------+
// ~   [FragExts]  ~ if Flag(Z)==1
// +---------------+
// ~      [u8]     ~
// +---------------+
//
typedef struct {
    _z_slice_t _payload;
    _z_zint_t _sn;
    bool first;
    bool drop;
} _z_t_msg_fragment_t;
void _z_t_msg_fragment_clear(_z_t_msg_fragment_t *msg);

/*------------------ Transport Message ------------------*/
typedef union {
    _z_t_msg_join_t _join;
    _z_t_msg_init_t _init;
    _z_t_msg_open_t _open;
    _z_t_msg_close_t _close;
    _z_t_msg_keep_alive_t _keep_alive;
    _z_t_msg_frame_t _frame;
    _z_t_msg_fragment_t _fragment;
} _z_transport_body_t;

typedef struct {
    _z_transport_body_t _body;
    uint8_t _header;
} _z_transport_message_t;
void _z_t_msg_clear(_z_transport_message_t *msg);

z_reliability_t _z_t_msg_get_reliability(_z_transport_message_t *msg);

/*------------------ Builders ------------------*/
_z_transport_message_t _z_t_msg_make_join(z_whatami_t whatami, _z_zint_t lease, _z_id_t zid,
                                          _z_conduit_sn_list_t next_sn);
_z_transport_message_t _z_t_msg_make_init_syn(z_whatami_t whatami, _z_id_t zid);
_z_transport_message_t _z_t_msg_make_init_ack(z_whatami_t whatami, _z_id_t zid, _z_slice_t cookie);
_z_transport_message_t _z_t_msg_make_open_syn(_z_zint_t lease, _z_zint_t initial_sn, _z_slice_t cookie);
_z_transport_message_t _z_t_msg_make_open_ack(_z_zint_t lease, _z_zint_t initial_sn);
_z_transport_message_t _z_t_msg_make_close(uint8_t reason, bool link_only);
_z_transport_message_t _z_t_msg_make_keep_alive(void);
_z_transport_message_t _z_t_msg_make_frame(_z_zint_t sn, _z_zbuf_t *payload, z_reliability_t reliability);
_z_transport_message_t _z_t_msg_make_frame_header(_z_zint_t sn, z_reliability_t reliability);
_z_transport_message_t _z_t_msg_make_fragment_header(_z_zint_t sn, z_reliability_t reliability, bool is_last,
                                                     bool first, bool drop);
_z_transport_message_t _z_t_msg_make_fragment(_z_zint_t sn, _z_slice_t messages, z_reliability_t reliability,
                                              bool is_last, bool first, bool drop);

/*------------------ Copy ------------------*/
void _z_t_msg_copy(_z_transport_message_t *clone, _z_transport_message_t *msg);
void _z_t_msg_copy_join(_z_t_msg_join_t *clone, _z_t_msg_join_t *msg);
void _z_t_msg_copy_init(_z_t_msg_init_t *clone, _z_t_msg_init_t *msg);
void _z_t_msg_copy_open(_z_t_msg_open_t *clone, _z_t_msg_open_t *msg);
void _z_t_msg_copy_close(_z_t_msg_close_t *clone, _z_t_msg_close_t *msg);
void _z_t_msg_copy_keep_alive(_z_t_msg_keep_alive_t *clone, _z_t_msg_keep_alive_t *msg);
void _z_t_msg_copy_frame(_z_t_msg_frame_t *clone, _z_t_msg_frame_t *msg);

typedef union {
    _z_s_msg_scout_t _scout;
    _z_s_msg_hello_t _hello;
} _z_scouting_body_t;

typedef struct {
    _z_scouting_body_t _body;
    uint8_t _header;
} _z_scouting_message_t;
void _z_s_msg_clear(_z_scouting_message_t *msg);

_z_scouting_message_t _z_s_msg_make_scout(z_what_t what, _z_id_t zid);
_z_scouting_message_t _z_s_msg_make_hello(z_whatami_t whatami, _z_id_t zid, _z_locator_array_t locators);

void _z_s_msg_copy(_z_scouting_message_t *clone, _z_scouting_message_t *msg);
void _z_s_msg_copy_scout(_z_s_msg_scout_t *clone, _z_s_msg_scout_t *msg);
void _z_s_msg_copy_hello(_z_s_msg_hello_t *clone, _z_s_msg_hello_t *msg);

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_TRANSPORT_H */
