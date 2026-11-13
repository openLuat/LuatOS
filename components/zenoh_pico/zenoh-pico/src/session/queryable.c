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

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "zenoh-pico/api/types.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/net/filtering.h"
#include "zenoh-pico/net/query.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/utils/locality.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"
#include "zenoh-pico/utils/string.h"

#if Z_FEATURE_QUERYABLE == 1

#define _Z_QLEINFOS_VEC_SIZE 4  // Arbitrary initial size

static inline _z_queryable_cache_data_t _z_queryable_cache_data_null(void) {
    _z_queryable_cache_data_t ret = {0};
    return ret;
}

void _z_unsafe_queryable_cache_invalidate(_z_session_t *zn) {
#if Z_FEATURE_RX_CACHE == 1
    _z_queryable_lru_cache_clear(&zn->_queryable_cache);
#else
    _ZP_UNUSED(zn);
#endif
}

#if Z_FEATURE_RX_CACHE == 1
int _z_queryable_cache_data_compare(const void *first, const void *second) {
    const _z_queryable_cache_data_t *first_data = (const _z_queryable_cache_data_t *)first;
    const _z_queryable_cache_data_t *second_data = (const _z_queryable_cache_data_t *)second;
    if (first_data->is_remote != second_data->is_remote) {
        return (int)first_data->is_remote - (int)second_data->is_remote;
    }
    return _z_keyexpr_compare(&first_data->ke, &second_data->ke);
}
#endif  // Z_FEATURE_RX_CACHE == 1

void _z_queryable_cache_data_clear(_z_queryable_cache_data_t *val) {
    _z_session_queryable_rc_svec_rc_drop(&val->infos);
    _z_keyexpr_clear(&val->ke);
}

bool _z_session_queryable_eq(const _z_session_queryable_t *one, const _z_session_queryable_t *two) {
    return one->_id == two->_id;
}

void _z_session_queryable_clear(_z_session_queryable_t *qle) {
    if (qle->_dropper != NULL) {
        qle->_dropper(qle->_arg);
        qle->_dropper = NULL;
    }
    _z_declared_keyexpr_clear(&qle->_key);
    _z_sync_group_notifier_drop(&qle->_session_callback_drop_notifier);
    _z_sync_group_notifier_drop(&qle->_queryable_callback_drop_notifier);
}

/*------------------ Queryable ------------------*/
static _z_session_queryable_rc_t *__z_get_session_queryable_by_id(_z_session_queryable_rc_slist_t *qles,
                                                                  const _z_zint_t id) {
    _z_session_queryable_rc_t *ret = NULL;

    _z_session_queryable_rc_slist_t *xs = qles;
    while (xs != NULL) {
        _z_session_queryable_rc_t *qle = _z_session_queryable_rc_slist_value(xs);
        if (id == _Z_RC_IN_VAL(qle)->_id) {
            ret = qle;
            break;
        }
        xs = _z_session_queryable_rc_slist_next(xs);
    }

    return ret;
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
static _z_session_queryable_rc_t *__unsafe_z_get_session_queryable_by_id(_z_session_t *zn, const _z_zint_t id) {
    _z_session_queryable_rc_slist_t *qles = zn->_local_queryable;
    return __z_get_session_queryable_by_id(qles, id);
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
static z_result_t __unsafe_z_get_session_queryables_by_key(_z_session_t *zn, const _z_keyexpr_t *key, bool is_remote,
                                                           _z_session_queryable_rc_svec_t *qle_infos) {
    _z_session_queryable_rc_slist_t *qles = zn->_local_queryable;

    *qle_infos = _z_session_queryable_rc_svec_make(_Z_QLEINFOS_VEC_SIZE);
    _Z_RETURN_ERR_OOM_IF_TRUE(qle_infos->_val == NULL);
    _z_session_queryable_rc_slist_t *xs = qles;
    while (xs != NULL) {
        // Parse queryable list
        _z_session_queryable_rc_t *qle = _z_session_queryable_rc_slist_value(xs);
        const _z_session_queryable_t *qle_val = _Z_RC_IN_VAL(qle);
        bool origin_allowed = is_remote ? _z_locality_allows_remote(qle_val->_allowed_origin)
                                        : _z_locality_allows_local(qle_val->_allowed_origin);
        if (origin_allowed && _z_keyexpr_intersects(&qle_val->_key._inner, key)) {
            _z_session_queryable_rc_t qle_clone = _z_session_queryable_rc_clone(qle);
            _Z_CLEAN_RETURN_IF_ERR(_z_session_queryable_rc_svec_append(qle_infos, &qle_clone, false),
                                   _z_session_queryable_rc_svec_clear(qle_infos));
        }
        xs = _z_session_queryable_rc_slist_next(xs);
    }
    return _Z_RES_OK;
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
static z_result_t __unsafe_z_get_session_queryables_rc_by_key(_z_session_t *zn, const _z_keyexpr_t *key, bool is_remote,
                                                              _z_session_queryable_rc_svec_rc_t *qle_infos) {
    *qle_infos = _z_session_queryable_rc_svec_rc_new_undefined();
    z_result_t ret = !_Z_RC_IS_NULL(qle_infos) ? _Z_RES_OK : _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    _Z_SET_IF_OK(ret, __unsafe_z_get_session_queryables_by_key(zn, key, is_remote, _Z_RC_IN_VAL(qle_infos)));
    if (ret != _Z_RES_OK) {
        _z_session_queryable_rc_svec_rc_drop(qle_infos);
    }
    return _Z_RES_OK;
}

_z_session_queryable_rc_t _z_get_session_queryable_by_id(_z_session_t *zn, const _z_zint_t id) {
    _z_session_queryable_rc_t out = _z_session_queryable_rc_null();
    _z_session_mutex_lock(zn);

    _z_session_queryable_rc_t *qle = __unsafe_z_get_session_queryable_by_id(zn, id);
    if (qle != NULL) {
        out = _z_session_queryable_rc_clone(qle);
    }
    _z_session_mutex_unlock(zn);

    return out;
}

_z_session_queryable_rc_t _z_register_session_queryable(_z_session_t *zn, _z_session_queryable_t *q) {
    _Z_DEBUG(">>> Allocating queryable for (%.*s)", (int)_z_string_len(&q->_key._inner._keyexpr),
             _z_string_data(&q->_key._inner._keyexpr));

    _z_session_queryable_rc_t out = _z_session_queryable_rc_new_from_val(q);
    if (_Z_RC_IS_NULL(&out)) {
        return out;
    }
    if (_z_session_mutex_lock_if_open(zn) != _Z_RES_OK) {
        _Z_WARN("Failed to acquire session mutex for registering queryable - session is closed");
        _z_session_queryable_rc_drop(&out);
        *q = _z_session_queryable_null();
        return out;
    }
    _z_unsafe_queryable_cache_invalidate(zn);
    zn->_local_queryable = _z_session_queryable_rc_slist_push_empty(zn->_local_queryable);
    _z_session_queryable_rc_t *ret = _z_session_queryable_rc_slist_value(zn->_local_queryable);
    *ret = _z_session_queryable_rc_clone(
        &out);  // immediately increase reference count to prevent eventual drop by concurrent session close
    _z_session_mutex_unlock(zn);

#if Z_FEATURE_LOCAL_QUERYABLE == 1
    if (!_Z_RC_IS_NULL(&out) && _z_locality_allows_local(q->_allowed_origin)) {
        _z_session_queryable_t *qle_val = _Z_RC_IN_VAL(&out);
        _z_write_filter_notify_queryable(zn, &qle_val->_key._inner, qle_val->_allowed_origin, qle_val->_complete, true);
    }
#endif

    return out;
}

static z_result_t _z_session_queryable_get_infos(_z_session_t *zn, _z_queryable_cache_data_t *out,
                                                 const _z_wireexpr_t *wireexpr, _z_transport_peer_common_t *peer) {
    out->is_remote = (peer != NULL);
    _Z_RETURN_IF_ERR(_z_get_keyexpr_from_wireexpr(zn, &out->ke, wireexpr, peer, true));
    _z_queryable_cache_data_t *cache_entry = NULL;
    z_result_t ret = _Z_RES_OK;
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_keyexpr_clear(&out->ke));
#if Z_FEATURE_RX_CACHE == 1
    cache_entry = _z_queryable_lru_cache_get(&zn->_queryable_cache, out);
    if (cache_entry != NULL && cache_entry->is_remote != out->is_remote) {
        cache_entry = NULL;
    }
#endif
    if (cache_entry != NULL) {  // Copy cache entry
        out->infos = _z_session_queryable_rc_svec_rc_clone(&cache_entry->infos);
    } else {  // Build queryable data
        _Z_SET_IF_OK(ret, __unsafe_z_get_session_queryables_rc_by_key(zn, &out->ke, out->is_remote, &out->infos));
#if Z_FEATURE_RX_CACHE == 1
        // Update cache
        _z_queryable_cache_data_t cache_storage = _z_queryable_cache_data_null();
        cache_storage.infos = _z_session_queryable_rc_svec_rc_clone(&out->infos);
        cache_storage.is_remote = out->is_remote;
        _Z_SET_IF_OK(ret, _z_keyexpr_copy(&cache_storage.ke, &out->ke));
        _Z_SET_IF_OK(ret, _z_queryable_lru_cache_insert(&zn->_queryable_cache, &cache_storage));
        if (ret != _Z_RES_OK) {
            _z_queryable_cache_data_clear(&cache_storage);
        }
#endif
    }
    _z_session_mutex_unlock(zn);
    if (ret != _Z_RES_OK) {
        _z_queryable_cache_data_clear(out);
    }
    return ret;
}

z_result_t _z_trigger_queryables(_z_transport_common_t *transport, _z_msg_query_t *msgq, _z_wireexpr_t *q_key,
                                 uint32_t qid, _z_n_qos_t qos, _z_transport_peer_common_t *peer) {
    bool is_local = peer == NULL;
    _z_session_t *zn = _z_transport_common_get_session(transport);
    _z_queryable_cache_data_t qle_infos = _z_queryable_cache_data_null();
    // Retrieve sub infos
    _Z_CLEAN_RETURN_IF_ERR(_z_session_queryable_get_infos(zn, &qle_infos, q_key, peer), _z_wireexpr_clear(q_key);
                           _z_msg_query_clear(msgq));
    // Check if there are queryables
    const _z_session_queryable_rc_svec_t *qles = _Z_RC_IN_VAL(&qle_infos.infos);
    size_t qle_nb = _z_session_queryable_rc_svec_len(qles);
    _Z_DEBUG("Triggering %ju queryables for key %.*s", (uintmax_t)qle_nb, (int)_z_string_len(&qle_infos.ke._keyexpr),
             _z_string_data(&qle_infos.ke._keyexpr));

    if (qle_nb == 0) {  // optimization for local queries, since moves can imply extra copy if aliased
        _z_wireexpr_clear(q_key);
        _z_queryable_cache_data_clear(&qle_infos);
        _z_msg_query_clear(msgq);
        _z_session_send_reply_final(zn, qid, is_local);
        return _Z_RES_OK;
    }
    // Build the z_query
    _z_query_rc_t query = _z_query_rc_new_undefined();
    z_result_t ret = _Z_RC_IS_NULL(&query) ? _Z_ERR_SYSTEM_OUT_OF_MEMORY : _Z_RES_OK;
    // Note: _z_query_move_data will make copies of all aliased fields, since query is under ref count
    // and thus it is impossible to detect when user moves it out of callback
    _Z_SET_IF_OK(ret, _z_query_move_data(_Z_RC_IN_VAL(&query), &msgq->_ext_value, &qle_infos.ke, &msgq->_parameters,
                                         &transport->_session, qid, &msgq->_ext_attachment, msgq->_implicit_anyke,
                                         &msgq->_ext_info));
    _Z_CLEAN_RETURN_IF_ERR(ret, _z_wireexpr_clear(q_key); _z_msg_query_clear(msgq);
                           _z_queryable_cache_data_clear(&qle_infos); _z_query_rc_drop(&query))

    _Z_RC_IN_VAL(&query)->_qos = qos;
    _Z_RC_IN_VAL(&query)->_is_local = is_local;
    // Parse session_queryable svec
    for (size_t i = 0; i < qle_nb; i++) {
        _z_session_queryable_t *qle_info = _Z_RC_IN_VAL(_z_session_queryable_rc_svec_get(qles, i));
        if (i + 1 == qle_nb) {
            qle_info->_callback(&query, qle_info->_arg);
        } else {
            _z_query_rc_t query_copy = _z_query_rc_clone(&query);
            qle_info->_callback(&query_copy, qle_info->_arg);
            _z_query_rc_drop(&query_copy);
        }
    }
    _z_wireexpr_clear(q_key);
    _z_query_rc_drop(&query);
    _z_queryable_cache_data_clear(&qle_infos);
    return _Z_RES_OK;
}

void _z_unregister_session_queryable(_z_session_t *zn, _z_session_queryable_rc_t *qle) {
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    _z_session_queryable_t *qle_val = _Z_RC_IN_VAL(qle);
    _z_write_filter_notify_queryable(zn, &qle_val->_key._inner, qle_val->_allowed_origin, qle_val->_complete, false);
#endif
    _z_session_mutex_lock(zn);
    _z_unsafe_queryable_cache_invalidate(zn);
    zn->_local_queryable =
        _z_session_queryable_rc_slist_drop_first_filter(zn->_local_queryable, _z_session_queryable_rc_eq, qle);
    _z_session_mutex_unlock(zn);
    _z_session_queryable_rc_drop(qle);
}

void _z_flush_session_queryable(_z_session_t *zn) {
    _z_session_queryable_rc_slist_t *queryables;
    _z_session_mutex_lock(zn);
    _z_unsafe_queryable_cache_invalidate(zn);
    queryables = zn->_local_queryable;
    zn->_local_queryable = _z_session_queryable_rc_slist_new();
    _z_session_mutex_unlock(zn);
    _z_session_queryable_rc_slist_free(&queryables);
}
#else  //  Z_FEATURE_QUERYABLE == 0

void _z_unsafe_queryable_cache_invalidate(_z_session_t *zn) { _ZP_UNUSED(zn); }

#endif  // Z_FEATURE_QUERYABLE == 1
