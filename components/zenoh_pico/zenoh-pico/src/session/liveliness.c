//
// Copyright (c) 2024 ZettaScale Technology
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

#include "zenoh-pico/api/liveliness.h"

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/collections/bytes.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/net/reply.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/subscription.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_LIVELINESS == 1
/**************** Liveliness Subscriber ****************/

#if Z_FEATURE_SUBSCRIPTION == 1
z_result_t _z_liveliness_process_remote_token_declare(_z_session_t *zn, uint32_t id, const _z_wireexpr_t *wireexpr,
                                                      const _z_timestamp_t *timestamp,
                                                      _z_transport_peer_common_t *peer) {
    _z_keyexpr_t ke;
    _Z_RETURN_IF_ERR(_z_get_keyexpr_from_wireexpr(zn, &ke, wireexpr, peer, false));
    z_result_t ret = _Z_RES_OK;
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_keyexpr_clear(&ke));

    const _z_keyexpr_t *pkeyexpr = _z_keyexpr_intmap_get(&zn->_remote_tokens, id);
    if (pkeyexpr != NULL) {
        // Already received this token
        _Z_DEBUG("Duplicate token id %i", (int)id);
        ret = _z_keyexpr_equals(pkeyexpr, &ke) ? _Z_RES_OK : _Z_ERR_KEYEXPR_NOT_MATCH;
        _z_session_mutex_unlock(zn);
        _z_keyexpr_clear(&ke);
        return ret;
    } else {
        _z_keyexpr_t *ke_on_heap = (_z_keyexpr_t *)z_malloc(sizeof(_z_keyexpr_t));
        if (ke_on_heap == NULL || _z_keyexpr_intmap_insert(&zn->_remote_tokens, id, ke_on_heap) == NULL) {
            ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            z_free(ke_on_heap);
        } else {
            *ke_on_heap = _z_keyexpr_steal(&ke);
        }
    }

    _z_session_mutex_unlock(zn);
    _z_wireexpr_t wireexpr2 = _z_wireexpr_alias(wireexpr);
    _Z_SET_IF_OK(ret, _z_trigger_liveliness_subscriptions_declare(zn, &wireexpr2, timestamp, peer));
    if (ret != _Z_RES_OK) {
        _z_session_mutex_lock(zn);
        // remote tokens kes do not reference any declaration, so it is safe to remove them under session mutex
        _z_keyexpr_intmap_remove(&zn->_remote_tokens, id);
        _z_session_mutex_unlock(zn);
        _z_keyexpr_clear(&ke);
    }
    return ret;
}

z_result_t _z_liveliness_process_remote_token_undeclare(_z_session_t *zn, uint32_t id,
                                                        const _z_timestamp_t *timestamp) {
    z_result_t ret = _Z_RES_OK;

    _z_keyexpr_t key = _z_keyexpr_null();
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    _z_keyexpr_t *keyexpr = (_z_keyexpr_t *)_z_keyexpr_intmap_get(&zn->_remote_tokens, id);
    if (keyexpr != NULL) {
        key = _z_keyexpr_steal(keyexpr);
        _z_keyexpr_intmap_remove(&zn->_remote_tokens, id);
    } else {
        _Z_ERROR_LOG(_Z_ERR_ENTITY_UNKNOWN);
        ret = _Z_ERR_ENTITY_UNKNOWN;
    }
    _z_session_mutex_unlock(zn);

    if (_z_keyexpr_check(&key)) {
        ret = _z_trigger_liveliness_subscriptions_undeclare(zn, &key, timestamp);
        _z_keyexpr_clear(&key);
    }
    return ret;
}

z_result_t _z_liveliness_subscription_undeclare_all(_z_session_t *zn) {
    z_result_t ret = _Z_RES_OK;

    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    // NOTE: it is safe to just move the data, since remote tokens store full copies of ke.
    _z_keyexpr_intmap_t token_list = zn->_remote_tokens;
    _z_keyexpr_intmap_init(&zn->_remote_tokens);
    _z_session_mutex_unlock(zn);

    _z_keyexpr_intmap_iterator_t iter = _z_keyexpr_intmap_iterator_make(&token_list);
    _z_timestamp_t tm = _z_timestamp_null();
    while (_z_keyexpr_intmap_iterator_next(&iter)) {
        _z_keyexpr_t *key = _z_keyexpr_intmap_iterator_value(&iter);
        ret = _z_trigger_liveliness_subscriptions_undeclare(zn, key, &tm);
        if (ret != _Z_RES_OK) {
            break;
        }
    }
    _z_keyexpr_intmap_clear(&token_list);

    return ret;
}
#endif  // Z_FEATURE_SUBSCRIPTION == 1

/**************** Liveliness Query ****************/

#if Z_FEATURE_QUERY == 1

void _z_liveliness_pending_query_clear(_z_liveliness_pending_query_t *pen_qry) {
    if (pen_qry->_dropper != NULL) {
        pen_qry->_dropper(pen_qry->_arg);
        pen_qry->_dropper = NULL;
    }
    _z_keyexpr_clear(&pen_qry->_key);
#ifdef Z_FEATURE_UNSTABLE_API
    _z_pending_query_cancellation_data_clear(&pen_qry->_cancellation_data);
#endif
}

_z_liveliness_pending_query_t *_z_unsafe_liveliness_register_pending_query(_z_session_t *zn) {
    _z_liveliness_pending_query_t *q = (_z_liveliness_pending_query_t *)z_malloc(sizeof(_z_liveliness_pending_query_t));
    if (q == NULL) {
        return NULL;
    }
    uint32_t id = zn->_liveliness_query_id++;
    q->_id = id;
    if (_z_liveliness_pending_query_intmap_insert(&zn->_liveliness_pending_queries, id, q) == NULL) {
        z_free(q);
        return NULL;
    }
    return q;
}

static z_result_t _z_liveliness_pending_query_reply(_z_session_t *zn, uint32_t interest_id,
                                                    const _z_wireexpr_t *wireexpr, const _z_timestamp_t *timestamp,
                                                    _z_transport_peer_common_t *peer) {
    _Z_DEBUG("Resolving %d - %.*s on mapping 0x%x", wireexpr->_id, (int)_z_string_len(&wireexpr->_suffix),
             _z_string_data(&wireexpr->_suffix), (unsigned int)wireexpr->_mapping);
    _z_keyexpr_t ke;
    _Z_RETURN_IF_ERR(_z_get_keyexpr_from_wireexpr(zn, &ke, wireexpr, peer, true));
    z_result_t ret = _Z_RES_OK;

    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));

    const _z_liveliness_pending_query_t *pq =
        _z_liveliness_pending_query_intmap_get(&zn->_liveliness_pending_queries, interest_id);
    if (pq == NULL) {
        _Z_ERROR_LOG(_Z_ERR_ENTITY_UNKNOWN);
        ret = _Z_ERR_ENTITY_UNKNOWN;
    }

    _Z_DEBUG("Liveliness pending query reply %i resolve result %i", (int)interest_id, ret);

    if (ret == _Z_RES_OK) {
        _Z_DEBUG("Reply liveliness query for %.*s", (int)_z_string_len(&ke._keyexpr), _z_string_data(&ke._keyexpr));

        if (!_z_keyexpr_intersects(&pq->_key, &ke)) {
            _Z_ERROR_LOG(_Z_ERR_QUERY_NOT_MATCH);
            ret = _Z_ERR_QUERY_NOT_MATCH;
        }

        if (ret == _Z_RES_OK) {
            _z_encoding_t encoding = _z_encoding_null();
            _z_bytes_t payload = _z_bytes_null();
            _z_bytes_t attachment = _z_bytes_null();
            _z_source_info_t source_info = _z_source_info_null();
            _z_reply_t reply;
            _z_reply_steal_data(&reply, &ke, _z_entity_global_id_null(), &payload, timestamp, &encoding,
                                Z_SAMPLE_KIND_PUT, &attachment, &source_info);

            pq->_callback(&reply, pq->_arg);
            _z_reply_clear(&reply);
        }
    }

    _z_session_mutex_unlock(zn);
    _z_keyexpr_clear(&ke);

    return ret;
}

z_result_t _z_liveliness_unregister_pending_query(_z_session_t *zn, uint32_t id) {
    z_result_t ret = _Z_ERR_ENTITY_UNKNOWN;
    _z_session_mutex_lock(zn);
    _z_liveliness_pending_query_t *pq =
        _z_liveliness_pending_query_intmap_extract(&zn->_liveliness_pending_queries, id);
    if (pq != NULL) {
        _z_liveliness_pending_query_clear(pq);
        z_free(pq);
        ret = _Z_RES_OK;
    }
    _z_session_mutex_unlock(zn);
    return ret;
}

#endif  // Z_FEATURE_QUERY == 1

/**************** Interest processing ****************/

z_result_t _z_liveliness_process_token_declare(_z_session_t *zn, const _z_n_msg_declare_t *decl,
                                               _z_transport_peer_common_t *peer) {
#if Z_FEATURE_QUERY == 1
    if (decl->_interest_id.has_value) {
        _z_liveliness_pending_query_reply(zn, decl->_interest_id.value, &decl->_decl._body._decl_token._keyexpr,
                                          &decl->_ext_timestamp, peer);
    }
#endif

#if Z_FEATURE_SUBSCRIPTION == 1
    return _z_liveliness_process_remote_token_declare(
        zn, decl->_decl._body._decl_token._id, &decl->_decl._body._decl_token._keyexpr, &decl->_ext_timestamp, peer);
#else
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
#endif
}

z_result_t _z_liveliness_process_token_undeclare(_z_session_t *zn, const _z_n_msg_declare_t *decl) {
#if Z_FEATURE_SUBSCRIPTION == 1
    return _z_liveliness_process_remote_token_undeclare(zn, decl->_decl._body._undecl_token._id, &decl->_ext_timestamp);
#else
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
    return _Z_RES_OK;
#endif
}

z_result_t _z_liveliness_process_declare_final(_z_session_t *zn, const _z_n_msg_declare_t *decl) {
    z_result_t ret = _Z_RES_OK;
#if Z_FEATURE_QUERY == 1
    if (decl->_interest_id.has_value) {
        ret = _z_liveliness_unregister_pending_query(zn, decl->_interest_id.value);
        if (ret != _Z_RES_OK) {
            _Z_ERROR_LOG(ret);
        } else {
            _Z_DEBUG("Liveliness pending query drop %zu", (size_t)decl->_interest_id.value);
        }
    }
#else
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
#endif
    return _Z_RES_OK;
}

/**************** Init/Clear ****************/

void _z_liveliness_init(_z_session_t *zn) {
    _z_session_mutex_lock(zn);

    zn->_remote_tokens = _z_keyexpr_intmap_make();
    zn->_local_tokens = _z_declared_keyexpr_intmap_make();
#if Z_FEATURE_QUERY == 1
    zn->_liveliness_query_id = 1;
    zn->_liveliness_pending_queries = _z_liveliness_pending_query_intmap_make();
#endif

    _z_session_mutex_unlock(zn);
}

void _z_liveliness_clear(_z_session_t *zn) {
    _z_session_mutex_lock(zn);
#if Z_FEATURE_QUERY == 1
    _z_liveliness_pending_query_intmap_clear(&zn->_liveliness_pending_queries);
#endif
    _z_declared_keyexpr_intmap_t local_tokens = zn->_local_tokens;
    zn->_local_tokens = _z_declared_keyexpr_intmap_make();
    _z_keyexpr_intmap_t remote_tokens = zn->_remote_tokens;
    zn->_remote_tokens = _z_keyexpr_intmap_make();
    _z_session_mutex_unlock(zn);
    // drop maps outside of session mutex to avoid deadlock
    _z_declared_keyexpr_intmap_clear(&local_tokens);
    _z_keyexpr_intmap_clear(&remote_tokens);
}

#else  // Z_FEATURE_LIVELINESS == 0

z_result_t _z_liveliness_process_token_declare(_z_session_t *zn, const _z_n_msg_declare_t *decl,
                                               _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}

z_result_t _z_liveliness_process_token_undeclare(_z_session_t *zn, const _z_n_msg_declare_t *decl) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
    return _Z_RES_OK;
}

z_result_t _z_liveliness_process_declare_final(_z_session_t *zn, const _z_n_msg_declare_t *decl) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
    return _Z_RES_OK;
}

#endif  // Z_FEATURE_LIVELINESS == 1
