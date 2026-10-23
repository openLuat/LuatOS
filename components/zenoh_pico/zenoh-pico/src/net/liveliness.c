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

#include "zenoh-pico/api/liveliness.h"

#include "zenoh-pico/net/liveliness.h"
#include "zenoh-pico/net/primitives.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/interest.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/subscription.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/utils/locality.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_LIVELINESS == 1

/**************** Liveliness Token ****************/
z_result_t _z_liveliness_send_declare_token(_z_session_t *zn, uint32_t id, const _z_declared_keyexpr_t *keyexpr) {
    _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(keyexpr, zn);
    _z_declaration_t declaration = _z_make_decl_token(&wireexpr, id);
    _z_network_message_t n_msg;
    _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());
    z_result_t ret = _z_send_declare(zn, &n_msg);
    _z_n_msg_clear(&n_msg);
    return ret;
}

z_result_t _z_liveliness_send_undeclare_token(_z_session_t *zn, uint32_t id, const _z_declared_keyexpr_t *keyexpr) {
    _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(keyexpr, zn);
    _z_declaration_t declaration = _z_make_undecl_token(id, &wireexpr);
    _z_network_message_t n_msg;
    _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());
    z_result_t ret = _z_send_undeclare(zn, &n_msg);
    _z_n_msg_clear(&n_msg);
    return ret;
}

z_result_t _z_declare_liveliness_token(const _z_session_rc_t *zn, _z_liveliness_token_t *ret_token,
                                       const _z_declared_keyexpr_t *keyexpr) {
    *ret_token = _z_liveliness_token_null();
    _Z_DEBUG("Declare liveliness token (%.*s)", (int)_z_string_len(&keyexpr->_inner._keyexpr),
             _z_string_data(&keyexpr->_inner._keyexpr));

    uint32_t id = _z_get_entity_id(_Z_RC_IN_VAL(zn));

    _z_declared_keyexpr_t ke;
    _Z_RETURN_IF_ERR(_z_declared_keyexpr_declare(zn, &ke, keyexpr));
    _Z_CLEAN_RETURN_IF_ERR(_z_liveliness_send_declare_token(_Z_RC_IN_VAL(zn), id, &ke), _z_declared_keyexpr_clear(&ke));
    z_result_t ret = _Z_RES_OK;

    if (_z_session_mutex_lock_if_open(_Z_RC_IN_VAL(zn)) != _Z_RES_OK) {
        _z_declared_keyexpr_clear(&ke);
        return _Z_ERR_SESSION_CLOSED;
    }
    const _z_declared_keyexpr_t *pkeyexpr = _z_declared_keyexpr_intmap_get(&_Z_RC_IN_VAL(zn)->_local_tokens, id);
    if (pkeyexpr != NULL) {
        // Already received this token
        _Z_ERROR("Duplicate token id %i", (int)id);
        ret = _Z_ERR_ENTITY_DECLARATION_FAILED;
    } else {
        _z_declared_keyexpr_t *ke_on_heap = (_z_declared_keyexpr_t *)z_malloc(sizeof(_z_declared_keyexpr_t));
        if (ke_on_heap == NULL ||
            _z_declared_keyexpr_intmap_insert(&_Z_RC_IN_VAL(zn)->_local_tokens, id, ke_on_heap) == NULL) {
            ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            z_free(ke_on_heap);
        } else {
            *ke_on_heap = ke;
        }
    }
    _z_session_mutex_unlock(_Z_RC_IN_VAL(zn));

    if (ret != _Z_RES_OK) {
        _z_liveliness_send_undeclare_token(_Z_RC_IN_VAL(zn), id, &ke);
        _z_declared_keyexpr_clear(&ke);
        return ret;
    }
    ret_token->_id = id;
    ret_token->_zn = _z_session_rc_clone_as_weak(zn);

    return _Z_RES_OK;
}

z_result_t _z_undeclare_liveliness_token(_z_liveliness_token_t *token) {
    if (token == NULL || _Z_RC_IS_NULL(&token->_zn)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&token->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        return _Z_ERR_SESSION_CLOSED;
    }
    _z_session_t *zn = _Z_RC_IN_VAL(&sess_rc);
#else
    _z_session_t *zn = _z_session_weak_as_unsafe_ptr(&token->_zn);
#endif
    z_result_t ret;
    _z_declared_keyexpr_t *ke = NULL;
    _Z_DEBUG("Unregister liveliness token (%i)", (int)token->_id);
    _z_session_mutex_lock(zn);
    ke = _z_declared_keyexpr_intmap_extract(&zn->_local_tokens, token->_id);
    _z_session_mutex_unlock(zn);
    if (ke != NULL) {
        ret = _z_liveliness_send_undeclare_token(zn, token->_id, ke);
        _z_declared_keyexpr_clear(
            ke);  // ke needs to be undeclared outside of mutex, since it might trigger resources update
        z_free(ke);
    } else {
        ret = _Z_ERR_ENTITY_UNKNOWN;
    }

#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return ret;
}

/**************** Liveliness Subscriber ****************/

z_result_t _z_liveliness_subscription_trigger_history(_z_session_t *zn, const _z_subscription_t *sub) {
    z_result_t ret = _Z_RES_OK;

    _Z_DEBUG("Retrieve liveliness history for %.*s", (int)_z_string_len(&sub->_key._inner._keyexpr),
             _z_string_data(&sub->_key._inner._keyexpr));

    _z_keyexpr_slist_t *tokens_list = _z_keyexpr_slist_new();
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    // TODO: could we call callbacks inside the mutex? - this would allow to avoid extra keyexpr copies, list
    // allocations, in addition it would also allow to stay consistent with respect to eventual remote undeclarations,
    // i.e. if they arrive during callback execution - they will only be delivered after initial history calls,
    // thus preventing potential declare/undeclare order inversion.
    // TODO: add support for local tokens
    _z_keyexpr_intmap_iterator_t iter = _z_keyexpr_intmap_iterator_make(&zn->_remote_tokens);
    while (_z_keyexpr_intmap_iterator_next(&iter)) {
        if (_z_keyexpr_intersects(&sub->_key._inner, _z_keyexpr_intmap_iterator_value(&iter))) {
            tokens_list = _z_keyexpr_slist_push(tokens_list, _z_keyexpr_intmap_iterator_value(&iter));
        }
    }
    _z_session_mutex_unlock(zn);

    _z_keyexpr_slist_t *pos = tokens_list;
    while (pos != NULL) {
        _z_sample_t s = _z_sample_null();
        s.kind = Z_SAMPLE_KIND_PUT;
        s.keyexpr._inner = _z_keyexpr_alias(_z_keyexpr_slist_value(pos));
        sub->_callback(&s, sub->_arg);
        _z_sample_clear(&s);
        pos = _z_keyexpr_slist_next(pos);
    }
    _z_keyexpr_slist_free(&tokens_list);

    return ret;
}

#if Z_FEATURE_SUBSCRIPTION == 1
z_result_t _z_register_liveliness_subscriber(uint32_t *out_sub_id, const _z_session_rc_t *zn,
                                             const _z_declared_keyexpr_t *keyexpr,
                                             _z_closure_sample_callback_t callback, _z_drop_handler_t dropper,
                                             bool history, void *arg, const _z_sync_group_t *callback_sync_group) {
    _z_subscription_t s = {0};
    s._id = _z_get_entity_id(_Z_RC_IN_VAL(zn));
    s._callback = callback;
    s._dropper = dropper;
    s._arg = arg;
    s._allowed_origin = z_locality_default();
    _Z_CLEAN_RETURN_IF_ERR(_z_declared_keyexpr_declare(zn, &s._key, keyexpr), _z_subscription_clear(&s));
    _Z_CLEAN_RETURN_IF_ERR(
        _z_sync_group_create_notifier(&_Z_RC_IN_VAL(zn)->_callback_drop_sync_group, &s._session_callback_drop_notifier),
        _z_subscription_clear(&s));
    if (callback_sync_group != NULL) {
        _Z_CLEAN_RETURN_IF_ERR(
            _z_sync_group_create_notifier(callback_sync_group, &s._subscriber_callback_drop_notifier),
            _z_subscription_clear(&s));
    }

    // Register subscription, stored at session-level, do not drop it by the end of this function.
    _z_subscription_rc_t sp_s =
        _z_register_subscription(_Z_RC_IN_VAL(zn), _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER, &s);
    if (_Z_RC_IS_NULL(&sp_s)) {
        _z_subscription_clear(&s);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    if (history) {
        _Z_CLEAN_RETURN_IF_ERR(
            _z_liveliness_subscription_trigger_history(_Z_RC_IN_VAL(zn), _Z_RC_IN_VAL(&sp_s)),
            _z_unregister_subscription(_Z_RC_IN_VAL(zn), _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER, &sp_s));
    }
    // Build the declare message to send on the wire
    uint8_t mode = history ? (_Z_INTEREST_FLAG_CURRENT | _Z_INTEREST_FLAG_FUTURE) : _Z_INTEREST_FLAG_FUTURE;
    _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(&_Z_RC_IN_VAL(&sp_s)->_key, _Z_RC_IN_VAL(zn));
    _z_interest_t interest = _z_make_interest(
        &wireexpr, s._id, _Z_INTEREST_FLAG_KEYEXPRS | _Z_INTEREST_FLAG_TOKENS | _Z_INTEREST_FLAG_RESTRICTED | mode);

    _z_network_message_t n_msg;
    _z_n_msg_make_interest(&n_msg, interest);
    z_result_t res = _z_send_declare(_Z_RC_IN_VAL(zn), &n_msg);
    _z_n_msg_clear(&n_msg);
    if (res != _Z_RES_OK) {
        _z_unregister_subscription(_Z_RC_IN_VAL(zn), _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER, &sp_s);
        res = _Z_ERR_TRANSPORT_TX_FAILED;
    } else {
        *out_sub_id = _Z_RC_IN_VAL(&sp_s)->_id;
        _z_subscription_rc_drop(&sp_s);
    }
    return res;
}
z_result_t _z_declare_liveliness_subscriber(_z_subscriber_t *subscriber, const _z_session_rc_t *zn,
                                            const _z_declared_keyexpr_t *keyexpr, _z_closure_sample_callback_t callback,
                                            _z_drop_handler_t dropper, bool history, void *arg) {
    *subscriber = _z_subscriber_null();
    subscriber->_zn = _z_session_rc_clone_as_weak(zn);
    z_result_t ret = _z_sync_group_create(&subscriber->_callback_drop_sync_group);
    _Z_SET_IF_OK(ret, _z_register_liveliness_subscriber(&subscriber->_entity_id, zn, keyexpr, callback, dropper,
                                                        history, arg, &subscriber->_callback_drop_sync_group));
    _Z_CLEAN_RETURN_IF_ERR(ret, _z_subscriber_clear(subscriber));
    return _Z_RES_OK;
}

z_result_t _z_undeclare_liveliness_subscriber(_z_subscriber_t *sub) {
    if (sub == NULL || _Z_RC_IS_NULL(&sub->_zn)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }

    _z_subscription_rc_t s =
        _z_get_subscription_by_id(_Z_RC_IN_VAL(&sub->_zn), _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER, sub->_entity_id);
    if (_Z_RC_IS_NULL(&s)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }

    _z_interest_t interest = _z_make_interest_final(_Z_RC_IN_VAL(&s)->_id);
    _z_network_message_t n_msg;
    _z_n_msg_make_interest(&n_msg, interest);
    if (_z_send_undeclare(_Z_RC_IN_VAL(&sub->_zn), &n_msg) != _Z_RES_OK) {
        _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
    }
    _z_n_msg_clear(&n_msg);

    _z_unregister_subscription(_Z_RC_IN_VAL(&sub->_zn), _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER, &s);
    return _z_sync_group_check(&sub->_callback_drop_sync_group) ? _z_sync_group_wait(&sub->_callback_drop_sync_group)
                                                                : _Z_RES_OK;
}
#endif  // Z_FEATURE_SUBSCRIPTION == 1

/**************** Liveliness Query ****************/

#if Z_FEATURE_QUERY == 1
#ifdef Z_FEATURE_UNSTABLE_API

typedef struct _z_cancel_liveliness_pending_query_arg_t {
    _z_session_weak_t _zn;
    uint32_t _qid;
} _z_cancel_liveliness_pending_query_arg_t;

z_result_t _z_cancel_liveliness_pending_query(void *arg) {
    _z_cancel_liveliness_pending_query_arg_t *a = (_z_cancel_liveliness_pending_query_arg_t *)arg;
    _z_session_rc_t s_rc = _z_session_weak_upgrade_if_open(&a->_zn);
    if (!_Z_RC_IS_NULL(&s_rc)) {
        _z_liveliness_unregister_pending_query(_Z_RC_IN_VAL(&s_rc), a->_qid);
        _z_session_rc_drop(&s_rc);
    }
    return _Z_RES_OK;
}

void _z_cancel_liveliness_pending_query_arg_drop(void *arg) {
    _z_cancel_liveliness_pending_query_arg_t *a = (_z_cancel_liveliness_pending_query_arg_t *)arg;
    _z_session_weak_drop(&a->_zn);
    z_free(a);
}

z_result_t _z_liveliness_pending_query_register_cancellation(_z_liveliness_pending_query_t *pq,
                                                             const _z_cancellation_token_rc_t *opt_cancellation_token,
                                                             const _z_session_rc_t *zn) {
    pq->_cancellation_data = _z_pending_query_cancellation_data_null();
    if (opt_cancellation_token != NULL) {
        _z_cancel_liveliness_pending_query_arg_t *arg =
            (_z_cancel_liveliness_pending_query_arg_t *)z_malloc(sizeof(_z_cancel_liveliness_pending_query_arg_t));
        if (arg == NULL) {
            return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        }
        arg->_zn = _z_session_rc_clone_as_weak(zn);
        arg->_qid = pq->_id;

        size_t handler_id = 0;
        _z_cancellation_token_on_cancel_handler_t handler;
        handler._on_cancel = _z_cancel_liveliness_pending_query;
        handler._on_drop = _z_cancel_liveliness_pending_query_arg_drop;
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

z_result_t _z_liveliness_query(const _z_session_rc_t *session, const _z_declared_keyexpr_t *keyexpr,
                               _z_closure_reply_callback_t callback, _z_drop_handler_t dropper, void *arg,
                               uint64_t timeout_ms, _z_cancellation_token_rc_t *opt_cancellation_token) {
    z_result_t ret = _Z_RES_OK;
    _z_session_t *zn = _Z_RC_IN_VAL(session);
    _Z_DEBUG("Register liveliness query for (%.*s)", (int)_z_string_len(&keyexpr->_inner._keyexpr),
             _z_string_data(&keyexpr->_inner._keyexpr));

    _z_keyexpr_t query_ke;
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_copy(&query_ke, &keyexpr->_inner), _z_drop_handler_execute(dropper, arg));

    uint32_t query_id;
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_keyexpr_clear(&query_ke);
                           _z_drop_handler_execute(dropper, arg););
    _z_liveliness_pending_query_t *pq = _z_unsafe_liveliness_register_pending_query(zn);
    if (pq == NULL) {
        _z_session_mutex_unlock(zn);
        _z_keyexpr_clear(&query_ke);
        _z_drop_handler_execute(dropper, arg);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    query_id = pq->_id;
    pq->_key = query_ke;
    pq->_callback = callback;
    pq->_dropper = dropper;
    pq->_arg = arg;
#ifdef Z_FEATURE_UNSTABLE_API
    ret = _z_liveliness_pending_query_register_cancellation(pq, opt_cancellation_token, session);
#else
    _ZP_UNUSED(opt_cancellation_token);
#endif
    _z_session_mutex_unlock(zn);

    if (ret == _Z_RES_OK) {
        _ZP_UNUSED(timeout_ms);  // Current interest in pico don't support timeout
        _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(keyexpr, zn);
        _z_interest_t interest = _z_make_interest(&wireexpr, query_id,
                                                  _Z_INTEREST_FLAG_KEYEXPRS | _Z_INTEREST_FLAG_TOKENS |
                                                      _Z_INTEREST_FLAG_RESTRICTED | _Z_INTEREST_FLAG_CURRENT);
        _z_network_message_t n_msg;
        _z_n_msg_make_interest(&n_msg, interest);
        ret = _z_send_declare(zn, &n_msg);

        if (ret != _Z_RES_OK) {
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_TX_FAILED);
            ret = _Z_ERR_TRANSPORT_TX_FAILED;
        }
        _z_n_msg_clear(&n_msg);
    }
    _Z_CLEAN_RETURN_IF_ERR(ret, _z_liveliness_unregister_pending_query(zn, query_id));

    return ret;
}
#endif  // Z_FEATURE_QUERY == 1

#endif  // Z_FEATURE_LIVELINESS == 1
