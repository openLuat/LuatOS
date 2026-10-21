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

#ifndef ZENOH_PICO_SAMPLE_NETAPI_H
#define ZENOH_PICO_SAMPLE_NETAPI_H

#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/ring.h"
#include "zenoh-pico/net/encoding.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/session.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * A zenoh-net data sample.
 *
 * A sample is the value associated to a given resource at a given point in time.
 *
 * Members:
 *   _z_keyexpr_t key: The resource key of this data sample.
 *   _z_slice_t value: The value of this data sample.
 *   _z_encoding_t encoding: The encoding for the value of this data sample.
 *   _z_source_info_t source_info: The source info for this data sample (unstable).
 */
typedef struct _z_sample_t {
    _z_declared_keyexpr_t keyexpr;
    _z_bytes_t payload;
    _z_timestamp_t timestamp;
    _z_encoding_t encoding;
    z_sample_kind_t kind;
    _z_qos_t qos;
    _z_bytes_t attachment;
    z_reliability_t reliability;
    _z_source_info_t source_info;
} _z_sample_t;
void _z_sample_clear(_z_sample_t *sample);

// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_sample_t _z_sample_null(void) { return (_z_sample_t){0}; }
static inline bool _z_sample_check(const _z_sample_t *sample) {
    return _z_declared_keyexpr_check(&sample->keyexpr) || _z_encoding_check(&sample->encoding) ||
           _z_bytes_check(&sample->payload) || _z_bytes_check(&sample->attachment);
}
static inline size_t _z_sample_size(const _z_sample_t *s) {
    (void)(s);
    return sizeof(_z_sample_t);
}

void _z_sample_steal_data(_z_sample_t *dst, _z_keyexpr_t *key, _z_bytes_t *payload, const _z_timestamp_t *timestamp,
                          _z_encoding_t *encoding, z_sample_kind_t kind, _z_qos_t qos, _z_bytes_t *attachment,
                          z_reliability_t reliability, _z_source_info_t *source_info);
z_result_t _z_sample_copy_data(_z_sample_t *dst, const _z_declared_keyexpr_t *key, const _z_bytes_t *payload,
                               const _z_timestamp_t *timestamp, const _z_encoding_t *encoding, z_sample_kind_t kind,
                               _z_qos_t qos, const _z_bytes_t *attachment, z_reliability_t reliability,
                               const _z_source_info_t *source_info);
z_result_t _z_sample_move(_z_sample_t *dst, _z_sample_t *src);

/**
 * Free a :c:type:`_z_sample_t`, including its internal fields.
 *
 * Parameters:
 *     sample: The :c:type:`_z_sample_t` to free.
 */
void _z_sample_free(_z_sample_t **sample);

z_result_t _z_sample_copy(_z_sample_t *dst, const _z_sample_t *src);
_z_sample_t _z_sample_duplicate(const _z_sample_t *src);

_Z_ELEM_DEFINE(_z_sample, _z_sample_t, _z_sample_size, _z_sample_clear, _z_sample_copy, _z_sample_move, _z_noop_eq,
               _z_noop_cmp, _z_noop_hash)
_Z_RING_DEFINE(_z_sample, _z_sample_t)

#ifdef __cplusplus
}
#endif
#endif /* ZENOH_PICO_SAMPLE_NETAPI_H */
