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

#ifndef ZENOH_PICO_REPLY_NETAPI_H
#define ZENOH_PICO_REPLY_NETAPI_H

#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/list.h"
#include "zenoh-pico/collections/refcount.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/net/encoding.h"
#include "zenoh-pico/net/sample.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/session.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Reply tag values.
 *
 * Enumerators:
 *     _Z_REPLY_TAG_DATA: Tag identifying that the reply contains some data.
 *     _Z_REPLY_TAG_FINAL: Tag identifying that the reply does not contain any data and that there will be no more
 *         replies for this query.
 *     _Z_REPLY_TAG_ERROR: Tag identifying that the reply contains error.
 *     _Z_REPLY_TAG_NONE: Tag identifying empty reply.
 */
typedef enum {
    _Z_REPLY_TAG_DATA = 0,
    _Z_REPLY_TAG_FINAL = 1,
    _Z_REPLY_TAG_ERROR = 2,
    _Z_REPLY_TAG_NONE = 3
} _z_reply_tag_t;

/**
 * An reply to a :c:func:`z_query`.
 *
 * Members:
 *   _z_sample_t data: a :c:type:`_z_sample_t` containing the key and value of the reply.
 *   _z_slice_t replier_id: The id of the entity that sent this reply.
 *
 */
typedef struct _z_reply_data_t {
    union {
        _z_value_t error;
        _z_sample_t sample;
    } _result;
    _z_entity_global_id_t replier_id;
    _z_reply_tag_t _tag;
} _z_reply_data_t;

// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_reply_data_t _z_reply_data_null(void) { return (_z_reply_data_t){0}; }
void _z_reply_data_clear(_z_reply_data_t *rd);
z_result_t _z_reply_data_copy(_z_reply_data_t *dst, const _z_reply_data_t *src);

/**
 * An reply to a :c:func:`z_query`.
 *
 * Members:
 *   _z_reply_t_Tag tag: Indicates if the reply contains data or if it's a FINAL reply.
 *   _z_reply_data_t data: The reply data if :c:member:`_z_reply_t.tag` equals
 * :c:member:`_z_reply_t_Tag._Z_REPLY_TAG_DATA`.
 *
 */
typedef struct _z_reply_t {
    _z_reply_data_t data;
} _z_reply_t;

// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_reply_t _z_reply_null(void) { return (_z_reply_t){0}; }
void _z_reply_steal_data(_z_reply_t *dst, _z_keyexpr_t *keyexpr, _z_entity_global_id_t replier_id, _z_bytes_t *payload,
                         const _z_timestamp_t *timestamp, _z_encoding_t *encoding, z_sample_kind_t kind,
                         _z_bytes_t *attachment, _z_source_info_t *source_info);
void _z_reply_err_steal_data(_z_reply_t *dst, _z_bytes_t *payload, _z_encoding_t *encoding,
                             _z_entity_global_id_t replier_id);
z_result_t _z_reply_move(_z_reply_t *dst, _z_reply_t *src);
void _z_reply_clear(_z_reply_t *src);
void _z_reply_free(_z_reply_t **hello);
z_result_t _z_reply_copy(_z_reply_t *dst, const _z_reply_t *src);

typedef struct _z_pending_reply_t {
    _z_reply_t _reply;
    _z_timestamp_t _tstamp;
} _z_pending_reply_t;

bool _z_pending_reply_eq(const _z_pending_reply_t *one, const _z_pending_reply_t *two);
void _z_pending_reply_clear(_z_pending_reply_t *res);

_Z_ELEM_DEFINE(_z_pending_reply, _z_pending_reply_t, _z_noop_size, _z_pending_reply_clear, _z_noop_copy, _z_noop_move,
               _z_pending_reply_eq, _z_noop_cmp, _z_noop_hash)
_Z_SLIST_DEFINE(_z_pending_reply, _z_pending_reply_t, false)

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_REPLY_NETAPI_H */
