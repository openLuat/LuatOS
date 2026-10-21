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

#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/net/liveliness.h"
#include "zenoh-pico/net/primitives.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_LIVELINESS == 1

/**************** Liveliness Token ****************/

bool _z_liveliness_token_check(const _z_liveliness_token_t *token) { return !_Z_RC_IS_NULL(&token->_zn); }

_z_liveliness_token_t _z_liveliness_token_null(void) {
    _z_liveliness_token_t s = {0};
    return s;
}

z_result_t _z_liveliness_token_clear(_z_liveliness_token_t *token) {
    z_result_t ret = _Z_RES_OK;
    if (_Z_RC_IS_NULL(&token->_zn)) {
        return ret;
    }
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&token->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        ret = _z_undeclare_liveliness_token(token);
        _z_session_rc_drop(&sess_rc);
    }
    _z_session_weak_drop(&token->_zn);
    *token = _z_liveliness_token_null();

    return ret;
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_liveliness_token_t, liveliness_token, _z_liveliness_token_check,
                                              _z_liveliness_token_null, _z_liveliness_token_clear)

z_result_t z_liveliness_token_options_default(z_liveliness_token_options_t *options) {
    options->__dummy = 0;
    return _Z_RES_OK;
}

z_result_t z_liveliness_declare_token(const z_loaned_session_t *zs, z_owned_liveliness_token_t *token,
                                      const z_loaned_keyexpr_t *keyexpr, const z_liveliness_token_options_t *options) {
    (void)options;
    return _z_declare_liveliness_token(zs, &token->_val, keyexpr);
}

z_result_t z_liveliness_undeclare_token(z_moved_liveliness_token_t *token) {
    return _z_liveliness_token_clear(&token->_this._val);
}

/**************** Liveliness Subscriber ****************/

#if Z_FEATURE_SUBSCRIPTION == 1
z_result_t z_liveliness_subscriber_options_default(z_liveliness_subscriber_options_t *options) {
    options->history = false;
    return _Z_RES_OK;
}

z_result_t z_liveliness_declare_subscriber(const z_loaned_session_t *zs, z_owned_subscriber_t *sub,
                                           const z_loaned_keyexpr_t *keyexpr, z_moved_closure_sample_t *callback,
                                           z_liveliness_subscriber_options_t *options) {
    _z_closure_sample_t closure = callback->_this._val;
    z_internal_closure_sample_null(&callback->_this);

    z_liveliness_subscriber_options_t opt;
    if (options == NULL) {
        z_liveliness_subscriber_options_default(&opt);
    } else {
        opt = *options;
    }

    if (sub != NULL) {
        sub->_val = _z_subscriber_null();
        return _z_declare_liveliness_subscriber(&sub->_val, zs, keyexpr, closure.call, closure.drop, opt.history,
                                                closure.context);
    } else {
        uint32_t _sub_id;
        return _z_register_liveliness_subscriber(&_sub_id, zs, keyexpr, closure.call, closure.drop, opt.history,
                                                 closure.context, NULL);
    }
}

z_result_t z_liveliness_declare_background_subscriber(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                                      z_moved_closure_sample_t *callback,
                                                      z_liveliness_subscriber_options_t *options) {
    return z_liveliness_declare_subscriber(zs, NULL, keyexpr, callback, options);
}
#endif  // Z_FEATURE_SUBSCRIPTION == 1

/**************** Liveliness Query ****************/

#if Z_FEATURE_QUERY == 1
z_result_t z_liveliness_get_options_default(z_liveliness_get_options_t *options) {
    options->timeout_ms = 0;
#ifdef Z_FEATURE_UNSTABLE_API
    options->cancellation_token = NULL;
#endif
    return _Z_RES_OK;
}

z_result_t z_liveliness_get(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                            z_moved_closure_reply_t *callback, z_liveliness_get_options_t *options) {
    z_result_t ret = _Z_RES_OK;

    void *ctx = callback->_this._val.context;
    callback->_this._val.context = NULL;

    z_liveliness_get_options_t opt;
    if (options == NULL) {
        z_liveliness_get_options_default(&opt);
    } else {
        opt = *options;
    }
    if (opt.timeout_ms == 0) {
        opt.timeout_ms = Z_GET_TIMEOUT_DEFAULT;
    }

    _z_cancellation_token_rc_t *cancellation_token = NULL;
#ifdef Z_FEATURE_UNSTABLE_API
    cancellation_token = opt.cancellation_token == NULL ? NULL : &opt.cancellation_token->_this._rc;
#else

#endif
    ret = _z_liveliness_query(zs, keyexpr, callback->_this._val.call, callback->_this._val.drop, ctx, opt.timeout_ms,
                              cancellation_token);

#ifdef Z_FEATURE_UNSTABLE_API
    z_cancellation_token_drop(opt.cancellation_token);
#endif
    z_internal_closure_reply_null(
        &callback->_this);  // call and drop passed to _z_liveliness_query, so we nullify the closure here
    return ret;
}
#endif  // Z_FEATURE_QUERY == 1

#endif  // Z_FEATURE_LIVELINESS == 1
