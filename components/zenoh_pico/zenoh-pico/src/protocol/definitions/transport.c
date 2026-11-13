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

#include "zenoh-pico/protocol/definitions/transport.h"

#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/utils/logging.h"

void _z_s_msg_scout_clear(_z_s_msg_scout_t *msg) {
    // Nothing to do
    _ZP_UNUSED(msg);
}

/*------------------ Locators Field ------------------*/
void _z_locators_clear(_z_locator_array_t *ls) { _z_locator_array_clear(ls); }

void _z_s_msg_hello_clear(_z_s_msg_hello_t *msg) { _z_locators_clear(&msg->_locators); }

void _z_t_msg_join_clear(_z_t_msg_join_t *msg) {
    // Nothing to do
    _ZP_UNUSED(msg);
}

void _z_t_msg_init_clear(_z_t_msg_init_t *msg) { _z_slice_clear(&msg->_cookie); }

void _z_t_msg_open_clear(_z_t_msg_open_t *msg) { _z_slice_clear(&msg->_cookie); }

void _z_t_msg_close_clear(_z_t_msg_close_t *msg) { _ZP_UNUSED(msg); }

void _z_t_msg_keep_alive_clear(_z_t_msg_keep_alive_t *msg) { _ZP_UNUSED(msg); }

void _z_t_msg_frame_clear(_z_t_msg_frame_t *msg) {
    if (msg->_payload != NULL) {
        _z_zbuf_reset(msg->_payload);
    }
}

void _z_t_msg_fragment_clear(_z_t_msg_fragment_t *msg) { _z_slice_clear(&msg->_payload); }

void _z_t_msg_clear(_z_transport_message_t *msg) {
    uint8_t mid = _Z_MID(msg->_header);
    switch (mid) {
        case _Z_MID_T_JOIN: {
            _z_t_msg_join_clear(&msg->_body._join);
        } break;

        case _Z_MID_T_INIT: {
            _z_t_msg_init_clear(&msg->_body._init);
        } break;

        case _Z_MID_T_OPEN: {
            _z_t_msg_open_clear(&msg->_body._open);
        } break;

        case _Z_MID_T_CLOSE: {
            _z_t_msg_close_clear(&msg->_body._close);
        } break;

        case _Z_MID_T_KEEP_ALIVE: {
            _z_t_msg_keep_alive_clear(&msg->_body._keep_alive);
        } break;

        case _Z_MID_T_FRAME: {
            _z_t_msg_frame_clear(&msg->_body._frame);
        } break;

        case _Z_MID_T_FRAGMENT: {
            _z_t_msg_fragment_clear(&msg->_body._fragment);
        } break;

        default: {
            _Z_INFO("WARNING: Trying to clear transport message with unknown ID(%d)", mid);
        } break;
    }
}

z_reliability_t _z_t_msg_get_reliability(_z_transport_message_t *msg) {
    if (_Z_HAS_FLAG(msg->_header, _Z_FLAG_T_FRAME_R)) {
        return Z_RELIABILITY_RELIABLE;
    }
    return Z_RELIABILITY_BEST_EFFORT;
}

/*------------------ Join Message ------------------*/
_z_transport_message_t _z_t_msg_make_join(z_whatami_t whatami, _z_zint_t lease, _z_id_t zid,
                                          _z_conduit_sn_list_t next_sn) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_JOIN;

    msg._body._join._version = Z_PROTO_VERSION;
    msg._body._join._whatami = whatami;
    msg._body._join._lease = lease;
    msg._body._join._seq_num_res = Z_SN_RESOLUTION;
    msg._body._join._req_id_res = Z_REQ_RESOLUTION;
    msg._body._join._batch_size = Z_BATCH_MULTICAST_SIZE;
    msg._body._join._next_sn = next_sn;
    msg._body._join._zid = zid;
#if Z_FEATURE_FRAGMENTATION == 1
    msg._body._join._patch = _Z_CURRENT_PATCH;
#endif

    if ((lease % 1000) == 0) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_JOIN_T);
    }

    if ((Z_BATCH_MULTICAST_SIZE != _Z_DEFAULT_MULTICAST_BATCH_SIZE) ||
        (Z_SN_RESOLUTION != _Z_DEFAULT_RESOLUTION_SIZE) || (Z_REQ_RESOLUTION != _Z_DEFAULT_RESOLUTION_SIZE)) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_JOIN_S);
    }

#if Z_FEATURE_FRAGMENTATION == 1
    bool has_patch = msg._body._join._patch != _Z_NO_PATCH;
#else
    bool has_patch = false;
#endif
    if (next_sn._is_qos || has_patch) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_Z);
    }

    return msg;
}

/*------------------ Init Message ------------------*/
_z_transport_message_t _z_t_msg_make_init_syn(z_whatami_t whatami, _z_id_t zid) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_INIT;

    msg._body._init._version = Z_PROTO_VERSION;
    msg._body._init._whatami = whatami;
    msg._body._init._zid = zid;
    msg._body._init._seq_num_res = Z_SN_RESOLUTION;
    msg._body._init._req_id_res = Z_REQ_RESOLUTION;
    msg._body._init._batch_size = Z_BATCH_UNICAST_SIZE;
    _z_slice_reset(&msg._body._init._cookie);
#if Z_FEATURE_FRAGMENTATION == 1
    msg._body._init._patch = _Z_CURRENT_PATCH;
#endif

    if ((msg._body._init._batch_size != _Z_DEFAULT_UNICAST_BATCH_SIZE) ||
        (msg._body._init._seq_num_res != _Z_DEFAULT_RESOLUTION_SIZE) ||
        (msg._body._init._req_id_res != _Z_DEFAULT_RESOLUTION_SIZE)) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_INIT_S);
    }

#if Z_FEATURE_FRAGMENTATION == 1
    if (msg._body._init._patch != _Z_NO_PATCH) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_Z);
    }
#endif

    return msg;
}

_z_transport_message_t _z_t_msg_make_init_ack(z_whatami_t whatami, _z_id_t zid, _z_slice_t cookie) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_INIT;
    _Z_SET_FLAG(msg._header, _Z_FLAG_T_INIT_A);

    msg._body._init._version = Z_PROTO_VERSION;
    msg._body._init._whatami = whatami;
    msg._body._init._zid = zid;
    msg._body._init._seq_num_res = Z_SN_RESOLUTION;
    msg._body._init._req_id_res = Z_REQ_RESOLUTION;
    msg._body._init._batch_size = Z_BATCH_UNICAST_SIZE;
    msg._body._init._cookie = cookie;
#if Z_FEATURE_FRAGMENTATION == 1
    msg._body._init._patch = _Z_CURRENT_PATCH;
#endif

    if ((msg._body._init._batch_size != _Z_DEFAULT_UNICAST_BATCH_SIZE) ||
        (msg._body._init._seq_num_res != _Z_DEFAULT_RESOLUTION_SIZE) ||
        (msg._body._init._req_id_res != _Z_DEFAULT_RESOLUTION_SIZE)) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_INIT_S);
    }

#if Z_FEATURE_FRAGMENTATION == 1
    if (msg._body._init._patch != _Z_NO_PATCH) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_Z);
    }
#endif
    return msg;
}

/*------------------ Open Message ------------------*/
_z_transport_message_t _z_t_msg_make_open_syn(_z_zint_t lease, _z_zint_t initial_sn, _z_slice_t cookie) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_OPEN;

    msg._body._open._lease = lease;
    msg._body._open._initial_sn = initial_sn;
    msg._body._open._cookie = cookie;

    if ((lease % 1000) == 0) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_OPEN_T);
    }

    return msg;
}

_z_transport_message_t _z_t_msg_make_open_ack(_z_zint_t lease, _z_zint_t initial_sn) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_OPEN;
    _Z_SET_FLAG(msg._header, _Z_FLAG_T_OPEN_A);

    msg._body._open._lease = lease;
    msg._body._open._initial_sn = initial_sn;
    _z_slice_reset(&msg._body._open._cookie);

    if ((lease % 1000) == 0) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_OPEN_T);
    }

    return msg;
}

/*------------------ Close Message ------------------*/
_z_transport_message_t _z_t_msg_make_close(uint8_t reason, bool link_only) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_CLOSE;

    msg._body._close._reason = reason;
    if (link_only == false) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_CLOSE_S);
    }

    return msg;
}

/*------------------ Keep Alive Message ------------------*/
_z_transport_message_t _z_t_msg_make_keep_alive(void) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_KEEP_ALIVE;

    return msg;
}

_z_transport_message_t _z_t_msg_make_frame(_z_zint_t sn, _z_zbuf_t *payload, z_reliability_t reliability) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_FRAME;

    msg._body._frame._sn = sn;
    if (reliability == Z_RELIABILITY_RELIABLE) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_FRAME_R);
    }
    msg._body._frame._payload = payload;
    return msg;
}

/*------------------ Frame Message ------------------*/
_z_transport_message_t _z_t_msg_make_frame_header(_z_zint_t sn, z_reliability_t reliability) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_FRAME;

    msg._body._frame._sn = sn;
    if (reliability == Z_RELIABILITY_RELIABLE) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_FRAME_R);
    }
    msg._body._frame._payload = NULL;
    return msg;
}

/*------------------ Fragment Message ------------------*/
_z_transport_message_t _z_t_msg_make_fragment_header(_z_zint_t sn, z_reliability_t reliability, bool is_last,
                                                     bool first, bool drop) {
    return _z_t_msg_make_fragment(sn, _z_slice_null(), reliability, is_last, first, drop);
}
_z_transport_message_t _z_t_msg_make_fragment(_z_zint_t sn, _z_slice_t payload, z_reliability_t reliability,
                                              bool is_last, bool first, bool drop) {
    _z_transport_message_t msg;
    msg._header = _Z_MID_T_FRAGMENT;
    if (is_last == false) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_FRAGMENT_M);
    }
    if (reliability == Z_RELIABILITY_RELIABLE) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_FRAGMENT_R);
    }

    msg._body._fragment._sn = sn;
    msg._body._fragment._payload = payload;
    if (first || drop) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_Z);
    }
    msg._body._fragment.first = first;
    msg._body._fragment.drop = drop;

    return msg;
}

void _z_t_msg_copy_fragment(_z_t_msg_fragment_t *clone, _z_t_msg_fragment_t *msg) {
    clone->_payload = msg->_payload;
    _z_slice_copy(&clone->_payload, &msg->_payload);
    clone->first = msg->first;
    clone->drop = msg->drop;
}

void _z_t_msg_copy_join(_z_t_msg_join_t *clone, _z_t_msg_join_t *msg) {
    clone->_version = msg->_version;
    clone->_whatami = msg->_whatami;
    clone->_lease = msg->_lease;
    clone->_seq_num_res = msg->_seq_num_res;
    clone->_req_id_res = msg->_req_id_res;
    clone->_batch_size = msg->_batch_size;
    clone->_next_sn = msg->_next_sn;
#if Z_FEATURE_FRAGMENTATION == 1
    clone->_patch = msg->_patch;
#endif
    memcpy(clone->_zid.id, msg->_zid.id, 16);
}

void _z_t_msg_copy_init(_z_t_msg_init_t *clone, _z_t_msg_init_t *msg) {
    clone->_version = msg->_version;
    clone->_whatami = msg->_whatami;
    clone->_seq_num_res = msg->_seq_num_res;
    clone->_req_id_res = msg->_req_id_res;
    clone->_batch_size = msg->_batch_size;
    memcpy(clone->_zid.id, msg->_zid.id, 16);
    if (!_z_slice_is_empty(&msg->_cookie)) {
        _z_slice_copy(&clone->_cookie, &msg->_cookie);
    }
#if Z_FEATURE_FRAGMENTATION == 1
    clone->_patch = msg->_patch;
#endif
}

void _z_t_msg_copy_open(_z_t_msg_open_t *clone, _z_t_msg_open_t *msg) {
    clone->_lease = msg->_lease;
    clone->_initial_sn = msg->_initial_sn;
    if (!_z_slice_is_empty(&msg->_cookie)) {
        _z_slice_copy(&clone->_cookie, &msg->_cookie);
    }
}

void _z_t_msg_copy_close(_z_t_msg_close_t *clone, _z_t_msg_close_t *msg) { clone->_reason = msg->_reason; }

void _z_t_msg_copy_keep_alive(_z_t_msg_keep_alive_t *clone, _z_t_msg_keep_alive_t *msg) {
    (void)(clone);
    (void)(msg);
}

void _z_t_msg_copy_frame(_z_t_msg_frame_t *clone, _z_t_msg_frame_t *msg) {
    clone->_sn = msg->_sn;
    if ((msg->_payload != NULL) && (clone->_payload != NULL)) {
        _z_zbuf_copy(clone->_payload, msg->_payload);
    }
}

/*------------------ Transport Message ------------------*/
void _z_t_msg_copy(_z_transport_message_t *clone, _z_transport_message_t *msg) {
    clone->_header = msg->_header;

    uint8_t mid = _Z_MID(msg->_header);
    switch (mid) {
        case _Z_MID_T_JOIN: {
            _z_t_msg_copy_join(&clone->_body._join, &msg->_body._join);
        } break;

        case _Z_MID_T_INIT: {
            _z_t_msg_copy_init(&clone->_body._init, &msg->_body._init);
        } break;

        case _Z_MID_T_OPEN: {
            _z_t_msg_copy_open(&clone->_body._open, &msg->_body._open);
        } break;

        case _Z_MID_T_CLOSE: {
            _z_t_msg_copy_close(&clone->_body._close, &msg->_body._close);
        } break;

        case _Z_MID_T_KEEP_ALIVE: {
            _z_t_msg_copy_keep_alive(&clone->_body._keep_alive, &msg->_body._keep_alive);
        } break;

        case _Z_MID_T_FRAME: {
            _z_t_msg_copy_frame(&clone->_body._frame, &msg->_body._frame);
        } break;

        case _Z_MID_T_FRAGMENT: {
            _z_t_msg_copy_fragment(&clone->_body._fragment, &msg->_body._fragment);
        } break;

        default: {
            _Z_INFO("WARNING: Trying to copy transport message with unknown ID(%d)", mid);
        } break;
    }
}

void _z_s_msg_clear(_z_scouting_message_t *msg) {
    uint8_t mid = _Z_MID(msg->_header);
    switch (mid) {
        case _Z_MID_SCOUT: {
            _z_s_msg_scout_clear(&msg->_body._scout);
        } break;

        case _Z_MID_HELLO: {
            _z_s_msg_hello_clear(&msg->_body._hello);
        } break;

        default: {
            _Z_INFO("WARNING: Trying to clear session message with unknown ID(%d)", mid);
        } break;
    }
}

/*=============================*/
/*     Transport Messages      */
/*=============================*/
/*------------------ Scout Message ------------------*/
_z_scouting_message_t _z_s_msg_make_scout(z_what_t what, _z_id_t zid) {
    _z_scouting_message_t msg;
    msg._header = _Z_MID_SCOUT;

    msg._body._scout._version = Z_PROTO_VERSION;
    msg._body._scout._what = what;
    msg._body._scout._zid = zid;

    return msg;
}

/*------------------ Hello Message ------------------*/
_z_scouting_message_t _z_s_msg_make_hello(z_whatami_t whatami, _z_id_t zid, _z_locator_array_t locators) {
    _z_scouting_message_t msg;
    msg._header = _Z_MID_HELLO;

    msg._body._hello._version = Z_PROTO_VERSION;
    msg._body._hello._whatami = whatami;
    msg._body._hello._zid = zid;
    msg._body._hello._locators = locators;

    if (_z_locator_array_is_empty(&locators) == false) {
        _Z_SET_FLAG(msg._header, _Z_FLAG_T_HELLO_L);
    }

    return msg;
}

void _z_s_msg_copy_scout(_z_s_msg_scout_t *clone, _z_s_msg_scout_t *msg) {
    clone->_what = msg->_what;
    clone->_version = msg->_version;
    memcpy(clone->_zid.id, msg->_zid.id, 16);
}

void _z_s_msg_copy_hello(_z_s_msg_hello_t *clone, _z_s_msg_hello_t *msg) {
    _z_locator_array_copy(&clone->_locators, &msg->_locators);
    memcpy(clone->_zid.id, msg->_zid.id, 16);
    clone->_whatami = msg->_whatami;
}

/*------------------ Scouting Message ------------------*/
void _z_s_msg_copy(_z_scouting_message_t *clone, _z_scouting_message_t *msg) {
    clone->_header = msg->_header;

    uint8_t mid = _Z_MID(msg->_header);
    switch (mid) {
        case _Z_MID_SCOUT: {
            _z_s_msg_copy_scout(&clone->_body._scout, &msg->_body._scout);
        } break;

        case _Z_MID_HELLO: {
            _z_s_msg_copy_hello(&clone->_body._hello, &msg->_body._hello);
        } break;

        default: {
            _Z_INFO("WARNING: Trying to copy session message with unknown ID(%d)", mid);
        } break;
    }
}
