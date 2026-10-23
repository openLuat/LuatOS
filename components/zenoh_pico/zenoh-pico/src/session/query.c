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

#include "zenoh-pico/session/query.h"

#include <stddef.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/net/reply.h"
#include "zenoh-pico/net/sample.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/utils/locality.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_QUERY == 1
void _z_pending_query_clear(_z_pending_query_t *pen_qry) {
    if (pen_qry->_dropper != NULL) {
        pen_qry->_dropper(pen_qry->_arg);
        pen_qry->_dropper = NULL;
    }
    _z_keyexpr_clear(&pen_qry->_key);
    _z_pending_reply_slist_free(&pen_qry->_pending_replies);
    pen_qry->_allowed_destination = z_locality_default();
    pen_qry->_remaining_finals = 0;
#ifdef Z_FEATURE_UNSTABLE_API
    _z_pending_query_cancellation_data_clear(&pen_qry->_cancellation_data);
#endif
}

bool _z_pending_query_eq(const _z_pending_query_t *one, const _z_pending_query_t *two) { return one->_id == two->_id; }
bool _z_pending_query_querier_eq(const _z_pending_query_t *one, const _z_pending_query_t *two) {
    return one->_querier_id.has_value == two->_querier_id.has_value && one->_querier_id.value == two->_querier_id.value;
}

static bool _z_pending_query_timeout(const _z_pending_query_t *foo, const _z_pending_query_t *pq) {
    _ZP_UNUSED(foo);
    bool result = z_clock_elapsed_ms((z_clock_t *)&pq->_start_time) >= pq->_timeout;
    if (result) {
        _Z_INFO("Dropping query because of timeout");
    }
    return result;
}

void _z_pending_query_process_timeout(_z_session_t *zn) {
    _z_session_mutex_lock(zn);
    // Extract all queries with timeout elapsed
    zn->_pending_queries = _z_pending_query_slist_drop_all_filter(zn->_pending_queries, _z_pending_query_timeout, NULL);
    _z_session_mutex_unlock(zn);
}

_z_fut_fn_result_t _z_pending_query_process_timeout_task_fn(void *session_arg, _z_executor_t *executor) {
    _ZP_UNUSED(executor);
    _z_session_t *zn = (_z_session_t *)session_arg;
    _z_pending_query_process_timeout(zn);
    return _z_fut_fn_result_wake_up_after(1000);
}

/*------------------ Query ------------------*/
/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
_z_pending_query_t *_z_unsafe_get_pending_query_by_id(_z_session_t *zn, const _z_zint_t id) {
    _z_pending_query_t *ret = NULL;

    _z_pending_query_slist_t *xs = zn->_pending_queries;
    while (xs != NULL) {
        _z_pending_query_t *pql = _z_pending_query_slist_value(xs);
        if (pql->_id == id) {
            ret = pql;
            break;
        }

        xs = _z_pending_query_slist_next(xs);
    }
    return ret;
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
_z_pending_query_t *_z_unsafe_register_pending_query(_z_session_t *zn) {
    _z_zint_t qid = zn->_query_id++;
    zn->_pending_queries = _z_pending_query_slist_push_empty(zn->_pending_queries);
    _z_pending_query_t *pq = _z_pending_query_slist_value(zn->_pending_queries);
    pq->_id = qid;
    return pq;
}

static z_result_t _z_trigger_query_reply_partial_inner(_z_session_t *zn, const _z_zint_t id, _z_keyexpr_t *keyexpr,
                                                       _z_msg_put_t *msg, z_sample_kind_t kind,
                                                       _z_entity_global_id_t *replier_id) {
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_keyexpr_clear(keyexpr); _z_msg_put_clear(msg));

    // Get query infos
    _z_pending_query_t *pen_qry = _z_unsafe_get_pending_query_by_id(zn, id);
    if (pen_qry == NULL) {
        _z_session_mutex_unlock(zn);
        _z_keyexpr_clear(keyexpr);
        _z_msg_put_clear(msg);
        // Not concerned by the reply
        return _Z_RES_OK;
    }

    if (!pen_qry->_anyke && !_z_keyexpr_intersects(&pen_qry->_key, keyexpr)) {
        _z_session_mutex_unlock(zn);
        _z_keyexpr_clear(keyexpr);
        _z_msg_put_clear(msg);
        // Not concerned by the reply
        return _Z_RES_OK;
    }
    // Build the reply
    _z_reply_t reply;
    _z_reply_steal_data(&reply, keyexpr, *replier_id, &msg->_payload, &msg->_commons._timestamp, &msg->_encoding, kind,
                        &msg->_attachment, &msg->_commons._source_info);
    // Process monotonic & latest consolidation mode
    if ((pen_qry->_consolidation == Z_CONSOLIDATION_MODE_LATEST) ||
        (pen_qry->_consolidation == Z_CONSOLIDATION_MODE_MONOTONIC)) {
        bool drop = false;
        _z_pending_reply_slist_t *curr_node = pen_qry->_pending_replies;
        _z_pending_reply_t *pen_rep = NULL;

        // Verify if this is a newer reply, free the old one in case it is
        while (curr_node != NULL) {
            pen_rep = _z_pending_reply_slist_value(curr_node);
            // Check if this is the same resource key
            if (_z_declared_keyexpr_equals(&pen_rep->_reply.data._result.sample.keyexpr,
                                           &reply.data._result.sample.keyexpr)) {
                if (msg->_commons._timestamp.time <= pen_rep->_tstamp.time) {
                    drop = true;
                } else {
                    pen_qry->_pending_replies = _z_pending_reply_slist_drop_first_filter(pen_qry->_pending_replies,
                                                                                         _z_pending_reply_eq, pen_rep);
                }
                break;
            }
            curr_node = _z_pending_reply_slist_next(curr_node);
        }
        if (!drop) {
            // Cache most recent reply
            _z_pending_reply_t tmp_rep;
            if (pen_qry->_consolidation == Z_CONSOLIDATION_MODE_MONOTONIC) {
                // No need to store the whole reply in the monotonic mode.
                tmp_rep._reply = _z_reply_null();
                tmp_rep._reply.data._tag = _Z_REPLY_TAG_DATA;
                _Z_CLEAN_RETURN_IF_ERR(_z_declared_keyexpr_copy(&tmp_rep._reply.data._result.sample.keyexpr,
                                                                &reply.data._result.sample.keyexpr),
                                       _z_reply_clear(&reply);
                                       _z_session_mutex_unlock(zn));
            } else {
                // Copy the reply to store it out of context
                _Z_CLEAN_RETURN_IF_ERR(_z_reply_move(&tmp_rep._reply, &reply), _z_reply_clear(&reply);
                                       _z_session_mutex_unlock(zn));
            }
            tmp_rep._tstamp = _z_timestamp_duplicate(&msg->_commons._timestamp);
            pen_qry->_pending_replies = _z_pending_reply_slist_push(pen_qry->_pending_replies, &tmp_rep);
            _Z_DEBUG("stored reply for id=%jd consolidation=%d", (intmax_t)id, pen_qry->_consolidation);
        }
    }
    _z_session_mutex_unlock(zn);

    // Trigger callback if applicable
    if (pen_qry->_consolidation != Z_CONSOLIDATION_MODE_LATEST) {
        _Z_DEBUG("immediate callback for id=%jd", (intmax_t)id);
        pen_qry->_callback(&reply, pen_qry->_arg);
    }
    _z_reply_clear(&reply);
    return _Z_RES_OK;
}

z_result_t _z_trigger_query_reply_partial(_z_session_t *zn, const _z_zint_t id, _z_wireexpr_t *wireexpr,
                                          _z_msg_put_t *msg, z_sample_kind_t kind, _z_entity_global_id_t *replier_id,
                                          _z_transport_peer_common_t *peer) {
    _z_keyexpr_t keyexpr;
    z_result_t ret = _z_get_keyexpr_from_wireexpr(zn, &keyexpr, wireexpr, peer, true);

    _Z_SET_IF_OK(ret, _z_trigger_query_reply_partial_inner(zn, id, &keyexpr, msg, kind, replier_id));
    // Clean up
    _z_keyexpr_clear(&keyexpr);
    _z_wireexpr_clear(wireexpr);
    _z_msg_put_clear(msg);
    return ret;
}

z_result_t _z_trigger_query_reply_err(_z_session_t *zn, _z_zint_t id, _z_msg_err_t *msg,
                                      _z_entity_global_id_t *replier_id) {
    // Retrieve query
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_bytes_drop(&msg->_payload);
                           _z_encoding_clear(&msg->_encoding));
    _z_pending_query_t *pen_qry = _z_unsafe_get_pending_query_by_id(zn, id);
    _z_session_mutex_unlock(zn);
    if (pen_qry == NULL) {
        // Not concerned by the reply
        _z_bytes_drop(&msg->_payload);
        _z_encoding_clear(&msg->_encoding);
        return _Z_RES_OK;
    }
    // Trigger the user callback
    _z_reply_t reply;
    _z_reply_err_steal_data(&reply, &msg->_payload, &msg->_encoding, *replier_id);
    pen_qry->_callback(&reply, pen_qry->_arg);
    _z_reply_clear(&reply);
    return _Z_RES_OK;
}

z_result_t _z_trigger_query_reply_final(_z_session_t *zn, _z_zint_t id) {
    // Retrieve query
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    _z_pending_query_t *pen_qry = _z_unsafe_get_pending_query_by_id(zn, id);
    if (pen_qry == NULL) {
        _z_session_mutex_unlock(zn);
        // Not concerned by the reply
        return _Z_RES_OK;
    }
    _Z_DEBUG("trigger_reply_final id=%jd", (intmax_t)id);

    if (pen_qry->_remaining_finals > 0) {
        pen_qry->_remaining_finals--;
    }

    bool do_finalize = (pen_qry->_remaining_finals == 0);

    if (pen_qry->_consolidation == Z_CONSOLIDATION_MODE_LATEST && do_finalize) {
        while (pen_qry->_pending_replies != NULL) {
            _z_pending_reply_t *pen_rep = _z_pending_reply_slist_value(pen_qry->_pending_replies);

            // Trigger the query handler
            _Z_DEBUG("deliver pending reply in final id=%jd", (intmax_t)id);
            pen_qry->_callback(&pen_rep->_reply, pen_qry->_arg);
            pen_qry->_pending_replies = _z_pending_reply_slist_pop(pen_qry->_pending_replies);
        }
    }
    // Finalize query if requested: drop pending query and trigger dropper callback,
    // which is equivalent to a reply with FINAL.
    if (do_finalize) {
        zn->_pending_queries =
            _z_pending_query_slist_drop_first_filter(zn->_pending_queries, _z_pending_query_eq, pen_qry);
    }
    _z_session_mutex_unlock(zn);
    return _Z_RES_OK;
}

void _z_unregister_pending_query(_z_session_t *zn, _z_zint_t qid) {
    _z_pending_query_t target = {0};
    target._id = qid;
    _z_session_mutex_lock(zn);
    zn->_pending_queries = _z_pending_query_slist_drop_first_filter(zn->_pending_queries, _z_pending_query_eq, &target);
    _z_session_mutex_unlock(zn);
}

void _z_unregister_pending_queries_from_querier(_z_session_t *zn, uint32_t querier_id) {
    _z_pending_query_t target = {0};
    target._querier_id = _z_optional_id_make_some(querier_id);
    _z_session_mutex_lock(zn);
    zn->_pending_queries =
        _z_pending_query_slist_drop_all_filter(zn->_pending_queries, _z_pending_query_querier_eq, &target);
    _z_session_mutex_unlock(zn);
}

void _z_flush_pending_queries(_z_session_t *zn) {
    _z_session_mutex_lock(zn);
    _z_pending_query_slist_t *queries = zn->_pending_queries;
    zn->_pending_queries = _z_pending_query_slist_new();
    _z_session_mutex_unlock(zn);
    _z_pending_query_slist_free(&queries);
}
#ifdef Z_FEATURE_UNSTABLE_API

typedef struct _z_cancel_pending_query_arg_t {
    _z_session_weak_t _zn;
    _z_zint_t _qid;
} _z_cancel_pending_query_arg_t;

z_result_t _z_cancel_pending_query(void *arg) {
    _z_cancel_pending_query_arg_t *a = (_z_cancel_pending_query_arg_t *)arg;
    _z_session_rc_t s_rc = _z_session_weak_upgrade_if_open(&a->_zn);
    if (!_Z_RC_IS_NULL(&s_rc)) {
        _z_unregister_pending_query(_Z_RC_IN_VAL(&s_rc), a->_qid);
    }
    _z_session_rc_drop(&s_rc);
    return _Z_RES_OK;
}

void _z_cancel_pending_query_arg_drop(void *arg) {
    _z_cancel_pending_query_arg_t *a = (_z_cancel_pending_query_arg_t *)arg;
    _z_session_weak_drop(&a->_zn);
    z_free(a);
}

z_result_t _z_pending_query_register_cancellation(_z_pending_query_t *pq,
                                                  const _z_cancellation_token_rc_t *opt_cancellation_token,
                                                  const _z_session_rc_t *zn) {
    pq->_cancellation_data = _z_pending_query_cancellation_data_null();
    if (opt_cancellation_token != NULL) {
        _z_cancel_pending_query_arg_t *arg =
            (_z_cancel_pending_query_arg_t *)z_malloc(sizeof(_z_cancel_pending_query_arg_t));
        if (arg == NULL) {
            return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        }
        arg->_zn = _z_session_rc_clone_as_weak(zn);
        arg->_qid = pq->_id;

        size_t handler_id = 0;
        _z_cancellation_token_on_cancel_handler_t handler;
        handler._on_cancel = _z_cancel_pending_query;
        handler._on_drop = _z_cancel_pending_query_arg_drop;
        handler._arg = (void *)arg;
        _Z_CLEAN_RETURN_IF_ERR(
            _z_cancellation_token_add_on_cancel_handler(_Z_RC_IN_VAL(opt_cancellation_token), &handler, &handler_id),
            _z_cancellation_token_on_cancel_handler_drop(&handler));
        pq->_cancellation_data._cancellation_token = _z_cancellation_token_rc_clone(opt_cancellation_token);
        pq->_cancellation_data._handler_id = handler_id;
        _Z_CLEAN_RETURN_IF_ERR(
            _z_cancellation_token_get_notifier(_Z_RC_IN_VAL(opt_cancellation_token), &pq->_cancellation_data._notifier),
            _z_pending_query_cancellation_data_clear(&pq->_cancellation_data));
    }
    return _Z_RES_OK;
}
#endif

#else

void _z_pending_query_process_timeout(_z_session_t* zn) {
    _ZP_UNUSED(zn);
    return;
}

#endif
