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

#include "zenoh-pico/protocol/definitions/message.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/protocol/codec.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/protocol/codec/ext.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/core.h"
#include "zenoh-pico/protocol/definitions/transport.h"
#include "zenoh-pico/protocol/ext.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/query_params.h"
#include "zenoh-pico/utils/result.h"

/*=============================*/
/*           Fields            */
/*=============================*/
/*------------------ Payload field ------------------*/
z_result_t _z_payload_encode(_z_wbuf_t *wbf, const _z_slice_t *pld) {
    z_result_t ret = _Z_RES_OK;
    _Z_DEBUG("Encoding _PAYLOAD");
    ret |= _z_slice_encode(wbf, pld);

    return ret;
}

z_result_t _z_payload_decode_na(_z_slice_t *pld, _z_zbuf_t *zbf) {
    _Z_DEBUG("Decoding _PAYLOAD");
    return _z_slice_decode(pld, zbf);
}

z_result_t _z_payload_decode(_z_slice_t *pld, _z_zbuf_t *zbf) { return _z_payload_decode_na(pld, zbf); }

z_result_t _z_id_encode_as_slice(_z_wbuf_t *wbf, const _z_id_t *id) {
    z_result_t ret = _Z_RES_OK;
    uint8_t len = _z_id_len(*id);

    if (len != 0) {
        _z_slice_t buf = _z_slice_alias_buf(id->id, len);
        ret = _z_slice_encode(wbf, &buf);
    } else {
        _Z_DEBUG("Attempted to encode invalid ID 0");
        _Z_ERROR_LOG(_Z_ERR_MESSAGE_ZENOH_UNKNOWN);
        ret = _Z_ERR_MESSAGE_ZENOH_UNKNOWN;
    }
    return ret;
}

/// Decodes a `zid` from the zbf, returning a negative value in case of error.
///
/// Note that while `_z_id_t` has an error state (full 0s), this function doesn't
/// guarantee that this state will be set in case of errors.
z_result_t _z_id_decode_as_slice(_z_id_t *id, _z_zbuf_t *zbf) {
    z_result_t ret = _Z_RES_OK;
    uint8_t len = _z_zbuf_read(zbf);
    _z_zbuf_read_bytes(zbf, id->id, 0, len);
    memset(id->id + len, 0, 16 - len);
    return ret;
}

/*------------------ Timestamp Field ------------------*/
z_result_t _z_timestamp_encode(_z_wbuf_t *wbf, const _z_timestamp_t *ts) {
    z_result_t ret = _Z_RES_OK;
    _Z_DEBUG("Encoding _TIMESTAMP");

    _Z_RETURN_IF_ERR(_z_zint64_encode(wbf, ts->time))
    ret |= _z_id_encode_as_slice(wbf, &ts->id);

    return ret;
}
z_result_t _z_timestamp_encode_ext(_z_wbuf_t *wbf, const _z_timestamp_t *ts) {
    // Encode extension size then timestamp
    size_t ext_size = (size_t)(_z_zint_len(ts->time) + 1 + _z_id_len(ts->id));
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, ext_size));
    return _z_timestamp_encode(wbf, ts);
}

z_result_t _z_timestamp_decode(_z_timestamp_t *ts, _z_zbuf_t *zbf) {
    _Z_DEBUG("Decoding _TIMESTAMP");
    z_result_t ret = _Z_RES_OK;

    ret |= _z_zint64_decode(&ts->time, zbf);
    ret |= _z_id_decode_as_slice(&ts->id, zbf);
    if (ret == _Z_RES_OK) {
        ts->valid = true;
    }
    return ret;
}

/*------------------ ResKey Field ------------------*/
z_result_t _z_wireexpr_encode(_z_wbuf_t *wbf, bool has_suffix, const _z_wireexpr_t *fld) {
    z_result_t ret = _Z_RES_OK;
    _Z_DEBUG("Encoding _RESKEY");

    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, fld->_id))
    if (has_suffix == true) {
        _Z_RETURN_IF_ERR(_z_string_encode(wbf, &fld->_suffix))
    }

    return ret;
}

z_result_t _z_wireexpr_decode(_z_wireexpr_t *ke, _z_zbuf_t *zbf, bool has_suffix, bool remote_mapping,
                              uintptr_t mapping) {
    _Z_DEBUG("Decoding _RESKEY");
    z_result_t ret = _Z_RES_OK;

    ret |= _z_zint16_decode(&ke->_id, zbf);
    ke->_mapping = (remote_mapping) ? mapping : _Z_KEYEXPR_MAPPING_LOCAL;
    if (has_suffix) {
        _z_string_t str = _z_string_null();
        ret |= _z_string_decode(&str, zbf);
        if (ret == _Z_RES_OK) {
            ke->_suffix = str;
        } else {
            ke->_suffix = _z_string_null();
        }
    } else {
        ke->_suffix = _z_string_null();
    }
    return ret;
}

/*------------------ Locators Field ------------------*/
z_result_t _z_locators_encode(_z_wbuf_t *wbf, const _z_locator_array_t *la) {
    z_result_t ret = _Z_RES_OK;
    _Z_DEBUG("Encoding _LOCATORS");
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, la->_len))
    for (size_t i = 0; i < la->_len; i++) {
        _z_string_t s = _z_locator_to_string(&la->_val[i]);
        _Z_RETURN_IF_ERR(_z_string_encode(wbf, &s))
        _z_string_clear(&s);
    }

    return ret;
}

z_result_t _z_locators_decode_na(_z_locator_array_t *a_loc, _z_zbuf_t *zbf) {
    _Z_DEBUG("Decoding _LOCATORS");
    z_result_t ret = _Z_RES_OK;

    _z_zint_t len = 0;  // Number of elements in the array
    ret |= _z_zsize_decode(&len, zbf);
    if (ret == _Z_RES_OK) {
        *a_loc = _z_locator_array_make(len);

        // Decode the elements
        for (size_t i = 0; i < len; i++) {
            _z_string_t str = _z_string_null();
            ret |= _z_string_decode(&str, zbf);
            if (ret == _Z_RES_OK) {
                _z_locator_init(&a_loc->_val[i]);
                ret |= _z_locator_from_string(&a_loc->_val[i], &str);
                _z_string_clear(&str);
            } else {
                a_loc->_len = i;
            }
        }
    } else {
        *a_loc = _z_locator_array_make(0);
    }

    return ret;
}

z_result_t _z_locators_decode(_z_locator_array_t *a_loc, _z_zbuf_t *zbf) { return _z_locators_decode_na(a_loc, zbf); }

/*=============================*/
/*        Zenoh Messages       */
/*=============================*/

z_result_t _z_source_info_decode(_z_source_info_t *info, _z_zbuf_t *zbf) {
    uint8_t zidlen = 0;
    _z_zint_t intbuf;
    z_result_t ret = _z_uint8_decode(&zidlen, zbf);
    if (ret == _Z_RES_OK) {
        zidlen = (zidlen >> 4) + 1;
        if (_z_zbuf_len(zbf) >= zidlen) {
            memset(info->_source_id.zid.id, 0, sizeof(info->_source_id.zid.id) / sizeof(info->_source_id.zid.id[0]));
            _z_zbuf_read_bytes(zbf, info->_source_id.zid.id, 0, zidlen);
        } else {
            _Z_INFO("Not enough bytes to read");
            _Z_ERROR_LOG(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
            ret = _Z_ERR_MESSAGE_DESERIALIZATION_FAILED;
        }
    }
    if (ret == _Z_RES_OK) {
        ret = _z_zsize_decode(&intbuf, zbf);
        if (intbuf <= UINT32_MAX) {
            info->_source_id.eid = (uint32_t)intbuf;
        } else {
            _Z_INFO("Invalid value decoded");
            _Z_ERROR_LOG(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
            ret = _Z_ERR_MESSAGE_DESERIALIZATION_FAILED;
        }
    }
    if (ret == _Z_RES_OK) {
        ret = _z_zsize_decode(&intbuf, zbf);
        if (intbuf <= UINT32_MAX) {
            info->_source_sn = (uint32_t)intbuf;
        } else {
            _Z_INFO("Invalid value decoded");
            _Z_ERROR_LOG(_Z_ERR_MESSAGE_DESERIALIZATION_FAILED);
            ret = _Z_ERR_MESSAGE_DESERIALIZATION_FAILED;
        }
    }
    return ret;
}
z_result_t _z_source_info_encode(_z_wbuf_t *wbf, const _z_source_info_t *info) {
    z_result_t ret = 0;
    uint8_t zidlen = _z_id_len(info->_source_id.zid);
    ret |= _z_uint8_encode(wbf, (uint8_t)((zidlen - 1) << 4));
    _z_slice_t zid = _z_slice_alias_buf(info->_source_id.zid.id, zidlen);
    ret |= _z_slice_val_encode(wbf, &zid);
    ret |= _z_zsize_encode(wbf, info->_source_id.eid);
    ret |= _z_zsize_encode(wbf, info->_source_sn);
    return ret;
}
z_result_t _z_source_info_encode_ext(_z_wbuf_t *wbf, const _z_source_info_t *info) {
    z_result_t ret = 0;
    uint8_t zidlen = _z_id_len(info->_source_id.zid);
    size_t ext_size = 1u + zidlen + _z_zint_len(info->_source_id.eid) + _z_zint_len(info->_source_sn);
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, ext_size));
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, (uint8_t)((zidlen - 1) << 4)));
    _z_slice_t zid = _z_slice_alias_buf(info->_source_id.zid.id, zidlen);
    _Z_RETURN_IF_ERR(_z_slice_val_encode(wbf, &zid));
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, info->_source_id.eid));
    _Z_RETURN_IF_ERR(_z_zsize_encode(wbf, info->_source_sn));
    return ret;
}

/*------------------ Push Body Field ------------------*/
z_result_t _z_push_body_encode(_z_wbuf_t *wbf, const _z_push_body_t *pshb) {
    uint8_t header = pshb->_is_put ? _Z_MID_Z_PUT : _Z_MID_Z_DEL;
    bool has_source_info = _z_id_check(pshb->_body._put._commons._source_info._source_id.zid) ||
                           pshb->_body._put._commons._source_info._source_sn != 0 ||
                           pshb->_body._put._commons._source_info._source_id.eid != 0;

    bool has_attachment = pshb->_is_put && _z_bytes_check(&pshb->_body._put._attachment);
    bool has_timestamp = _z_timestamp_check(&pshb->_body._put._commons._timestamp);
    bool has_encoding = false;
    if (has_source_info || has_attachment) {
        header |= _Z_FLAG_Z_Z;
    }
    if (pshb->_is_put) {
        if (has_timestamp) {
            header |= _Z_FLAG_Z_P_T;
        }
        has_encoding = _z_encoding_check(&pshb->_body._put._encoding);
        if (has_encoding) {
            header |= _Z_FLAG_Z_P_E;
        }
    } else {
        if (has_timestamp) {
            header |= _Z_FLAG_Z_D_T;
        }
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    if (has_timestamp) {
        _Z_RETURN_IF_ERR(_z_timestamp_encode(wbf, &pshb->_body._put._commons._timestamp));
    }

    if (has_encoding) {
        _Z_RETURN_IF_ERR(_z_encoding_encode(wbf, &pshb->_body._put._encoding));
    }

    if (has_source_info) {
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, _Z_MSG_EXT_ENC_ZBUF | 0x01 | (has_attachment ? _Z_FLAG_Z_Z : 0)));
        _Z_RETURN_IF_ERR(_z_source_info_encode_ext(wbf, &pshb->_body._put._commons._source_info));
    }
    if (has_attachment) {
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, _Z_MSG_EXT_ENC_ZBUF | 0x03));
        _Z_RETURN_IF_ERR(_z_bytes_encode(wbf, &pshb->_body._put._attachment));
    }
    if (pshb->_is_put) {
        _Z_RETURN_IF_ERR(_z_bytes_encode(wbf, &pshb->_body._put._payload));
    }

    return _Z_RES_OK;
}
z_result_t _z_push_body_decode_extensions(_z_msg_ext_t *extension, void *ctx) {
    _z_push_body_t *pshb = (_z_push_body_t *)ctx;
    z_result_t ret = _Z_RES_OK;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case _Z_MSG_EXT_ENC_ZBUF | 0x01: {
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            ret = _z_source_info_decode(&pshb->_body._put._commons._source_info, &zbf);
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x03: {  // Attachment
            _z_slice_t s;
            if (_z_slice_is_alloced(&extension->_body._zbuf._val)) {
                s = _z_slice_steal(&extension->_body._zbuf._val);
            } else {
                _Z_RETURN_IF_ERR(_z_slice_copy(&s, &extension->_body._zbuf._val));
            }
            ret = _z_bytes_from_slice(&pshb->_body._put._attachment, &s);
            break;
        }
        default:
            if (_Z_HAS_FLAG(extension->_header, _Z_MSG_EXT_FLAG_M)) {
                ret = _z_msg_ext_unknown_error(extension, 0x08);
            }
    }
    return ret;
}

z_result_t _z_push_body_decode(_z_push_body_t *pshb, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs) {
    z_result_t ret = _Z_RES_OK;
    switch (_Z_MID(header)) {
        case _Z_MID_Z_PUT: {
            pshb->_is_put = true;
            if (_Z_HAS_FLAG(header, _Z_FLAG_Z_P_T)) {
                _Z_RETURN_IF_ERR(_z_timestamp_decode(&pshb->_body._put._commons._timestamp, zbf));
            }
            if ((ret == _Z_RES_OK) && _Z_HAS_FLAG(header, _Z_FLAG_Z_P_E)) {
                _Z_RETURN_IF_ERR(_z_encoding_decode(&pshb->_body._put._encoding, zbf));
            }
            if ((ret == _Z_RES_OK) && _Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
                _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_push_body_decode_extensions, pshb));
            }
            if (ret == _Z_RES_OK) {
                _Z_RETURN_IF_ERR(_z_bytes_decode(&pshb->_body._put._payload, zbf, arcs));
            }
            break;
        }
        case _Z_MID_Z_DEL: {
            pshb->_is_put = false;
            if (_Z_HAS_FLAG(header, _Z_FLAG_Z_D_T)) {
                _Z_RETURN_IF_ERR(_z_timestamp_decode(&pshb->_body._put._commons._timestamp, zbf));
            }
            if ((ret == _Z_RES_OK) && _Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
                _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_push_body_decode_extensions, pshb));
            }
            break;
        }
        default: {
            _Z_ERROR_LOG(_Z_ERR_MESSAGE_ZENOH_UNKNOWN);
            ret = _Z_ERR_MESSAGE_ZENOH_UNKNOWN;
        }
    }
    return ret;
}

z_result_t _z_put_encode(_z_wbuf_t *wbf, const _z_msg_put_t *put) {
    _z_push_body_t body = {._is_put = true, ._body = {._put = *put}};
    return _z_push_body_encode(wbf, &body);
}
z_result_t _z_put_decode(_z_msg_put_t *put, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs) {
    assert(_Z_MID(header) == _Z_MID_Z_PUT);
    _z_push_body_t body = {._is_put = true, ._body = {._put = *put}};
    z_result_t ret = _z_push_body_decode(&body, zbf, header, arcs);
    *put = body._body._put;
    return ret;
}

z_result_t _z_del_encode(_z_wbuf_t *wbf, const _z_msg_del_t *del) {
    _z_push_body_t body = {._is_put = false, ._body = {._del = *del}};
    return _z_push_body_encode(wbf, &body);
}
z_result_t _z_del_decode(_z_msg_del_t *del, _z_zbuf_t *zbf, uint8_t header) {
    assert(_Z_MID(header) == _Z_MID_Z_DEL);
    _z_push_body_t body = {._is_put = false, ._body = {._del = *del}};
    z_result_t ret = _z_push_body_decode(&body, zbf, header, NULL);
    *del = body._body._del;
    return ret;
}

/*------------------ Query Message ------------------*/
z_result_t _z_query_encode(_z_wbuf_t *wbf, const _z_msg_query_t *msg) {
    z_result_t ret = _Z_RES_OK;
    uint8_t header = _Z_MID_Z_QUERY;

    bool has_params = _z_slice_check(&msg->_parameters) && msg->_parameters.len > 0;
    if (has_params || msg->_implicit_anyke) {
        _Z_SET_FLAG(header, _Z_FLAG_Z_Q_P);
    }
    bool has_consolidation = (msg->_consolidation != Z_CONSOLIDATION_MODE_DEFAULT);
    if (has_consolidation) {
        _Z_SET_FLAG(header, _Z_FLAG_Z_Q_C);
    }
    _z_msg_query_reqexts_t required_exts = _z_msg_query_required_extensions(msg);
    if (required_exts.body || required_exts.info || required_exts.attachment) {
        header |= _Z_FLAG_Z_Z;
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    if (has_consolidation) {
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, msg->_consolidation));
    }
    if (msg->_implicit_anyke) {
        if (has_params) {
            _z_slice_t anykey_slice = _z_slice_from_buf_custom_deleter(
                (uint8_t *)_Z_QUERY_PARAMS_LIST_SEPARATOR _Z_QUERY_PARAMS_KEY_ANYKE,
                _Z_QUERY_PARAMS_LIST_SEPARATOR_LEN + _Z_QUERY_PARAMS_KEY_ANYKE_LEN, _z_delete_context_static());
            _z_slice_t combined[2] = {msg->_parameters, anykey_slice};
            _Z_RETURN_IF_ERR(_z_slices_encode(wbf, combined, 2));
        } else {
            _z_slice_t anykey_slice = _z_slice_from_buf_custom_deleter(
                (uint8_t *)_Z_QUERY_PARAMS_KEY_ANYKE, _Z_QUERY_PARAMS_KEY_ANYKE_LEN, _z_delete_context_static());
            _Z_RETURN_IF_ERR(_z_slice_encode(wbf, &anykey_slice));
        }
    } else if (has_params) {
        _Z_RETURN_IF_ERR(_z_slice_encode(wbf, &msg->_parameters));
    }

    if (required_exts.body) {
        uint8_t extheader = _Z_MSG_EXT_ENC_ZBUF | 0x03;
        if (required_exts.info || required_exts.attachment) {
            extheader |= _Z_FLAG_Z_Z;
        }
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_value_encode(wbf, &msg->_ext_value));
    }
    if (required_exts.info) {
        uint8_t extheader = _Z_MSG_EXT_ENC_ZBUF | 0x01;
        if (required_exts.attachment) {
            extheader |= _Z_FLAG_Z_Z;
        }
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_source_info_encode_ext(wbf, &msg->_ext_info));
    }
    if (required_exts.attachment) {
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, _Z_MSG_EXT_ENC_ZBUF | 0x05));
        _Z_RETURN_IF_ERR(_z_bytes_encode(wbf, &msg->_ext_attachment));
    }
    return ret;
}

z_result_t _z_query_decode_extensions(_z_msg_ext_t *extension, void *ctx) {
    _z_msg_query_t *msg = (_z_msg_query_t *)ctx;
    z_result_t ret = _Z_RES_OK;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case _Z_MSG_EXT_ENC_ZBUF | 0x01: {  // Source Info
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            ret = _z_source_info_decode(&msg->_ext_info, &zbf);
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x03: {  // Payload
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            ret = _z_value_decode(&msg->_ext_value, &zbf);
            break;
        }
        case _Z_MSG_EXT_ENC_ZBUF | 0x05: {  // Attachment
            _z_slice_t s;
            if (_z_slice_is_alloced(&extension->_body._zbuf._val)) {
                s = _z_slice_steal(&extension->_body._zbuf._val);
            } else {
                _Z_RETURN_IF_ERR(_z_slice_copy(&s, &extension->_body._zbuf._val));
            }
            ret = _z_bytes_from_slice(&msg->_ext_attachment, &s);
            break;
        }
        default:
            if (_Z_HAS_FLAG(extension->_header, _Z_MSG_EXT_FLAG_M)) {
                ret = _z_msg_ext_unknown_error(extension, 0x09);
            }
    }
    return ret;
}

z_result_t _z_query_decode(_z_msg_query_t *msg, _z_zbuf_t *zbf, uint8_t header) {
    _Z_DEBUG("Decoding _Z_MID_Z_QUERY");
    z_result_t ret = _Z_RES_OK;
    msg->_implicit_anyke = false;
    // implicit_anyke is always false on reception, since the presence of the _anyke parameter is signaled by
    // the presence of the _anyke key in the parameters list, which is parsed later.
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Q_C)) {
        _Z_RETURN_IF_ERR(_z_uint8_decode((uint8_t *)&msg->_consolidation, zbf));
    } else {
        msg->_consolidation = Z_CONSOLIDATION_MODE_DEFAULT;
    }
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Q_P)) {
        _Z_RETURN_IF_ERR(_z_slice_decode(&msg->_parameters, zbf));
    } else {
        _z_slice_clear(&msg->_parameters);
    }
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_query_decode_extensions, msg));
    }
    return ret;
}

z_result_t _z_reply_encode(_z_wbuf_t *wbf, const _z_msg_reply_t *reply) {
    uint8_t header = _Z_MID_Z_REPLY;
    bool has_consolidation = reply->_consolidation != Z_CONSOLIDATION_MODE_DEFAULT;
    if (has_consolidation) {
        _Z_SET_FLAG(header, _Z_FLAG_Z_R_C);
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    if (has_consolidation) {
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, reply->_consolidation));
    }
    _Z_RETURN_IF_ERR(_z_push_body_encode(wbf, &reply->_body));
    return _Z_RES_OK;
}
z_result_t _z_reply_decode_extension(_z_msg_ext_t *extension, void *ctx) {
    _ZP_UNUSED(ctx);
    z_result_t ret = _Z_RES_OK;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        default:
            ret = _z_msg_ext_unknown_error(extension, 0x0a);
            break;
    }
    return ret;
}
z_result_t _z_reply_decode(_z_msg_reply_t *reply, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs) {
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_R_C)) {
        _Z_RETURN_IF_ERR(_z_uint8_decode((uint8_t *)&reply->_consolidation, zbf));
    } else {
        reply->_consolidation = Z_CONSOLIDATION_MODE_DEFAULT;
    }
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_reply_decode_extension, reply));
    }
    uint8_t put_header = 0;
    _Z_RETURN_IF_ERR(_z_uint8_decode(&put_header, zbf));
    _Z_RETURN_IF_ERR(_z_push_body_decode(&reply->_body, zbf, put_header, arcs));
    return _Z_RES_OK;
}

z_result_t _z_err_encode(_z_wbuf_t *wbf, const _z_msg_err_t *err) {
    z_result_t ret = _Z_RES_OK;
    uint8_t header = _Z_MID_Z_ERR;

    // Encode header
    bool has_encoding = _z_encoding_check(&err->_encoding);
    if (has_encoding) {
        _Z_SET_FLAG(header, _Z_FLAG_Z_E_E);
    }
    bool has_sinfo_ext = _z_id_check(err->_ext_source_info._source_id.zid) ||
                         err->_ext_source_info._source_id.eid != 0 || err->_ext_source_info._source_sn != 0;
    if (has_sinfo_ext) {
        _Z_SET_FLAG(header, _Z_FLAG_Z_Z);
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, header));
    // Encode encoding
    if (has_encoding) {
        _Z_RETURN_IF_ERR(_z_encoding_encode(wbf, &err->_encoding));
    }
    // Encode extensions
    if (has_sinfo_ext) {
        uint8_t extheader = _Z_MSG_EXT_ENC_ZBUF | 0x01;
        _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, extheader));
        _Z_RETURN_IF_ERR(_z_source_info_encode_ext(wbf, &err->_ext_source_info));
    }
    // Encode payload
    _Z_RETURN_IF_ERR(_z_bytes_encode(wbf, &err->_payload));
    return ret;
}
z_result_t _z_err_decode_extension(_z_msg_ext_t *extension, void *ctx) {
    z_result_t ret = _Z_RES_OK;
    _z_msg_err_t *reply = (_z_msg_err_t *)ctx;
    switch (_Z_EXT_FULL_ID(extension->_header)) {
        case _Z_MSG_EXT_ENC_ZBUF | 0x01: {
            _z_zbuf_t zbf = _z_slice_as_zbuf(extension->_body._zbuf._val);
            ret = _z_source_info_decode(&reply->_ext_source_info, &zbf);
            break;
        }
        default:
            if (_Z_HAS_FLAG(extension->_header, _Z_MSG_EXT_FLAG_M)) {
                ret = _z_msg_ext_unknown_error(extension, 0x0a);
            }
    }
    return ret;
}
z_result_t _z_err_decode(_z_msg_err_t *err, _z_zbuf_t *zbf, uint8_t header, _z_arc_slice_t *arcs) {
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_E_E)) {
        _Z_RETURN_IF_ERR(_z_encoding_decode(&err->_encoding, zbf));
    }
    if (_Z_HAS_FLAG(header, _Z_FLAG_Z_Z)) {
        _Z_RETURN_IF_ERR(_z_msg_ext_decode_iter(zbf, _z_err_decode_extension, err));
    }
    _Z_RETURN_IF_ERR(_z_bytes_decode(&err->_payload, zbf, arcs));
    return _Z_RES_OK;
}

/*=============================*/
/*       Scouting Messages     */
/*=============================*/
/*------------------ Scout Message ------------------*/
z_result_t _z_scout_encode(_z_wbuf_t *wbf, uint8_t header, const _z_s_msg_scout_t *msg) {
    z_result_t ret = _Z_RES_OK;
    (void)(header);
    _Z_DEBUG("Encoding _Z_MID_SCOUT");

    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, msg->_version))

    uint8_t cbyte = msg->_what & 0x07;
    uint8_t zid_len = _z_id_len(msg->_zid);
    if (zid_len > 0) {
        _Z_SET_FLAG(cbyte, _Z_FLAG_T_SCOUT_I);
        cbyte |= (uint8_t)(((zid_len - 1) & 0x0F) << 4);
    }
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, cbyte))

    ret |= _z_wbuf_write_bytes(wbf, msg->_zid.id, 0, zid_len);

    return ret;
}

z_result_t _z_scout_decode(_z_s_msg_scout_t *msg, _z_zbuf_t *zbf, uint8_t header) {
    z_result_t ret = _Z_RES_OK;
    (void)(header);
    _Z_DEBUG("Decoding _Z_MID_SCOUT");
    *msg = (_z_s_msg_scout_t){0};

    ret |= _z_uint8_decode(&msg->_version, zbf);

    uint8_t cbyte = 0;
    ret |= _z_uint8_decode(&cbyte, zbf);
    msg->_what = cbyte & 0x07;
    msg->_zid = _z_id_empty();
    if ((ret == _Z_RES_OK) && (_Z_HAS_FLAG(cbyte, _Z_FLAG_T_SCOUT_I) == true)) {
        uint8_t zidlen = ((cbyte & 0xF0) >> 4) + (uint8_t)1;
        _z_zbuf_read_bytes(zbf, msg->_zid.id, 0, zidlen);
    }

    return ret;
}

/*------------------ Hello Message ------------------*/
z_result_t _z_hello_encode(_z_wbuf_t *wbf, uint8_t header, const _z_s_msg_hello_t *msg) {
    z_result_t ret = _Z_RES_OK;
    _Z_DEBUG("Encoding _Z_MID_HELLO");

    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, msg->_version))
    uint8_t zidlen = _z_id_len(msg->_zid);
    uint8_t cbyte = 0;
    cbyte |= _z_whatami_to_uint8(msg->_whatami);
    cbyte |= (uint8_t)(((zidlen - 1) & 0x0F) << 4);
    _Z_RETURN_IF_ERR(_z_uint8_encode(wbf, cbyte))
    _z_slice_t s = _z_slice_alias_buf(msg->_zid.id, zidlen);
    _Z_RETURN_IF_ERR(_z_slice_val_encode(wbf, &s));

    if (_Z_HAS_FLAG(header, _Z_FLAG_T_HELLO_L) == true) {
        _Z_RETURN_IF_ERR(_z_locators_encode(wbf, &msg->_locators))
    }

    return ret;
}

z_result_t _z_hello_decode_na(_z_s_msg_hello_t *msg, _z_zbuf_t *zbf, uint8_t header) {
    _Z_DEBUG("Decoding _Z_MID_HELLO");
    z_result_t ret = _Z_RES_OK;
    *msg = (_z_s_msg_hello_t){0};

    ret |= _z_uint8_decode(&msg->_version, zbf);

    uint8_t cbyte = 0;
    ret |= _z_uint8_decode(&cbyte, zbf);
    msg->_whatami = _z_whatami_from_uint8(cbyte);
    uint8_t zidlen = ((cbyte & 0xF0) >> 4) + (uint8_t)1;

    if (ret == _Z_RES_OK) {
        msg->_zid = _z_id_empty();
        _z_zbuf_read_bytes(zbf, msg->_zid.id, 0, zidlen);
    } else {
        msg->_zid = _z_id_empty();
    }

    if ((ret == _Z_RES_OK) && (_Z_HAS_FLAG(header, _Z_FLAG_T_HELLO_L) == true)) {
        ret |= _z_locators_decode(&msg->_locators, zbf);
        if (ret != _Z_RES_OK) {
            msg->_locators = _z_locator_array_empty();
        }
    } else {
        msg->_locators = _z_locator_array_empty();
    }

    return ret;
}

z_result_t _z_hello_decode(_z_s_msg_hello_t *msg, _z_zbuf_t *zbf, uint8_t header) {
    return _z_hello_decode_na(msg, zbf, header);
}

z_result_t _z_scouting_message_encode(_z_wbuf_t *wbf, const _z_scouting_message_t *msg) {
    z_result_t ret = _Z_RES_OK;

    uint8_t header = msg->_header;

    _Z_RETURN_IF_ERR(_z_wbuf_write(wbf, header))
    switch (_Z_MID(msg->_header)) {
        case _Z_MID_SCOUT: {
            ret |= _z_scout_encode(wbf, msg->_header, &msg->_body._scout);
        } break;

        case _Z_MID_HELLO: {
            ret |= _z_hello_encode(wbf, msg->_header, &msg->_body._hello);
        } break;

        default: {
            _Z_INFO("WARNING: Trying to encode session message with unknown ID(%d)", _Z_MID(msg->_header));
            ret |= _Z_ERR_MESSAGE_TRANSPORT_UNKNOWN;
        } break;
    }

    return ret;
}
z_result_t _z_scouting_message_decode_na(_z_scouting_message_t *msg, _z_zbuf_t *zbf) {
    z_result_t ret = _Z_RES_OK;
    *msg = (_z_scouting_message_t){0};

    bool is_last = false;

    do {
        ret |= _z_uint8_decode(&msg->_header, zbf);  // Decode the header
        if (ret == _Z_RES_OK) {
            uint8_t mid = _Z_MID(msg->_header);
            switch (mid) {
                case _Z_MID_SCOUT: {
                    ret |= _z_scout_decode(&msg->_body._scout, zbf, msg->_header);
                    is_last = true;
                } break;

                case _Z_MID_HELLO: {
                    ret |= _z_hello_decode(&msg->_body._hello, zbf, msg->_header);
                    is_last = true;
                } break;

                default: {
                    _Z_INFO("WARNING: Trying to decode scouting message with unknown ID(0x%x)", mid);
                    ret |= _Z_ERR_MESSAGE_TRANSPORT_UNKNOWN;
                    is_last = true;
                } break;
            }
        } else {
            msg->_header = 0xFF;
        }
    } while ((ret == _Z_RES_OK) && (is_last == false));

    if ((ret == _Z_RES_OK) && (msg->_header & _Z_MSG_EXT_FLAG_Z) != 0) {
        ret |= _z_msg_ext_skip_non_mandatories(zbf, 0x06);
    }

    return ret;
}

z_result_t _z_scouting_message_decode(_z_scouting_message_t *s_msg, _z_zbuf_t *zbf) {
    return _z_scouting_message_decode_na(s_msg, zbf);
}
