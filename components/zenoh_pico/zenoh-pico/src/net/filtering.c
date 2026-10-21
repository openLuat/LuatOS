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

#include "zenoh-pico/net/filtering.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/net/primitives.h"
#include "zenoh-pico/session/matching.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/utils/locality.h"

#if Z_FEATURE_INTEREST == 1

typedef struct _z_write_filter_registration_t {
    _z_write_filter_ctx_rc_t ctx_rc;
    struct _z_write_filter_registration_t *next;
} _z_write_filter_registration_t;

static bool _z_filter_target_peer_eq(const void *left, const void *right) {
    const _z_filter_target_t *left_val = (const _z_filter_target_t *)left;
    const _z_filter_target_t *right_val = (const _z_filter_target_t *)right;
    return left_val->peer == right_val->peer;
}

static bool _z_filter_target_eq(const void *left, const void *right) {
    const _z_filter_target_t *left_val = (const _z_filter_target_t *)left;
    const _z_filter_target_t *right_val = (const _z_filter_target_t *)right;
    return (left_val->peer == right_val->peer) && (left_val->decl_id == right_val->decl_id);
}

#if Z_FEATURE_MULTI_THREAD == 1
static void _z_write_filter_mutex_lock(_z_write_filter_ctx_t *ctx) { _z_mutex_lock(&ctx->mutex); }
static void _z_write_filter_mutex_unlock(_z_write_filter_ctx_t *ctx) { _z_mutex_unlock(&ctx->mutex); }
#else
static void _z_write_filter_mutex_lock(_z_write_filter_ctx_t *ctx) { _ZP_UNUSED(ctx); }
static void _z_write_filter_mutex_unlock(_z_write_filter_ctx_t *ctx) { _ZP_UNUSED(ctx); }
#endif

static bool _z_write_filter_push_target(_z_write_filter_ctx_t *ctx, _z_transport_peer_common_t *peer, uint32_t id) {
    _z_filter_target_t target = {.peer = (uintptr_t)peer, .decl_id = id};
    ctx->targets = _z_filter_target_slist_push(ctx->targets, &target);
    if (ctx->targets == NULL) {  // Allocation can fail
        return false;
    }
    return true;
}

static inline bool _z_write_filter_peer_allowed(const _z_write_filter_ctx_t *ctx, _z_transport_peer_common_t *peer) {
    return ((peer == NULL) && ctx->allow_local) || ((peer != NULL) && ctx->allow_remote);
}

static void _z_write_filter_ctx_update_state(_z_write_filter_ctx_t *ctx) {
    uint8_t prev_state = ctx->state;
    ctx->state = (ctx->targets == NULL && ctx->local_targets == 0) ? WRITE_FILTER_ACTIVE : WRITE_FILTER_OFF;
    if (prev_state != ctx->state) {
        _Z_DEBUG("Updated write filter state: %d", ctx->state);
#if Z_FEATURE_MATCHING
        _z_closure_matching_status_intmap_iterator_t it =
            _z_closure_matching_status_intmap_iterator_make(&ctx->callbacks);
        _z_matching_status_t s = {.matching = ctx->state != WRITE_FILTER_ACTIVE};
        while (_z_closure_matching_status_intmap_iterator_next(&it)) {
            _z_closure_matching_status_t *c = _z_closure_matching_status_intmap_iterator_value(&it);
            c->call(&s, c->context);
        }
#endif
    }
}

#if Z_FEATURE_LOCAL_SUBSCRIBER == 1 || Z_FEATURE_LOCAL_QUERYABLE == 1
static void _z_write_filter_ctx_add_local_match(_z_write_filter_ctx_t *ctx) {
    _z_write_filter_mutex_lock(ctx);
    ctx->local_targets++;
    _z_write_filter_ctx_update_state(ctx);
    _z_write_filter_mutex_unlock(ctx);
}

static void _z_write_filter_ctx_remove_local_match(_z_write_filter_ctx_t *ctx) {
    _z_write_filter_mutex_lock(ctx);
    if (ctx->local_targets > 0) {
        ctx->local_targets--;
    }
    _z_write_filter_ctx_update_state(ctx);
    _z_write_filter_mutex_unlock(ctx);
}
#endif

static z_result_t _z_write_filter_session_register(_z_session_t *session, _z_write_filter_ctx_t *ctx,
                                                   _z_write_filter_ctx_rc_t *ctx_rc) {
    _z_write_filter_registration_t *registration =
        (_z_write_filter_registration_t *)z_malloc(sizeof(_z_write_filter_registration_t));
    if (registration == NULL) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }

    registration->ctx_rc = _z_write_filter_ctx_rc_clone(ctx_rc);
    if (_Z_RC_IS_NULL(&registration->ctx_rc)) {
        z_free(registration);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    if (_z_session_mutex_lock_if_open(session) != _Z_RES_OK) {
        _Z_WARN("Failed to lock session for write filter registration - session may be closing");
        _z_write_filter_ctx_rc_drop(&registration->ctx_rc);
        z_free(registration);
        return _Z_ERR_SESSION_CLOSED;
    }
    registration->next = session->_write_filters;
    session->_write_filters = registration;

#if (Z_FEATURE_LOCAL_SUBSCRIBER == 1) || (Z_FEATURE_LOCAL_QUERYABLE == 1)
    if (ctx->allow_local) {
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
        if (ctx->target_type == _Z_WRITE_FILTER_SUBSCRIBER) {
            _z_subscription_rc_slist_t *node = session->_subscriptions;
            while (node != NULL) {
                _z_subscription_t *sub = _Z_RC_IN_VAL(_z_subscription_rc_slist_value(node));
                if (_z_locality_allows_local(sub->_allowed_origin) &&
                    _z_keyexpr_intersects(&ctx->key, &sub->_key._inner)) {
                    _z_write_filter_ctx_add_local_match(ctx);
                }
                node = _z_subscription_rc_slist_next(node);
            }
        }
#endif
#if Z_FEATURE_LOCAL_QUERYABLE == 1
        if (ctx->target_type == _Z_WRITE_FILTER_QUERYABLE) {
            _z_session_queryable_rc_slist_t *node = session->_local_queryable;
            while (node != NULL) {
                _z_session_queryable_t *queryable = _Z_RC_IN_VAL(_z_session_queryable_rc_slist_value(node));
                if (_z_locality_allows_local(queryable->_allowed_origin)) {
                    if (ctx->is_complete
                            ? (queryable->_complete && _z_keyexpr_includes(&queryable->_key._inner, &ctx->key))
                            : _z_keyexpr_intersects(&ctx->key, &queryable->_key._inner)) {
                        _z_write_filter_ctx_add_local_match(ctx);
                    }
                }
                node = _z_session_queryable_rc_slist_next(node);
            }
        }
#endif
    }
#endif
    _z_session_mutex_unlock(session);

    ctx->registration = registration;
    return _Z_RES_OK;
}

static void _z_write_filter_session_unregister(_z_write_filter_ctx_t *ctx) {
    _z_write_filter_registration_t *registration = ctx->registration;
    if (registration == NULL) {
        return;
    }
    ctx->registration = NULL;

    _z_session_rc_t session_rc = _z_session_weak_upgrade_if_open(&_Z_RC_IN_VAL(&registration->ctx_rc)->zn);
    if (_Z_RC_IS_NULL(&session_rc)) {
        _z_write_filter_ctx_rc_drop(&registration->ctx_rc);
        z_free(registration);
        return;
    }
    _z_session_t *session = _Z_RC_IN_VAL(&session_rc);
    _z_session_mutex_lock(session);
    _z_write_filter_registration_t **iter = &session->_write_filters;
    while (*iter != NULL && *iter != registration) {
        iter = &((*iter)->next);
    }
    if (*iter != NULL) {
        *iter = registration->next;
    }
    _z_session_mutex_unlock(session);
    _z_session_rc_drop(&session_rc);

    _z_write_filter_ctx_rc_drop(&registration->ctx_rc);
    z_free(registration);
}

static void _z_write_filter_callback(const _z_interest_msg_t *msg, _z_transport_peer_common_t *peer, void *arg) {
    _z_write_filter_ctx_t *ctx = (_z_write_filter_ctx_t *)arg;
    // Process message
    _z_write_filter_mutex_lock(ctx);
    switch (msg->type) {
        case _Z_INTEREST_MSG_TYPE_DECL_SUBSCRIBER:
        case _Z_INTEREST_MSG_TYPE_DECL_QUERYABLE: {
            // the message might be a redeclare - so we need to remove the previous one first
            _z_filter_target_t target = {.decl_id = msg->id, .peer = (uintptr_t)peer};
            ctx->targets = _z_filter_target_slist_drop_first_filter(ctx->targets, _z_filter_target_eq, &target);
            bool peer_allowed = _z_write_filter_peer_allowed(ctx, peer);
            if (peer_allowed &&
                (!ctx->is_complete ||
                 (msg->is_complete && (ctx->is_aggregate || _z_keyexpr_includes(msg->key, &ctx->key))))) {
                _z_write_filter_push_target(ctx, peer, msg->id);
            }
            break;
        }
        case _Z_INTEREST_MSG_TYPE_UNDECL_SUBSCRIBER:
        case _Z_INTEREST_MSG_TYPE_UNDECL_QUERYABLE: {
            _z_filter_target_t target = {.decl_id = msg->id, .peer = (uintptr_t)peer};
            ctx->targets = _z_filter_target_slist_drop_first_filter(ctx->targets, _z_filter_target_eq, &target);
        } break;
        case _Z_INTEREST_MSG_TYPE_CONNECTION_DROPPED: {
            _z_filter_target_t target = {.decl_id = 0, .peer = (uintptr_t)peer};
            ctx->targets = _z_filter_target_slist_drop_all_filter(ctx->targets, _z_filter_target_peer_eq, &target);
        } break;
        default:
            break;
    }
    _z_write_filter_ctx_update_state(ctx);
    _z_write_filter_mutex_unlock(ctx);
}

z_result_t _z_write_filter_create(const _z_session_rc_t *zn, _z_write_filter_t *filter,
                                  const _z_declared_keyexpr_t *keyexpr, uint8_t interest_flag, bool complete,
                                  z_locality_t locality) {
    uint8_t flags = interest_flag | _Z_INTEREST_FLAG_RESTRICTED | _Z_INTEREST_FLAG_CURRENT;
    if (_Z_RC_IN_VAL(zn)->_mode == Z_WHATAMI_CLIENT) {
        // Add client specific flags
        flags |= _Z_INTEREST_FLAG_KEYEXPRS | _Z_INTEREST_FLAG_AGGREGATE | _Z_INTEREST_FLAG_FUTURE;
    } else if (_Z_RC_IN_VAL(zn)->_mode == Z_WHATAMI_PEER && _z_session_has_router_peer(_Z_RC_IN_VAL(zn))) {
        // Add additional flags when in peer mode and connected to a router
        flags |= _Z_INTEREST_FLAG_KEYEXPRS | _Z_INTEREST_FLAG_FUTURE;
    }
    filter->ctx = _z_write_filter_ctx_rc_null();
    _z_keyexpr_t ke;
    _Z_RETURN_IF_ERR(_z_keyexpr_copy(&ke, &keyexpr->_inner));
    _z_write_filter_ctx_t *ctx = (_z_write_filter_ctx_t *)z_malloc(sizeof(_z_write_filter_ctx_t));

    if (ctx == NULL) {
        _z_keyexpr_clear(&ke);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_CLEAN_RETURN_IF_ERR(_z_mutex_init(&ctx->mutex), _z_keyexpr_clear(&ke); z_free(ctx));
#endif
    ctx->state = WRITE_FILTER_ACTIVE;
    ctx->targets = _z_filter_target_slist_new();
#if Z_FEATURE_MATCHING
    _z_closure_matching_status_intmap_init(&ctx->callbacks);
#endif
    bool expects_queryable = _Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_QUERYABLES);
    assert(expects_queryable != _Z_HAS_FLAG(flags, _Z_INTEREST_FLAG_SUBSCRIBERS) &&
           "write filter must target exactly one entity type");
    ctx->is_complete = complete;
    ctx->is_aggregate = (flags & _Z_INTEREST_FLAG_AGGREGATE) != 0;
    ctx->allow_local = _z_locality_allows_local(locality);
    ctx->allow_remote = _z_locality_allows_remote(locality);
    ctx->target_type = expects_queryable ? _Z_WRITE_FILTER_QUERYABLE : _Z_WRITE_FILTER_SUBSCRIBER;
    ctx->key = ke;
    ctx->zn = _z_session_rc_clone_as_weak(zn);
    if (_Z_RC_IS_NULL(&ctx->zn)) {
        _z_write_filter_ctx_clear(ctx);
        z_free(ctx);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    ctx->local_targets = 0;
    ctx->registration = NULL;
    filter->ctx = _z_write_filter_ctx_rc_new(ctx);

    if (_Z_RC_IS_NULL(&filter->ctx)) {
        _z_write_filter_ctx_clear(ctx);
        z_free(ctx);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    _z_write_filter_ctx_rc_t filter_ctx_clone = _z_write_filter_ctx_rc_clone(&filter->ctx);
    _z_void_rc_t ctx_void = _z_write_filter_ctx_rc_to_void(&filter_ctx_clone);
    filter->_interest_id = _z_add_interest(_Z_RC_IN_VAL(zn), keyexpr, _z_write_filter_callback, flags, &ctx_void);
    if (filter->_interest_id == 0) {
        _z_write_filter_ctx_rc_drop(&filter->ctx);
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }

    _Z_CLEAN_RETURN_IF_ERR(_z_write_filter_session_register(_Z_RC_IN_VAL(zn), ctx, &filter->ctx),
                           _z_remove_interest(_Z_RC_IN_VAL(zn), filter->_interest_id);
                           _z_write_filter_ctx_rc_drop(&filter->ctx));

    return _Z_RES_OK;
}

z_result_t _z_write_filter_ctx_clear(_z_write_filter_ctx_t *ctx) {
    z_result_t res = _Z_RES_OK;
    _z_write_filter_session_unregister(ctx);
    _z_write_filter_mutex_lock(ctx);
    _z_filter_target_slist_free(&ctx->targets);
#if Z_FEATURE_MATCHING
    _z_closure_matching_status_intmap_clear(&ctx->callbacks);
#endif
    _z_keyexpr_clear(&ctx->key);
    _z_session_weak_drop(&ctx->zn);
    _z_write_filter_mutex_unlock(ctx);

#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_drop(&ctx->mutex);
#endif
    return res;
}

z_result_t _z_write_filter_clear(_z_write_filter_t *filter) {
    if (_Z_RC_IS_NULL(&filter->ctx)) {
        return _Z_RES_OK;
    }
    _z_write_filter_session_unregister(_Z_RC_IN_VAL(&filter->ctx));
    _z_session_rc_t s = _z_session_weak_upgrade_if_open(&_Z_RC_IN_VAL(&filter->ctx)->zn);
    if (!_Z_RC_IS_NULL(&s)) {
        _z_remove_interest(_Z_RC_IN_VAL(&s), filter->_interest_id);
        _z_session_rc_drop(&s);
    }
    _z_write_filter_ctx_remove_callbacks(_Z_RC_IN_VAL(&filter->ctx));
    _z_write_filter_ctx_rc_drop(&filter->ctx);
    return _Z_RES_OK;
}

#if Z_FEATURE_MATCHING == 1
void _z_write_filter_ctx_remove_callback(_z_write_filter_ctx_t *ctx, size_t id) {
    _z_write_filter_mutex_lock(ctx);
    _z_closure_matching_status_intmap_remove(&ctx->callbacks, id);
    _z_write_filter_mutex_unlock(ctx);
}

void _z_write_filter_ctx_remove_callbacks(_z_write_filter_ctx_t *ctx) {
    _z_write_filter_mutex_lock(ctx);
    _z_closure_matching_status_intmap_clear(&ctx->callbacks);
    _z_write_filter_mutex_unlock(ctx);
}

z_result_t _z_write_filter_ctx_add_callback(_z_write_filter_ctx_t *ctx, size_t id, _z_closure_matching_status_t *v) {
    _z_closure_matching_status_t *ptr = (_z_closure_matching_status_t *)z_malloc(sizeof(_z_closure_matching_status_t));
    if (ptr == NULL) {
        _z_closure_matching_status_clear(v);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    *ptr = *v;
    *v = (_z_closure_matching_status_t){NULL, NULL, NULL};
    _z_write_filter_mutex_lock(ctx);
    if (!_z_write_filter_ctx_active(ctx)) {
        _z_matching_status_t s = (_z_matching_status_t){.matching = true};
        ptr->call(&s, ptr->context);
    }
    _z_closure_matching_status_intmap_insert(&ctx->callbacks, id, ptr);
    _z_write_filter_mutex_unlock(ctx);
    return _Z_RES_OK;
}
#endif

#if Z_FEATURE_LOCAL_SUBSCRIBER == 1 || Z_FEATURE_LOCAL_QUERYABLE == 1
static void _z_write_filter_match_free(void **value) {
    if (value == NULL || *value == NULL) {
        return;
    }
    _z_write_filter_ctx_rc_t *ctx = (_z_write_filter_ctx_rc_t *)(*value);
    _z_write_filter_ctx_rc_drop(ctx);
    z_free(ctx);
    *value = NULL;
}

static void _z_write_filter_notify_local_entity(_z_session_t *session, const _z_keyexpr_t *key,
                                                z_locality_t allowed_origin, bool is_complete,
                                                _z_write_filter_target_type_t source_type, bool add) {
    if (!_z_locality_allows_local(allowed_origin)) {
        return;
    }

    if (_z_session_mutex_lock_if_open(session) != _Z_RES_OK) {
        return;
    }

    _z_list_t *matches = NULL;
    for (_z_write_filter_registration_t *registration = session->_write_filters; registration != NULL;
         registration = registration->next) {
        _z_write_filter_ctx_t *registration_ctx = _Z_RC_IN_VAL(&registration->ctx_rc);
        if (!(registration_ctx->allow_local &&
              (registration_ctx->is_complete ? (is_complete && _z_keyexpr_includes(key, &registration_ctx->key))
                                             : _z_keyexpr_intersects(&registration_ctx->key, key)))) {
            continue;
        }
        if (registration_ctx->target_type != source_type) {
            continue;
        }
        _z_write_filter_ctx_rc_t *ctx_clone = (_z_write_filter_ctx_rc_t *)z_malloc(sizeof(_z_write_filter_ctx_rc_t));
        if (ctx_clone == NULL) {
            _z_list_free(&matches, _z_write_filter_match_free);
            _z_session_mutex_unlock(session);
            return;
        }
        *ctx_clone = _z_write_filter_ctx_rc_clone(&registration->ctx_rc);
        _z_list_t *new_head = _z_list_push(matches, ctx_clone);
        assert(new_head != matches && "Failed to allocate write-filter match node");
        matches = new_head;
    }

    _z_session_mutex_unlock(session);

    _z_list_t *it = matches;
    while (it != NULL) {
        _z_write_filter_ctx_rc_t *ctx_clone = (_z_write_filter_ctx_rc_t *)_z_list_value(it);
        _z_write_filter_ctx_t *matched_ctx = _Z_RC_IN_VAL(ctx_clone);
        if (add) {
            _z_write_filter_ctx_add_local_match(matched_ctx);
        } else {
            _z_write_filter_ctx_remove_local_match(matched_ctx);
        }
        it = _z_list_next(it);
    }
    _z_list_free(&matches, _z_write_filter_match_free);
}

void _z_write_filter_notify_subscriber(_z_session_t *session, const _z_keyexpr_t *key, z_locality_t allowed_origin,
                                       bool add) {
    _z_write_filter_notify_local_entity(session, key, allowed_origin, true, _Z_WRITE_FILTER_SUBSCRIBER, add);
}

void _z_write_filter_notify_queryable(_z_session_t *session, const _z_keyexpr_t *key, z_locality_t allowed_origin,
                                      bool is_complete, bool add) {
    _z_write_filter_notify_local_entity(session, key, allowed_origin, is_complete, _Z_WRITE_FILTER_QUERYABLE, add);
}
#else
void _z_write_filter_notify_subscriber(_z_session_t *session, const _z_keyexpr_t *key, z_locality_t allowed_origin,
                                       bool add) {
    _ZP_UNUSED(session);
    _ZP_UNUSED(key);
    _ZP_UNUSED(allowed_origin);
    _ZP_UNUSED(add);
}

void _z_write_filter_notify_queryable(_z_session_t *session, const _z_keyexpr_t *key, z_locality_t allowed_origin,
                                      bool is_complete, bool add) {
    _ZP_UNUSED(session);
    _ZP_UNUSED(key);
    _ZP_UNUSED(allowed_origin);
    _ZP_UNUSED(is_complete);
    _ZP_UNUSED(add);
}
#endif  // Z_FEATURE_LOCAL_SUBSCRIBER == 1 || Z_FEATURE_LOCAL_QUERYABLE == 1

#else  // Z_FEATURE_INTEREST == 0
z_result_t _z_write_filter_create(const _z_session_rc_t *zn, _z_write_filter_t *filter,
                                  const _z_declared_keyexpr_t *keyexpr, uint8_t interest_flag, bool complete,
                                  z_locality_t locality) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(keyexpr);
    _ZP_UNUSED(filter);
    _ZP_UNUSED(interest_flag);
    _ZP_UNUSED(complete);
    _ZP_UNUSED(locality);
    return _Z_RES_OK;
}

z_result_t _z_write_filter_clear(_z_write_filter_t *filter) {
    _ZP_UNUSED(filter);
    return _Z_RES_OK;
}

void _z_write_filter_notify_subscriber(_z_session_t *session, const _z_keyexpr_t *key, z_locality_t allowed_origin,
                                       bool add) {
    _ZP_UNUSED(session);
    _ZP_UNUSED(key);
    _ZP_UNUSED(allowed_origin);
    _ZP_UNUSED(add);
}

void _z_write_filter_notify_queryable(_z_session_t *session, const _z_keyexpr_t *key, z_locality_t allowed_origin,
                                      bool is_complete, bool add) {
    _ZP_UNUSED(session);
    _ZP_UNUSED(key);
    _ZP_UNUSED(allowed_origin);
    _ZP_UNUSED(is_complete);
    _ZP_UNUSED(add);
}

#endif
