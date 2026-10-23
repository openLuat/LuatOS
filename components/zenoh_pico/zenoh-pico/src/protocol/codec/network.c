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

#include "zenoh-pico/protocol/codec/network.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/protocol/codec.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/protocol/codec/declarations.h"
#include "zenoh-pico/protocol/codec/ext.h"
#include "zenoh-pico/protocol/codec/interest.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/core.h"
#include "zenoh-pico/protocol/definitions/interest.h"
#include "zenoh-pico/protocol/definitions/message.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/protocol/ext.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/result.h"

/*------------------ Push Message ------------------*/

z_result_t _z_push_encode(_z_wbuf_t *wbf, const _z_n_msg_push_t *msg) {
    uint8_t header = _Z_MID_N_PUSH | (_z_wireexpr_is_local(&msg->_key) ? _Z_FLAG_N_REQUEST_M : 0);
    bool has_suffix = _z_wireexpr_has_suffix(&msg->_key);
    bool has_qos_ext = msg->_qos._val != _Z_N_QOS_DEFAULT._val;
    bool has_timestamp_ext = _z_timestamp_check(&msg->_timestamp);
    if (has_suffix) {
        header |= _Z_FLAG_N_REQUEST_N;
    }
    if (has_qos_ext || has_timestamp_ext) {
        header |= _Z_FLAG_N_Z;
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    _Z_RETURN_IF_ERR(_z_wireexpr_encode(wbf, has_suffix, &msg->_key));

    if (has_qos_ext) {
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, (uint8_t)(_Z_MSG_EXT_ENC_ZINT | 0x01 | (has_timestamp_ext << 7))));
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, msg->_qos._val));
    }

    if (has_timestamp_ext) {
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, _Z_MSG_EXT_ENC_ZBUF | 0x02));
        _Z_RETURN_IF_ERR(_z_timestamp_encode_ext(wbf, &msg->_timestamp));
    }

    _Z_RETURN_IF_ERR(_z_push_body_encode(wbf, &msg->_body));

    return _Z_RES_OK;
}

z_result_t _z_push_decode_ext_cb(_z_msg_ext_t *extension, void *ctx) {
    z_result_t ret = _Z_RES_OK;
    _z_n_msg_push_t *msg = (_z_n_msg_push_t *)ctx;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case _Z_MSG_EXT_ENC_ZINT | 0x01: {  // QOS ext
            if (extension->_body._zint._val > UINT32_MAX) {
                _Z_INFO("Invalid value decoded");
                _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
            }
            msg->_qos = (_z_n_qos_t){._val = (uint8_t)extension->_body._zint._val};
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x02: {  // Timestamp ext
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            ret = _z_timestamp_decode(&msg->_timestamp, &zbf);
            break;
        }
        default:
            if ((extension->_header & _Z_MSG_EXT_FLAG_M) != 0) {
                ret = _z_msg_ext_unknown_error(extension, 0x07);
            }
    }
    return ret;
}

z_result_t _z_push_decode(_z_n_msg_push_t *msg, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs,
                          uintptr_t mapping) {
    z_result_t ret = _Z_RES_OK;
    msg->_qos = _Z_N_QOS_DEFAULT;
    ret |= _z_wireexpr_decode(&msg->_key, zbf, _Z_HAS_FLAG(header, _Z_FLAG_N_PUSH_N),
                              _Z_HAS_FLAG(header, _Z_FLAG_N_PUSH_M), mapping);
    if ((ret == _Z_RES_OK) && _Z_HAS_FLAG(header, _Z_FLAG_N_Z)) {
        ret = _z_msg_ext_decode_iter(zbf, _z_push_decode_ext_cb, msg);
    }
    if (ret == _Z_RES_OK) {
        uint8_t msgheader;
        _Z_RETURN_IF_ERR(_z_uint8_decode(&msgheader, zbf));
        _Z_RETURN_IF_ERR(_z_push_body_decode(&msg->_body, zbf, msgheader, arcs));
    }

    return ret;
}

/*------------------ Request Message ------------------*/
z_result_t _z_request_encode(_z_wbuf_t *wbf, const _z_n_msg_request_t *msg) {
    z_result_t ret = _Z_RES_OK;
    uint8_t header = _Z_MID_N_REQUEST | (_z_wireexpr_is_local(&msg->_key) ? _Z_FLAG_N_REQUEST_M : 0);
    bool has_suffix = _z_wireexpr_has_suffix(&msg->_key);
    if (has_suffix) {
        header |= _Z_FLAG_N_REQUEST_N;
    }
    _z_n_msg_request_exts_t exts = _z_n_msg_request_needed_exts(msg);
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, (uint8_t)(header | (exts.n != 0 ? _Z_FLAG_Z_Z : 0))));
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_rid));
    _Z_RETURN_IF_ERR(_z_wireexpr_encode(wbf, has_suffix, &msg->_key));

    if (exts.ext_qos) {
        exts.n -= 1;
        uint8_t extheader = 0x01 | _Z_MSG_EXT_ENC_ZINT | (exts.n ? _Z_FLAG_Z_Z : 0);
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_ext_qos._val));
    }
    if (exts.ext_tstamp) {
        exts.n -= 1;
        uint8_t extheader = 0x02 | _Z_MSG_EXT_ENC_ZBUF | (exts.n ? _Z_FLAG_Z_Z : 0);
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_timestamp_encode_ext(wbf, &msg->_ext_timestamp));
    }
    if (exts.ext_target) {
        exts.n -= 1;
        uint8_t extheader = 0x04 | _Z_MSG_EXT_ENC_ZINT | (exts.n ? _Z_FLAG_Z_Z : 0) | _Z_MSG_EXT_FLAG_M;
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_ext_target));
    }
    if (exts.ext_budget) {
        exts.n -= 1;
        uint8_t extheader = 0x05 | _Z_MSG_EXT_ENC_ZINT | (exts.n ? _Z_FLAG_Z_Z : 0);
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_ext_budget));
    }
    if (exts.ext_timeout_ms) {
        exts.n -= 1;
        uint8_t extheader = 0x06 | _Z_MSG_EXT_ENC_ZINT | (exts.n ? _Z_FLAG_Z_Z : 0);
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_zint64_encode(wbf, msg->_ext_timeout_ms));
    }

    switch (msg->_tag) {
        case _Z_REQUEST_QUERY: {
            _Z_RETURN_IF_ERR(_z_query_encode(wbf, &msg->_body._query));
        } break;
        case _Z_REQUEST_PUT: {
            _Z_RETURN_IF_ERR(_z_put_encode(wbf, &msg->_body._put));
        } break;
        case _Z_REQUEST_DEL: {
            _Z_RETURN_IF_ERR(_z_del_encode(wbf, &msg->_body._del));
        } break;
    }
    return ret;
}
z_result_t _z_request_decode_extensions(_z_msg_ext_t *extension, void *ctx) {
    _z_n_msg_request_t *msg = (_z_n_msg_request_t *)ctx;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case 0x01 | _Z_MSG_EXT_ENC_ZINT: {  // QOS ext
            if (extension->_body._zint._val > UINT8_MAX) {
                _Z_INFO("Invalid value decoded");
                _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
            }
            msg->_ext_qos = (_z_n_qos_t){._val = (uint8_t)extension->_body._zint._val};
            break;
        }
        case 0x02 | _Z_MSG_EXT_ENC_ZBUF: {  // Timestamp ext
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            _Z_RETURN_IF_ERR(_z_timestamp_decode(&msg->_ext_timestamp, &zbf));
            break;
        }
        case 0x04 | _Z_MSG_EXT_ENC_ZINT | _Z_MSG_EXT_FLAG_M: {
            msg->_ext_target = (uint8_t)extension->_body._zint._val;
            if (msg->_ext_target > 2) {
                _Z_INFO("Invalid value decoded");
                _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
            }
        } break;
        case 0x05 | _Z_MSG_EXT_ENC_ZINT: {
            if (extension->_body._zint._val > UINT32_MAX) {
                _Z_INFO("Request extension budget was truncated to u32.");
            }
            msg->_ext_budget = (uint32_t)extension->_body._zint._val;
        } break;
        case 0x06 | _Z_MSG_EXT_ENC_ZINT: {
            msg->_ext_timeout_ms = extension->_body._zint._val;
        } break;
        default:
            if ((extension->_header & _Z_MSG_EXT_FLAG_M) != 0) {
                return _z_msg_ext_unknown_error(extension, 0x16);
            }
    }
    return _Z_RES_OK;
}
z_result_t _z_request_decode(_z_n_msg_request_t *msg, _z_zbuf_t *zbf, const uint8_t header, _z_arc_slice_t *arcs,
                             uintptr_t mapping) {
    msg->_ext_qos = _Z_N_QOS_DEFAULT;
    _Z_RETURN_IF_ERR(_z_zsize_decode(&msg->_rid, zbf));
    _Z_RETURN_IF_ERR(_z_wireexpr_decode(&msg->_key, zbf, _Z_HAS_FLAG(header, _Z_FLAG_N_REQUEST_N),
                                        _Z_HAS_FLAG(header, _Z_FLAG_N_REQUEST_M), mapping));
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_request_decode_extensions, msg));
    }
    uint8_t zheader;
    _Z_RETURN_IF_ERR(_z_uint8_decode(&zheader, zbf));
    switch (_Z_MID(zheader)) {
        case _Z_MID_Z_QUERY: {
            msg->_tag = _Z_REQUEST_QUERY;
            _Z_RETURN_IF_ERR(_z_query_decode(&msg->_body._query, zbf, zheader));
        } break;
        case _Z_MID_Z_PUT: {
            msg->_tag = _Z_REQUEST_PUT;
            _Z_RETURN_IF_ERR(_z_put_decode(&msg->_body._put, zbf, zheader, arcs));
        } break;
        case _Z_MID_Z_DEL: {
            msg->_tag = _Z_REQUEST_DEL;
            _Z_RETURN_IF_ERR(_z_del_decode(&msg->_body._del, zbf, zheader));
        } break;
        default:
            _Z_INFO("Unknown request type received: %d", _Z_MID(zheader));
            _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
    }
    return _Z_RES_OK;
}

/*------------------ Response Message ------------------*/
z_result_t _z_response_encode(_z_wbuf_t *wbf, const _z_n_msg_response_t *msg) {
    z_result_t ret = _Z_RES_OK;
    uint8_t header = _Z_MID_N_RESPONSE;
    _Z_DEBUG("Encoding _Z_MID_N_RESPONSE");
    bool has_qos_ext = msg->_ext_qos._val != _Z_N_QOS_DEFAULT._val;
    bool has_ts_ext = _z_timestamp_check(&msg->_ext_timestamp);
    bool has_responder_ext = _z_id_check(msg->_ext_responder._zid) || msg->_ext_responder._eid != 0;
    int n_ext = (has_qos_ext ? 1 : 0) + (has_ts_ext ? 1 : 0) + (has_responder_ext ? 1 : 0);
    bool has_suffix = _z_wireexpr_has_suffix(&msg->_key);
    if (_z_wireexpr_is_local(&msg->_key)) {
        _Z_SET_FLAG(header, _Z_FLAG_N_RESPONSE_M);
    }
    if (has_suffix) {
        _Z_SET_FLAG(header, _Z_FLAG_N_RESPONSE_N);
    }
    if (n_ext != 0) {
        _Z_SET_FLAG(header, _Z_FLAG_Z_Z);
    }

    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_request_id));
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_key._id));
    if (has_suffix) {
        _Z_RETURN_IF_ERR(_z_string_encode(wbf, &msg->_key._suffix))
    }
    if (has_qos_ext) {
        n_ext -= 1;
        uint8_t extheader = _Z_MSG_EXT_ENC_ZINT | 0x01;
        if (n_ext != 0) {
            extheader |= _Z_FLAG_Z_Z;
        }
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_ext_qos._val));
    }
    if (has_ts_ext) {
        n_ext -= 1;
        uint8_t extheader = _Z_MSG_EXT_ENC_ZBUF | 0x02 | (n_ext != 0 ? _Z_FLAG_Z_Z : 0);
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_timestamp_encode_ext(wbf, &msg->_ext_timestamp));
    }
    if (has_responder_ext) {
        n_ext -= 1;
        uint8_t extheader = _Z_MSG_EXT_ENC_ZBUF | 0x03 | (n_ext != 0 ? _Z_FLAG_Z_Z : 0);
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        uint8_t zidlen = _z_id_len(msg->_ext_responder._zid);
        extheader = (uint8_t)((zidlen - 1) << 4);
        size_t ext_size = (size_t)(zidlen + 1 + _z_zint_len(msg->_ext_responder._eid));
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, ext_size));
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_wbuf_write_bytes(wbf, msg->_ext_responder._zid.id, 0, zidlen));
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_ext_responder._eid));
    }
    switch (msg->_tag) {
        case _Z_RESPONSE_BODY_REPLY: {
            _Z_RETURN_IF_ERR(_z_reply_encode(wbf, &msg->_body._reply));
            break;
        }
        case _Z_RESPONSE_BODY_ERR: {
            _Z_RETURN_IF_ERR(_z_err_encode(wbf, &msg->_body._err));
            break;
        }
    }
    return ret;
}

z_result_t _z_response_decode_extension(_z_msg_ext_t *extension, void *ctx) {
    z_result_t ret = _Z_RES_OK;
    _z_n_msg_response_t *msg = (_z_n_msg_response_t *)ctx;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case _Z_MSG_EXT_ENC_ZINT | 0x01: {
            msg->_ext_qos._val = (uint8_t)extension->_body._zint._val;
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x02: {
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            ret = _z_timestamp_decode(&msg->_ext_timestamp, &zbf);
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x03: {
            _z_zbuf_t _zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            _z_zbuf_t *zbf = &_zbf;
            uint8_t header;
            _Z_RETURN_IF_ERR(_z_uint8_decode(&header, zbf));
            uint8_t zidlen = (header >> 4) + (uint8_t)1;
            _Z_RETURN_IF_ERR(_z_zbuf_read_exact(zbf, msg->_ext_responder._zid.id, zidlen));
            _Z_RETURN_IF_ERR(_z_zint32_decode(&msg->_ext_responder._eid, zbf));
            break;
        }
        default:
            if (_Z_HAS_FLAG(extension->_header, _Z_MSG_EXT_FLAG_M)) {
                ret = _z_msg_ext_unknown_error(extension, 0x0d);
            }
    }
    return ret;
}

z_result_t _z_response_decode(_z_n_msg_response_t *msg, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs,
                              uintptr_t mapping) {
    _Z_DEBUG("Decoding _Z_MID_N_RESPONSE");
    msg->_ext_qos = _Z_N_QOS_DEFAULT;
    _Z_RETURN_IF_ERR(_z_zsize_decode(&msg->_request_id, zbf));
    _Z_RETURN_IF_ERR(_z_wireexpr_decode(&msg->_key, zbf, _Z_HAS_FLAG(header, _Z_FLAG_N_RESPONSE_N),
                                        _Z_HAS_FLAG(header, _Z_FLAG_N_RESPONSE_M), mapping));
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_response_decode_extension, msg));
    }
    uint8_t inner_header;
    _Z_RETURN_IF_ERR(_z_uint8_decode(&inner_header, zbf));
    switch (_Z_MID(inner_header)) {
        case _Z_MID_Z_REPLY: {
            msg->_tag = _Z_RESPONSE_BODY_REPLY;
            return _z_reply_decode(&msg->_body._reply, zbf, inner_header, arcs);
            break;
        }
        case _Z_MID_Z_ERR: {
            msg->_tag = _Z_RESPONSE_BODY_ERR;
            return _z_err_decode(&msg->_body._err, zbf, inner_header, arcs);
            break;
        }
        default: {
            _Z_ERROR("Unknown N_MID: %d", _Z_MID(inner_header));
            _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
        }
    }
}

/*------------------ Response Final Message ------------------*/
z_result_t _z_response_final_encode(_z_wbuf_t *wbf, const _z_n_msg_response_final_t *msg) {
    z_result_t ret = _Z_RES_OK;
    _Z_DEBUG("Encoding _Z_MID_N_RESPONSE_FINAL");
    uint8_t header = _Z_MID_N_RESPONSE_FINAL;
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, msg->_request_id));

    return ret;
}

z_result_t _z_response_final_decode(_z_n_msg_response_final_t *msg, _z_zbuf_t *zbf, uint8_t header) {
    (void)(header);
    z_result_t ret = _Z_RES_OK;
    ret |= _z_zsize_decode(&msg->_request_id, zbf);
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_skip_non_mandatories(zbf, 0x1a));
    }
    return ret;
}

z_result_t _z_declare_encode(_z_wbuf_t *wbf, const _z_n_msg_declare_t *decl) {
    uint8_t header = _Z_MID_N_DECLARE;
    bool has_qos_ext = decl->_ext_qos._val != _Z_N_QOS_DEFAULT._val;
    bool has_timestamp_ext = _z_timestamp_check(&decl->_ext_timestamp);
    int n_ext = (has_qos_ext ? 1 : 0) + (has_timestamp_ext ? 1 : 0);
    if (n_ext != 0) {
        header |= _Z_FLAG_N_Z;
    }
    if (decl->_interest_id.has_value) {
        header |= _Z_FLAG_N_DECLARE_I;
    }
    // Encode header
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    // Encode interest id
    if (decl->_interest_id.has_value) {
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, decl->_interest_id.value));
    }
    // Encode extensions
    if (has_qos_ext) {
        n_ext -= 1;
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, 0x01 | _Z_MSG_EXT_ENC_ZINT | (n_ext != 0 ? _Z_FLAG_Z_Z : 0)));
        _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, decl->_ext_qos._val));
    }
    if (has_timestamp_ext) {
        n_ext -= 1;
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, 0x02 | _Z_MSG_EXT_ENC_ZBUF | (n_ext != 0 ? _Z_FLAG_Z_Z : 0)));
        _Z_RETURN_IF_ERR(_z_timestamp_encode_ext(wbf, &decl->_ext_timestamp));
    }
    // Encode declaration
    return _z_declaration_encode(wbf, &decl->_decl);
}
z_result_t _z_declare_decode_extensions(_z_msg_ext_t *extension, void *ctx) {
    _z_n_msg_declare_t *decl = (_z_n_msg_declare_t *)ctx;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case _Z_MSG_EXT_ENC_ZINT | 0x01: {
            decl->_ext_qos._val = (uint8_t)extension->_body._zint._val;
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x02: {
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            return _z_timestamp_decode(&decl->_ext_timestamp, &zbf);
        }
        default:
            if (_Z_HAS_FLAG(extension->_header, _Z_MSG_EXT_FLAG_M)) {
                return _z_msg_ext_unknown_error(extension, 0x19);
            }
    }
    return _Z_RES_OK;
}
z_result_t _z_declare_decode(_z_n_msg_declare_t *decl, _z_zbuf_t *zbf, uint8_t header, uintptr_t mapping) {
    decl->_ext_qos = _Z_N_QOS_DEFAULT;
    // Retrieve interest id
    if (_Z_HAS_FLAG(header, _Z_FLAG_N_DECLARE_I)) {
        _Z_RETURN_IF_ERR(_z_zint32_decode(&decl->_interest_id.value, zbf));
        decl->_interest_id.has_value = true;
    }
    // Decode extensions
    if (_Z_HAS_FLAG(header, _Z_FLAG_N_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_declare_decode_extensions, decl))
    }
    // Decode declaration
    return _z_declaration_decode(&decl->_decl, zbf, mapping);
}

z_result_t _z_n_interest_encode(_z_wbuf_t *wbf, const _z_n_msg_interest_t *interest) {
    // Set header
    uint8_t header = _Z_MID_N_INTEREST;
    bool is_final = true;
    if (_Z_HAS_FLAG(interest->_interest.flags, _Z_INTEREST_FLAG_CURRENT)) {
        is_final = false;
        _Z_SET_FLAG(header, _Z_FLAG_N_INTEREST_CURRENT);
    }
    if (_Z_HAS_FLAG(interest->_interest.flags, _Z_INTEREST_FLAG_FUTURE)) {
        is_final = false;
        _Z_SET_FLAG(header, _Z_FLAG_N_INTEREST_FUTURE);
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    return _z_interest_encode(wbf, &interest->_interest, is_final);
}

z_result_t _z_n_interest_decode(_z_n_msg_interest_t *interest, _z_zbuf_t *zbf, uint8_t header, uintptr_t mapping) {
    interest->_interest = _z_interest_null();
    bool is_final = true;
    bool has_ext = false;

    if (_Z_HAS_FLAG(header, _Z_FLAG_N_INTEREST_CURRENT)) {
        _Z_SET_FLAG(interest->_interest.flags, _Z_INTEREST_FLAG_CURRENT);
        is_final = false;
    }
    if (_Z_HAS_FLAG(header, _Z_FLAG_N_INTEREST_FUTURE)) {
        _Z_SET_FLAG(interest->_interest.flags, _Z_INTEREST_FLAG_FUTURE);
        is_final = false;
    }
    // Decode extention
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
        has_ext = true;
    }
    return _z_interest_decode(&interest->_interest, zbf, is_final, has_ext, mapping);
}

z_result_t _z_oam_encode(_z_wbuf_t *wbf, const _z_n_msg_oam_t *oam) {
    uint8_t header = _Z_MID_N_OAM;
    bool has_qos_ext = oam->_ext_qos._val != _Z_N_QOS_DEFAULT._val;
    bool has_timestamp_ext = _z_timestamp_check(&oam->_ext_timestamp);
    int n_ext = (has_qos_ext ? 1 : 0) + (has_timestamp_ext ? 1 : 0);
    if (n_ext != 0) {
        header |= _Z_FLAG_N_Z;
    }
    switch (oam->_enc) {
        case _Z_OAM_BODY_UNIT: {
            header |= _Z_MSG_EXT_ENC_UNIT;
        } break;
        case _Z_OAM_BODY_ZINT: {
            header |= _Z_MSG_EXT_ENC_ZINT;
        } break;
        case _Z_OAM_BODY_ZBUF: {
            header |= _Z_MSG_EXT_ENC_ZBUF;
        } break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    _Z_RETURN_IF_ERR(_z_zint16_encode(wbf, oam->_id));

    if (has_qos_ext) {
        n_ext -= 1;
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, 0x01 | _Z_MSG_EXT_ENC_ZINT | (n_ext != 0 ? _Z_FLAG_Z_Z : 0)));
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, oam->_ext_qos._val));
    }
    if (has_timestamp_ext) {
        n_ext -= 1;
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, 0x02 | _Z_MSG_EXT_ENC_ZBUF | (n_ext != 0 ? _Z_FLAG_Z_Z : 0)));
        _Z_RETURN_IF_ERR(_z_timestamp_encode_ext(wbf, &oam->_ext_timestamp));
    }

    switch (oam->_enc) {
        case _Z_OAM_BODY_UNIT: {
            // No body to encode
        } break;
        case _Z_OAM_BODY_ZINT: {
            _Z_RETURN_IF_ERR(_z_zint64_encode(wbf, oam->_body._zint._val));
        } break;
        case _Z_OAM_BODY_ZBUF: {
            _Z_RETURN_IF_ERR(_z_slice_encode(wbf, &oam->_body._zbuf._val));
        } break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }

    return _Z_RES_OK;
}

z_result_t _z_oam_decode_extensions(_z_msg_ext_t *extension, void *ctx) {
    _z_n_msg_oam_t *oam = (_z_n_msg_oam_t *)ctx;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case _Z_MSG_EXT_ENC_ZINT | 0x01: {
            oam->_ext_qos._val = (uint8_t)extension->_body._zint._val;
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x02: {
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            return _z_timestamp_decode(&oam->_ext_timestamp, &zbf);
        }
        default:
            if (_Z_HAS_FLAG(extension->_header, _Z_MSG_EXT_FLAG_M)) {
                return _z_msg_ext_unknown_error(extension, 0x20);
            }
    }
    return _Z_RES_OK;
}

z_result_t _z_oam_decode(_z_n_msg_oam_t *oam, _z_zbuf_t *zbf, uint8_t header) {
    _Z_DEBUG("Decoding _Z_MID_N_OAM");
    // Decode ID
    _Z_RETURN_IF_ERR(_z_zint16_decode(&oam->_id, zbf));

    // Initialize extensions with default values
    oam->_ext_qos = _Z_N_QOS_DEFAULT;
    oam->_ext_timestamp = _z_timestamp_null();

    // Decode extensions
    if (_Z_HAS_FLAG(header, _Z_FLAG_N_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_oam_decode_extensions, oam))
    }

    // Decode payload
    switch (_Z_EXT_ENC(header)) {
        case _Z_MSG_EXT_ENC_UNIT: {
            oam->_enc = _Z_OAM_BODY_UNIT;
            return _Z_RES_OK;
        } break;

        case _Z_MSG_EXT_ENC_ZINT: {
            oam->_enc = _Z_OAM_BODY_ZINT;
            return _z_zint64_decode(&oam->_body._zint._val, zbf);
        } break;

        case _Z_MSG_EXT_ENC_ZBUF: {
            oam->_enc = _Z_OAM_BODY_ZBUF;
            return _z_slice_decode(&oam->_body._zbuf._val, zbf);
        } break;
        default: {
            _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
        }
    }
}

z_result_t _z_network_message_encode(_z_wbuf_t *wbf, const _z_network_message_t *msg) {
    switch (msg->_tag) {
        case _Z_N_DECLARE: {
            return _z_declare_encode(wbf, &msg->_body._declare);
        } break;
#if Z_FEATURE_PUBLICATION == 1
        case _Z_N_PUSH: {
            return _z_push_encode(wbf, &msg->_body._push);
        } break;
#endif
#if Z_FEATURE_QUERY == 1
        case _Z_N_REQUEST: {
            return _z_request_encode(wbf, &msg->_body._request);
        } break;
#endif
#if Z_FEATURE_QUERYABLE == 1
        case _Z_N_RESPONSE: {
            return _z_response_encode(wbf, &msg->_body._response);
        } break;
        case _Z_N_RESPONSE_FINAL: {
            return _z_response_final_encode(wbf, &msg->_body._response_final);
        } break;
#endif
#if Z_FEATURE_INTEREST == 1
        case _Z_N_INTEREST: {
            return _z_n_interest_encode(wbf, &msg->_body._interest);
        } break;
#endif
        case _Z_N_OAM: {
            return _z_oam_encode(wbf, &msg->_body._oam);
        } break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
}
z_result_t _z_network_message_decode(_z_network_message_t *msg, _z_zbuf_t *zbf, _z_arc_slice_t *arcs,
                                     uintptr_t mapping) {
    uint8_t *header;
    *msg = (_z_network_message_t){0};
    _Z_RETURN_IF_ERR(_z_uint8_decode_as_ref(&header, zbf));
    switch (_Z_MID(*header)) {
        case _Z_MID_N_DECLARE: {
            msg->_tag = _Z_N_DECLARE;
            return _z_declare_decode(&msg->_body._declare, zbf, *header, mapping);
        } break;
        case _Z_MID_N_PUSH: {
            msg->_tag = _Z_N_PUSH;
            return _z_push_decode(&msg->_body._push, zbf, *header, arcs, mapping);
        } break;
        case _Z_MID_N_REQUEST: {
            msg->_tag = _Z_N_REQUEST;
            return _z_request_decode(&msg->_body._request, zbf, *header, arcs, mapping);
        } break;
        case _Z_MID_N_RESPONSE: {
            msg->_tag = _Z_N_RESPONSE;
            return _z_response_decode(&msg->_body._response, zbf, *header, arcs, mapping);
        } break;
        case _Z_MID_N_RESPONSE_FINAL: {
            msg->_tag = _Z_N_RESPONSE_FINAL;
            return _z_response_final_decode(&msg->_body._response_final, zbf, *header);
        } break;
        case _Z_MID_N_INTEREST: {
            msg->_tag = _Z_N_INTEREST;
            return _z_n_interest_decode(&msg->_body._interest, zbf, *header, mapping);
        } break;
        case _Z_MID_N_OAM: {
            msg->_tag = _Z_N_OAM;
            return _z_oam_decode(&msg->_body._oam, zbf, *header);
        } break;
        default:
            _Z_INFO("Unknown message type received: %d", _Z_MID(*header));
            _Z_ERROR_RETURN(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
    }
}
