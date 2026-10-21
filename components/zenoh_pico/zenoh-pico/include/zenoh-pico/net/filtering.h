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

#ifndef ZENOH_PICO_FILTERING_NETAPI_H
#define ZENOH_PICO_FILTERING_NETAPI_H

#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/utils/locality.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uintptr_t peer;
    uint32_t decl_id;
} _z_filter_target_t;

typedef z_element_eq_f _z_filter_target_eq_f;
typedef z_element_eq_f _z_filter_target_predicate_f;
#define _z_filter_target_elem_copy _z_noop_copy
#define _z_filter_target_elem_clear _z_noop_clear
_Z_SLIST_DEFINE(_z_filter_target, _z_filter_target_t, false)

typedef enum {
    WRITE_FILTER_ACTIVE = 0,
    WRITE_FILTER_OFF = 1,
} _z_write_filter_state_t;

struct _z_write_filter_registration_t;

typedef enum {
    _Z_WRITE_FILTER_SUBSCRIBER = 0,
    _Z_WRITE_FILTER_QUERYABLE = 1,
} _z_write_filter_target_type_t;

typedef struct {
    _z_session_weak_t zn;
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_t mutex;
#endif
    _z_filter_target_slist_t *targets;
#if Z_FEATURE_MATCHING == 1
    _z_closure_matching_status_intmap_t callbacks;
#endif
    _z_keyexpr_t key;
    uint8_t state;
    bool is_complete;
    bool is_aggregate;
    bool allow_local;
    bool allow_remote;
    _z_write_filter_target_type_t target_type;
    size_t local_targets;
    struct _z_write_filter_registration_t *registration;
} _z_write_filter_ctx_t;

z_result_t _z_write_filter_ctx_clear(_z_write_filter_ctx_t *filter);

_Z_REFCOUNT_DEFINE_NO_FROM_VAL(_z_write_filter_ctx, _z_write_filter_ctx)

/**
 * Return type when declaring a queryable.
 */
typedef struct _z_write_filter_t {
    uint32_t _interest_id;
    _z_write_filter_ctx_rc_t ctx;
} _z_write_filter_t;

z_result_t _z_write_filter_create(const _z_session_rc_t *zn, _z_write_filter_t *filter,
                                  const _z_declared_keyexpr_t *keyexpr, uint8_t interest_flag, bool complete,
                                  z_locality_t locality);
z_result_t _z_write_filter_clear(_z_write_filter_t *filter);
void _z_write_filter_notify_subscriber(struct _z_session_t *session, const _z_keyexpr_t *key,
                                       z_locality_t allowed_origin, bool add);
void _z_write_filter_notify_queryable(struct _z_session_t *session, const _z_keyexpr_t *key,
                                      z_locality_t allowed_origin, bool is_complete, bool add);

#if Z_FEATURE_MATCHING
z_result_t _z_write_filter_ctx_add_callback(_z_write_filter_ctx_t *filter, size_t id, _z_closure_matching_status_t *v);
void _z_write_filter_ctx_remove_callback(_z_write_filter_ctx_t *filter, size_t id);
void _z_write_filter_ctx_remove_callbacks(_z_write_filter_ctx_t *ctx);
#endif

#if Z_FEATURE_INTEREST == 1
static inline bool _z_write_filter_ctx_active(const _z_write_filter_ctx_t *ctx) {
    return ctx->state == WRITE_FILTER_ACTIVE;
}
static inline bool _z_write_filter_active(const _z_write_filter_t *filter) {
    return _z_write_filter_ctx_active(_Z_RC_IN_VAL(&filter->ctx));
}
#else
static inline bool _z_write_filter_active(const _z_write_filter_t *filter) {
    _ZP_UNUSED(filter);
    return false;
}
#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_FILTERING_NETAPI_H */
