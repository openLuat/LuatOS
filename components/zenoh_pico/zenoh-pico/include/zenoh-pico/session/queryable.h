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

#ifndef ZENOH_PICO_SESSION_QUERYABLE_H
#define ZENOH_PICO_SESSION_QUERYABLE_H

#include <stdbool.h>
#include <zenoh-pico/session/session.h>

#include "zenoh-pico/collections/lru_cache.h"

// Forward declaration to avoid cyclical include
typedef struct _z_session_t _z_session_t;
typedef struct _z_session_rc_t _z_session_rc_t;

// Queryable infos
_Z_SVEC_DEFINE(_z_session_queryable_rc, _z_session_queryable_rc_t)
_Z_REFCOUNT_DEFINE(_z_session_queryable_rc_svec, _z_session_queryable_rc_svec)

typedef struct {
    _z_keyexpr_t ke;
    _z_session_queryable_rc_svec_rc_t infos;
    bool is_remote;
} _z_queryable_cache_data_t;

void _z_unsafe_queryable_cache_invalidate(_z_session_t *zn);
int _z_queryable_cache_data_compare(const void *first, const void *second);
void _z_queryable_cache_data_clear(_z_queryable_cache_data_t *val);

#if Z_FEATURE_QUERYABLE == 1
#define _Z_QUERYABLE_COMPLETE_DEFAULT false
#define _Z_QUERYABLE_DISTANCE_DEFAULT 0

#if Z_FEATURE_RX_CACHE == 1
_Z_ELEM_DEFINE(_z_queryable, _z_queryable_cache_data_t, _z_noop_size, _z_queryable_cache_data_clear, _z_noop_copy,
               _z_noop_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_LRU_CACHE_DEFINE(_z_queryable, _z_queryable_cache_data_t, _z_queryable_cache_data_compare)
#endif

/*------------------ Queryable ------------------*/
_z_session_queryable_rc_t _z_get_session_queryable_by_id(_z_session_t *zn, const _z_zint_t id);
_z_session_queryable_rc_t _z_register_session_queryable(_z_session_t *zn, _z_session_queryable_t *q);
z_result_t _z_trigger_queryables(_z_transport_common_t *transport, _z_msg_query_t *query, _z_wireexpr_t *q_key,
                                 uint32_t qid, _z_n_qos_t qos, _z_transport_peer_common_t *peer);
void _z_unregister_session_queryable(_z_session_t *zn, _z_session_queryable_rc_t *q);
void _z_flush_session_queryable(_z_session_t *zn);
#endif

#endif /* ZENOH_PICO_SESSION_QUERYABLE_H */
