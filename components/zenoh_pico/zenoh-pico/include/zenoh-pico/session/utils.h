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

#ifndef INCLUDE_ZENOH_PICO_SESSION_UTILS_H
#define INCLUDE_ZENOH_PICO_SESSION_UTILS_H

#include <stdbool.h>
#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

/*------------------ Session ------------------*/
_z_hello_slist_t *_z_scout_inner(const z_what_t what, _z_id_t id, _z_string_t *locator, const uint32_t timeout,
                                 const bool exit_on_first);

z_result_t _z_session_init(_z_session_t *zn, const _z_id_t *zid);
void _z_session_clear(_z_session_t *zn);
z_result_t _z_session_close(_z_session_t *zn);

z_result_t _z_handle_network_message(_z_transport_common_t *transport, _z_zenoh_message_t *z_msg,
                                     _z_transport_peer_common_t *peer);

#if Z_FEATURE_MULTI_THREAD == 1
static inline z_result_t _z_session_mutex_lock(_z_session_t *zn) { return _z_mutex_lock(&zn->_mutex_inner); }
static inline z_result_t _z_session_mutex_lock_if_open(_z_session_t *zn) {
    _Z_RETURN_IF_ERR(_z_mutex_lock(&zn->_mutex_inner));
    if (_z_session_is_closed(zn)) {
        _z_mutex_unlock(&zn->_mutex_inner);
        return _Z_ERR_SESSION_CLOSED;
    }
    return _Z_RES_OK;
}
static inline void _z_session_mutex_unlock(_z_session_t *zn) { (void)_z_mutex_unlock(&zn->_mutex_inner); }
static inline void _z_session_transport_mutex_lock(_z_session_t *zn) { (void)_z_mutex_rec_lock(&zn->_mutex_transport); }
static inline void _z_session_transport_mutex_unlock(_z_session_t *zn) {
    (void)_z_mutex_rec_unlock(&zn->_mutex_transport);
}
#if Z_FEATURE_ADMIN_SPACE == 1
static inline void _z_session_admin_space_mutex_lock(_z_session_t *zn) { (void)_z_mutex_lock(&zn->_mutex_admin_space); }
static inline void _z_session_admin_space_mutex_unlock(_z_session_t *zn) {
    (void)_z_mutex_unlock(&zn->_mutex_admin_space);
}
#else
static inline void _z_session_admin_space_mutex_lock(_z_session_t *zn) { _ZP_UNUSED(zn); }
static inline void _z_session_admin_space_mutex_unlock(_z_session_t *zn) { _ZP_UNUSED(zn); }
#endif
#else
static inline z_result_t _z_session_mutex_lock(_z_session_t *zn) {
    _ZP_UNUSED(zn);
    return _Z_RES_OK;
}
static inline z_result_t _z_session_mutex_lock_if_open(_z_session_t *zn) {
    return _z_session_is_closed(zn) ? _Z_ERR_SESSION_CLOSED : _Z_RES_OK;
}
static inline void _z_session_mutex_unlock(_z_session_t *zn) { _ZP_UNUSED(zn); }
static inline void _z_session_transport_mutex_lock(_z_session_t *zn) { _ZP_UNUSED(zn); }
static inline void _z_session_transport_mutex_unlock(_z_session_t *zn) { _ZP_UNUSED(zn); }
static inline void _z_session_admin_space_mutex_lock(_z_session_t *zn) { _ZP_UNUSED(zn); }
static inline void _z_session_admin_space_mutex_unlock(_z_session_t *zn) { _ZP_UNUSED(zn); }
#endif

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_SESSION_UTILS_H */
