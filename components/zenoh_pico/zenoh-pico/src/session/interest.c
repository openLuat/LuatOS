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
#include "zenoh-pico/net/query.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/declarations.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/queryable.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/multicast/lease.h"
#include "zenoh-pico/utils/logging.h"

static z_result_t _z_interest_send_decl_resource(_z_session_t *zn, uint32_t interest_id, void *peer,
                                                 const _z_keyexpr_t *restr_key) {
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    _z_resource_slist_t *res_list = _z_resource_slist_clone(zn->_local_resources);
    _z_session_mutex_unlock(zn);
    _z_resource_slist_t *xs = res_list;
    while (xs != NULL) {
        _z_resource_t *res = _z_resource_slist_value(xs);
        // Check if key is concerned
        if (restr_key == NULL || _z_keyexpr_intersects(restr_key, &res->_key)) {
            // Build the declare message to send on the wire
            _z_wireexpr_t wireexpr = _z_keyexpr_alias_to_wire(&res->_key);
            _z_declaration_t declaration = _z_make_decl_keyexpr(res->_id, &wireexpr);
            _z_network_message_t n_msg;
            _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_some(interest_id));
            z_result_t ret = _z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, peer);
            _z_n_msg_clear(&n_msg);
            if (ret != _Z_RES_OK) {
                _z_resource_slist_free(&res_list);
                _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
            }
        }
        xs = _z_resource_slist_next(xs);
    }
    _z_resource_slist_free(&res_list);
    return _Z_RES_OK;
}

#if Z_FEATURE_SUBSCRIPTION == 1
static z_result_t _z_interest_send_decl_subscriber(_z_session_t *zn, uint32_t interest_id, void *peer,
                                                   const _z_keyexpr_t *restr_key) {
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    _z_subscription_rc_slist_t *sub_list = _z_subscription_rc_slist_clone(zn->_subscriptions);
    _z_session_mutex_unlock(zn);
    _z_subscription_rc_slist_t *xs = sub_list;
    while (xs != NULL) {
        _z_subscription_rc_t *sub = _z_subscription_rc_slist_value(xs);
        // Check if key is concerned
        if (restr_key == NULL || _z_keyexpr_intersects(restr_key, &_Z_RC_IN_VAL(sub)->_key._inner)) {
            // Build the declare message to send on the wire
            _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(&_Z_RC_IN_VAL(sub)->_key, zn);
            _z_declaration_t declaration = _z_make_decl_subscriber(&wireexpr, _Z_RC_IN_VAL(sub)->_id);
            _z_network_message_t n_msg;
            _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_some(interest_id));
            z_result_t ret = _z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, peer);
            _z_n_msg_clear(&n_msg);
            if (ret != _Z_RES_OK) {
                _z_subscription_rc_slist_free(&sub_list);
                _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
            }
        }
        xs = _z_subscription_rc_slist_next(xs);
    }
    _z_subscription_rc_slist_free(&sub_list);
    return _Z_RES_OK;
}
#else
static z_result_t _z_interest_send_decl_subscriber(_z_session_t *zn, uint32_t interest_id, void *peer,
                                                   const _z_keyexpr_t *restr_key) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(interest_id);
    _ZP_UNUSED(peer);
    _ZP_UNUSED(restr_key);
    return _Z_RES_OK;
}
#endif

#if Z_FEATURE_QUERYABLE == 1
static z_result_t _z_interest_send_decl_queryable(_z_session_t *zn, uint32_t interest_id, void *peer,
                                                  const _z_keyexpr_t *restr_key) {
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    _z_session_queryable_rc_slist_t *qle_list = _z_session_queryable_rc_slist_clone(zn->_local_queryable);
    _z_session_mutex_unlock(zn);
    _z_session_queryable_rc_slist_t *xs = qle_list;
    while (xs != NULL) {
        _z_session_queryable_rc_t *qle = _z_session_queryable_rc_slist_value(xs);
        // Check if key is concerned
        if (restr_key == NULL || _z_keyexpr_intersects(restr_key, &_Z_RC_IN_VAL(qle)->_key._inner)) {
            // Build the declare message to send on the wire
            _z_wireexpr_t wireexpr = _z_declared_keyexpr_alias_to_wire(&_Z_RC_IN_VAL(qle)->_key, zn);
            _z_declaration_t declaration = _z_make_decl_queryable(
                &wireexpr, _Z_RC_IN_VAL(qle)->_id, _Z_RC_IN_VAL(qle)->_complete, _Z_QUERYABLE_DISTANCE_DEFAULT);
            _z_network_message_t n_msg;
            _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_some(interest_id));
            z_result_t ret = _z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, peer);
            _z_n_msg_clear(&n_msg);
            if (ret != _Z_RES_OK) {
                _z_session_queryable_rc_slist_free(&qle_list);
                _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
            }
        }
        xs = _z_session_queryable_rc_slist_next(xs);
    }
    _z_session_queryable_rc_slist_free(&qle_list);
    return _Z_RES_OK;
}
#else
static z_result_t _z_interest_send_decl_queryable(_z_session_t *zn, uint32_t interest_id, void *peer,
                                                  const _z_keyexpr_t *restr_key) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(interest_id);
    _ZP_UNUSED(peer);
    _ZP_UNUSED(restr_key);
    return _Z_RES_OK;
}
#endif

#if Z_FEATURE_LIVELINESS == 1
static z_result_t _z_interest_send_decl_token(_z_session_t *zn, uint32_t interest_id, void *peer,
                                              const _z_keyexpr_t *restr_key) {
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    _z_declared_keyexpr_intmap_t token_list = _z_declared_keyexpr_intmap_clone(&zn->_local_tokens);
    _z_session_mutex_unlock(zn);
    _z_declared_keyexpr_intmap_iterator_t iter = _z_declared_keyexpr_intmap_iterator_make(&token_list);
    while (_z_declared_keyexpr_intmap_iterator_next(&iter)) {
        uint32_t id = (uint32_t)_z_declared_keyexpr_intmap_iterator_key(&iter);
        // Check if key is concerned
        if (restr_key == NULL ||
            _z_keyexpr_intersects(restr_key, &_z_declared_keyexpr_intmap_iterator_value(&iter)->_inner)) {
            // Build the declare message to send on the wire
            _z_wireexpr_t wireexpr =
                _z_declared_keyexpr_alias_to_wire(_z_declared_keyexpr_intmap_iterator_value(&iter), zn);
            _z_declaration_t declaration = _z_make_decl_token(&wireexpr, id);
            _z_network_message_t n_msg;
            _z_n_msg_make_declare(&n_msg, declaration, _z_optional_id_make_some(interest_id));
            z_result_t ret = _z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, peer);
            _z_n_msg_clear(&n_msg);
            if (ret != _Z_RES_OK) {
                _z_declared_keyexpr_intmap_clear(&token_list);
                _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
            }
        }
    }
    _z_declared_keyexpr_intmap_clear(&token_list);
    return _Z_RES_OK;
}
#else
static z_result_t _z_interest_send_decl_token(_z_session_t *zn, uint32_t interest_id, void *peer,
                                              const _z_keyexpr_t *restr_key) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(interest_id);
    _ZP_UNUSED(peer);
    _ZP_UNUSED(restr_key);
    return _Z_RES_OK;
}
#endif

static z_result_t _z_interest_send_declare_final(_z_session_t *zn, uint32_t interest_id, void *peer) {
    _z_declaration_t decl = _z_make_decl_final();
    _z_network_message_t n_msg;
    _z_n_msg_make_declare(&n_msg, decl, _z_optional_id_make_some(interest_id));
    z_result_t ret = _z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, peer);
    _z_n_msg_clear(&n_msg);
    if (ret != _Z_RES_OK) {
        _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_TX_FAILED);
    }
    return _Z_RES_OK;
}

z_result_t _z_interest_push_declarations_to_peer(_z_session_t *zn, void *peer) {
    _Z_RETURN_IF_ERR(_z_interest_send_decl_resource(zn, 0, peer, NULL));
    _Z_RETURN_IF_ERR(_z_interest_send_decl_subscriber(zn, 0, peer, NULL));
    _Z_RETURN_IF_ERR(_z_interest_send_decl_queryable(zn, 0, peer, NULL));
    _Z_RETURN_IF_ERR(_z_interest_send_decl_token(zn, 0, peer, NULL));
    _Z_RETURN_IF_ERR(_z_interest_send_declare_final(zn, 0, peer));
    return _Z_RES_OK;
}

z_result_t _z_interest_pull_resource_from_peers(_z_session_t *zn) {
    // Retrieve all current resource declarations
    uint32_t eid = _z_get_entity_id(zn);
    uint8_t flags = _Z_INTEREST_FLAG_KEYEXPRS | _Z_INTEREST_FLAG_CURRENT;
    // Send message on the network
    _z_interest_t interest = _z_make_interest(NULL, eid, flags);
    _z_network_message_t n_msg;
    _z_n_msg_make_interest(&n_msg, interest);
    z_result_t ret = _z_send_n_msg(zn, &n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL);
    _z_n_msg_clear(&n_msg);
    return ret;
}

#if Z_FEATURE_INTEREST == 1
void _z_declare_data_clear(_z_declare_data_t *data) { _z_keyexpr_clear(&data->_key); }
size_t _z_declare_data_size(_z_declare_data_t *data) {
    _ZP_UNUSED(data);
    return sizeof(_z_declare_data_t);
}
void _z_declare_data_copy(_z_declare_data_t *dst, const _z_declare_data_t *src) {
    dst->_id = src->_id;
    dst->_type = src->_type;
    dst->_peer = src->_peer;
    _z_keyexpr_copy(&dst->_key, &src->_key);
}

bool _z_declare_data_eq(const _z_declare_data_t *left, const _z_declare_data_t *right) {
    return ((left->_id == right->_id) && (left->_type == right->_type));
}

bool _z_session_interest_eq(const _z_session_interest_t *one, const _z_session_interest_t *two) {
    return one->_id == two->_id;
}

void _z_session_interest_clear(_z_session_interest_t *intr) {
    _z_keyexpr_clear(&intr->_key);
    _z_void_rc_drop(&intr->_arg);
}

/*------------------ interest ------------------*/
static _z_session_interest_rc_t *__z_get_interest_by_id(_z_session_interest_rc_slist_t *intrs, const _z_zint_t id) {
    _z_session_interest_rc_t *ret = NULL;
    _z_session_interest_rc_slist_t *xs = intrs;
    while (xs != NULL) {
        _z_session_interest_rc_t *intr = _z_session_interest_rc_slist_value(xs);
        if (id == _Z_RC_IN_VAL(intr)->_id) {
            ret = intr;
            break;
        }
        xs = _z_session_interest_rc_slist_next(xs);
    }
    return ret;
}

static _z_session_interest_rc_slist_t *__z_get_interest_by_key_and_flags(_z_session_interest_rc_slist_t *intrs,
                                                                         uint8_t flags, const _z_keyexpr_t *key,
                                                                         _z_optional_id_t interest_id) {
    _z_session_interest_rc_slist_t *ret = NULL;
    _z_session_interest_rc_slist_t *xs = intrs;
    while (xs != NULL) {
        _z_session_interest_rc_t *intr = _z_session_interest_rc_slist_value(xs);
        if ((_Z_RC_IN_VAL(intr)->_flags & flags) == 0) {
            xs = _z_session_interest_rc_slist_next(xs);
            continue;
        }
        // consider only interests with matching id if specified (which corresponds to CURRENT interest response)
        // ignore 0 id, since it is the one initially used by peers for declarations propagation
        if (interest_id.has_value && interest_id.value != 0 && interest_id.value != _Z_RC_IN_VAL(intr)->_id) {
            xs = _z_session_interest_rc_slist_next(xs);
            continue;
        }
        bool is_matching = _z_session_interest_is_aggregate(_Z_RC_IN_VAL(intr))
                               ? _z_keyexpr_equals(&_Z_RC_IN_VAL(intr)->_key, key)
                               : _z_keyexpr_intersects(&_Z_RC_IN_VAL(intr)->_key, key);

        if (is_matching) {
            ret = _z_session_interest_rc_slist_push_empty(ret);
            _z_session_interest_rc_t *new_intr = _z_session_interest_rc_slist_value(ret);
            *new_intr = _z_session_interest_rc_clone(intr);
        }
        xs = _z_session_interest_rc_slist_next(xs);
    }
    return ret;
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
static _z_session_interest_rc_t *__unsafe_z_get_interest_by_id(_z_session_t *zn, const _z_zint_t id) {
    _z_session_interest_rc_slist_t *intrs = zn->_local_interests;
    return __z_get_interest_by_id(intrs, id);
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
static _z_session_interest_rc_slist_t *__unsafe_z_get_interest_by_key_and_flags(_z_session_t *zn, uint8_t flags,
                                                                                const _z_keyexpr_t *key,
                                                                                _z_optional_id_t interest_id) {
    _z_session_interest_rc_slist_t *intrs = zn->_local_interests;
    return __z_get_interest_by_key_and_flags(intrs, flags, key, interest_id);
}

_z_session_interest_rc_t *_z_get_interest_by_id(_z_session_t *zn, const _z_zint_t id) {
    _z_session_mutex_lock(zn);
    _z_session_interest_rc_t *intr = __unsafe_z_get_interest_by_id(zn, id);
    _z_session_mutex_unlock(zn);
    return intr;
}

_z_session_interest_rc_t *_z_register_interest(_z_session_t *zn, _z_session_interest_t *intr) {
    _Z_DEBUG(">>> Allocating interest for (%.*s)", (int)_z_string_len(&intr->_key._keyexpr),
             _z_string_data(&intr->_key._keyexpr));
    _z_session_interest_rc_t *ret = NULL;

    if (_z_session_mutex_lock_if_open(zn) != _Z_RES_OK) {
        _Z_WARN("Failed to acquire session mutex for registering interest for (%.*s) - session is closed",
                (int)_z_string_len(&intr->_key._keyexpr), _z_string_data(&intr->_key._keyexpr));
        return ret;
    }
    zn->_local_interests = _z_session_interest_rc_slist_push_empty(zn->_local_interests);
    ret = _z_session_interest_rc_slist_value(zn->_local_interests);
    *ret = _z_session_interest_rc_new_from_val(intr);
    _z_session_mutex_unlock(zn);
    return ret;
}

static z_result_t _unsafe_z_register_declare(_z_session_t *zn, const _z_keyexpr_t *key, uint32_t id, uint8_t type,
                                             bool complete, _z_transport_peer_common_t *peer) {
    zn->_remote_declares = _z_declare_data_slist_push_empty(zn->_remote_declares);
    _z_declare_data_t *decl = _z_declare_data_slist_value(zn->_remote_declares);
    _z_keyexpr_copy(&decl->_key, key);
    decl->_id = id;
    decl->_type = type;
    decl->_complete = complete;
    decl->_peer = peer;
    return _Z_RES_OK;
}

static _z_declare_data_t *_unsafe_z_get_declare(_z_session_t *zn, uint32_t id, uint8_t type) {
    _z_declare_data_slist_t *xs = zn->_remote_declares;
    _z_declare_data_t comp = {._key = _z_keyexpr_null(), ._id = id, ._type = type, ._complete = false};
    while (xs != NULL) {
        _z_declare_data_t *decl = _z_declare_data_slist_value(xs);
        if (_z_declare_data_eq(&comp, decl)) {
            return decl;
        }
        xs = _z_declare_data_slist_next(xs);
    }
    return NULL;
}

static z_result_t _unsafe_z_unregister_declare(_z_session_t *zn, uint32_t id, uint8_t type) {
    _z_declare_data_t decl = {._key = _z_keyexpr_null(), ._id = id, ._type = type, ._complete = false};
    zn->_remote_declares = _z_declare_data_slist_drop_first_filter(zn->_remote_declares, _z_declare_data_eq, &decl);
    return _Z_RES_OK;
}

z_result_t _z_interest_process_declares(_z_session_t *zn, const _z_n_msg_declare_t *decl,
                                        _z_transport_peer_common_t *peer) {
    const _z_wireexpr_t *decl_key = NULL;
    _z_interest_msg_t msg;
    uint8_t flags = 0;
    uint8_t decl_type = 0;
    msg.is_complete = false;

    switch (decl->_decl._tag) {
        case _Z_DECL_SUBSCRIBER:
            msg.type = _Z_INTEREST_MSG_TYPE_DECL_SUBSCRIBER;
            msg.id = decl->_decl._body._decl_subscriber._id;
            decl_key = &decl->_decl._body._decl_subscriber._keyexpr;
            decl_type = _Z_DECLARE_TYPE_SUBSCRIBER;
            flags = _Z_INTEREST_FLAG_SUBSCRIBERS;
            break;
        case _Z_DECL_QUERYABLE:
            msg.type = _Z_INTEREST_MSG_TYPE_DECL_QUERYABLE;
            msg.id = decl->_decl._body._decl_queryable._id;
            decl_key = &decl->_decl._body._decl_queryable._keyexpr;
            decl_type = _Z_DECLARE_TYPE_QUERYABLE;
            flags = _Z_INTEREST_FLAG_QUERYABLES;
            msg.is_complete = decl->_decl._body._decl_queryable._ext_queryable_info._complete;
            break;
        case _Z_DECL_TOKEN:
            msg.type = _Z_INTEREST_MSG_TYPE_DECL_TOKEN;
            msg.id = decl->_decl._body._decl_token._id;
            decl_key = &decl->_decl._body._decl_token._keyexpr;
            decl_type = _Z_DECLARE_TYPE_TOKEN;
            flags = _Z_INTEREST_FLAG_TOKENS;
            break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_MESSAGE_ZENOH_DECLARATION_UNKNOWN);
    }
    // Retrieve key
    _z_keyexpr_t key;
    if (_z_get_keyexpr_from_wireexpr(zn, &key, decl_key, peer, true) != _Z_RES_OK) {
        _Z_ERROR_RETURN(_Z_ERR_KEYEXPR_UNKNOWN);
    }
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_keyexpr_clear(&key));
    msg.key = &key;
    // NOTE: it is possible that it is a redeclare of an existing entity - so we might need to update it
    _z_declare_data_t *prev_decl = _unsafe_z_get_declare(zn, msg.id, decl_type);
    if (prev_decl != NULL) {  // possible change in queryable completness
        prev_decl->_complete = msg.is_complete;
    } else {
        // register new declare
        _unsafe_z_register_declare(zn, &key, msg.id, decl_type, msg.is_complete, peer);
    }
    // Retrieve interests
    _z_session_interest_rc_slist_t *intrs =
        __unsafe_z_get_interest_by_key_and_flags(zn, flags, &key, decl->_interest_id);
    _z_session_mutex_unlock(zn);
    // update interests with new value
    _z_session_interest_rc_slist_t *xs = intrs;
    while (xs != NULL) {
        _z_session_interest_rc_t *intr = _z_session_interest_rc_slist_value(xs);
        if (_Z_RC_IN_VAL(intr)->_callback != NULL) {
            _Z_RC_IN_VAL(intr)->_callback(&msg, peer, _Z_RC_IN_VAL(&_Z_RC_IN_VAL(intr)->_arg));
        }
        xs = _z_session_interest_rc_slist_next(xs);
    }
    // Clean up
    _z_keyexpr_clear(&key);
    _z_session_interest_rc_slist_free(&intrs);
    return _Z_RES_OK;
}

z_result_t _z_interest_process_undeclares(_z_session_t *zn, const _z_declaration_t *decl,
                                          _z_transport_peer_common_t *peer) {
    _z_interest_msg_t msg = {0};
    uint8_t flags = 0;
    uint8_t decl_type = 0;
    switch (decl->_tag) {
        case _Z_UNDECL_SUBSCRIBER:
            msg.type = _Z_INTEREST_MSG_TYPE_UNDECL_SUBSCRIBER;
            msg.id = decl->_body._undecl_subscriber._id;
            decl_type = _Z_DECLARE_TYPE_SUBSCRIBER;
            flags = _Z_INTEREST_FLAG_SUBSCRIBERS;
            break;
        case _Z_UNDECL_QUERYABLE:
            msg.type = _Z_INTEREST_MSG_TYPE_UNDECL_QUERYABLE;
            msg.id = decl->_body._undecl_queryable._id;
            decl_type = _Z_DECLARE_TYPE_QUERYABLE;
            flags = _Z_INTEREST_FLAG_QUERYABLES;
            break;
        case _Z_UNDECL_TOKEN:
            msg.type = _Z_INTEREST_MSG_TYPE_UNDECL_TOKEN;
            msg.id = decl->_body._undecl_token._id;
            decl_type = _Z_DECLARE_TYPE_TOKEN;
            flags = _Z_INTEREST_FLAG_TOKENS;
            break;
        default:
            _Z_ERROR_RETURN(_Z_ERR_MESSAGE_ZENOH_DECLARATION_UNKNOWN);
    }
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    // Retrieve declare data
    _z_declare_data_t *prev_decl = _unsafe_z_get_declare(zn, msg.id, decl_type);
    if (prev_decl == NULL) {
        _z_session_mutex_unlock(zn);
        _Z_ERROR_RETURN(_Z_ERR_MESSAGE_ZENOH_DECLARATION_UNKNOWN);
    }
    _z_session_interest_rc_slist_t *intrs =
        __unsafe_z_get_interest_by_key_and_flags(zn, flags, &prev_decl->_key, _z_optional_id_make_none());
    // Remove declare
    _unsafe_z_unregister_declare(zn, msg.id, decl_type);
    _z_session_mutex_unlock(zn);

    // Parse session_interest list
    _z_session_interest_rc_slist_t *xs = intrs;
    while (xs != NULL) {
        _z_session_interest_rc_t *intr = _z_session_interest_rc_slist_value(xs);
        if (_Z_RC_IN_VAL(intr)->_callback != NULL) {
            _Z_RC_IN_VAL(intr)->_callback(&msg, peer, _Z_RC_IN_VAL(&_Z_RC_IN_VAL(intr)->_arg));
        }
        xs = _z_session_interest_rc_slist_next(xs);
    }
    // Clean up
    _z_session_interest_rc_slist_free(&intrs);
    return _Z_RES_OK;
}

void _z_unregister_interest(_z_session_t *zn, _z_session_interest_rc_t *intr) {
    _z_session_mutex_lock(zn);
    zn->_local_interests =
        _z_session_interest_rc_slist_drop_first_filter(zn->_local_interests, _z_session_interest_rc_eq, intr);
    _z_session_mutex_unlock(zn);
}

void _z_interest_init(_z_session_t *zn) {
    _z_session_mutex_lock(zn);
    zn->_local_interests = NULL;
    zn->_remote_declares = NULL;
    _z_session_mutex_unlock(zn);
}

void _z_flush_interest(_z_session_t *zn) {
    _z_session_mutex_lock(zn);
    _z_session_interest_rc_slist_free(&zn->_local_interests);
    _z_declare_data_slist_free(&zn->_remote_declares);
    _z_session_mutex_unlock(zn);
}

z_result_t _z_interest_process_declare_final(_z_session_t *zn, uint32_t id, _z_transport_peer_common_t *peer) {
    _z_interest_msg_t msg = {.type = _Z_INTEREST_MSG_TYPE_FINAL, .id = id};
    // Retrieve interest
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    _z_session_interest_rc_t *intr = __unsafe_z_get_interest_by_id(zn, id);
    _z_session_mutex_unlock(zn);
    if (intr == NULL) {
        return _Z_RES_OK;
    }
    // Trigger callback
    if (_Z_RC_IN_VAL(intr)->_callback != NULL) {
        _Z_RC_IN_VAL(intr)->_callback(&msg, peer, _Z_RC_IN_VAL(&_Z_RC_IN_VAL(intr)->_arg));
    }
    return _Z_RES_OK;
}

z_result_t _z_interest_process_interest_final(_z_session_t *zn, uint32_t id) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(id);
    // TODO: Update future masks
    return _Z_RES_OK;
}

z_result_t _z_interest_process_interest(_z_session_t *zn, const _z_wireexpr_t *wireexpr, uint32_t id, uint8_t flags,
                                        _z_transport_peer_common_t *peer) {
    // Check transport type
    if (zn->_tp._type == _Z_TRANSPORT_UNICAST_TYPE) {
        return _Z_RES_OK;  // Nothing to do on unicast
    }
    // Push a join in case it's a new node
    _Z_RETURN_IF_ERR(_zp_multicast_send_join(&zn->_tp._transport._multicast));
    _z_keyexpr_t restr_key = _z_keyexpr_null();
    if (_Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_RESTRICTED)) {
        _Z_RETURN_IF_ERR(_z_get_keyexpr_from_wireexpr(zn, &restr_key, wireexpr, peer, true));
    }
    _z_keyexpr_t *restr_key_opt = _z_keyexpr_check(&restr_key) ? &restr_key : NULL;
    z_result_t ret = _Z_RES_OK;
    // Current flags process
    if (_Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_CURRENT)) {
        // Send all declare
        if (ret == _Z_RES_OK && _Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_KEYEXPRS)) {
            _Z_DEBUG("Sending declare resources");
            ret = _z_interest_send_decl_resource(zn, id, NULL, restr_key_opt);
        }
        if (ret == _Z_RES_OK && _Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_SUBSCRIBERS)) {
            _Z_DEBUG("Sending declare subscribers");
            ret = _z_interest_send_decl_subscriber(zn, id, NULL, restr_key_opt);
        }
        if (ret == _Z_RES_OK && _Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_QUERYABLES)) {
            _Z_DEBUG("Sending declare queryables");
            ret = _z_interest_send_decl_queryable(zn, id, NULL, restr_key_opt);
        }
        if (ret == _Z_RES_OK && _Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_TOKENS)) {
            _Z_DEBUG("Sending declare tokens");
            ret = _z_interest_send_decl_token(zn, id, NULL, restr_key_opt);
        }
        // Send final declare
        _Z_SET_IF_OK(ret, _z_interest_send_declare_final(zn, id, NULL));
    }
    _z_keyexpr_clear(&restr_key);
    return ret;
}

void _z_interest_peer_disconnected(_z_session_t *zn, _z_transport_peer_common_t *peer) {
    // Clone session interest list
    if (_z_session_mutex_lock_if_open(zn) != _Z_RES_OK) {
        return;
    }
    _z_session_interest_rc_slist_t *intrs = _z_session_interest_rc_slist_clone(zn->_local_interests);
    _z_session_mutex_unlock(zn);

    // Parse session_interest list
    _z_interest_msg_t msg = {.id = 0, .type = _Z_INTEREST_MSG_TYPE_CONNECTION_DROPPED};
    _z_session_interest_rc_slist_t *xs = intrs;
    while (xs != NULL) {
        _z_session_interest_rc_t *intr = _z_session_interest_rc_slist_value(xs);
        if (_Z_RC_IN_VAL(intr)->_callback != NULL) {
            _Z_RC_IN_VAL(intr)->_callback(&msg, peer, _Z_RC_IN_VAL(&_Z_RC_IN_VAL(intr)->_arg));
        }
        xs = _z_session_interest_rc_slist_next(xs);
    }
    // Clean up
    _z_session_interest_rc_slist_free(&intrs);
}

void _z_interest_replay_declare(_z_session_t *zn, _z_session_interest_t *interest) {
    if (_z_session_mutex_lock_if_open(zn) != _Z_RES_OK) {
        return;
    }
    _z_declare_data_slist_t *res_list = _z_declare_data_slist_clone(zn->_remote_declares);
    _z_session_mutex_unlock(zn);

    _z_declare_data_slist_t *xs = res_list;
    while (xs != NULL) {
        _z_declare_data_t *res = _z_declare_data_slist_value(xs);
        bool is_matching = _z_session_interest_is_aggregate(interest)
                               ? _z_keyexpr_equals(&interest->_key, &res->_key)
                               : _z_keyexpr_intersects(&interest->_key, &res->_key);
        if (is_matching) {
            _z_interest_msg_t msg = {0};
            msg.key = &res->_key;
            msg.is_complete = res->_complete;
            msg.id = res->_id;
            switch (res->_type) {
                default:
                    break;
                case _Z_DECLARE_TYPE_QUERYABLE:
                    msg.type = _Z_INTEREST_MSG_TYPE_DECL_QUERYABLE;
                    break;
                case _Z_DECLARE_TYPE_SUBSCRIBER:
                    msg.type = _Z_INTEREST_MSG_TYPE_DECL_SUBSCRIBER;
                    break;
                case _Z_DECLARE_TYPE_TOKEN:
                    msg.type = _Z_INTEREST_MSG_TYPE_DECL_TOKEN;
                    break;
            }
            interest->_callback(&msg, res->_peer, _Z_RC_IN_VAL(&interest->_arg));
        }
        xs = _z_declare_data_slist_next(xs);
    }
    _z_declare_data_slist_free(&res_list);
}

#else
void _z_interest_init(_z_session_t *zn) { _ZP_UNUSED(zn); }

void _z_flush_interest(_z_session_t *zn) { _ZP_UNUSED(zn); }

z_result_t _z_interest_process_declares(_z_session_t *zn, const _z_n_msg_declare_t *decl,
                                        _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}

z_result_t _z_interest_process_undeclares(_z_session_t *zn, const _z_declaration_t *decl,
                                          _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(decl);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}

z_result_t _z_interest_process_declare_final(_z_session_t *zn, uint32_t id, _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(id);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}

z_result_t _z_interest_process_interest_final(_z_session_t *zn, uint32_t id) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(id);
    return _Z_RES_OK;
}

z_result_t _z_interest_process_interest(_z_session_t *zn, _z_wireexpr_t *wireexpr, uint32_t id, uint8_t flags,
                                        _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(wireexpr);
    _ZP_UNUSED(id);
    _ZP_UNUSED(flags);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}

void _z_interest_peer_disconnected(_z_session_t *zn, _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(peer);
}
#endif
