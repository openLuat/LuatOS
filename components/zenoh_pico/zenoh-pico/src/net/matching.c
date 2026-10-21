//
// Copyright (c) 2025 ZettaScale Technology
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

#include "zenoh-pico/net/matching.h"

#include <stddef.h>

#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/net/filtering.h"
#include "zenoh-pico/net/primitives.h"
#include "zenoh-pico/protocol/definitions/interest.h"
#include "zenoh-pico/session/matching.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_MATCHING == 1
z_result_t _z_matching_listener_register(uint32_t *listener_id, _z_session_t *s, const _z_write_filter_ctx_rc_t *ctx,
                                         _z_closure_matching_status_t *callback) {
    *listener_id = _z_get_entity_id(s);
    _z_closure_matching_status_t c;
    c = *callback;
    *callback = (_z_closure_matching_status_t){NULL, NULL, NULL};

    return _z_write_filter_ctx_add_callback(_Z_RC_IN_VAL(ctx), *listener_id, &c);
}

z_result_t _z_matching_listener_declare(_z_matching_listener_t *listener, _z_session_t *s,
                                        const _z_write_filter_ctx_rc_t *ctx, _z_closure_matching_status_t *callback) {
    *listener = _z_matching_listener_null();
    listener->_write_filter_ctx = _z_write_filter_ctx_rc_clone_as_weak(ctx);
    _Z_CLEAN_RETURN_IF_ERR(_z_matching_listener_register(&listener->_id, s, ctx, callback),
                           _z_matching_listener_clear(listener));
    return _Z_RES_OK;
}

z_result_t _z_matching_listener_undeclare(_z_matching_listener_t *listener) {
    _z_write_filter_ctx_rc_t write_filter = _z_write_filter_ctx_weak_upgrade(&listener->_write_filter_ctx);
    if (!_Z_RC_IS_NULL(&write_filter)) {
        _z_write_filter_ctx_remove_callback(_Z_RC_IN_VAL(&write_filter), listener->_id);
        _z_write_filter_ctx_rc_drop(&write_filter);
    }
    return _Z_RES_OK;
}

void _z_matching_listener_clear(_z_matching_listener_t *listener) {
    _z_write_filter_ctx_weak_drop(&listener->_write_filter_ctx);
    *listener = _z_matching_listener_null();
}

void _z_matching_listener_free(_z_matching_listener_t **listener) {
    _z_matching_listener_t *ptr = *listener;

    if (ptr != NULL) {
        _z_matching_listener_clear(ptr);

        z_free(ptr);
        *listener = NULL;
    }
}

#endif
