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

#ifndef ZENOH_PICO_QUERY_NETAPI_H
#define ZENOH_PICO_QUERY_NETAPI_H

#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/collections/bytes.h"
#include "zenoh-pico/net/filtering.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/utils/query_params.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * The query to be answered by a queryable.
 */
typedef struct _z_query_t {
    _z_declared_keyexpr_t _key;
    _z_value_t _value;
    uint32_t _request_id;
    _z_session_weak_t _zn;
    _z_bytes_t _attachment;
    _z_string_t _parameters;
    _z_source_info_t _source_info;
    _z_n_qos_t _qos;
    bool _anyke;
    bool _is_local;
} _z_query_t;

// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_query_t _z_query_null(void) { return (_z_query_t){0}; }
static inline bool _z_query_check(const _z_query_t *query) {
    return _z_declared_keyexpr_check(&query->_key) || _z_value_check(&query->_value) ||
           _z_bytes_check(&query->_attachment) || _z_string_check(&query->_parameters);
}
z_result_t _z_query_send_reply_final(_z_query_t *q);
z_result_t _z_session_send_reply_final(_z_session_t *session, uint32_t query_id, bool is_local);
void _z_query_clear(_z_query_t *q);
void _z_query_free(_z_query_t **query);

_Z_REFCOUNT_DEFINE(_z_query, _z_query)

/**
 * Return type when declaring a querier.
 */
typedef struct _z_querier_t {
    _z_declared_keyexpr_t _key;
    uint32_t _id;
    _z_session_weak_t _zn;
    _z_encoding_t _encoding;
    z_consolidation_mode_t _consolidation_mode;
    z_query_target_t _target;
    z_congestion_control_t _congestion_control;
    z_priority_t _priority;
    z_reliability_t reliability;
    bool _is_express;
    z_reply_keyexpr_t _accept_replies;
    uint64_t _timeout_ms;
    z_locality_t _allowed_destination;
    _z_write_filter_t _filter;
} _z_querier_t;

#if Z_FEATURE_QUERY == 1
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_querier_t _z_querier_null(void) { return (_z_querier_t){0}; }
static inline bool _z_querier_check(const _z_querier_t *querier) { return !_Z_RC_IS_NULL(&querier->_zn); }
#endif

/**
 * Return type when declaring a queryable.
 */
typedef struct {
    uint32_t _entity_id;
    _z_session_weak_t _zn;
    _z_sync_group_t _callback_drop_sync_group;
} _z_queryable_t;

#if Z_FEATURE_QUERYABLE == 1
// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_queryable_t _z_queryable_null(void) { return (_z_queryable_t){0}; }
static inline bool _z_queryable_check(const _z_queryable_t *queryable) { return !_Z_RC_IS_NULL(&queryable->_zn); }
static inline z_result_t _z_query_move_data(_z_query_t *dst, _z_value_t *value, _z_keyexpr_t *key,
                                            _z_slice_t *parameters, const _z_session_weak_t *zn, uint32_t request_id,
                                            _z_bytes_t *attachment, bool implicit_anyke,
                                            const _z_source_info_t *source_info) {
    *dst = _z_query_null();
    dst->_anyke = implicit_anyke || _z_parameters_has_anyke((const char *)parameters->start, parameters->len);
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_move(&dst->_key._inner, key), _z_query_clear(dst));
    _Z_CLEAN_RETURN_IF_ERR(_z_value_move(&dst->_value, value), _z_query_clear(dst));
    _Z_CLEAN_RETURN_IF_ERR(_z_bytes_move(&dst->_attachment, attachment), _z_query_clear(dst));
    _Z_CLEAN_RETURN_IF_ERR(_z_slice_move(&dst->_parameters._slice, parameters), _z_query_clear(dst));
    dst->_request_id = request_id;
    dst->_zn = _z_session_weak_clone(zn);
    dst->_source_info = *source_info;
    return _Z_RES_OK;
}
void _z_queryable_clear(_z_queryable_t *qbl);
void _z_queryable_free(_z_queryable_t **qbl);

#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_QUERY_NETAPI_H */
