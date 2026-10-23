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

#include "zenoh-pico/net/primitives.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/net/filtering.h"
#include "zenoh-pico/net/liveliness.h"
#include "zenoh-pico/net/logger.h"
#include "zenoh-pico/net/matching.h"
#include "zenoh-pico/net/sample.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/declarations.h"
#include "zenoh-pico/protocol/definitions/interest.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/session/interest.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/liveliness.h"
#include "zenoh-pico/session/loopback.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/session/queryable.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/subscription.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/utils/locality.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/query_params.h"
#include "zenoh-pico/utils/result.h"
#include "zenoh-pico/utils/string.h"

/*------------------ Declaration Helpers ------------------*/
z_result_t _z_send_declare(_z_session_t *zn, const _z_network_message_t *n_msg) {
    z_result_t ret = _Z_RES_OK;
    ret = _z_send_n_msg(zn, n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL);

#if Z_FEATURE_AUTO_RECONNECT == 1
    if (ret == _Z_RES_OK) {
        _z_cache_declaration(zn, n_msg);
    }
#endif

    return ret;
}

z_result_t _z_send_undeclare(_z_session_t *zn, const _z_network_message_t *n_msg) {
    z_result_t ret = _Z_RES_OK;
    ret = _z_send_n_msg(zn, n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL);

#if Z_FEATURE_AUTO_RECONNECT == 1
    if (ret == _Z_RES_OK) {
        _z_prune_declaration(zn, n_msg);
    }
#endif

    return ret;
}
/*------------------ Scouting ------------------*/
#if Z_FEATURE_SCOUTING == 1
void _z_scout(const z_what_t what, const _z_id_t zid, _z_string_t *locator, const uint32_t timeout,
              _z_closure_hello_callback_t callback, void *arg_call, _z_drop_handler_t dropper, void *arg_drop) {
    _z_hello_slist_t *hellos = _z_scout_inner(what, zid, locator, timeout, false);

    while (hellos != NULL) {
        _z_hello_t *hello = _z_hello_slist_value(hellos);
        (*callback)(hello, arg_call);
        hellos = _z_hello_slist_pop(hellos);
    }
    if (dropper != NULL) {
        (*dropper)(arg_drop);
    }
    _z_hello_slist_free(&hellos);
}
#endif

/*------------------ Resource Declaration ------------------*/
z_result_t _z_declare_resource(_z_session_t *zn, const _z_string_t *key, uint16_t *out_id) {
    _z_wireexpr_t expr = _z_wireexpr_null();
    expr._id = Z_RESOURCE_ID_NONE;
    expr._suffix = _z_string_alias(*key);
    z_result_t ret = _z_register_resource(zn, &expr, Z_RESOURCE_ID_NONE, NULL, out_id);
    if (ret == _Z_RES_OK) {
        // Build the declare message to send on the wire
        _z_declaration_t declaration = _z_make_decl_keyexpr(*out_id, &expr);
        _z_network_message_t n_msg;
        _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());
        ret = _z_send_declare(zn, &n_msg);
        if (ret != _Z_RES_OK) {
            _z_unregister_resource(zn, *out_id, NULL);
        }
        _z_n_msg_clear(&n_msg);
    }
    return ret;
}

z_result_t _z_undeclare_resource(_z_session_t *zn, uint16_t rid) {
    _Z_DEBUG("Undeclaring local keyexpr %d", rid);
    z_result_t ret = _z_unregister_resource(zn, rid, NULL);
    if (ret == _Z_RES_OK) {
        // Build the declare message to send on the wire
        _z_declaration_t declaration = _z_make_undecl_keyexpr(rid);
        _z_network_message_t n_msg;
        _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());
        if (_z_send_undeclare(zn, &n_msg) != _Z_RES_OK) {
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_TX_FAILED);
            ret = _Z_ERR_TRANSPORT_TX_FAILED;
        }
        _z_n_msg_clear(&n_msg);
    } else if (ret > 0) {
        ret = _Z_RES_OK;
    } else {
        _Z_ERROR_LOG(ret);
    }

    return ret;
}

#if Z_FEATURE_PUBLICATION == 1
/*------------------  Publisher Declaration ------------------*/
z_result_t _z_declare_publisher(_z_publisher_t *publisher, const _z_session_rc_t *zn,
                                const _z_declared_keyexpr_t *keyexpr, _z_encoding_t *encoding,
                                z_congestion_control_t congestion_control, z_priority_t priority, bool is_express,
                                z_reliability_t reliability, z_locality_t allowed_destination) {
    publisher->_id = _z_get_entity_id(_Z_RC_IN_VAL(zn));
    publisher->_congestion_control = congestion_control;
    publisher->_priority = priority;
    publisher->_is_express = is_express;
    publisher->reliability = reliability;
    publisher->_zn = _z_session_rc_clone_as_weak(zn);
    publisher->_encoding = encoding == NULL ? _z_encoding_null() : _z_encoding_steal(encoding);
    publisher->_allowed_destination = allowed_destination;
    publisher->_filter = (_z_write_filter_t){0};
    _Z_CLEAN_RETURN_IF_ERR(_z_declared_keyexpr_declare(zn, &publisher->_key, keyexpr),
                           _z_undeclare_publisher(publisher));
    return _Z_RES_OK;
}

z_result_t _z_undeclare_publisher(_z_publisher_t *pub) {
    if (pub == NULL || _Z_RC_IS_NULL(&pub->_zn)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
    _z_write_filter_clear(&pub->_filter);
    _z_declared_keyexpr_clear(&pub->_key);
    _z_session_weak_drop(&pub->_zn);
    _z_encoding_clear(&pub->_encoding);
    *pub = _z_publisher_null();
    return _Z_RES_OK;
}

/*------------------ Write ------------------*/
z_result_t _z_write(_z_session_t *zn, const _z_declared_keyexpr_t *keyexpr, _z_bytes_t *payload,
                    _z_encoding_t *encoding, z_sample_kind_t kind, z_congestion_control_t cong_ctrl,
                    z_priority_t priority, bool is_express, const _z_timestamp_t *timestamp, _z_bytes_t *attachment,
                    z_reliability_t reliability, const _z_source_info_t *source_info,
                    z_locality_t allowed_destination) {
    z_result_t ret = _Z_RES_OK;
    _z_qos_t qos = _z_n_qos_make(is_express, cong_ctrl == Z_CONGESTION_CONTROL_BLOCK, priority);

    if (_z_locality_allows_remote(allowed_destination)) {
        _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(keyexpr, zn);
        _z_network_message_t msg;
        switch (kind) {
            case Z_SAMPLE_KIND_PUT:
                _z_n_msg_make_push_put(&msg, &wireexpr, payload, encoding, qos, timestamp, attachment, reliability,
                                       source_info);
                break;
            case Z_SAMPLE_KIND_DELETE:
                _z_n_msg_make_push_del(&msg, &wireexpr, qos, timestamp, reliability, source_info);
                break;
            default:
                _Z_ERROR_RETURN(_Z_ERR_GENERIC);
        }
        if (_z_send_n_msg(zn, &msg, reliability, cong_ctrl, NULL) != _Z_RES_OK) {
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_TX_FAILED);
            ret = _Z_ERR_TRANSPORT_TX_FAILED;
        }
    }

#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    if (ret == _Z_RES_OK && _z_locality_allows_local(allowed_destination)) {
        ret = _z_session_deliver_push_locally(zn, &keyexpr->_inner, payload, encoding, kind, qos, timestamp, attachment,
                                              reliability, source_info);
    }
#endif
    return ret;
}
#endif

#if Z_FEATURE_SUBSCRIPTION == 1
/*------------------ Subscriber Declaration ------------------*/
z_result_t _z_register_subscriber(uint32_t *sub_id, const _z_session_rc_t *zn, const _z_declared_keyexpr_t *keyexpr,
                                  _z_closure_sample_callback_t callback, _z_drop_handler_t dropper, void *arg,
                                  z_locality_t allowed_origin, const _z_sync_group_t *callback_drop_sync_group) {
    _z_subscription_t s = {0};
    s._id = _z_get_entity_id(_Z_RC_IN_VAL(zn));
    s._callback = callback;
    s._dropper = dropper;
    s._arg = arg;
    s._allowed_origin = allowed_origin;
    _Z_CLEAN_RETURN_IF_ERR(_z_declared_keyexpr_declare_non_wild_prefix(zn, &s._key, keyexpr),
                           _z_subscription_clear(&s));
    _Z_CLEAN_RETURN_IF_ERR(
        _z_sync_group_create_notifier(&_Z_RC_IN_VAL(zn)->_callback_drop_sync_group, &s._session_callback_drop_notifier),
        _z_subscription_clear(&s));
    if (callback_drop_sync_group != NULL) {
        _Z_CLEAN_RETURN_IF_ERR(
            _z_sync_group_create_notifier(callback_drop_sync_group, &s._subscriber_callback_drop_notifier),
            _z_subscription_clear(&s));
    }

    _z_subscription_rc_t sp_s = _z_register_subscription(_Z_RC_IN_VAL(zn), _Z_SUBSCRIBER_KIND_SUBSCRIBER, &s);
    if (_Z_RC_IS_NULL(&sp_s)) {
        _z_subscription_clear(&s);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    if (_z_locality_allows_remote(allowed_origin)) {
        _z_wireexpr_t wire_expr = _z_declared_keyexpr_alias_to_wire(keyexpr, _Z_RC_IN_VAL(zn));
        _z_declaration_t declaration = _z_make_decl_subscriber(&wire_expr, s._id);
        _z_network_message_t n_msg;
        _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());
        z_result_t res = _z_send_declare(_Z_RC_IN_VAL(zn), &n_msg);
        _z_n_msg_clear(&n_msg);
        if (res != _Z_RES_OK) {
            _z_unregister_subscription(_Z_RC_IN_VAL(zn), _Z_SUBSCRIBER_KIND_SUBSCRIBER, &sp_s);
            return res;
        }
    }
    *sub_id = s._id;
    _z_subscription_rc_drop(&sp_s);  // we do not keep this data for the time being inside subscriber, and rc copy is
                                     // still stored inside the session
    return _Z_RES_OK;
}

z_result_t _z_declare_subscriber(_z_subscriber_t *subscriber, const _z_session_rc_t *zn,
                                 const _z_declared_keyexpr_t *keyexpr, _z_closure_sample_callback_t callback,
                                 _z_drop_handler_t dropper, void *arg, z_locality_t allowed_origin) {
    *subscriber = _z_subscriber_null();
    subscriber->_zn = _z_session_rc_clone_as_weak(zn);
    z_result_t ret = _z_sync_group_create(&subscriber->_callback_drop_sync_group);
    _Z_SET_IF_OK(ret, _z_register_subscriber(&subscriber->_entity_id, zn, keyexpr, callback, dropper, arg,
                                             allowed_origin, &subscriber->_callback_drop_sync_group));
    _Z_CLEAN_RETURN_IF_ERR(ret, _z_subscriber_clear(subscriber));
    return _Z_RES_OK;
}

z_result_t _z_undeclare_subscriber(_z_subscriber_t *sub) {
    if (sub == NULL || _Z_RC_IS_NULL(&sub->_zn)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&sub->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        return _Z_ERR_SESSION_CLOSED;
    }
    _z_session_t *zn = _Z_RC_IN_VAL(&sess_rc);
#else
    _z_session_t *zn = _z_session_weak_as_unsafe_ptr(&sub->_zn);
#endif
    // Find subscription entry
    _z_subscription_rc_t s = _z_get_subscription_by_id(zn, _Z_SUBSCRIBER_KIND_SUBSCRIBER, sub->_entity_id);
    if (_Z_RC_IS_NULL(&s)) {
#if Z_FEATURE_LIVELINESS == 1
#if Z_FEATURE_SESSION_CHECK == 1
        _z_session_rc_drop(&sess_rc);
#endif
        // Not found, treat it as a liveliness subscriber
        return _z_undeclare_liveliness_subscriber(sub);
#else
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
#endif
    }
    z_result_t ret = _Z_RES_OK;
    if (_z_locality_allows_remote(_Z_RC_IN_VAL(&s)->_allowed_origin)) {
        _z_declaration_t declaration;
        if (zn->_mode == Z_WHATAMI_CLIENT) {
            declaration = _z_make_undecl_subscriber(sub->_entity_id, NULL);
        } else {
            _z_wireexpr_t expr = _z_declared_keyexpr_alias_to_wire(&_Z_RC_IN_VAL(&s)->_key, zn);
            declaration = _z_make_undecl_subscriber(sub->_entity_id, &expr);
        }
        _z_network_message_t n_msg;
        _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());
        if (_z_send_undeclare(zn, &n_msg) != _Z_RES_OK) {
            ret = _Z_ERR_TRANSPORT_TX_FAILED;
        }
        _z_n_msg_clear(&n_msg);
    }
    _z_unregister_subscription(zn, _Z_SUBSCRIBER_KIND_SUBSCRIBER, &s);
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    z_result_t wait_ret = _z_sync_group_check(&sub->_callback_drop_sync_group)
                              ? _z_sync_group_wait(&sub->_callback_drop_sync_group)
                              : _Z_RES_OK;
    return ret == _Z_RES_OK ? wait_ret : ret;
}
#endif

#if Z_FEATURE_QUERYABLE == 1
/*------------------ Queryable Declaration ------------------*/
z_result_t _z_register_queryable(uint32_t *queryable_id, const _z_session_rc_t *zn,
                                 const _z_declared_keyexpr_t *keyexpr, bool complete,
                                 _z_closure_query_callback_t callback, _z_drop_handler_t dropper, void *arg,
                                 z_locality_t allowed_origin, const _z_sync_group_t *callback_drop_sync_group) {
    _z_session_queryable_t q = {0};
    q._id = _z_get_entity_id(_Z_RC_IN_VAL(zn));
    q._complete = complete;
    q._callback = callback;
    q._dropper = dropper;
    q._arg = arg;
    q._allowed_origin = allowed_origin;
    _Z_CLEAN_RETURN_IF_ERR(_z_declared_keyexpr_declare_non_wild_prefix(zn, &q._key, keyexpr),
                           _z_session_queryable_clear(&q));
    _Z_CLEAN_RETURN_IF_ERR(
        _z_sync_group_create_notifier(&_Z_RC_IN_VAL(zn)->_callback_drop_sync_group, &q._session_callback_drop_notifier),
        _z_session_queryable_clear(&q));
    if (callback_drop_sync_group != NULL) {
        _Z_CLEAN_RETURN_IF_ERR(
            _z_sync_group_create_notifier(callback_drop_sync_group, &q._queryable_callback_drop_notifier),
            _z_session_queryable_clear(&q));
    }

    // Create session_queryable entry, stored at session-level, do not drop it by the end of this function.
    _z_session_queryable_rc_t sp_q = _z_register_session_queryable(_Z_RC_IN_VAL(zn), &q);
    if (_Z_RC_IS_NULL(&sp_q)) {
        _z_session_queryable_clear(&q);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    if (_z_locality_allows_remote(allowed_origin)) {
        // Build the declare message to send on the wire
        _z_wireexpr_t wire_expr = _z_declared_keyexpr_alias_to_wire(&q._key, _Z_RC_IN_VAL(zn));
        _z_declaration_t declaration =
            _z_make_decl_queryable(&wire_expr, q._id, q._complete, _Z_QUERYABLE_DISTANCE_DEFAULT);
        _z_network_message_t n_msg;
        _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());

        z_result_t res = _z_send_declare(_Z_RC_IN_VAL(zn), &n_msg);
        _z_n_msg_clear(&n_msg);
        if (res != _Z_RES_OK) {
            _z_unregister_session_queryable(_Z_RC_IN_VAL(zn), &sp_q);
            return res;
        }
    }
    *queryable_id = q._id;
    _z_session_queryable_rc_drop(&sp_q);  // we do not keep this data for the time being inside queryable, and rc copy
                                          // is still stored inside the session
    return _Z_RES_OK;
}

z_result_t _z_declare_queryable(_z_queryable_t *queryable, const _z_session_rc_t *zn,
                                const _z_declared_keyexpr_t *keyexpr, bool complete,
                                _z_closure_query_callback_t callback, _z_drop_handler_t dropper, void *arg,
                                z_locality_t allowed_origin) {
    *queryable = _z_queryable_null();
    queryable->_zn = _z_session_rc_clone_as_weak(zn);
    z_result_t ret = _z_sync_group_create(&queryable->_callback_drop_sync_group);
    _Z_SET_IF_OK(ret, _z_register_queryable(&queryable->_entity_id, zn, keyexpr, complete, callback, dropper, arg,
                                            allowed_origin, &queryable->_callback_drop_sync_group));
    _Z_CLEAN_RETURN_IF_ERR(ret, _z_queryable_clear(queryable));
    return _Z_RES_OK;
}

z_result_t _z_undeclare_queryable(_z_queryable_t *qle) {
    if (qle == NULL || _Z_RC_IS_NULL(&qle->_zn)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&qle->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        return _Z_ERR_SESSION_CLOSED;
    }
    _z_session_t *zn = _Z_RC_IN_VAL(&sess_rc);
#else
    _z_session_t *zn = _z_session_weak_as_unsafe_ptr(&sub->_zn);
#endif
    // Find session_queryable entry
    _z_session_queryable_rc_t q = _z_get_session_queryable_by_id(zn, qle->_entity_id);
    z_result_t ret = _Z_RES_OK;
    if (_Z_RC_IS_NULL(&q)) {
#if Z_FEATURE_SESSION_CHECK == 1
        _z_session_rc_drop(&sess_rc);
#endif
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
    if (_z_locality_allows_remote(_Z_RC_IN_VAL(&q)->_allowed_origin)) {
        // Build the declare message to send on the wire
        _z_declaration_t declaration;
        if (zn->_mode == Z_WHATAMI_CLIENT) {
            declaration = _z_make_undecl_queryable(qle->_entity_id, NULL);
        } else {
            _z_wireexpr_t expr = _z_declared_keyexpr_alias_to_wire(&_Z_RC_IN_VAL(&q)->_key, zn);
            declaration = _z_make_undecl_queryable(qle->_entity_id, &expr);
        }
        _z_network_message_t n_msg;
        _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_none());
        ret = _z_send_undeclare(zn, &n_msg);
        if (ret != _Z_RES_OK) {
            ret = _Z_ERR_TRANSPORT_TX_FAILED;
        }
        _z_n_msg_clear(&n_msg);
    }
    _z_unregister_session_queryable(zn, &q);
    z_result_t wait_ret = _z_sync_group_check(&qle->_callback_drop_sync_group)
                              ? _z_sync_group_wait(&qle->_callback_drop_sync_group)
                              : _Z_RES_OK;
    ret = ret == _Z_RES_OK ? wait_ret : ret;
#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_drop(&sess_rc);
#endif
    return ret;
}

z_result_t _z_send_reply(const _z_query_t *query, const _z_session_rc_t *zsrc, const _z_declared_keyexpr_t *keyexpr,
                         _z_bytes_t *payload, _z_encoding_t *encoding, const z_sample_kind_t kind, bool is_express,
                         const _z_timestamp_t *timestamp, _z_bytes_t *att, _z_source_info_t *source_info) {
    _z_session_t *zn = _Z_RC_IN_VAL(zsrc);
    _Z_DEBUG("send_reply: rid=%jd kind=%d", (intmax_t)query->_request_id, (int)kind);
    // Check key expression
    if (!query->_anyke && !_z_declared_keyexpr_intersects(&query->_key, keyexpr)) {
        _Z_ERROR_RETURN(_Z_ERR_KEYEXPR_NOT_MATCH);
    }
    // Build the reply context decorator. This is NOT the final reply.
    _z_n_qos_t qos =
        _z_n_qos_create(is_express, _z_n_qos_get_congestion_control(query->_qos), _z_n_qos_get_priority(query->_qos));
    if (query->_is_local) {
        return _z_session_deliver_reply_locally(query, zsrc, keyexpr, payload, encoding, kind, qos, timestamp, att,
                                                source_info);
    }

    _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(keyexpr, _Z_RC_IN_VAL(zsrc));
    _z_zenoh_message_t z_msg;
    switch (kind) {
        case Z_SAMPLE_KIND_PUT:
            _z_n_msg_make_reply_ok_put(&z_msg, &zn->_local_zid, query->_request_id, &wireexpr, Z_RELIABILITY_DEFAULT,
                                       Z_CONSOLIDATION_MODE_DEFAULT, qos, timestamp, source_info, payload, encoding,
                                       att);
            break;
        case Z_SAMPLE_KIND_DELETE:
            _z_n_msg_make_reply_ok_del(&z_msg, &zn->_local_zid, query->_request_id, &wireexpr, Z_RELIABILITY_DEFAULT,
                                       Z_CONSOLIDATION_MODE_DEFAULT, qos, timestamp, source_info, att);
            break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
    // Send message on network
    if (_z_send_n_msg(zn, &z_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL) != _Z_RES_OK) {
        _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
    }
    // Freeing z_msg is unnecessary, as all of its components are aliased
    return _Z_RES_OK;
}

z_result_t _z_send_reply_err(const _z_query_t *query, const _z_session_rc_t *zsrc, _z_bytes_t *payload,
                             _z_encoding_t *encoding) {
    z_result_t ret = _Z_RES_OK;
    _z_session_t *zn = _Z_RC_IN_VAL(zsrc);

    // Build the reply context decorator. This is NOT the final reply.
    _z_n_qos_t qos = _z_n_qos_make(false, true, Z_PRIORITY_DEFAULT);
    _z_source_info_t source_info = _z_source_info_null();
    if (query->_is_local) {
        return _z_session_deliver_reply_err_locally(query, zsrc, payload, encoding, qos);
    }

    _z_zenoh_message_t msg;
    _z_n_msg_make_reply_err(&msg, &zn->_local_zid, query->_request_id, Z_RELIABILITY_DEFAULT, qos, payload, encoding,
                            &source_info);
    // Send message on network
    if (_z_send_n_msg(zn, &msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL) != _Z_RES_OK) {
        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_TX_FAILED);
        ret = _Z_ERR_TRANSPORT_TX_FAILED;
    }
    return ret;
}
#endif

#if Z_FEATURE_QUERY == 1
/*------------------  Querier Declaration ------------------*/
z_result_t _z_declare_querier(_z_querier_t *querier, const _z_session_rc_t *zn, const _z_declared_keyexpr_t *keyexpr,
                              z_consolidation_mode_t consolidation_mode, z_congestion_control_t congestion_control,
                              z_query_target_t target, z_priority_t priority, bool is_express, uint64_t timeout_ms,
                              _z_encoding_t *encoding, z_reliability_t reliability, z_locality_t allowed_destination,
                              z_reply_keyexpr_t accept_replies) {
    *querier = _z_querier_null();
    querier->_encoding = encoding == NULL ? _z_encoding_null() : _z_encoding_steal(encoding);
    querier->reliability = reliability;
    querier->_id = _z_get_entity_id(_Z_RC_IN_VAL(zn));
    querier->_consolidation_mode = consolidation_mode;
    querier->_congestion_control = congestion_control;
    querier->_target = target;
    querier->_priority = priority;
    querier->_is_express = is_express;
    querier->_accept_replies = accept_replies;
    querier->_timeout_ms = timeout_ms;
    querier->_allowed_destination = allowed_destination;
    querier->_zn = _z_session_rc_clone_as_weak(zn);
    querier->_filter = (_z_write_filter_t){0};
    _Z_CLEAN_RETURN_IF_ERR(_z_declared_keyexpr_declare(zn, &querier->_key, keyexpr), _z_undeclare_querier(querier));
    return _Z_RES_OK;
}

z_result_t _z_undeclare_querier(_z_querier_t *querier) {
    if (querier == NULL || _Z_RC_IS_NULL(&querier->_zn)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
    _z_session_rc_t s = _z_session_weak_upgrade_if_open(&querier->_zn);
    if (!_Z_RC_IS_NULL(&s)) {
        _z_unregister_pending_queries_from_querier(_Z_RC_IN_VAL(&s), querier->_id);
        _z_session_rc_drop(&s);
    }
    _z_write_filter_clear(&querier->_filter);
    _z_declared_keyexpr_clear(&querier->_key);
    _z_session_weak_drop(&querier->_zn);
    _z_encoding_clear(&querier->_encoding);
    *querier = _z_querier_null();
    return _Z_RES_OK;
}

/*------------------ Query ------------------*/
z_result_t _z_query(const _z_session_rc_t *session, _z_optional_id_t querier_id, const _z_declared_keyexpr_t *keyexpr,
                    const char *parameters, size_t parameters_len, z_query_target_t target,
                    z_consolidation_mode_t consolidation, _z_bytes_t *payload, _z_encoding_t *encoding,
                    _z_closure_reply_callback_t callback, _z_drop_handler_t dropper, void *arg, uint64_t timeout_ms,
                    _z_bytes_t *attachment, _z_n_qos_t qos, _z_source_info_t *source_info,
                    z_reply_keyexpr_t accept_replies, z_locality_t allowed_destination,
                    _z_cancellation_token_rc_t *opt_cancellation_token) {
    _z_session_t *zn = _Z_RC_IN_VAL(session);
    if (parameters == NULL && parameters_len > 0) {
        _Z_ERROR("Non-zero length string should not be NULL");
        return Z_EINVAL;
    }
    _z_keyexpr_t ke_query;
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_copy(&ke_query, &keyexpr->_inner), _z_drop_handler_execute(dropper, arg));

    if (consolidation == Z_CONSOLIDATION_MODE_AUTO) {
        if (parameters != NULL && _z_strstr(parameters, parameters + parameters_len, Z_SELECTOR_TIME) != NULL) {
            consolidation = Z_CONSOLIDATION_MODE_NONE;
        } else {
            consolidation = Z_CONSOLIDATION_MODE_LATEST;
        }
    }
    bool allow_local = _z_locality_allows_local(allowed_destination);
    bool allow_remote = _z_locality_allows_remote(allowed_destination);
    _z_transport_common_t *common = _z_transport_get_common(&zn->_tp);
    bool remote_possible = allow_remote && (common != NULL && common->_link != NULL);

    bool _anyke_in_parameters = _z_parameters_has_anyke(parameters, parameters_len);
    bool _anyke_option = accept_replies == Z_REPLY_KEYEXPR_ANY;
    // extra _anyke parameter only if it's not already in the parameters list
    bool implicit_anyke = _anyke_option && !_anyke_in_parameters;

    // Add the pending query to the current session
    _z_zint_t qid;
    z_result_t ret = _Z_RES_OK;
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_keyexpr_clear(&ke_query);
                           _z_drop_handler_execute(dropper, arg));
    _z_pending_query_t *pq = _z_unsafe_register_pending_query(zn);
    if (pq == NULL) {
        _z_session_mutex_unlock(zn);
        _z_keyexpr_clear(&ke_query);
        _z_drop_handler_execute(dropper, arg);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    // Fill the pending query object
    qid = pq->_id;
    pq->_querier_id = querier_id;
    pq->_key = ke_query;
    pq->_target = target;
    pq->_consolidation = consolidation;
    pq->_anyke = _anyke_in_parameters || _anyke_option;
    pq->_callback = callback;
    pq->_dropper = dropper;
    pq->_pending_replies = NULL;
    pq->_allowed_destination = allowed_destination;
    pq->_arg = arg;
    pq->_timeout = timeout_ms;
    pq->_start_time = z_clock_now();
    // Count how many finals we expect: one for the local path (if handled_locally)
    // and one for the remote path (if remote is allowed). Keep at least 1 to avoid stuck pending.
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    pq->_remaining_finals = (uint8_t)((allow_local ? 1 : 0) + (allow_remote ? 1 : 0));
#else
    _ZP_UNUSED(allow_local);
    pq->_remaining_finals = 1;
#endif
#ifdef Z_FEATURE_UNSTABLE_API
    ret = _z_pending_query_register_cancellation(pq, opt_cancellation_token, session);
#else
    _ZP_UNUSED(opt_cancellation_token);
#endif
    _z_session_mutex_unlock(zn);
    // Send query message
    _z_slice_t params =
        (parameters == NULL) ? _z_slice_null() : _z_slice_alias_buf((uint8_t *)parameters, parameters_len);
    if (ret == _Z_RES_OK && remote_possible) {
        _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(keyexpr, zn);
        _z_zenoh_message_t z_msg;
        _z_n_msg_make_query(&z_msg, &wireexpr, &params, qid, Z_RELIABILITY_DEFAULT, consolidation, payload, encoding,
                            timeout_ms, attachment, qos, source_info, implicit_anyke);
        ret = _z_send_n_msg(zn, &z_msg, Z_RELIABILITY_RELIABLE, _z_n_qos_get_congestion_control(qos), NULL);
    }
#if Z_FEATURE_LOCAL_QUERYABLE == 1
    if (ret == _Z_RES_OK && allow_local) {
        ret = _z_session_deliver_query_locally(zn, &keyexpr->_inner, &params, consolidation, payload, encoding,
                                               attachment, source_info, qid, timeout_ms, qos, implicit_anyke);
    }
#endif
    _Z_CLEAN_RETURN_IF_ERR(ret, _z_unregister_pending_query(zn, qid));
    return _Z_RES_OK;
}
#endif

#if Z_FEATURE_INTEREST == 1
/*------------------ Interest Declaration ------------------*/
uint32_t _z_add_interest(_z_session_t *zn, const _z_declared_keyexpr_t *keyexpr, _z_interest_handler_t callback,
                         uint8_t flags, _z_void_rc_t *arg) {
    _z_session_interest_t intr;
    intr._id = _z_get_entity_id(zn);
    intr._flags = flags;
    intr._callback = callback;
    intr._arg = *arg;
    *arg = _z_void_rc_null();
    if (_z_keyexpr_copy(&intr._key, &keyexpr->_inner) != _Z_RES_OK) {
        _z_void_rc_drop(&intr._arg);
        return 0;
    }

    // Create interest entry, stored at session-level, do not drop it by the end of this function.
    _z_session_interest_rc_t *sintr = _z_register_interest(zn, &intr);
    if (sintr == NULL) {
        _z_void_rc_drop(&intr._arg);
        _z_keyexpr_clear(&intr._key);
        return 0;
    }
    // Build the interest message to send on the wire (only needed in client mode or multicast transport or when
    // connected to a router in peer mode)
    if (zn->_mode == Z_WHATAMI_CLIENT || _z_session_has_router_peer(zn)
#if Z_FEATURE_MULTICAST_DECLARATIONS == 1
        || (zn->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE)
#endif
    ) {
        _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(keyexpr, zn);
        _z_interest_t interest = _z_make_interest(&wireexpr, intr._id, intr._flags);
        _z_network_message_t n_msg;
        _z_n_msg_make_interest(&n_msg, interest);
        if (_z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL) != _Z_RES_OK) {
            _z_unregister_interest(zn, sintr);
            return 0;
        }
#if Z_FEATURE_AUTO_RECONNECT == 1
        _z_cache_declaration(zn, &n_msg);
#endif
        _z_n_msg_clear(&n_msg);
    }
    // Replay declares
    _z_interest_replay_declare(zn, &intr);
    return intr._id;
}

z_result_t _z_remove_interest(_z_session_t *zn, uint32_t interest_id) {
    // Find interest entry
    _z_session_interest_rc_t *sintr = _z_get_interest_by_id(zn, interest_id);
    if (sintr == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
    // Build the declare message to send on the wire (only needed in client mode or multicast transport)
    if (zn->_mode == Z_WHATAMI_CLIENT
#if Z_FEATURE_MULTICAST_DECLARATIONS == 1
        || (zn->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE)
#endif
    ) {
        _z_interest_t interest = _z_make_interest_final(_Z_RC_IN_VAL(sintr)->_id);
        _z_network_message_t n_msg;
        _z_n_msg_make_interest(&n_msg, interest);
        if (_z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL) != _Z_RES_OK) {
            _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
        }
#if Z_FEATURE_AUTO_RECONNECT == 1
        _z_prune_declaration(zn, &n_msg);
#endif
        _z_n_msg_clear(&n_msg);
    }
    // Only if message is successfully send, session interest can be removed
    _z_unregister_interest(zn, sintr);
    return _Z_RES_OK;
}
#endif
