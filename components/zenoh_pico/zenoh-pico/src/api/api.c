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
//   Błażej Sowa, <blazej@fictionlab.pl>

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "zenoh-pico/api/admin_space.h"
#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/api/olv_macros.h"
#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/collections/advanced_cache.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/net/config.h"
#include "zenoh-pico/net/filtering.h"
#include "zenoh-pico/net/logger.h"
#include "zenoh-pico/net/matching.h"
#include "zenoh-pico/net/primitives.h"
#include "zenoh-pico/net/sample.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/interest.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/queryable.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/subscription.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/multicast.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast.h"
#include "zenoh-pico/utils/config.h"
#include "zenoh-pico/utils/endianness.h"
#include "zenoh-pico/utils/locality.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"
#include "zenoh-pico/utils/result.h"
#include "zenoh-pico/utils/uuid.h"

/********* Data Types Handlers *********/

z_result_t z_view_string_from_str(z_view_string_t *str, const char *value) {
    str->_val = _z_string_alias_str((char *)value);
    return _Z_RES_OK;
}

z_result_t z_view_string_from_substr(z_view_string_t *str, const char *value, size_t len) {
    str->_val = _z_string_alias_substr((char *)value, len);
    return _Z_RES_OK;
}

_z_string_svec_t _z_string_array_null(void) { return _z_string_svec_make(0); }

void z_string_array_new(z_owned_string_array_t *a) { a->_val = _z_string_array_null(); }

size_t z_string_array_push_by_alias(z_loaned_string_array_t *a, const z_loaned_string_t *value) {
    _z_string_t str = _z_string_alias(*value);
    _z_string_svec_append(a, &str, true);

    return _z_string_svec_len(a);
}

size_t z_string_array_push_by_copy(z_loaned_string_array_t *a, const z_loaned_string_t *value) {
    _z_string_t str;
    _z_string_copy(&str, value);
    _z_string_svec_append(a, &str, true);

    return _z_string_svec_len(a);
}

const z_loaned_string_t *z_string_array_get(const z_loaned_string_array_t *a, size_t k) {
    return _z_string_svec_get(a, k);
}

size_t z_string_array_len(const z_loaned_string_array_t *a) { return _z_string_svec_len(a); }

bool z_string_array_is_empty(const z_loaned_string_array_t *a) { return _z_string_svec_is_empty(a); }

z_result_t z_keyexpr_is_canon(const char *start, size_t len) { return _z_keyexpr_is_canon(start, len); }

z_result_t z_keyexpr_canonize(char *start, size_t *len) { return _z_keyexpr_canonize(start, len); }

z_result_t z_keyexpr_canonize_null_terminated(char *start) {
    size_t len = (start != NULL) ? strlen(start) : 0;
    z_result_t res = _z_keyexpr_canonize(start, &len);
    if (res == _Z_RES_OK) {
        start[len] = '\0';
    }
    return res;
}

void z_view_keyexpr_from_str_unchecked(z_view_keyexpr_t *keyexpr, const char *name) {
    // SAFETY: Documentation specifies that string should be null-terminated.
    // Flawfinder: ignore [CWE-126]
    keyexpr->_val = _z_declared_keyexpr_alias_from_substr(name, strlen(name));
}

z_result_t z_view_keyexpr_from_substr(z_view_keyexpr_t *keyexpr, const char *name, size_t len) {
    if (_z_keyexpr_is_canon(name, len) != Z_KEYEXPR_CANON_SUCCESS) {
        return Z_EINVAL;
    }
    keyexpr->_val = _z_declared_keyexpr_alias_from_substr(name, len);
    return _Z_RES_OK;
}

z_result_t z_view_keyexpr_from_str(z_view_keyexpr_t *keyexpr, const char *name) {
    size_t name_len = strlen(name);
    return z_view_keyexpr_from_substr(keyexpr, name, name_len);
}

z_result_t z_view_keyexpr_from_substr_autocanonize(z_view_keyexpr_t *keyexpr, char *name, size_t *len) {
    _Z_RETURN_IF_ERR(z_keyexpr_canonize(name, len));
    keyexpr->_val = _z_declared_keyexpr_alias_from_substr(name, *len);
    return _Z_RES_OK;
}

z_result_t z_view_keyexpr_from_str_autocanonize(z_view_keyexpr_t *keyexpr, char *name) {
    size_t name_len = strlen(name);
    return z_view_keyexpr_from_substr_autocanonize(keyexpr, name, &name_len);
}

void z_view_keyexpr_from_substr_unchecked(z_view_keyexpr_t *keyexpr, const char *name, size_t len) {
    keyexpr->_val = _z_declared_keyexpr_alias_from_substr(name, len);
}

z_result_t z_keyexpr_as_view_string(const z_loaned_keyexpr_t *keyexpr, z_view_string_t *s) {
    s->_val = _z_string_alias(keyexpr->_inner._keyexpr);
    return _Z_RES_OK;
}

z_result_t z_keyexpr_concat(z_owned_keyexpr_t *key, const z_loaned_keyexpr_t *left, const char *right, size_t len) {
    return _z_declared_keyexpr_concat(&key->_val, left, right, len);
}

z_result_t z_keyexpr_join(z_owned_keyexpr_t *key, const z_loaned_keyexpr_t *left, const z_loaned_keyexpr_t *right) {
    return _z_declared_keyexpr_join(&key->_val, left, right);
}

z_result_t _z_keyexpr_append_suffix(z_owned_keyexpr_t *prefix, const z_loaned_keyexpr_t *right) {
    z_owned_keyexpr_t tmp;
    if (_z_string_len(&prefix->_val._inner._keyexpr) == 0) {
        if (_z_string_len(&right->_inner._keyexpr) == 0) {
            _Z_ERROR_RETURN(_Z_ERR_INVALID);
        }
        return z_keyexpr_clone(prefix, right);
    }
    _Z_RETURN_IF_ERR(z_keyexpr_join(&tmp, z_keyexpr_loan(prefix), right));
    _z_declared_keyexpr_clear(&prefix->_val);
    z_keyexpr_take(prefix, z_keyexpr_move(&tmp));
    return _Z_RES_OK;
}

z_result_t _z_keyexpr_append_substr(z_owned_keyexpr_t *prefix, const char *right, size_t len) {
    z_view_keyexpr_t ke_right;
    z_view_keyexpr_from_substr_unchecked(&ke_right, right, len);
    return _z_keyexpr_append_suffix(prefix, z_view_keyexpr_loan(&ke_right));
}

z_result_t _z_keyexpr_append_str_array(z_owned_keyexpr_t *prefix, const char *strs[], size_t count) {
    for (size_t i = 0; i < count; ++i) {
        fflush(stdout);
        _Z_RETURN_IF_ERR(_z_keyexpr_append_str(prefix, strs[i]));
    }
    return _Z_RES_OK;
}

z_keyexpr_intersection_level_t z_keyexpr_relation_to(const z_loaned_keyexpr_t *left, const z_loaned_keyexpr_t *right) {
    if (z_keyexpr_equals(left, right)) {
        return Z_KEYEXPR_INTERSECTION_LEVEL_EQUALS;
    } else if (z_keyexpr_includes(left, right)) {
        return Z_KEYEXPR_INTERSECTION_LEVEL_INCLUDES;
    } else if (z_keyexpr_intersects(left, right)) {
        return Z_KEYEXPR_INTERSECTION_LEVEL_INTERSECTS;
    }
    return Z_KEYEXPR_INTERSECTION_LEVEL_DISJOINT;
}

bool z_keyexpr_includes(const z_loaned_keyexpr_t *l, const z_loaned_keyexpr_t *r) {
    return _z_declared_keyexpr_includes(l, r);
}

bool z_keyexpr_intersects(const z_loaned_keyexpr_t *l, const z_loaned_keyexpr_t *r) {
    return _z_declared_keyexpr_intersects(l, r);
}

bool z_keyexpr_equals(const z_loaned_keyexpr_t *l, const z_loaned_keyexpr_t *r) {
    return _z_declared_keyexpr_equals(l, r);
}

z_result_t z_config_default(z_owned_config_t *config) { return _z_config_default(&config->_val); }

const char *zp_config_get(const z_loaned_config_t *config, uint8_t key) { return _z_config_get(config, key); }

z_result_t zp_config_insert(z_loaned_config_t *config, uint8_t key, const char *value) {
    return _zp_config_insert(config, key, value);
}

_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_encoding_t, encoding, _z_encoding_check, _z_encoding_null, _z_encoding_copy,
                              _z_encoding_move, _z_encoding_clear)

bool z_encoding_equals(const z_loaned_encoding_t *left, const z_loaned_encoding_t *right) {
    return left->id == right->id && _z_string_equals(&left->schema, &right->schema);
}

z_result_t z_slice_copy_from_buf(z_owned_slice_t *slice, const uint8_t *data, size_t len) {
    slice->_val = _z_slice_copy_from_buf(data, len);
    if (slice->_val.start == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    } else {
        return _Z_RES_OK;
    }
}

z_result_t z_slice_from_buf(z_owned_slice_t *slice, uint8_t *data, size_t len,
                            void (*deleter)(void *data, void *context), void *context) {
    slice->_val = _z_slice_from_buf_custom_deleter(data, len, _z_delete_context_create(deleter, context));
    return _Z_RES_OK;
}

z_result_t z_view_slice_from_buf(z_view_slice_t *slice, const uint8_t *data, size_t len) {
    slice->_val = _z_slice_alias_buf(data, len);
    return _Z_RES_OK;
}

const uint8_t *z_slice_data(const z_loaned_slice_t *slice) { return slice->start; }

size_t z_slice_len(const z_loaned_slice_t *slice) { return slice->len; }

void z_slice_empty(z_owned_slice_t *slice) { slice->_val = _z_slice_null(); }

bool z_slice_is_empty(const z_loaned_slice_t *slice) { return _z_slice_is_empty(slice); }

z_result_t z_bytes_to_slice(const z_loaned_bytes_t *bytes, z_owned_slice_t *dst) {
    dst->_val = _z_slice_null();
    return _z_bytes_to_slice(bytes, &dst->_val);
}

z_result_t z_bytes_to_string(const z_loaned_bytes_t *bytes, z_owned_string_t *s) {
    // Init owned string
    z_internal_string_null(s);
    // Convert bytes to string
    size_t len = _z_bytes_len(bytes);
    if (len == 0) {
        return _Z_RES_OK;
    }
    s->_val = _z_string_preallocate(len);
    if (_z_string_len(&s->_val) != len) _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    _z_bytes_to_buf(bytes, (uint8_t *)_z_string_data(&s->_val), len);
    return _Z_RES_OK;
}

z_result_t z_bytes_from_slice(z_owned_bytes_t *bytes, z_moved_slice_t *slice) {
    z_bytes_empty(bytes);
    _z_slice_t s = _z_slice_steal(&slice->_this._val);
    _Z_CLEAN_RETURN_IF_ERR(_z_bytes_from_slice(&bytes->_val, &s), _z_slice_clear(&s));
    return _Z_RES_OK;
}

z_result_t z_bytes_from_buf(z_owned_bytes_t *bytes, uint8_t *data, size_t len,
                            void (*deleter)(void *data, void *context), void *context) {
    z_owned_slice_t s;
    s._val = _z_slice_from_buf_custom_deleter(data, len, _z_delete_context_create(deleter, context));
    return z_bytes_from_slice(bytes, z_slice_move(&s));
}

z_result_t z_bytes_from_static_buf(z_owned_bytes_t *bytes, const uint8_t *data, size_t len) {
    z_owned_slice_t s;
    s._val = _z_slice_from_buf_custom_deleter(data, len, _z_delete_context_static());
    return z_bytes_from_slice(bytes, z_slice_move(&s));
}

z_result_t z_bytes_copy_from_buf(z_owned_bytes_t *bytes, const uint8_t *data, size_t len) {
    z_owned_slice_t s;
    s._val = _z_slice_copy_from_buf(data, len);
    if (s._val.len != len) _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    return z_bytes_from_slice(bytes, z_slice_move(&s));
}

z_result_t z_bytes_copy_from_slice(z_owned_bytes_t *bytes, const z_loaned_slice_t *slice) {
    z_owned_slice_t s;
    _Z_RETURN_IF_ERR(_z_slice_copy(&s._val, slice));
    return z_bytes_from_slice(bytes, z_slice_move(&s));
}

z_result_t z_bytes_from_string(z_owned_bytes_t *bytes, z_moved_string_t *s) {
    z_owned_slice_t slice;
    size_t str_len = _z_string_len(&s->_this._val);
    slice._val = _z_slice_steal(&s->_this._val._slice);
    slice._val.len = str_len;
    return z_bytes_from_slice(bytes, z_slice_move(&slice));
}

z_result_t z_bytes_copy_from_string(z_owned_bytes_t *bytes, const z_loaned_string_t *value) {
    z_owned_string_t s;
    _Z_RETURN_IF_ERR(_z_string_copy(&s._val, value));

    return z_bytes_from_string(bytes, z_string_move(&s));
}

z_result_t z_bytes_from_str(z_owned_bytes_t *bytes, char *value, void (*deleter)(void *value, void *context),
                            void *context) {
    z_owned_string_t s;
    s._val = _z_string_from_str_custom_deleter(value, _z_delete_context_create(deleter, context));
    return z_bytes_from_string(bytes, z_string_move(&s));
}

z_result_t z_bytes_copy_from_str(z_owned_bytes_t *bytes, const char *value) {
    z_owned_string_t s;
    s._val = _z_string_copy_from_str(value);
    if (s._val._slice.start == NULL && value != NULL) _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    return z_bytes_from_string(bytes, z_string_move(&s));
}

z_result_t z_bytes_from_static_str(z_owned_bytes_t *bytes, const char *value) {
    z_owned_string_t s;
    s._val = _z_string_from_str_custom_deleter((char *)value, _z_delete_context_static());
    return z_bytes_from_string(bytes, z_string_move(&s));
}

void z_bytes_empty(z_owned_bytes_t *bytes) { bytes->_val = _z_bytes_null(); }

size_t z_bytes_len(const z_loaned_bytes_t *bytes) { return _z_bytes_len(bytes); }

bool z_bytes_is_empty(const z_loaned_bytes_t *bytes) { return _z_bytes_is_empty(bytes); }

z_bytes_reader_t z_bytes_get_reader(const z_loaned_bytes_t *bytes) { return _z_bytes_get_reader(bytes); }

size_t z_bytes_reader_read(z_bytes_reader_t *reader, uint8_t *dst, size_t len) {
    return _z_bytes_reader_read(reader, dst, len);
}

z_result_t z_bytes_reader_seek(z_bytes_reader_t *reader, int64_t offset, int origin) {
    return _z_bytes_reader_seek(reader, offset, origin);
}

int64_t z_bytes_reader_tell(z_bytes_reader_t *reader) { return _z_bytes_reader_tell(reader); }
size_t z_bytes_reader_remaining(const z_bytes_reader_t *reader) { return _z_bytes_reader_remaining(reader); }

z_bytes_slice_iterator_t z_bytes_get_slice_iterator(const z_loaned_bytes_t *bytes) {
    return (z_bytes_slice_iterator_t){._bytes = bytes, ._slice_idx = 0};
}

#if defined(Z_FEATURE_UNSTABLE_API)
z_result_t z_bytes_get_contiguous_view(const z_loaned_bytes_t *bytes, z_view_slice_t *view) {
    size_t num_slices = _z_bytes_num_slices(bytes);
    if (num_slices > 1) {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    } else if (num_slices == 1) {
        _z_arc_slice_t *slice = _z_bytes_get_slice(bytes, 0);
        z_view_slice_from_buf(view, _z_arc_slice_data(slice), _z_arc_slice_len(slice));
        return _Z_RES_OK;
    } else {
        z_view_slice_empty(view);
        return _Z_RES_OK;
    }
}
#endif

bool z_bytes_slice_iterator_next(z_bytes_slice_iterator_t *iter, z_view_slice_t *out) {
    if (iter->_slice_idx >= _z_bytes_num_slices(iter->_bytes)) {
        return false;
    }
    const _z_arc_slice_t *arc_slice = _z_bytes_get_slice(iter->_bytes, iter->_slice_idx);
    out->_val =
        _z_slice_alias_buf(_z_slice_simple_rc_value(&arc_slice->slice)->start + arc_slice->start, arc_slice->len);
    iter->_slice_idx++;
    return true;
}

void z_bytes_writer_finish(z_moved_bytes_writer_t *writer, z_owned_bytes_t *bytes) {
    bytes->_val = _z_bytes_writer_finish(&writer->_this._val);
}

z_result_t z_bytes_writer_empty(z_owned_bytes_writer_t *writer) {
    writer->_val = _z_bytes_writer_empty();
    return _Z_RES_OK;
}

z_result_t z_bytes_writer_write_all(z_loaned_bytes_writer_t *writer, const uint8_t *src, size_t len) {
    return _z_bytes_writer_write_all(writer, src, len);
}

z_result_t z_bytes_writer_append(z_loaned_bytes_writer_t *writer, z_moved_bytes_t *bytes) {
    return _z_bytes_writer_append_z_bytes(writer, &bytes->_this._val);
}

z_result_t z_timestamp_new(z_timestamp_t *ts, const z_loaned_session_t *zs) {
    *ts = _z_timestamp_null();
    _z_time_since_epoch t;
    _Z_RETURN_IF_ERR(_z_get_time_since_epoch(&t));
    ts->valid = true;
    ts->time = _z_timestamp_ntp64_from_time(t.secs, t.nanos);
    ts->id = _Z_RC_IN_VAL(zs)->_local_zid;
    return _Z_RES_OK;
}

uint64_t z_timestamp_ntp64_time(const z_timestamp_t *ts) { return ts->time; }

z_id_t z_timestamp_id(const z_timestamp_t *ts) { return ts->id; }

z_result_t z_entity_global_id_new(z_entity_global_id_t *gid, const z_id_t *zid, uint32_t eid) {
    *gid = _z_entity_global_id_null();
    gid->zid = *zid;
    gid->eid = eid;
    return _Z_RES_OK;
}

uint32_t z_entity_global_id_eid(const z_entity_global_id_t *gid) { return gid->eid; }

z_id_t z_entity_global_id_zid(const z_entity_global_id_t *gid) { return gid->zid; }

z_source_info_t z_source_info_new(const z_entity_global_id_t *source_id, uint32_t source_sn) {
    z_source_info_t si;
    si._source_id = *source_id;
    si._source_sn = source_sn;
    return si;
}

uint32_t z_source_info_sn(const z_source_info_t *info) { return info->_source_sn; }

z_entity_global_id_t z_source_info_id(const z_source_info_t *info) { return info->_source_id; }

z_query_target_t z_query_target_default(void) { return Z_QUERY_TARGET_DEFAULT; }

z_reply_keyexpr_t z_reply_keyexpr_default(void) { return Z_REPLY_KEYEXPR_DEFAULT; }

z_query_consolidation_t z_query_consolidation_auto(void) {
    return (z_query_consolidation_t){.mode = Z_CONSOLIDATION_MODE_AUTO};
}

z_query_consolidation_t z_query_consolidation_latest(void) {
    return (z_query_consolidation_t){.mode = Z_CONSOLIDATION_MODE_LATEST};
}

z_query_consolidation_t z_query_consolidation_monotonic(void) {
    return (z_query_consolidation_t){.mode = Z_CONSOLIDATION_MODE_MONOTONIC};
}

z_query_consolidation_t z_query_consolidation_none(void) {
    return (z_query_consolidation_t){.mode = Z_CONSOLIDATION_MODE_NONE};
}

z_query_consolidation_t z_query_consolidation_default(void) { return z_query_consolidation_auto(); }

void z_query_parameters(const z_loaned_query_t *query, z_view_string_t *parameters) {
    parameters->_val = _z_string_alias(_Z_RC_IN_VAL(query)->_parameters);
}

z_reply_keyexpr_t z_query_accepts_replies(const z_loaned_query_t *query) {
    return _Z_RC_IN_VAL(query)->_anyke ? Z_REPLY_KEYEXPR_ANY : Z_REPLY_KEYEXPR_MATCHING_QUERY;
}

const z_loaned_bytes_t *z_query_attachment(const z_loaned_query_t *query) { return &_Z_RC_IN_VAL(query)->_attachment; }

const z_loaned_keyexpr_t *z_query_keyexpr(const z_loaned_query_t *query) { return &_Z_RC_IN_VAL(query)->_key; }

const z_loaned_bytes_t *z_query_payload(const z_loaned_query_t *query) { return &_Z_RC_IN_VAL(query)->_value.payload; }

const z_source_info_t *z_query_source_info(const z_loaned_query_t *query) {
    const z_source_info_t *info = &_Z_RC_IN_VAL(query)->_source_info;
    return _z_source_info_check(info) ? info : NULL;
}

const z_loaned_encoding_t *z_query_encoding(const z_loaned_query_t *query) {
    return &_Z_RC_IN_VAL(query)->_value.encoding;
}

void z_closure_sample_call(const z_loaned_closure_sample_t *closure, z_loaned_sample_t *sample) {
    if (closure->call != NULL) {
        (closure->call)(sample, closure->context);
    }
}

void z_closure_query_call(const z_loaned_closure_query_t *closure, z_loaned_query_t *query) {
    if (closure->call != NULL) {
        (closure->call)(query, closure->context);
    }
}

void z_closure_reply_call(const z_loaned_closure_reply_t *closure, z_loaned_reply_t *reply) {
    if (closure->call != NULL) {
        (closure->call)(reply, closure->context);
    }
}

void z_closure_hello_call(const z_loaned_closure_hello_t *closure, z_loaned_hello_t *hello) {
    if (closure->call != NULL) {
        (closure->call)(hello, closure->context);
    }
}

void z_closure_zid_call(const z_loaned_closure_zid_t *closure, const z_id_t *id) {
    if (closure->call != NULL) {
        (closure->call)(id, closure->context);
    }
}

#if Z_FEATURE_CONNECTIVITY == 1
void z_closure_transport_call(const z_loaned_closure_transport_t *closure, z_loaned_transport_t *transport) {
    if (closure->call != NULL) {
        (closure->call)(transport, closure->context);
    }
}

void z_closure_link_call(const z_loaned_closure_link_t *closure, z_loaned_link_t *link) {
    if (closure->call != NULL) {
        (closure->call)(link, closure->context);
    }
}

void z_closure_transport_event_call(const z_loaned_closure_transport_event_t *closure,
                                    z_loaned_transport_event_t *event) {
    if (closure->call != NULL) {
        (closure->call)(event, closure->context);
    }
}

void z_closure_link_event_call(const z_loaned_closure_link_event_t *closure, z_loaned_link_event_t *event) {
    if (closure->call != NULL) {
        (closure->call)(event, closure->context);
    }
}
#endif

void z_closure_matching_status_call(const z_loaned_closure_matching_status_t *closure,
                                    const z_matching_status_t *status) {
    if (closure->call != NULL) {
        (closure->call)(status, closure->context);
    }
}

void ze_closure_miss_call(const ze_loaned_closure_miss_t *closure, const ze_miss_t *miss) {
    if (closure->call != NULL) {
        (closure->call)(miss, closure->context);
    }
}

bool _z_config_check(const _z_config_t *config) { return !_z_str_intmap_is_empty(config); }
_z_config_t _z_config_null(void) { return _z_str_intmap_make(); }
z_result_t _z_config_copy(_z_config_t *dst, const _z_config_t *src) {
    *dst = _z_str_intmap_clone(src);
    return _Z_RES_OK;
}
void _z_config_drop(_z_config_t *config) { _z_str_intmap_clear(config); }
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_config_t, config, _z_config_check, _z_config_null, _z_config_copy, _z_str_intmap_move,
                              _z_config_drop)

_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_string_t, string, _z_string_check, _z_string_null, _z_string_copy, _z_string_move,
                              _z_string_clear)

_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_value_t, reply_err, _z_value_check, _z_value_null, _z_value_copy, _z_value_move,
                              _z_value_clear)

_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_declared_keyexpr_t, keyexpr, _z_declared_keyexpr_check, _z_declared_keyexpr_null,
                              _z_declared_keyexpr_copy, _z_declared_keyexpr_move, _z_declared_keyexpr_clear)
_Z_VIEW_FUNCTIONS_IMPL(_z_declared_keyexpr_t, keyexpr, _z_declared_keyexpr_check, _z_declared_keyexpr_null)
_Z_VIEW_FUNCTIONS_IMPL(_z_string_t, string, _z_string_check, _z_string_null)
_Z_VIEW_FUNCTIONS_IMPL(_z_slice_t, slice, _z_slice_check, _z_slice_null)

_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_hello_t, hello, _z_hello_check, _z_hello_null, _z_hello_copy, _z_hello_move,
                              _z_hello_clear)

bool _z_string_array_check(const _z_string_svec_t *val) { return !_z_string_svec_is_empty(val); }
z_result_t _z_string_array_copy(_z_string_svec_t *dst, const _z_string_svec_t *src) {
    return _z_string_svec_copy(dst, src, true);
}
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_string_svec_t, string_array, _z_string_array_check, _z_string_array_null,
                              _z_string_array_copy, _z_string_svec_move, _z_string_svec_clear)
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_slice_t, slice, _z_slice_check, _z_slice_null, _z_slice_copy, _z_slice_move,
                              _z_slice_clear)
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_bytes_t, bytes, _z_bytes_check, _z_bytes_null, _z_bytes_copy, _z_bytes_move,
                              _z_bytes_drop)
_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_IMPL(_z_bytes_writer_t, bytes_writer, _z_bytes_writer_check, _z_bytes_writer_empty,
                                      _z_bytes_writer_move, _z_bytes_writer_clear)

#if Z_FEATURE_PUBLICATION == 1 || Z_FEATURE_QUERYABLE == 1 || Z_FEATURE_QUERY == 1
// Convert a user owned bytes payload to an internal bytes payload, returning an empty one if value invalid
static inline _z_bytes_t *_z_bytes_from_moved(z_moved_bytes_t *bytes) {
    return (bytes == NULL) ? NULL : &bytes->_this._val;
}

// Convert a user owned encoding to an internal encoding, return default encoding if value invalid
static inline _z_encoding_t *_z_encoding_from_moved(z_moved_encoding_t *encoding) {
    return (encoding == NULL) ? NULL : &encoding->_this._val;
}
#endif

_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_sample_t, sample, _z_sample_check, _z_sample_null, _z_sample_copy, _z_sample_move,
                              _z_sample_clear)
_Z_OWNED_FUNCTIONS_RC_IMPL_NO_DROP_CLONE(session)

#if Z_FEATURE_CONNECTIVITY == 1
bool _z_info_transport_check(const _z_info_transport_t *transport) { return _z_id_check(transport->_zid); }
_z_info_transport_t _z_info_transport_null(void) { return (_z_info_transport_t){0}; }
z_result_t _z_info_transport_copy(_z_info_transport_t *dst, const _z_info_transport_t *src) {
    *dst = *src;
    return _Z_RES_OK;
}
z_result_t _z_info_transport_move(_z_info_transport_t *dst, _z_info_transport_t *src) {
    *dst = *src;
    *src = _z_info_transport_null();
    return _Z_RES_OK;
}
void _z_info_transport_clear(_z_info_transport_t *transport) { *transport = _z_info_transport_null(); }

bool _z_info_link_check(const _z_info_link_t *link) { return _z_id_check(link->_zid); }
_z_info_link_t _z_info_link_null(void) {
    _z_info_link_t link = {0};
    link._src = _z_string_null();
    link._dst = _z_string_null();
    return link;
}
z_result_t _z_info_link_copy(_z_info_link_t *dst, const _z_info_link_t *src) {
    *dst = _z_info_link_null();
    dst->_zid = src->_zid;
    dst->_mtu = src->_mtu;
    dst->_is_streamed = src->_is_streamed;
    dst->_is_reliable = src->_is_reliable;
    _Z_RETURN_IF_ERR(_z_string_copy(&dst->_src, &src->_src));
    _Z_CLEAN_RETURN_IF_ERR(_z_string_copy(&dst->_dst, &src->_dst), _z_string_clear(&dst->_src));
    return _Z_RES_OK;
}
z_result_t _z_info_link_move(_z_info_link_t *dst, _z_info_link_t *src) {
    *dst = _z_info_link_null();
    dst->_zid = src->_zid;
    dst->_mtu = src->_mtu;
    dst->_is_streamed = src->_is_streamed;
    dst->_is_reliable = src->_is_reliable;
    _Z_RETURN_IF_ERR(_z_string_move(&dst->_src, &src->_src));
    _Z_CLEAN_RETURN_IF_ERR(_z_string_move(&dst->_dst, &src->_dst), _z_string_clear(&dst->_src));
    *src = _z_info_link_null();
    return _Z_RES_OK;
}
void _z_info_link_clear(_z_info_link_t *link) {
    _z_string_clear(&link->_src);
    _z_string_clear(&link->_dst);
    *link = _z_info_link_null();
}

bool _z_info_transport_event_check(const _z_info_transport_event_t *event) {
    return _z_info_transport_check(&event->transport);
}
_z_info_transport_event_t _z_info_transport_event_null(void) {
    _z_info_transport_event_t event = {0};
    event.kind = Z_SAMPLE_KIND_DEFAULT;
    event.transport = _z_info_transport_null();
    return event;
}
z_result_t _z_info_transport_event_copy(_z_info_transport_event_t *dst, const _z_info_transport_event_t *src) {
    *dst = *src;
    return _Z_RES_OK;
}
z_result_t _z_info_transport_event_move(_z_info_transport_event_t *dst, _z_info_transport_event_t *src) {
    *dst = *src;
    *src = _z_info_transport_event_null();
    return _Z_RES_OK;
}
void _z_info_transport_event_clear(_z_info_transport_event_t *event) { *event = _z_info_transport_event_null(); }

bool _z_info_link_event_check(const _z_info_link_event_t *event) { return _z_info_link_check(&event->link); }
_z_info_link_event_t _z_info_link_event_null(void) {
    _z_info_link_event_t event = {0};
    event.kind = Z_SAMPLE_KIND_DEFAULT;
    event.link = _z_info_link_null();
    return event;
}
z_result_t _z_info_link_event_copy(_z_info_link_event_t *dst, const _z_info_link_event_t *src) {
    *dst = _z_info_link_event_null();
    dst->kind = src->kind;
    return _z_info_link_copy(&dst->link, &src->link);
}
z_result_t _z_info_link_event_move(_z_info_link_event_t *dst, _z_info_link_event_t *src) {
    *dst = _z_info_link_event_null();
    dst->kind = src->kind;
    _Z_RETURN_IF_ERR(_z_info_link_move(&dst->link, &src->link));
    src->kind = Z_SAMPLE_KIND_DEFAULT;
    return _Z_RES_OK;
}
void _z_info_link_event_clear(_z_info_link_event_t *event) {
    _z_info_link_clear(&event->link);
    event->kind = Z_SAMPLE_KIND_DEFAULT;
}

_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_info_transport_t, transport, _z_info_transport_check, _z_info_transport_null,
                              _z_info_transport_copy, _z_info_transport_move, _z_info_transport_clear)
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_info_link_t, link, _z_info_link_check, _z_info_link_null, _z_info_link_copy,
                              _z_info_link_move, _z_info_link_clear)
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_info_transport_event_t, transport_event, _z_info_transport_event_check,
                              _z_info_transport_event_null, _z_info_transport_event_copy, _z_info_transport_event_move,
                              _z_info_transport_event_clear)
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_info_link_event_t, link_event, _z_info_link_event_check, _z_info_link_event_null,
                              _z_info_link_event_copy, _z_info_link_event_move, _z_info_link_event_clear)
#endif

_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_sample, _z_closure_sample_callback_t, z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_query, _z_closure_query_callback_t, z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_reply, _z_closure_reply_callback_t, z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_hello, z_closure_hello_callback_t, z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_zid, z_closure_zid_callback_t, z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_matching_status, _z_closure_matching_status_callback_t,
                                z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL_PREFIX(ze, closure_miss, ze_closure_miss_callback_t, z_closure_drop_callback_t)
#if Z_FEATURE_CONNECTIVITY == 1
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_transport, z_closure_transport_callback_t, z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_link, z_closure_link_callback_t, z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_transport_event, z_closure_transport_event_callback_t,
                                z_closure_drop_callback_t)
_Z_OWNED_FUNCTIONS_CLOSURE_IMPL(closure_link_event, z_closure_link_event_callback_t, z_closure_drop_callback_t)
#endif

/************* Primitives **************/
#if Z_FEATURE_SCOUTING == 1
z_id_t z_hello_zid(const z_loaned_hello_t *hello) { return hello->_zid; }

z_whatami_t z_hello_whatami(const z_loaned_hello_t *hello) { return hello->_whatami; }

const z_loaned_string_array_t *zp_hello_locators(const z_loaned_hello_t *hello) { return &hello->_locators; }

void z_hello_locators(const z_loaned_hello_t *hello, z_owned_string_array_t *locators_out) {
    z_string_array_clone(locators_out, &hello->_locators);
}

static const char *WHAT_AM_I_TO_STRING_MAP[8] = {
    "Other",              // 0
    "Router",             // 0b1
    "Peer",               // 0b01
    "Router|Peer",        // 0b11,
    "Client",             // 0b100
    "Router|Client",      // 0b101
    "Peer|Client",        // 0b110
    "Router|Peer|Client"  // 0b111
};

z_result_t z_whatami_to_view_string(z_whatami_t whatami, z_view_string_t *str_out) {
    uint8_t idx = (uint8_t)whatami;
    if (idx >= _ZP_ARRAY_SIZE(WHAT_AM_I_TO_STRING_MAP) || idx == 0) {
        z_view_string_from_str(str_out, WHAT_AM_I_TO_STRING_MAP[0]);
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    } else {
        z_view_string_from_str(str_out, WHAT_AM_I_TO_STRING_MAP[idx]);
    }
    return _Z_RES_OK;
}

typedef struct __z_hello_handler_wrapper_t {
    z_closure_hello_callback_t user_call;
    void *ctx;
} __z_hello_handler_wrapper_t;

void __z_hello_handler(_z_hello_t *hello, __z_hello_handler_wrapper_t *wrapped_ctx) {
    wrapped_ctx->user_call(hello, wrapped_ctx->ctx);
}

z_result_t z_scout(z_moved_config_t *config, z_moved_closure_hello_t *callback, const z_scout_options_t *options) {
    void *ctx = callback->_this._val.context;
    callback->_this._val.context = NULL;

    // TODO[API-NET]: When API and NET are a single layer, there is no wrap the user callback and args
    //                to enclose the z_reply_t into a z_owned_reply_t.
    __z_hello_handler_wrapper_t *wrapped_ctx =
        (__z_hello_handler_wrapper_t *)z_malloc(sizeof(__z_hello_handler_wrapper_t));
    if (wrapped_ctx == NULL) {
        z_internal_closure_hello_null(&callback->_this);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    wrapped_ctx->user_call = callback->_this._val.call;
    wrapped_ctx->ctx = ctx;

    z_what_t what;
    if (options != NULL) {
        what = options->what;
    } else {
        char *opt_as_str = _z_config_get(&config->_this._val, Z_CONFIG_SCOUTING_WHAT_KEY);
        if (opt_as_str == NULL) {
            opt_as_str = (char *)Z_CONFIG_SCOUTING_WHAT_DEFAULT;
        }
        what = strtol(opt_as_str, NULL, 10);
    }

    char *opt_as_str = _z_config_get(&config->_this._val, Z_CONFIG_MULTICAST_LOCATOR_KEY);
    if (opt_as_str == NULL) {
        opt_as_str = (char *)Z_CONFIG_MULTICAST_LOCATOR_DEFAULT;
    }
    _z_string_t mcast_locator = _z_string_alias_str(opt_as_str);

    uint32_t timeout;
    if (options != NULL) {
        timeout = options->timeout_ms;
    } else {
        opt_as_str = _z_config_get(&config->_this._val, Z_CONFIG_SCOUTING_TIMEOUT_KEY);
        if (opt_as_str == NULL) {
            opt_as_str = (char *)Z_CONFIG_SCOUTING_TIMEOUT_DEFAULT;
        }
        timeout = (uint32_t)strtoul(opt_as_str, NULL, 10);
    }

    _z_id_t zid = _z_id_empty();
    char *zid_str = _z_config_get(&config->_this._val, Z_CONFIG_SESSION_ZID_KEY);
    if (zid_str != NULL) {
        _z_uuid_to_bytes(zid.id, zid_str);
    }

    _z_scout(what, zid, &mcast_locator, timeout, __z_hello_handler, wrapped_ctx, callback->_this._val.drop, ctx);

    z_free(wrapped_ctx);
    z_config_drop(config);
    z_internal_closure_hello_null(&callback->_this);

    return _Z_RES_OK;
}
#endif

void z_open_options_default(z_open_options_t *options) {
#if Z_FEATURE_ADMIN_SPACE == 1
    options->auto_start_admin_space = false;
#endif
#if Z_FEATURE_MULTI_THREAD == 1
    options->auto_start_lease_task = false;
    options->auto_start_read_task = true;
    options->executor_task_attributes = NULL;
#endif
#if Z_FEATURE_ADMIN_SPACE == 0 && Z_FEATURE_MULTI_THREAD == 0
    options->__dummy = 0;
#endif
}

static _z_id_t _z_session_get_zid(const _z_config_t *config) {
    _z_id_t zid = _z_id_empty();
    char *opt_as_str = _z_config_get(config, Z_CONFIG_SESSION_ZID_KEY);
    if (opt_as_str != NULL) {
        _z_uuid_to_bytes(zid.id, opt_as_str);
    } else {
        _z_session_generate_zid(&zid, Z_ZID_LENGTH);
    }
    return zid;
}

static z_result_t _z_session_rc_init(z_owned_session_t *zs, _z_id_t *zid) {
    z_internal_session_null(zs);
    _z_session_t *s = (_z_session_t *)z_malloc(sizeof(_z_session_t));
    if (s == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }

    z_result_t ret = _z_session_init(s, zid);
    if (ret != _Z_RES_OK) {
        _Z_ERROR("_z_open failed: %i", ret);
        z_free(s);
        return ret;
    }

    _z_session_rc_t zsrc = _z_session_rc_new(s);
    if (zsrc._cnt == NULL) {
        _z_session_clear(s);
        z_free(s);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    zs->_rc = zsrc;

    return _Z_RES_OK;
}

z_result_t z_open(z_owned_session_t *zs, z_moved_config_t *config, const z_open_options_t *options) {
    z_internal_session_null(zs);
    z_open_options_t opts;
    if (options == NULL) {
        z_open_options_default(&opts);
    } else {
        opts = *options;
    }

    if (config == NULL) {
        _Z_ERROR("A valid config is missing.");
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
    _z_config_t *cfg = &config->_this._val;

    _z_id_t zid = _z_session_get_zid(cfg);
    if (!_z_id_check(zid)) {
        _Z_ERROR("Invalid ZID.");
        z_config_drop(config);
        return _Z_ERR_INVALID;
    }

    z_result_t ret = _z_session_rc_init(zs, &zid);
    if (ret != _Z_RES_OK) {
        z_config_drop(config);
        return ret;
    }

    ret = _z_open(&zs->_rc, cfg, &zid);
    _Z_SET_IF_OK(ret, _zp_start_transport_tasks(_Z_RC_IN_VAL(&zs->_rc)));
    if (ret != _Z_RES_OK) {
        z_session_drop(z_session_move(zs));
        z_config_drop(config);
        return ret;
    }
#if Z_FEATURE_MULTI_THREAD == 1
    if (opts.auto_start_read_task) {
        _Z_CLEAN_RETURN_IF_ERR(_z_runtime_start(&_Z_RC_IN_VAL(&zs->_rc)->_runtime, opts.executor_task_attributes),
                               z_session_drop(z_session_move(zs));
                               z_config_drop(config));
    }
#endif
#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_ADMIN_SPACE == 1
    if (opts.auto_start_admin_space) {
        _Z_CLEAN_RETURN_IF_ERR(zp_start_admin_space(z_session_loan_mut(zs)), z_session_drop(z_session_move(zs));
                               z_config_drop(config));
    }
#endif
#endif

    // Clean up
#if Z_FEATURE_AUTO_RECONNECT == 1
    _Z_OWNED_RC_IN_VAL(zs)->_config = config->_this._val;
    z_internal_config_null(&config->_this);
#else
    z_config_drop(config);
#endif

    return _Z_RES_OK;
}

void z_close_options_default(z_close_options_t *options) { options->__dummy = 0; }

void z_session_drop(z_moved_session_t *zs) {
    if (!_Z_RC_IS_NULL(&zs->_this._rc)) {
        // force closing of the session (since it might not do it automatically due to temporary pending rc copies)
        z_close(&zs->_this._rc, NULL);
        _z_session_rc_drop(&zs->_this._rc);
    }
}

z_result_t z_close(z_loaned_session_t *zs, const z_close_options_t *options) {
    _ZP_UNUSED(options);
    if (_Z_RC_IS_NULL(zs)) {
        return _Z_RES_OK;
    }
    return _z_session_close(_Z_RC_IN_VAL(zs));
}

bool z_session_is_closed(const z_loaned_session_t *zs) { return _z_session_is_closed(_Z_RC_IN_VAL(zs)); }

#ifdef Z_FEATURE_UNSTABLE_API
z_entity_global_id_t z_session_id(const z_loaned_session_t *zs) {
    z_entity_global_id_t ret;
    // eid counter starts from 1, so it is safe to use 0 for session
    z_entity_global_id_new(&ret, &_Z_RC_IN_VAL(zs)->_local_zid, 0);  // never fails
    return ret;
}
#endif

z_result_t z_info_peers_zid(const z_loaned_session_t *zs, z_moved_closure_zid_t *callback) {
    if (_Z_RC_IN_VAL(zs)->_mode != Z_WHATAMI_PEER) {
        return _Z_RES_OK;
    }
    // Call transport function
    switch (_Z_RC_IN_VAL(zs)->_tp._type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            _zp_unicast_fetch_zid(&(_Z_RC_IN_VAL(zs)->_tp), &callback->_this._val);
            break;
        case _Z_TRANSPORT_MULTICAST_TYPE:
        case _Z_TRANSPORT_RAWETH_TYPE:
            _zp_multicast_fetch_zid(&(_Z_RC_IN_VAL(zs)->_tp), &callback->_this._val);
            break;
        default:
            break;
    }
    z_closure_zid_drop(callback);
    return _Z_RES_OK;
}

z_result_t z_info_routers_zid(const z_loaned_session_t *zs, z_moved_closure_zid_t *callback) {
    if (_Z_RC_IN_VAL(zs)->_mode != Z_WHATAMI_CLIENT) {
        return _Z_RES_OK;
    }
    // Call transport function
    switch (_Z_RC_IN_VAL(zs)->_tp._type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            _zp_unicast_fetch_zid(&(_Z_RC_IN_VAL(zs)->_tp), &callback->_this._val);
            break;
        default:
            break;
    }
    z_closure_zid_drop(callback);
    return _Z_RES_OK;
}

z_id_t z_info_zid(const z_loaned_session_t *zs) { return _Z_RC_IN_VAL(zs)->_local_zid; }

#if Z_FEATURE_CONNECTIVITY == 1
void _z_info_transport_from_peer(_z_info_transport_t *out, const _z_transport_peer_common_t *peer, bool is_multicast) {
    *out = _z_info_transport_null();
    out->_zid = peer->_remote_zid;
    out->_whatami = peer->_remote_whatami;
    out->_is_qos = false;
    out->_is_multicast = is_multicast;
    out->_is_shm = false;
}

bool _z_info_transport_filter_match(const _z_info_transport_t *transport, const _z_info_transport_t *filter) {
    return _z_id_eq(&transport->_zid, &filter->_zid) && transport->_is_multicast == filter->_is_multicast;
}

static z_result_t _z_info_link_make(_z_info_link_t *link, const _z_transport_peer_common_t *peer,
                                    const _z_transport_common_t *transport_common) {
    *link = _z_info_link_null();
    link->_zid = peer->_remote_zid;
    if (transport_common != NULL && transport_common->_link != NULL) {
        link->_mtu = transport_common->_link->_mtu;
        link->_is_streamed = transport_common->_link->_cap._flow == Z_LINK_CAP_FLOW_STREAM;
        link->_is_reliable = transport_common->_link->_cap._is_reliable;
    }
    _Z_RETURN_IF_ERR(_z_string_copy(&link->_src, &peer->_link_src));
    _Z_CLEAN_RETURN_IF_ERR(_z_string_copy(&link->_dst, &peer->_link_dst), _z_string_clear(&link->_src));
    return _Z_RES_OK;
}

void z_info_links_options_default(z_info_links_options_t *options) { options->transport = NULL; }

z_result_t z_info_transports(const z_loaned_session_t *zs, z_moved_closure_transport_t *callback) {
    z_result_t ret = _Z_RES_OK;
    _z_session_t *session = _Z_RC_IN_VAL(zs);
    _z_transport_t *transport = &session->_tp;
    _z_session_transport_mutex_lock(session);
    _z_transport_common_t *transport_common = _z_transport_get_common(transport);
    if (transport_common != NULL) {
        _z_transport_peer_mutex_lock(transport_common);
    }

    switch (transport->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE: {
            _z_transport_peer_unicast_slist_t *curr = transport->_transport._unicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_unicast_slist_next(curr)) {
                _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(curr);
                _z_info_transport_t info_transport;
                _z_info_transport_from_peer(&info_transport, &peer->common, false);
                z_closure_transport_call(&callback->_this._val, &info_transport);
            }
            break;
        }
        case _Z_TRANSPORT_MULTICAST_TYPE:
        case _Z_TRANSPORT_RAWETH_TYPE: {
            _z_transport_peer_multicast_slist_t *curr = transport->_transport._multicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_multicast_slist_next(curr)) {
                _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(curr);
                _z_info_transport_t info_transport;
                _z_info_transport_from_peer(&info_transport, &peer->common, true);
                z_closure_transport_call(&callback->_this._val, &info_transport);
            }
            break;
        }
        default:
            break;
    }

    if (transport_common != NULL) {
        _z_transport_peer_mutex_unlock(transport_common);
    }
    _z_session_transport_mutex_unlock(session);

    z_closure_transport_drop(callback);
    return ret;
}

z_result_t z_info_links(const z_loaned_session_t *zs, z_moved_closure_link_t *callback,
                        z_info_links_options_t *options) {
    z_result_t ret = _Z_RES_OK;
    z_info_links_options_t opt;
    z_info_links_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    _z_info_transport_t transport_filter = _z_info_transport_null();
    bool has_transport_filter = false;
    if (opt.transport != NULL) {
        if (!z_internal_transport_check(&opt.transport->_this)) {
            ret = _Z_ERR_INVALID;
        } else {
            transport_filter = *z_transport_loan(&opt.transport->_this);
            has_transport_filter = true;
        }
    }

    _z_session_t *session = _Z_RC_IN_VAL(zs);
    _z_transport_t *transport = &session->_tp;
    if (ret != _Z_RES_OK) {
        goto out;
    }

    _z_session_transport_mutex_lock(session);
    _z_transport_common_t *transport_common = _z_transport_get_common(transport);
    if (transport_common != NULL) {
        _z_transport_peer_mutex_lock(transport_common);
    }

    switch (transport->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE: {
            _z_transport_peer_unicast_slist_t *curr = transport->_transport._unicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_unicast_slist_next(curr)) {
                _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(curr);
                _z_info_transport_t info_transport;
                _z_info_transport_from_peer(&info_transport, &peer->common, false);
                if (has_transport_filter && !_z_info_transport_filter_match(&info_transport, &transport_filter)) {
                    continue;
                }

                _z_info_link_t info_link;
                ret = _z_info_link_make(&info_link, &peer->common, transport_common);
                if (ret != _Z_RES_OK) {
                    break;
                }
                z_closure_link_call(&callback->_this._val, &info_link);
                _z_info_link_clear(&info_link);
            }
            break;
        }
        case _Z_TRANSPORT_MULTICAST_TYPE:
        case _Z_TRANSPORT_RAWETH_TYPE: {
            _z_transport_peer_multicast_slist_t *curr = transport->_transport._multicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_multicast_slist_next(curr)) {
                _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(curr);
                _z_info_transport_t info_transport;
                _z_info_transport_from_peer(&info_transport, &peer->common, true);
                if (has_transport_filter && !_z_info_transport_filter_match(&info_transport, &transport_filter)) {
                    continue;
                }

                _z_info_link_t info_link;
                ret = _z_info_link_make(&info_link, &peer->common, transport_common);
                if (ret != _Z_RES_OK) {
                    break;
                }
                z_closure_link_call(&callback->_this._val, &info_link);
                _z_info_link_clear(&info_link);
            }
            break;
        }
        default:
            break;
    }

    if (transport_common != NULL) {
        _z_transport_peer_mutex_unlock(transport_common);
    }
    _z_session_transport_mutex_unlock(session);

out:
    z_transport_drop(opt.transport);

    z_closure_link_drop(callback);
    return ret;
}

z_id_t z_transport_zid(const z_loaned_transport_t *transport) { return transport->_zid; }
z_whatami_t z_transport_whatami(const z_loaned_transport_t *transport) { return transport->_whatami; }
bool z_transport_is_qos(const z_loaned_transport_t *transport) { return transport->_is_qos; }
bool z_transport_is_multicast(const z_loaned_transport_t *transport) { return transport->_is_multicast; }
bool z_transport_is_shm(const z_loaned_transport_t *transport) { return transport->_is_shm; }

z_id_t z_link_zid(const z_loaned_link_t *link) { return link->_zid; }
z_result_t z_link_src(const z_loaned_link_t *link, z_owned_string_t *str_out) {
    str_out->_val = _z_string_null();
    return _z_string_copy(&str_out->_val, &link->_src);
}
z_result_t z_link_dst(const z_loaned_link_t *link, z_owned_string_t *str_out) {
    str_out->_val = _z_string_null();
    return _z_string_copy(&str_out->_val, &link->_dst);
}
uint16_t z_link_mtu(const z_loaned_link_t *link) { return link->_mtu; }
bool z_link_is_streamed(const z_loaned_link_t *link) { return link->_is_streamed; }
bool z_link_is_reliable(const z_loaned_link_t *link) { return link->_is_reliable; }

void z_link_group(const z_loaned_link_t *link, z_owned_string_t *str_out) {
    (void)link;
    str_out->_val = _z_string_null();
}
void z_link_auth_identifier(const z_loaned_link_t *link, z_owned_string_t *str_out) {
    (void)link;
    str_out->_val = _z_string_null();
}
void z_link_interfaces(const z_loaned_link_t *link, z_owned_string_array_t *interfaces_out) {
    (void)link;
    interfaces_out->_val = _z_string_svec_null();
}
bool z_link_priorities(const z_loaned_link_t *link, uint8_t *min_out, uint8_t *max_out) {
    (void)link;
    (void)min_out;
    (void)max_out;
    return false;
}
bool z_link_reliability(const z_loaned_link_t *link, z_reliability_t *reliability_out) {
    (void)link;
    (void)reliability_out;
    return false;
}

z_sample_kind_t z_transport_event_kind(const z_loaned_transport_event_t *event) { return event->kind; }
const z_loaned_transport_t *z_transport_event_transport(const z_loaned_transport_event_t *event) {
    return &event->transport;
}
z_loaned_transport_t *z_transport_event_transport_mut(z_loaned_transport_event_t *event) { return &event->transport; }

z_sample_kind_t z_link_event_kind(const z_loaned_link_event_t *event) { return event->kind; }
const z_loaned_link_t *z_link_event_link(const z_loaned_link_event_t *event) { return &event->link; }
z_loaned_link_t *z_link_event_link_mut(z_loaned_link_event_t *event) { return &event->link; }
#endif

z_result_t z_id_to_string(const z_id_t *id, z_owned_string_t *str) {
    str->_val = _z_id_to_string(id);
    if (!_z_string_check(&str->_val)) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    return _Z_RES_OK;
}

const z_loaned_keyexpr_t *z_sample_keyexpr(const z_loaned_sample_t *sample) { return &sample->keyexpr; }
z_sample_kind_t z_sample_kind(const z_loaned_sample_t *sample) { return sample->kind; }
#ifdef Z_FEATURE_UNSTABLE_API
z_reliability_t z_sample_reliability(const z_loaned_sample_t *sample) { return sample->reliability; }
const z_source_info_t *z_sample_source_info(const z_loaned_sample_t *sample) {
    const z_source_info_t *info = &sample->source_info;
    return _z_source_info_check(info) ? info : NULL;
}
#endif
const z_loaned_bytes_t *z_sample_payload(const z_loaned_sample_t *sample) { return &sample->payload; }
const z_timestamp_t *z_sample_timestamp(const z_loaned_sample_t *sample) {
    if (_z_timestamp_check(&sample->timestamp)) {
        return &sample->timestamp;
    } else {
        return NULL;
    }
}
const z_loaned_encoding_t *z_sample_encoding(const z_loaned_sample_t *sample) { return &sample->encoding; }
const z_loaned_bytes_t *z_sample_attachment(const z_loaned_sample_t *sample) { return &sample->attachment; }
z_congestion_control_t z_sample_congestion_control(const z_loaned_sample_t *sample) {
    return _z_n_qos_get_congestion_control(sample->qos);
}
bool z_sample_express(const z_loaned_sample_t *sample) { return _z_n_qos_get_express(sample->qos); }
z_priority_t z_sample_priority(const z_loaned_sample_t *sample) { return _z_n_qos_get_priority(sample->qos); }

const z_loaned_bytes_t *z_reply_err_payload(const z_loaned_reply_err_t *reply_err) { return &reply_err->payload; }
const z_loaned_encoding_t *z_reply_err_encoding(const z_loaned_reply_err_t *reply_err) { return &reply_err->encoding; }

const char *z_string_data(const z_loaned_string_t *str) { return _z_string_data(str); }
size_t z_string_len(const z_loaned_string_t *str) { return _z_string_len(str); }

z_result_t z_string_copy_from_str(z_owned_string_t *str, const char *value) {
    str->_val = _z_string_copy_from_str(value);
    if (str->_val._slice.start == NULL && value != NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    return _Z_RES_OK;
}

z_result_t z_string_from_str(z_owned_string_t *str, char *value, void (*deleter)(void *value, void *context),
                             void *context) {
    str->_val = _z_string_from_str_custom_deleter(value, _z_delete_context_create(deleter, context));
    return _Z_RES_OK;
}

void z_string_empty(z_owned_string_t *str) { str->_val = _z_string_null(); }

z_result_t z_string_copy_from_substr(z_owned_string_t *str, const char *value, size_t len) {
    str->_val = _z_string_copy_from_substr(value, len);
    return _Z_RES_OK;
}

bool z_string_is_empty(const z_loaned_string_t *str) { return _z_string_is_empty(str); }

const z_loaned_slice_t *z_string_as_slice(const z_loaned_string_t *str) { return &str->_slice; }

z_priority_t z_priority_default(void) { return Z_PRIORITY_DEFAULT; }

#if Z_FEATURE_PUBLICATION == 1
void _z_publisher_drop(_z_publisher_t *pub) { _z_undeclare_publisher(pub); }

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_publisher_t, publisher, _z_publisher_check, _z_publisher_null,
                                              _z_publisher_drop)

void z_put_options_default(z_put_options_t *options) {
    options->congestion_control = z_internal_congestion_control_default_push();
    options->priority = Z_PRIORITY_DEFAULT;
    options->encoding = NULL;
    options->is_express = false;
    options->timestamp = NULL;
    options->attachment = NULL;
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    options->allowed_destination = z_locality_default();
#endif
#ifdef Z_FEATURE_UNSTABLE_API
    options->reliability = Z_RELIABILITY_DEFAULT;
    options->source_info = NULL;
#endif
}

void z_delete_options_default(z_delete_options_t *options) {
    options->congestion_control = z_internal_congestion_control_default_push();
    options->is_express = false;
    options->timestamp = NULL;
    options->priority = Z_PRIORITY_DEFAULT;
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    options->allowed_destination = z_locality_default();
#endif
#ifdef Z_FEATURE_UNSTABLE_API
    options->reliability = Z_RELIABILITY_DEFAULT;
    options->source_info = NULL;
#endif
}

z_result_t z_put(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr, z_moved_bytes_t *payload,
                 const z_put_options_t *options) {
    z_result_t ret = 0;

    z_put_options_t opt;
    z_put_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }
    z_reliability_t reliability = Z_RELIABILITY_DEFAULT;
    _z_source_info_t *source_info = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    reliability = opt.reliability;
    source_info = opt.source_info;
#endif

    _z_bytes_t *payload_bytes = _z_bytes_from_moved(payload);
    _z_bytes_t *attachment_bytes = _z_bytes_from_moved(opt.attachment);
    _z_encoding_t *encoding = _z_encoding_from_moved(opt.encoding);
    z_locality_t allowed_destination = z_locality_default();
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    allowed_destination = opt.allowed_destination;
#endif
    ret = _z_write(_Z_RC_IN_VAL(zs), keyexpr, payload_bytes, encoding, Z_SAMPLE_KIND_PUT, opt.congestion_control,
                   opt.priority, opt.is_express, opt.timestamp, attachment_bytes, reliability, source_info,
                   allowed_destination);

    z_encoding_drop(opt.encoding);
    z_bytes_drop(opt.attachment);
    z_bytes_drop(payload);

    return ret;
}

z_result_t z_delete(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                    const z_delete_options_t *options) {
    z_result_t ret = 0;

    z_delete_options_t opt;
    z_delete_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }
    z_reliability_t reliability = Z_RELIABILITY_DEFAULT;
    _z_source_info_t *source_info = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    reliability = opt.reliability;
    source_info = opt.source_info;
#endif
    z_locality_t allowed_destination = z_locality_default();
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    allowed_destination = opt.allowed_destination;
#endif
    ret = _z_write(_Z_RC_IN_VAL(zs), keyexpr, NULL, NULL, Z_SAMPLE_KIND_DELETE, opt.congestion_control, opt.priority,
                   opt.is_express, opt.timestamp, NULL, reliability, source_info, allowed_destination);
    return ret;
}

void z_publisher_options_default(z_publisher_options_t *options) {
    options->encoding = NULL;
    options->congestion_control = z_internal_congestion_control_default_push();
    options->priority = Z_PRIORITY_DEFAULT;
    options->is_express = false;
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    options->allowed_destination = z_locality_default();
#endif
#ifdef Z_FEATURE_UNSTABLE_API
    options->reliability = Z_RELIABILITY_DEFAULT;
#endif
}

z_result_t z_declare_publisher(const z_loaned_session_t *zs, z_owned_publisher_t *pub,
                               const z_loaned_keyexpr_t *keyexpr, const z_publisher_options_t *options) {
    pub->_val = _z_publisher_null();
    // Set options
    z_publisher_options_t opt;
    z_publisher_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }
    z_reliability_t reliability = Z_RELIABILITY_DEFAULT;
#ifdef Z_FEATURE_UNSTABLE_API
    reliability = opt.reliability;
#endif
    z_locality_t allowed_destination = z_locality_default();
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    allowed_destination = opt.allowed_destination;
#endif
    z_result_t res =
        _z_declare_publisher(&pub->_val, zs, keyexpr, opt.encoding == NULL ? NULL : &opt.encoding->_this._val,
                             opt.congestion_control, opt.priority, opt.is_express, reliability, allowed_destination);
    _Z_SET_IF_OK(res, _z_write_filter_create(zs, &pub->_val._filter, &pub->_val._key, _Z_INTEREST_FLAG_SUBSCRIBERS,
                                             false, allowed_destination));
    if (res != _Z_RES_OK) {
        _z_publisher_drop(&pub->_val);
    }
    return res;
}

z_result_t z_undeclare_publisher(z_moved_publisher_t *pub) { return _z_undeclare_publisher(&pub->_this._val); }

void z_publisher_put_options_default(z_publisher_put_options_t *options) {
    options->encoding = NULL;
    options->attachment = NULL;
    options->timestamp = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    options->source_info = NULL;
#endif
}

void z_publisher_delete_options_default(z_publisher_delete_options_t *options) {
    options->timestamp = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    options->source_info = NULL;
#endif
}

#if Z_FEATURE_ADVANCED_PUBLICATION == 1
z_result_t _z_publisher_put_impl(const z_loaned_publisher_t *pub, z_moved_bytes_t *payload,
                                 const z_publisher_put_options_t *options, _ze_advanced_cache_t *cache) {
#else
z_result_t _z_publisher_put_impl(const z_loaned_publisher_t *pub, z_moved_bytes_t *payload,
                                 const z_publisher_put_options_t *options) {
#endif
    z_result_t ret = 0;
    // Build options
    z_publisher_put_options_t opt;
    z_publisher_put_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }
    z_reliability_t reliability = Z_RELIABILITY_DEFAULT;
    _z_source_info_t *source_info = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    reliability = pub->reliability;
    if (opt.source_info != NULL) {
        source_info = opt.source_info;
    }
#endif

    _z_encoding_t encoding;
    if (opt.encoding == NULL) {
        encoding = _z_encoding_alias(
            &pub->_encoding);  // it is safe to use alias, since it will be unaffected by clear operation
    } else {
        encoding = _z_encoding_steal(&opt.encoding->_this._val);
    }

    _z_session_t *session = NULL;
#if Z_FEATURE_SESSION_CHECK == 1
    // Try to upgrade session rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&pub->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        session = _Z_RC_IN_VAL(&sess_rc);
    } else {
        _Z_ERROR_LOG(_Z_ERR_SESSION_CLOSED);
        ret = _Z_ERR_SESSION_CLOSED;
    }
#else
    session = _Z_RC_IN_VAL(&pub->_zn);
#endif

    if (session != NULL) {
        _z_bytes_t *payload_bytes = _z_bytes_from_moved(payload);
        _z_bytes_t *attachment_bytes = _z_bytes_from_moved(opt.attachment);
#if Z_FEATURE_ADVANCED_PUBLICATION == 1
        if (cache != NULL) {
            _z_timestamp_t local_timestamp = (opt.timestamp != NULL) ? *opt.timestamp : _z_timestamp_null();
            _z_source_info_t local_source_info = (source_info != NULL) ? *source_info : _z_source_info_null();
            _z_bytes_t local_payload = (payload_bytes != NULL) ? *payload_bytes : _z_bytes_null();
            _z_bytes_t local_attachment = (attachment_bytes != NULL) ? *attachment_bytes : _z_bytes_null();

            _z_sample_t sample;
            z_result_t res = _z_sample_copy_data(
                &sample, &pub->_key, &local_payload, &local_timestamp, &encoding, Z_SAMPLE_KIND_PUT,
                _z_n_qos_make(pub->_is_express, pub->_congestion_control == Z_CONGESTION_CONTROL_BLOCK, pub->_priority),
                &local_attachment, reliability, &local_source_info);
            if (res == _Z_RES_OK) {
                res = _ze_advanced_cache_add(cache, &sample);
                if (res != _Z_RES_OK) {
                    _Z_ERROR("Failed to add sample to advanced publisher cache: %i", res);
                    _z_sample_clear(&sample);
                }
            } else {
                _Z_ERROR("Failed to create sample from data: %i", res);
            }
        }
#endif
        // Check if write filter is active before writing
        if (
#if Z_FEATURE_MULTICAST_DECLARATIONS == 0
            session->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE ||
#endif
            !_z_write_filter_active(&pub->_filter)) {
            // Write value
            ret = _z_write(session, &pub->_key, payload_bytes, &encoding, Z_SAMPLE_KIND_PUT, pub->_congestion_control,
                           pub->_priority, pub->_is_express, opt.timestamp, attachment_bytes, reliability, source_info,
                           pub->_allowed_destination);
        }
    } else {
        _Z_ERROR_LOG(_Z_ERR_SESSION_CLOSED);
        ret = _Z_ERR_SESSION_CLOSED;
    }

#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif

    // Clean-up
    _z_encoding_clear(&encoding);
    z_bytes_drop(opt.attachment);
    z_bytes_drop(payload);
    return ret;
}

z_result_t z_publisher_put(const z_loaned_publisher_t *pub, z_moved_bytes_t *payload,
                           const z_publisher_put_options_t *options) {
#if Z_FEATURE_ADVANCED_PUBLICATION == 1
    return _z_publisher_put_impl(pub, payload, options, NULL);
#else
    return _z_publisher_put_impl(pub, payload, options);
#endif
}

#if Z_FEATURE_ADVANCED_PUBLICATION == 1
z_result_t _z_publisher_delete_impl(const z_loaned_publisher_t *pub, const z_publisher_delete_options_t *options,
                                    _ze_advanced_cache_t *cache) {
#else
z_result_t _z_publisher_delete_impl(const z_loaned_publisher_t *pub, const z_publisher_delete_options_t *options) {
#endif
    // Build options
    z_publisher_delete_options_t opt;
    z_publisher_delete_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }
    z_reliability_t reliability = Z_RELIABILITY_DEFAULT;
    _z_source_info_t *source_info = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    reliability = pub->reliability;
    source_info = opt.source_info;
#endif

    _z_session_t *session = NULL;
#if Z_FEATURE_SESSION_CHECK == 1
    // Try to upgrade session rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&pub->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        session = _Z_RC_IN_VAL(&sess_rc);
    } else {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
#else
    session = _Z_RC_IN_VAL(&pub->_zn);
#endif
    z_result_t ret = _Z_RES_OK;
    if (
#if Z_FEATURE_MULTICAST_DECLARATIONS == 0
        session->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE ||
#endif
        !_z_write_filter_active(&pub->_filter)) {
        ret = _z_write(session, &pub->_key, NULL, NULL, Z_SAMPLE_KIND_DELETE, pub->_congestion_control, pub->_priority,
                       pub->_is_express, opt.timestamp, NULL, reliability, source_info, pub->_allowed_destination);
    }
#if Z_FEATURE_ADVANCED_PUBLICATION == 1
    if (cache != NULL) {
        _z_timestamp_t cache_timestamp = (opt.timestamp != NULL) ? *opt.timestamp : _z_timestamp_null();
        _z_source_info_t cache_source_info = (source_info != NULL) ? *source_info : _z_source_info_null();
        _z_bytes_t payload_bytes = _z_bytes_null();
        _z_bytes_t attachment_bytes = _z_bytes_null();

        _z_sample_t sample;
        z_result_t res = _z_sample_copy_data(
            &sample, &pub->_key, &payload_bytes, &cache_timestamp, NULL, Z_SAMPLE_KIND_DELETE,
            _z_n_qos_make(pub->_is_express, pub->_congestion_control == Z_CONGESTION_CONTROL_BLOCK, pub->_priority),
            &attachment_bytes, reliability, &cache_source_info);
        if (res == _Z_RES_OK) {
            res = _ze_advanced_cache_add(cache, &sample);
            if (res != _Z_RES_OK) {
                _Z_ERROR("Failed to add sample to advanced publisher cache: %i", res);
                _z_sample_clear(&sample);
            }
        } else {
            _Z_ERROR("Failed to create sample from data: %i", res);
        }
    }
#endif

#if Z_FEATURE_SESSION_CHECK == 1
    // Clean up
    _z_session_rc_drop(&sess_rc);
#endif
    return ret;
}

z_result_t z_publisher_delete(const z_loaned_publisher_t *pub, const z_publisher_delete_options_t *options) {
#if Z_FEATURE_ADVANCED_PUBLICATION == 1
    return _z_publisher_delete_impl(pub, options, NULL);
#else
    return _z_publisher_delete_impl(pub, options);
#endif
}

const z_loaned_keyexpr_t *z_publisher_keyexpr(const z_loaned_publisher_t *publisher) {
    return (const z_loaned_keyexpr_t *)&publisher->_key;
}

#ifdef Z_FEATURE_UNSTABLE_API
z_entity_global_id_t z_publisher_id(const z_loaned_publisher_t *publisher) {
    z_entity_global_id_t egid;
    _z_session_t *session = NULL;
#if Z_FEATURE_SESSION_CHECK == 1
    // Try to upgrade session rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&publisher->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        session = _Z_RC_IN_VAL(&sess_rc);
    } else {
        egid = _z_entity_global_id_null();
    }
#else
    session = _Z_RC_IN_VAL(&publisher->_zn);
#endif

    if (session != NULL) {
        egid.zid = session->_local_zid;
        egid.eid = (uint32_t)publisher->_id;
    } else {
        egid = _z_entity_global_id_null();
    }

#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return egid;
}
#endif

#if Z_FEATURE_MATCHING == 1
z_result_t z_publisher_declare_background_matching_listener(const z_loaned_publisher_t *publisher,
                                                            z_moved_closure_matching_status_t *callback) {
    return z_publisher_declare_matching_listener(publisher, NULL, callback);
}

z_result_t z_publisher_declare_matching_listener(const z_loaned_publisher_t *publisher,
                                                 z_owned_matching_listener_t *matching_listener,
                                                 z_moved_closure_matching_status_t *callback) {
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&publisher->_zn);
    z_result_t ret = _Z_RES_OK;
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        if (matching_listener != NULL) {
            matching_listener->_val = _z_matching_listener_null();
            ret = _z_matching_listener_declare(&matching_listener->_val, _Z_RC_IN_VAL(&sess_rc),
                                               &publisher->_filter.ctx, &callback->_this._val);
        } else {
            uint32_t _listener_id;
            ret = _z_matching_listener_register(&_listener_id, _Z_RC_IN_VAL(&sess_rc), &publisher->_filter.ctx,
                                                &callback->_this._val);
        }
        _z_session_rc_drop(&sess_rc);
    } else {
        if (matching_listener != NULL) {
            matching_listener->_val = _z_matching_listener_null();
        }
        _z_closure_matching_status_clear(&callback->_this._val);
        z_internal_closure_matching_status_null(&callback->_this);
        ret = _Z_ERR_GENERIC;
    }
    return ret;
}

z_result_t z_publisher_get_matching_status(const z_loaned_publisher_t *publisher,
                                           z_matching_status_t *matching_status) {
    matching_status->matching = !_z_write_filter_active(&publisher->_filter);
    return _Z_RES_OK;
}
#endif  // Z_FEATURE_MATCHING == 1

#endif  // Z_FEATURE_PUBLICATION == 1

#if Z_FEATURE_QUERY == 1
bool _z_reply_check(const _z_reply_t *reply) {
    if (reply->data._tag == _Z_REPLY_TAG_DATA) {
        return _z_sample_check(&reply->data._result.sample);
    } else if (reply->data._tag == _Z_REPLY_TAG_ERROR) {
        return _z_value_check(&reply->data._result.error);
    }
    return false;
}
_Z_OWNED_FUNCTIONS_VALUE_IMPL(_z_reply_t, reply, _z_reply_check, _z_reply_null, _z_reply_copy, _z_reply_move,
                              _z_reply_clear)

void z_get_options_default(z_get_options_t *options) {
    options->target = z_query_target_default();
    options->consolidation = z_query_consolidation_default();
    options->congestion_control = z_internal_congestion_control_default_request();
    options->priority = Z_PRIORITY_DEFAULT;
    options->is_express = false;
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    options->allowed_destination = z_locality_default();
#endif
    options->encoding = NULL;
    options->payload = NULL;
    options->attachment = NULL;
    options->timeout_ms = 0;
#ifdef Z_FEATURE_UNSTABLE_API
    options->source_info = NULL;
    options->cancellation_token = NULL;
#endif
    options->accept_replies = z_reply_keyexpr_default();
}

z_result_t z_get(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr, const char *parameters,
                 z_moved_closure_reply_t *callback, z_get_options_t *options) {
    return z_get_with_parameters_substr(zs, keyexpr, parameters, parameters == NULL ? 0 : strlen(parameters), callback,
                                        options);
}

z_result_t z_get_with_parameters_substr(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                        const char *parameters, size_t parameters_len,
                                        z_moved_closure_reply_t *callback, z_get_options_t *options) {
    z_result_t ret = _Z_RES_OK;
    _z_closure_reply_t closure = callback->_this._val;
    z_internal_closure_reply_null(&callback->_this);

    z_get_options_t opt;
    if (options != NULL) {
        opt = *options;
    } else {
        z_get_options_default(&opt);
    }
    if (opt.timeout_ms == 0) {
        opt.timeout_ms = Z_GET_TIMEOUT_DEFAULT;
    }
    _z_source_info_t *source_info = NULL;
    _z_cancellation_token_rc_t *cancellation_token = NULL;

#ifdef Z_FEATURE_UNSTABLE_API
    source_info = opt.source_info;
    cancellation_token = opt.cancellation_token == NULL ? NULL : &opt.cancellation_token->_this._rc;
#endif
    _z_n_qos_t qos = _z_n_qos_make(opt.is_express, opt.congestion_control == Z_CONGESTION_CONTROL_BLOCK, opt.priority);
    z_locality_t allowed_destination = z_locality_default();
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    allowed_destination = opt.allowed_destination;
#endif
    ret = _z_query(zs, _z_optional_id_make_none(), keyexpr, parameters, parameters_len, opt.target,
                   opt.consolidation.mode, _z_bytes_from_moved(opt.payload), _z_encoding_from_moved(opt.encoding),
                   closure.call, closure.drop, closure.context, opt.timeout_ms, _z_bytes_from_moved(opt.attachment),
                   qos, source_info, opt.accept_replies, allowed_destination, cancellation_token);
    // Clean-up
#ifdef Z_FEATURE_UNSTABLE_API
    z_cancellation_token_drop(opt.cancellation_token);
#endif
    z_bytes_drop(opt.payload);
    z_encoding_drop(opt.encoding);
    z_bytes_drop(opt.attachment);
    return ret;
}

void _z_querier_drop(_z_querier_t *querier) { _z_undeclare_querier(querier); }

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_querier_t, querier, _z_querier_check, _z_querier_null, _z_querier_drop)

void z_querier_get_options_default(z_querier_get_options_t *options) {
    options->encoding = NULL;
    options->attachment = NULL;
    options->payload = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    options->source_info = NULL;
    options->cancellation_token = NULL;
#endif
}

void z_querier_options_default(z_querier_options_t *options) {
    options->encoding = NULL;
    options->target = z_query_target_default();
    options->consolidation = z_query_consolidation_default();
    options->congestion_control = z_internal_congestion_control_default_request();
    options->priority = Z_PRIORITY_DEFAULT;
    options->is_express = false;
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    options->allowed_destination = z_locality_default();
#endif
    options->timeout_ms = 0;
    options->accept_replies = z_reply_keyexpr_default();
}

z_result_t z_declare_querier(const z_loaned_session_t *zs, z_owned_querier_t *querier,
                             const z_loaned_keyexpr_t *keyexpr, z_querier_options_t *options) {
    querier->_val = _z_querier_null();

    // Set options
    z_querier_options_t opt;
    if (options != NULL) {
        opt = *options;
    } else {
        z_querier_options_default(&opt);
    }
    if (opt.timeout_ms == 0) {
        opt.timeout_ms = Z_GET_TIMEOUT_DEFAULT;
    }
    z_reliability_t reliability = Z_RELIABILITY_DEFAULT;
    z_locality_t allowed_destination = z_locality_default();
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    allowed_destination = opt.allowed_destination;
#endif

    z_result_t res = _z_declare_querier(&querier->_val, zs, keyexpr, opt.consolidation.mode, opt.congestion_control,
                                        opt.target, opt.priority, opt.is_express, opt.timeout_ms,
                                        opt.encoding == NULL ? NULL : &opt.encoding->_this._val, reliability,
                                        allowed_destination, opt.accept_replies);
    _Z_SET_IF_OK(res,
                 _z_write_filter_create(zs, &querier->_val._filter, &querier->_val._key, _Z_INTEREST_FLAG_QUERYABLES,
                                        querier->_val._target == Z_QUERY_TARGET_ALL_COMPLETE, allowed_destination));
    return res;
}

z_result_t z_undeclare_querier(z_moved_querier_t *querier) { return _z_undeclare_querier(&querier->_this._val); }

z_result_t z_querier_get(const z_loaned_querier_t *querier, const char *parameters, z_moved_closure_reply_t *callback,
                         z_querier_get_options_t *options) {
    return z_querier_get_with_parameters_substr(querier, parameters, parameters == NULL ? 0 : strlen(parameters),
                                                callback, options);
}

z_result_t z_querier_get_with_parameters_substr(const z_loaned_querier_t *querier, const char *parameters,
                                                size_t parameters_len, z_moved_closure_reply_t *callback,
                                                z_querier_get_options_t *options) {
    z_result_t ret = _Z_RES_OK;
    _z_closure_reply_t closure = callback->_this._val;
    z_internal_closure_reply_null(&callback->_this);

    z_querier_get_options_t opt;
    z_querier_get_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    _z_encoding_t encoding;
    if (opt.encoding == NULL) {
        encoding = _z_encoding_alias(
            &querier->_encoding);  // it is safe to use alias, since it is unaffected by clear operation
    } else {
        encoding = _z_encoding_steal(&opt.encoding->_this._val);
    }

    _z_session_t *session = NULL;

    // Try to upgrade session rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&querier->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        session = _Z_RC_IN_VAL(&sess_rc);
    } else {
        _Z_ERROR_LOG(_Z_ERR_SESSION_CLOSED);
        ret = _Z_ERR_SESSION_CLOSED;
    }

    _z_source_info_t *source_info = NULL;
    _z_cancellation_token_rc_t *cancellation_token = NULL;
    bool should_proceed = ret == _Z_RES_OK && !_z_write_filter_active(&querier->_filter);
#if Z_FEATURE_MULTICAST_DECLARATIONS == 0
    should_proceed = should_proceed || (session->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE);
#endif
#ifdef Z_FEATURE_UNSTABLE_API
    source_info = opt.source_info;
    cancellation_token = opt.cancellation_token == NULL ? NULL : &opt.cancellation_token->_this._rc;
#endif
    if (should_proceed) {
        _z_n_qos_t qos = _z_n_qos_make(querier->_is_express, querier->_congestion_control == Z_CONGESTION_CONTROL_BLOCK,
                                       querier->_priority);
        ret = _z_query(&sess_rc, _z_optional_id_make_some(querier->_id), &querier->_key, parameters, parameters_len,
                       querier->_target, querier->_consolidation_mode, _z_bytes_from_moved(opt.payload), &encoding,
                       closure.call, closure.drop, closure.context, querier->_timeout_ms,
                       _z_bytes_from_moved(opt.attachment), qos, source_info, querier->_accept_replies,
                       querier->_allowed_destination, cancellation_token);
    } else if (closure.drop != NULL) {
        closure.drop(closure.context);
    }

    _z_session_rc_drop(&sess_rc);
    // Clean-up
#ifdef Z_FEATURE_UNSTABLE_API
    z_cancellation_token_drop(opt.cancellation_token);
#endif
    z_bytes_drop(opt.payload);
    _z_encoding_clear(&encoding);
    z_bytes_drop(opt.attachment);
    return ret;
}

const z_loaned_keyexpr_t *z_querier_keyexpr(const z_loaned_querier_t *querier) {
    return (const z_loaned_keyexpr_t *)&querier->_key;
}

#ifdef Z_FEATURE_UNSTABLE_API
z_entity_global_id_t z_querier_id(const z_loaned_querier_t *querier) {
    z_entity_global_id_t egid;
    _z_session_t *session = NULL;
#if Z_FEATURE_SESSION_CHECK == 1
    // Try to upgrade session rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&querier->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        session = _Z_RC_IN_VAL(&sess_rc);
    } else {
        egid = _z_entity_global_id_null();
    }
#else
    session = _Z_RC_IN_VAL(&querier->_zn);
#endif

    if (session != NULL) {
        egid.zid = session->_local_zid;
        egid.eid = (uint32_t)querier->_id;
    } else {
        egid = _z_entity_global_id_null();
    }

#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return egid;
}
#endif

#if Z_FEATURE_MATCHING == 1
z_result_t z_querier_declare_background_matching_listener(const z_loaned_querier_t *querier,
                                                          z_moved_closure_matching_status_t *callback) {
    return z_querier_declare_matching_listener(querier, NULL, callback);
}
z_result_t z_querier_declare_matching_listener(const z_loaned_querier_t *querier,
                                               z_owned_matching_listener_t *matching_listener,
                                               z_moved_closure_matching_status_t *callback) {
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&querier->_zn);
    z_result_t ret = _Z_RES_OK;
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        if (matching_listener != NULL) {
            matching_listener->_val = _z_matching_listener_null();
            ret = _z_matching_listener_declare(&matching_listener->_val, _Z_RC_IN_VAL(&sess_rc), &querier->_filter.ctx,
                                               &callback->_this._val);
        } else {
            uint32_t _listener_id;
            ret = _z_matching_listener_register(&_listener_id, _Z_RC_IN_VAL(&sess_rc), &querier->_filter.ctx,
                                                &callback->_this._val);
        }
        _z_session_rc_drop(&sess_rc);
    } else {
        if (matching_listener != NULL) {
            matching_listener->_val = _z_matching_listener_null();
        }
        _z_closure_matching_status_clear(&callback->_this._val);
        z_internal_closure_matching_status_null(&callback->_this);
        ret = _Z_ERR_GENERIC;
    }
    return ret;
}

z_result_t z_querier_get_matching_status(const z_loaned_querier_t *querier, z_matching_status_t *matching_status) {
    matching_status->matching = !_z_write_filter_active(&querier->_filter);
    return _Z_RES_OK;
}

#endif  // Z_FEATURE_MATCHING == 1

bool z_reply_is_ok(const z_loaned_reply_t *reply) { return reply->data._tag != _Z_REPLY_TAG_ERROR; }

const z_loaned_sample_t *z_reply_ok(const z_loaned_reply_t *reply) { return &reply->data._result.sample; }

const z_loaned_reply_err_t *z_reply_err(const z_loaned_reply_t *reply) { return &reply->data._result.error; }

#ifdef Z_FEATURE_UNSTABLE_API
bool z_reply_replier_id(const z_loaned_reply_t *reply, z_entity_global_id_t *out_id) {
    if (_z_entity_global_id_check(&reply->data.replier_id)) {
        *out_id = reply->data.replier_id;
        return true;
    }
    return false;
}
#endif  // Z_FEATURE_UNSTABLE_API

#endif  // Z_FEATURE_QUERY == 1

#if Z_FEATURE_QUERYABLE == 1
_Z_OWNED_FUNCTIONS_RC_IMPL(query)

z_result_t z_query_take_from_loaned(z_owned_query_t *dst, z_loaned_query_t *src) {
    dst->_rc = *src;
    _z_query_t q = _z_query_null();
    *src = _z_query_rc_new_from_val(&q);
    if (_Z_RC_IS_NULL(src)) {
        *src = dst->_rc;  // reset src to its original value
        z_internal_query_null(dst);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    return _Z_RES_OK;
}

void _z_queryable_drop(_z_queryable_t *queryable) {
    _z_undeclare_queryable(queryable);
    _z_queryable_clear(queryable);
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_queryable_t, queryable, _z_queryable_check, _z_queryable_null,
                                              _z_queryable_drop)

void z_queryable_options_default(z_queryable_options_t *options) {
    options->complete = _Z_QUERYABLE_COMPLETE_DEFAULT;
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    options->allowed_origin = z_locality_default();
#endif
}

z_result_t z_declare_background_queryable(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                          z_moved_closure_query_t *callback, const z_queryable_options_t *options) {
    return z_declare_queryable(zs, NULL, keyexpr, callback, options);
}

z_result_t z_declare_queryable(const z_loaned_session_t *zs, z_owned_queryable_t *queryable,
                               const z_loaned_keyexpr_t *keyexpr, z_moved_closure_query_t *callback,
                               const z_queryable_options_t *options) {
    _z_closure_query_t closure = callback->_this._val;
    z_internal_closure_query_null(&callback->_this);

    z_queryable_options_t opt;
    z_queryable_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    z_locality_t allowed_origin = z_locality_default();
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    allowed_origin = opt.allowed_origin;
#endif
    if (queryable != NULL) {
        return _z_declare_queryable(&queryable->_val, zs, keyexpr, opt.complete, closure.call, closure.drop,
                                    closure.context, allowed_origin);
    } else {
        uint32_t _queryable_id;
        return _z_register_queryable(&_queryable_id, zs, keyexpr, opt.complete, closure.call, closure.drop,
                                     closure.context, allowed_origin, NULL);
    }
}

z_result_t z_undeclare_queryable(z_moved_queryable_t *queryable) {
    z_result_t ret = _z_undeclare_queryable(&queryable->_this._val);
    _z_queryable_clear(&queryable->_this._val);
    return ret;
}

const z_loaned_keyexpr_t *z_queryable_keyexpr(const z_loaned_queryable_t *queryable) {
    // Retrieve keyexpr from session
    const z_loaned_keyexpr_t *ret = NULL;
    uint32_t lookup = queryable->_entity_id;
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&queryable->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        return ret;
    }
    _z_session_t *zn = _Z_RC_IN_VAL(&sess_rc);
#else
    _z_session_t *zn = _z_session_weak_as_unsafe_ptr(&sub->_zn);
#endif
    if (_z_session_mutex_lock_if_open(zn) != _Z_RES_OK) {
        _Z_WARN("Failed to lock session for queryable keyexpr retrieval - session may be closing");
#if Z_FEATURE_SESSION_CHECK == 1
        _z_session_rc_drop(&sess_rc);
#endif
        return ret;
    }
    _z_session_queryable_rc_slist_t *node = zn->_local_queryable;
    while (node != NULL) {
        _z_session_queryable_rc_t *val = _z_session_queryable_rc_slist_value(node);
        if (_Z_RC_IN_VAL(val)->_id == lookup) {
            ret = (const z_loaned_keyexpr_t *)&_Z_RC_IN_VAL(val)->_key;
            break;
        }
        node = _z_session_queryable_rc_slist_next(node);
    }
    _z_session_mutex_unlock(zn);
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return ret;
}

void z_query_reply_options_default(z_query_reply_options_t *options) {
    options->encoding = NULL;
    options->congestion_control = Z_CONGESTION_CONTROL_BLOCK;
    options->priority = Z_PRIORITY_DEFAULT;
    options->timestamp = NULL;
    options->is_express = false;
    options->attachment = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    options->source_info = NULL;
#endif
}

z_result_t z_query_reply(const z_loaned_query_t *query, const z_loaned_keyexpr_t *keyexpr, z_moved_bytes_t *payload,
                         const z_query_reply_options_t *options) {
    // Try upgrading session weak to rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&_Z_RC_IN_VAL(query)->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    // Set options
    z_query_reply_options_t opts;
    if (options == NULL) {
        z_query_reply_options_default(&opts);
    } else {
        opts = *options;
    }
    _z_source_info_t *source_info = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    source_info = opts.source_info;
#endif
    z_result_t ret = _z_send_reply(_Z_RC_IN_VAL(query), &sess_rc, keyexpr, _z_bytes_from_moved(payload),
                                   _z_encoding_from_moved(opts.encoding), Z_SAMPLE_KIND_PUT, opts.is_express,
                                   opts.timestamp, _z_bytes_from_moved(opts.attachment), source_info);
    // Clean-up
    _z_session_rc_drop(&sess_rc);
    z_encoding_drop(opts.encoding);
    z_bytes_drop(opts.attachment);
    z_bytes_drop(payload);
    return ret;
}

z_result_t _z_query_reply_sample(const z_loaned_query_t *query, z_loaned_sample_t *sample,
                                 const z_query_reply_options_t *options) {
    // Try upgrading session weak to rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&_Z_RC_IN_VAL(query)->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    // Set options
    z_query_reply_options_t opts;
    if (options == NULL) {
        z_query_reply_options_default(&opts);
    } else {
        opts = *options;
    }

    z_result_t ret =
        _z_send_reply(_Z_RC_IN_VAL(query), &sess_rc, &sample->keyexpr, &sample->payload, &sample->encoding,
                      sample->kind, opts.is_express, &sample->timestamp, &sample->attachment, &sample->source_info);
    // Clean-up
    _z_session_rc_drop(&sess_rc);
    return ret;
}

void z_query_reply_del_options_default(z_query_reply_del_options_t *options) {
    options->congestion_control = Z_CONGESTION_CONTROL_BLOCK;
    options->priority = Z_PRIORITY_DEFAULT;
    options->timestamp = NULL;
    options->is_express = false;
    options->attachment = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    options->source_info = NULL;
#endif
}

z_result_t z_query_reply_del(const z_loaned_query_t *query, const z_loaned_keyexpr_t *keyexpr,
                             const z_query_reply_del_options_t *options) {
    // Try upgrading session weak to rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&_Z_RC_IN_VAL(query)->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    z_query_reply_del_options_t opts;
    if (options == NULL) {
        z_query_reply_del_options_default(&opts);
    } else {
        opts = *options;
    }
    _z_source_info_t *source_info = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    source_info = opts.source_info;
#endif
    z_result_t ret = _z_send_reply(_Z_RC_IN_VAL(query), &sess_rc, keyexpr, NULL, NULL, Z_SAMPLE_KIND_DELETE,
                                   opts.is_express, opts.timestamp, _z_bytes_from_moved(opts.attachment), source_info);
    // Clean-up
    _z_session_rc_drop(&sess_rc);
    z_bytes_drop(opts.attachment);
    return ret;
}

void z_query_reply_err_options_default(z_query_reply_err_options_t *options) { options->encoding = NULL; }

z_result_t z_query_reply_err(const z_loaned_query_t *query, z_moved_bytes_t *payload,
                             const z_query_reply_err_options_t *options) {
    // Try upgrading session weak to rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&_Z_RC_IN_VAL(query)->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    z_query_reply_err_options_t opts;
    if (options == NULL) {
        z_query_reply_err_options_default(&opts);
    } else {
        opts = *options;
    }
    z_result_t ret = _z_send_reply_err(_Z_RC_IN_VAL(query), &sess_rc, _z_bytes_from_moved(payload),
                                       _z_encoding_from_moved(opts.encoding));
    // Clean-up
    _z_session_rc_drop(&sess_rc);
    z_encoding_drop(opts.encoding);
    z_bytes_drop(payload);
    return ret;
}

#ifdef Z_FEATURE_UNSTABLE_API
z_entity_global_id_t z_queryable_id(const z_loaned_queryable_t *queryable) {
    z_entity_global_id_t egid;
    _z_session_t *session = NULL;
#if Z_FEATURE_SESSION_CHECK == 1
    // Try to upgrade session rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&queryable->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        session = _Z_RC_IN_VAL(&sess_rc);
    } else {
        egid = _z_entity_global_id_null();
    }
#else
    session = _Z_RC_IN_VAL(&queryable->_zn);
#endif

    if (session != NULL) {
        egid.zid = session->_local_zid;
        egid.eid = queryable->_entity_id;
    } else {
        egid = _z_entity_global_id_null();
    }

#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return egid;
}
#endif

#endif

z_result_t z_keyexpr_from_str_autocanonize(z_owned_keyexpr_t *key, const char *name) {
    size_t len = strlen(name);
    return z_keyexpr_from_substr_autocanonize(key, name, &len);
}

z_result_t z_keyexpr_from_substr_autocanonize(z_owned_keyexpr_t *key, const char *name, size_t *len) {
    _Z_RETURN_IF_ERR(z_keyexpr_from_substr(key, name, *len));

    _Z_CLEAN_RETURN_IF_ERR(
        z_keyexpr_canonize((char *)_z_string_data(&key->_val._inner._keyexpr), &key->_val._inner._keyexpr._slice.len),
        _z_declared_keyexpr_clear(&key->_val));
    *len = _z_string_len(&key->_val._inner._keyexpr);
    return _Z_RES_OK;
}

z_result_t z_keyexpr_from_str(z_owned_keyexpr_t *key, const char *name) {
    return z_keyexpr_from_substr(key, name, strlen(name));
}

z_result_t z_keyexpr_from_substr(z_owned_keyexpr_t *key, const char *name, size_t len) {
    z_internal_keyexpr_null(key);
    return _z_declared_keyexpr_from_substr(&key->_val, name, len);
}

z_result_t z_declare_keyexpr(const z_loaned_session_t *zs, z_owned_keyexpr_t *key, const z_loaned_keyexpr_t *keyexpr) {
#if Z_FEATURE_MULTICAST_DECLARATIONS == 0
    if (_Z_RC_IN_VAL(zs)->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE) {
        _Z_WARN(
            "Declaring a keyexpr without Z_FEATURE_MULTICAST_DECLARATIONS might generate unknown key expression errors "
            "during communications\n");
    }
#endif
    return _z_declared_keyexpr_declare(zs, &key->_val, keyexpr);
}

z_result_t z_undeclare_keyexpr(const z_loaned_session_t *zs, z_moved_keyexpr_t *keyexpr) {
    _z_keyexpr_wire_declaration_rc_t *declaration = &keyexpr->_this._val._declaration;
    z_result_t ret = _Z_RES_OK;
    if (_Z_RC_IS_NULL(declaration)) {
        ret = _Z_ERR_INVALID;
    } else if (!_z_keyexpr_wire_declaration_is_declared_on_session(_Z_RC_IN_VAL(declaration), _Z_RC_IN_VAL(zs))) {
        ret = _Z_ERR_KEYEXPR_DECLARED_ON_ANOTHER_SESSION;
    } else if (_z_keyexpr_wire_declaration_rc_strong_count(declaration) == 1) {
        ret = _z_keyexpr_wire_declaration_undeclare(_Z_RC_IN_VAL(declaration));
    }
    z_keyexpr_drop(keyexpr);
    return ret;
}

#if Z_FEATURE_SUBSCRIPTION == 1
void _z_subscriber_drop(_z_subscriber_t *sub) {
    _z_undeclare_subscriber(sub);
    _z_subscriber_clear(sub);
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_subscriber_t, subscriber, _z_subscriber_check, _z_subscriber_null,
                                              _z_subscriber_drop)

void z_subscriber_options_default(z_subscriber_options_t *options) {
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    options->allowed_origin = z_locality_default();
#else
    options->__dummy = 0;
#endif
}

z_result_t z_declare_background_subscriber(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                           z_moved_closure_sample_t *callback, const z_subscriber_options_t *options) {
    return z_declare_subscriber(zs, NULL, keyexpr, callback, options);
}

z_result_t z_declare_subscriber(const z_loaned_session_t *zs, z_owned_subscriber_t *sub,
                                const z_loaned_keyexpr_t *keyexpr, z_moved_closure_sample_t *callback,
                                const z_subscriber_options_t *options) {
    _z_closure_sample_t closure = callback->_this._val;
    z_internal_closure_sample_null(&callback->_this);

    z_subscriber_options_t opt;
    z_subscriber_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    z_locality_t allowed_origin = z_locality_default();
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    allowed_origin = opt.allowed_origin;
#endif
    if (sub != NULL) {
        sub->_val = _z_subscriber_null();
        return _z_declare_subscriber(&sub->_val, zs, keyexpr, closure.call, closure.drop, closure.context,
                                     allowed_origin);
    } else {
        uint32_t _sub_id;
        return _z_register_subscriber(&_sub_id, zs, keyexpr, closure.call, closure.drop, closure.context,
                                      allowed_origin, NULL);
    }
}

z_result_t z_undeclare_subscriber(z_moved_subscriber_t *sub) {
    z_result_t ret = _z_undeclare_subscriber(&sub->_this._val);
    _z_subscriber_clear(&sub->_this._val);
    return ret;
}

const z_loaned_keyexpr_t *z_subscriber_keyexpr(const z_loaned_subscriber_t *sub) {
    const z_loaned_keyexpr_t *ret = NULL;
    // Retrieve keyexpr from session
    uint32_t lookup = sub->_entity_id;
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&sub->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        return ret;
    }
    _z_session_t *zn = _Z_RC_IN_VAL(&sess_rc);
#else
    _z_session_t *zn = _z_session_weak_as_unsafe_ptr(&sub->_zn);
#endif
    if (_z_session_mutex_lock_if_open(zn) != _Z_RES_OK) {
        _Z_WARN("Failed to lock session for subscriber keyexpr retrieval - session may be closing");
#if Z_FEATURE_SESSION_CHECK == 1
        _z_session_rc_drop(&sess_rc);
#endif
        return ret;
    }
    _z_subscription_rc_slist_t *node = zn->_subscriptions;
    while (node != NULL) {
        _z_subscription_rc_t *val = _z_subscription_rc_slist_value(node);
        if (_Z_RC_IN_VAL(val)->_id == lookup) {
            ret = (const z_loaned_keyexpr_t *)&_Z_RC_IN_VAL(val)->_key;
            break;
        }
        node = _z_subscription_rc_slist_next(node);
    }
    _z_session_mutex_unlock(zn);
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return ret;
}

#ifdef Z_FEATURE_UNSTABLE_API
z_entity_global_id_t z_subscriber_id(const z_loaned_subscriber_t *subscriber) {
    z_entity_global_id_t egid;
    _z_session_t *session = NULL;
#if Z_FEATURE_SESSION_CHECK == 1
    // Try to upgrade session rc
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&subscriber->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        session = _Z_RC_IN_VAL(&sess_rc);
    } else {
        egid = _z_entity_global_id_null();
    }
#else
    session = _Z_RC_IN_VAL(&subscriber->_zn);
#endif

    if (session != NULL) {
        egid.zid = session->_local_zid;
        egid.eid = subscriber->_entity_id;
    } else {
        egid = _z_entity_global_id_null();
    }

#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return egid;
}
#endif
#endif

#if Z_FEATURE_BATCHING == 1
z_result_t zp_batch_start(const z_loaned_session_t *zs) {
    if (_Z_RC_IS_NULL(zs)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    _z_session_t *session = _Z_RC_IN_VAL(zs);
    return _z_transport_start_batching(&session->_tp) ? _Z_RES_OK : _Z_ERR_GENERIC;
}

z_result_t zp_batch_flush(const z_loaned_session_t *zs) {
    _z_session_t *session = _Z_RC_IN_VAL(zs);
    if (_Z_RC_IS_NULL(zs)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    // Send current batch without dropping
    return _z_send_n_batch(session, Z_CONGESTION_CONTROL_BLOCK);
}

z_result_t zp_batch_stop(const z_loaned_session_t *zs) {
    _z_session_t *session = _Z_RC_IN_VAL(zs);
    if (_Z_RC_IS_NULL(zs)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    _z_transport_stop_batching(&session->_tp);
    // Send remaining batch without dropping
    return _z_send_n_batch(session, Z_CONGESTION_CONTROL_BLOCK);
}
#endif

#if Z_FEATURE_MATCHING == 1
void _z_matching_listener_drop(_z_matching_listener_t *listener) {
    _z_matching_listener_undeclare(listener);
    _z_matching_listener_clear(listener);
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_matching_listener_t, matching_listener, _z_matching_listener_check,
                                              _z_matching_listener_null, _z_matching_listener_drop)

z_result_t z_undeclare_matching_listener(z_moved_matching_listener_t *listener) {
    z_result_t ret = _z_matching_listener_undeclare(&listener->_this._val);
    _z_matching_listener_clear(&listener->_this._val);
    return ret;
}
#endif
#if Z_FEATURE_MULTI_THREAD == 1
/**************** Tasks ****************/
void zp_task_read_options_default(zp_task_read_options_t *options) { options->task_attributes = NULL; }

z_result_t zp_start_read_task(z_loaned_session_t *zs, const zp_task_read_options_t *options) {
    return _z_background_executor_start(&_Z_RC_IN_VAL(zs)->_runtime, options == NULL ? NULL : options->task_attributes);
}

z_result_t zp_stop_read_task(z_loaned_session_t *zs) {
    return _z_runtime_stop((_z_runtime_t *)&_Z_RC_IN_VAL(zs)->_runtime);
}

bool zp_read_task_is_running(const z_loaned_session_t *zs) {
    return _z_background_executor_is_running(&_Z_RC_IN_VAL(zs)->_runtime);
}

void zp_task_lease_options_default(zp_task_lease_options_t *options) { options->task_attributes = NULL; }

z_result_t zp_start_lease_task(z_loaned_session_t *zs, const zp_task_lease_options_t *options) {
    _ZP_UNUSED(zs);
    _ZP_UNUSED(options);
    return _Z_RES_OK;
}

z_result_t zp_stop_lease_task(z_loaned_session_t *zs) {
    _ZP_UNUSED(zs);
    return _Z_RES_OK;
}

bool zp_lease_task_is_running(const z_loaned_session_t *zs) {
    return _z_background_executor_is_running(&_Z_RC_IN_VAL(zs)->_runtime);
}
#else
void zp_read_options_default(zp_read_options_t *options) { options->single_read = false; }

z_result_t zp_read(const z_loaned_session_t *zs, const zp_read_options_t *options) {
    zp_read_options_t opt;
    if (options != NULL) {
        opt = *options;
    } else {
        zp_read_options_default(&opt);
    }
    return _zp_read(_Z_RC_IN_VAL(zs), opt.single_read);
}

void zp_send_keep_alive_options_default(zp_send_keep_alive_options_t *options) { options->__dummy = 0; }

z_result_t zp_send_keep_alive(const z_loaned_session_t *zs, const zp_send_keep_alive_options_t *options) {
    (void)(options);
    return _zp_send_keep_alive(_Z_RC_IN_VAL(zs));
}

void zp_send_join_options_default(zp_send_join_options_t *options) { options->__dummy = 0; }

z_result_t zp_send_join(const z_loaned_session_t *zs, const zp_send_join_options_t *options) {
    (void)(options);
    return _zp_send_join(_Z_RC_IN_VAL(zs));
}

void zp_spin_once(const z_loaned_session_t *zs) {
    if (!z_session_is_closed(zs)) {
        _z_runtime_spin_once((_z_runtime_t *)&_Z_RC_IN_VAL(zs)->_runtime);
    }
}
#endif

#ifdef Z_FEATURE_UNSTABLE_API
z_reliability_t z_reliability_default(void) { return Z_RELIABILITY_DEFAULT; }
#endif

#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_QUERY == 1

_Z_OWNED_FUNCTIONS_RC_IMPL(cancellation_token)

z_result_t z_cancellation_token_new(z_owned_cancellation_token_t *cancellation_token) {
    _z_cancellation_token_t *ct = (_z_cancellation_token_t *)z_malloc(sizeof(_z_cancellation_token_t));
    if (ct == NULL) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    _Z_CLEAN_RETURN_IF_ERR(_z_cancellation_token_create(ct), z_free(ct));

    cancellation_token->_rc = _z_cancellation_token_rc_new(ct);
    if (_Z_RC_IS_NULL(&cancellation_token->_rc)) {
        _z_cancellation_token_clear(ct);
        z_free(ct);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    return _Z_RES_OK;
}

z_result_t z_cancellation_token_cancel(z_loaned_cancellation_token_t *cancellation_token) {
    return _z_cancellation_token_cancel(_Z_RC_IN_VAL(cancellation_token));
}

bool z_cancellation_token_is_cancelled(const z_loaned_cancellation_token_t *cancellation_token) {
    return _z_cancellation_token_is_cancelled(_Z_RC_IN_VAL(cancellation_token));
}
#endif
#endif
