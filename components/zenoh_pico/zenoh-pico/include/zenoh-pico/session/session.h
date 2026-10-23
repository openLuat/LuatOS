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

#ifndef INCLUDE_ZENOH_PICO_SESSION_SESSION_H
#define INCLUDE_ZENOH_PICO_SESSION_SESSION_H

#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/list.h"
#include "zenoh-pico/collections/refcount.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/cancellation.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/transport/manager.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * The callback signature of the cleanup functions.
 */
typedef void (*_z_drop_handler_t)(void *arg);

static inline void _z_drop_handler_execute(_z_drop_handler_t dropper, void *arg) {
    if (dropper != NULL) {
        dropper(arg);
    }
}

typedef enum {
    _Z_SUBSCRIBER_KIND_SUBSCRIBER = 0,
    _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER = 1,
} _z_subscriber_kind_t;

typedef struct {
    _z_keyexpr_t _key;
    uint16_t _id;
    uint16_t _refcount;
} _z_resource_t;

bool _z_resource_eq(const _z_resource_t *one, const _z_resource_t *two);
void _z_resource_clear(_z_resource_t *res);
void _z_resource_copy(_z_resource_t *dst, const _z_resource_t *src);
void _z_resource_free(_z_resource_t **res);
size_t _z_resource_size(_z_resource_t *p);

_Z_ELEM_DEFINE(_z_resource, _z_resource_t, _z_resource_size, _z_resource_clear, _z_resource_copy, _z_noop_move,
               _z_resource_eq, _z_noop_cmp, _z_noop_hash)
_Z_SLIST_DEFINE(_z_resource, _z_resource_t, true)

_Z_ELEM_DEFINE(_z_keyexpr, _z_keyexpr_t, _z_keyexpr_size, _z_keyexpr_clear, _z_keyexpr_copy, _z_keyexpr_move,
               _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_INT_MAP_DEFINE(_z_keyexpr, _z_keyexpr_t)
_Z_SLIST_DEFINE(_z_keyexpr, _z_keyexpr_t, true)
_Z_ELEM_DEFINE(_z_declared_keyexpr, _z_declared_keyexpr_t, _z_declared_keyexpr_size, _z_declared_keyexpr_clear,
               _z_declared_keyexpr_copy, _z_declared_keyexpr_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_INT_MAP_DEFINE(_z_declared_keyexpr, _z_declared_keyexpr_t)

// Forward declaration to avoid cyclical include
typedef struct _z_sample_t _z_sample_t;

/**
 * The callback signature of the functions handling data messages.
 */
typedef void (*_z_closure_sample_callback_t)(_z_sample_t *sample, void *arg);

typedef struct {
    _z_declared_keyexpr_t _key;
    uint32_t _id;
    z_locality_t _allowed_origin;
    _z_closure_sample_callback_t _callback;
    _z_drop_handler_t _dropper;
    void *_arg;
    _z_sync_group_notifier_t _session_callback_drop_notifier;
    _z_sync_group_notifier_t _subscriber_callback_drop_notifier;
} _z_subscription_t;

bool _z_subscription_eq(const _z_subscription_t *one, const _z_subscription_t *two);
void _z_subscription_clear(_z_subscription_t *sub);

static inline _z_subscription_t _z_subscription_null(void) {
    _z_subscription_t s = {0};
    return s;
}

_Z_REFCOUNT_DEFINE(_z_subscription, _z_subscription)
_Z_ELEM_DEFINE(_z_subscriber, _z_subscription_t, _z_noop_size, _z_subscription_clear, _z_noop_copy, _z_noop_move,
               _z_subscription_eq, _z_noop_cmp, _z_noop_hash)
_Z_ELEM_DEFINE(_z_subscription_rc, _z_subscription_rc_t, _z_subscription_rc_size, _z_subscription_rc_drop,
               _z_subscription_rc_copy, _z_noop_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_SLIST_DEFINE(_z_subscription_rc, _z_subscription_rc_t, true)

typedef struct {
    _z_keyexpr_t _key;
    uint32_t _id;
} _z_publication_t;

// Forward type declaration to avoid cyclical include
typedef struct _z_query_rc_t _z_query_rc_t;

/**
 * The callback signature of the functions handling query messages.
 */
typedef void (*_z_closure_query_callback_t)(_z_query_rc_t *query, void *arg);

typedef struct {
    _z_declared_keyexpr_t _key;
    uint32_t _id;
    _z_closure_query_callback_t _callback;
    _z_drop_handler_t _dropper;
    void *_arg;
    bool _complete;
    z_locality_t _allowed_origin;
    _z_sync_group_notifier_t _session_callback_drop_notifier;
    _z_sync_group_notifier_t _queryable_callback_drop_notifier;
} _z_session_queryable_t;

static inline _z_session_queryable_t _z_session_queryable_null(void) {
    _z_session_queryable_t qle = {0};
    return qle;
}

bool _z_session_queryable_eq(const _z_session_queryable_t *one, const _z_session_queryable_t *two);
void _z_session_queryable_clear(_z_session_queryable_t *res);

_Z_REFCOUNT_DEFINE(_z_session_queryable, _z_session_queryable)
_Z_ELEM_DEFINE(_z_session_queryable, _z_session_queryable_t, _z_noop_size, _z_session_queryable_clear, _z_noop_copy,
               _z_noop_move, _z_session_queryable_eq, _z_noop_cmp, _z_noop_hash)
_Z_ELEM_DEFINE(_z_session_queryable_rc, _z_session_queryable_rc_t, _z_session_queryable_rc_size,
               _z_session_queryable_rc_drop, _z_session_queryable_rc_copy, _z_noop_move, _z_noop_eq, _z_noop_cmp,
               _z_noop_hash)
_Z_SLIST_DEFINE(_z_session_queryable_rc, _z_session_queryable_rc_t, true)

// Forward declaration to avoid cyclical includes
typedef struct _z_reply_t _z_reply_t;
typedef _z_slist_t _z_pending_reply_slist_t;
typedef struct _z_reply_t _z_reply_t;

/**
 * The callback signature of the functions handling query replies.
 */
typedef void (*_z_closure_reply_callback_t)(_z_reply_t *reply, void *arg);

typedef struct _z_pending_query_t _z_pending_query_t;
#ifdef Z_FEATURE_UNSTABLE_API
typedef struct {
    _z_cancellation_token_rc_t _cancellation_token;
    size_t _handler_id;
    _z_sync_group_notifier_t _notifier;
} _z_pending_query_cancellation_data_t;

static inline _z_pending_query_cancellation_data_t _z_pending_query_cancellation_data_null(void) {
    _z_pending_query_cancellation_data_t d = {0};
    return d;
}
static inline void _z_pending_query_cancellation_data_clear(_z_pending_query_cancellation_data_t *data) {
    if (!_Z_RC_IS_NULL(&data->_cancellation_token)) {
        _z_cancellation_token_remove_on_cancel_handler(_Z_RC_IN_VAL(&data->_cancellation_token), data->_handler_id);
        _z_cancellation_token_rc_drop(&data->_cancellation_token);
        _z_sync_group_notifier_drop(&data->_notifier);
    }
}

z_result_t _z_pending_query_register_cancellation(_z_pending_query_t *pq,
                                                  const _z_cancellation_token_rc_t *opt_cancellation_token,
                                                  const _z_session_rc_t *session);

void _z_pending_query_cancellation_data_clear(_z_pending_query_cancellation_data_t *data);
#endif
struct _z_pending_query_t {
    _z_keyexpr_t _key;
    _z_optional_id_t _querier_id;
    _z_zint_t _id;
    _z_closure_reply_callback_t _callback;
    _z_drop_handler_t _dropper;
    z_locality_t _allowed_destination;
    z_clock_t _start_time;
    uint64_t _timeout;
    void *_arg;
    uint8_t _remaining_finals;
    _z_pending_reply_slist_t *_pending_replies;
    z_query_target_t _target;
    z_consolidation_mode_t _consolidation;
    bool _anyke;
#ifdef Z_FEATURE_UNSTABLE_API
    _z_pending_query_cancellation_data_t _cancellation_data;
#endif
};

bool _z_pending_query_eq(const _z_pending_query_t *one, const _z_pending_query_t *two);
void _z_pending_query_clear(_z_pending_query_t *res);

_Z_ELEM_DEFINE(_z_pending_query, _z_pending_query_t, _z_noop_size, _z_pending_query_clear, _z_noop_copy, _z_noop_move,
               _z_pending_query_eq, _z_noop_cmp, _z_noop_hash)
_Z_SLIST_DEFINE(_z_pending_query, _z_pending_query_t, false)

struct __z_hello_handler_wrapper_t;  // Forward declaration to be used in _z_closure_hello_callback_t
/**
 * The callback signature of the functions handling hello messages.
 */
typedef void (*_z_closure_hello_callback_t)(_z_hello_t *hello, struct __z_hello_handler_wrapper_t *arg);

z_result_t _z_session_generate_zid(_z_id_t *bs, uint8_t size);

typedef enum {
    _Z_INTEREST_MSG_TYPE_FINAL = 0,
    _Z_INTEREST_MSG_TYPE_DECL_SUBSCRIBER = 1,
    _Z_INTEREST_MSG_TYPE_DECL_QUERYABLE = 2,
    _Z_INTEREST_MSG_TYPE_DECL_TOKEN = 3,
    _Z_INTEREST_MSG_TYPE_UNDECL_SUBSCRIBER = 4,
    _Z_INTEREST_MSG_TYPE_UNDECL_QUERYABLE = 5,
    _Z_INTEREST_MSG_TYPE_UNDECL_TOKEN = 6,
    _Z_INTEREST_MSG_TYPE_CONNECTION_DROPPED = 7,
} _z_interest_msg_type_t;

typedef struct _z_interest_msg_t {
    uint32_t id;
    uint8_t type;
    const _z_keyexpr_t *key;
    bool is_complete;
} _z_interest_msg_t;

/**
 * The callback signature of the functions handling interest messages.
 */
typedef void (*_z_interest_handler_t)(const _z_interest_msg_t *msg, _z_transport_peer_common_t *peer, void *arg);

typedef struct {
    _z_keyexpr_t _key;
    uint32_t _id;
    _z_interest_handler_t _callback;
    _z_void_rc_t _arg;
    uint8_t _flags;
} _z_session_interest_t;

bool _z_session_interest_eq(const _z_session_interest_t *one, const _z_session_interest_t *two);
void _z_session_interest_clear(_z_session_interest_t *res);

static inline bool _z_session_interest_is_aggregate(const _z_session_interest_t *intr) {
    return (intr->_flags & _Z_INTEREST_FLAG_AGGREGATE) != 0;
}

_Z_REFCOUNT_DEFINE(_z_session_interest, _z_session_interest)
_Z_ELEM_DEFINE(_z_session_interest, _z_session_interest_t, _z_noop_size, _z_session_interest_clear, _z_noop_copy,
               _z_noop_move, _z_session_interest_eq, _z_noop_cmp, _z_noop_hash)
_Z_ELEM_DEFINE(_z_session_interest_rc, _z_session_interest_rc_t, _z_session_interest_rc_size,
               _z_session_interest_rc_drop, _z_session_interest_rc_copy, _z_noop_move, _z_noop_eq, _z_noop_cmp,
               _z_noop_hash)
_Z_SLIST_DEFINE(_z_session_interest_rc, _z_session_interest_rc_t, true)

typedef enum {
    _Z_DECLARE_TYPE_SUBSCRIBER = 0,
    _Z_DECLARE_TYPE_QUERYABLE = 1,
    _Z_DECLARE_TYPE_TOKEN = 2,
} _z_declare_type_t;

typedef struct {
    _z_keyexpr_t _key;
    _z_transport_peer_common_t *_peer;
    uint32_t _id;
    uint8_t _type;
    bool _complete;
} _z_declare_data_t;

void _z_declare_data_clear(_z_declare_data_t *data);
size_t _z_declare_data_size(_z_declare_data_t *data);
void _z_declare_data_copy(_z_declare_data_t *dst, const _z_declare_data_t *src);
_Z_ELEM_DEFINE(_z_declare_data, _z_declare_data_t, _z_declare_data_size, _z_declare_data_clear, _z_declare_data_copy,
               _z_noop_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_SLIST_DEFINE(_z_declare_data, _z_declare_data_t, true)

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_SESSION_SESSION_H */
