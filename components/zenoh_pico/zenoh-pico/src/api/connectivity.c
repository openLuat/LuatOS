//
// Copyright (c) 2026 ZettaScale Technology
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

#include <stdbool.h>

#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_CONNECTIVITY == 1

static inline void _z_connectivity_transport_from_event_data(_z_info_transport_t *out,
                                                             const _z_connectivity_peer_event_data_t *peer,
                                                             bool is_multicast) {
    *out = (_z_info_transport_t){0};
    out->_zid = peer->_remote_zid;
    out->_whatami = peer->_remote_whatami;
    out->_is_qos = false;
    out->_is_multicast = is_multicast;
    out->_is_shm = false;
}

static z_result_t _z_connectivity_link_fill(_z_info_link_t *link, const _z_connectivity_peer_event_data_t *peer,
                                            uint16_t mtu, bool is_streamed, bool is_reliable) {
    *link = (_z_info_link_t){0};
    link->_src = _z_string_null();
    link->_dst = _z_string_null();
    link->_zid = peer->_remote_zid;
    link->_mtu = mtu;
    link->_is_streamed = is_streamed;
    link->_is_reliable = is_reliable;
    if (_z_string_check(&peer->_link_src)) {
        _Z_RETURN_IF_ERR(_z_string_copy(&link->_src, &peer->_link_src));
    }
    if (_z_string_check(&peer->_link_dst)) {
        _Z_CLEAN_RETURN_IF_ERR(_z_string_copy(&link->_dst, &peer->_link_dst), _z_string_clear(&link->_src));
    }
    return _Z_RES_OK;
}

static inline void _z_connectivity_link_clear(_z_info_link_t *link) {
    _z_string_clear(&link->_src);
    _z_string_clear(&link->_dst);
    *link = (_z_info_link_t){0};
}

static inline void _z_connectivity_link_event_clear(_z_info_link_event_t *event) {
    _z_connectivity_link_clear(&event->link);
    event->kind = Z_SAMPLE_KIND_DEFAULT;
}

static bool _z_connectivity_dispatch_link_put_for_peer(_z_closure_link_event_t *callback,
                                                       const _z_transport_common_t *transport_common,
                                                       const _z_transport_peer_common_t *peer, bool is_multicast,
                                                       bool has_transport_filter,
                                                       const _z_info_transport_t *transport_filter) {
    _z_connectivity_peer_event_data_t peer_event_data = {0};
    _z_connectivity_peer_event_data_alias_from_common(&peer_event_data, peer);

    _z_info_transport_t info_transport;
    _z_connectivity_transport_from_event_data(&info_transport, &peer_event_data, is_multicast);
    if (has_transport_filter && !_z_info_transport_filter_match(&info_transport, transport_filter)) {
        return true;
    }

    uint16_t mtu = 0;
    bool is_streamed = false;
    bool is_reliable = false;
    _z_transport_link_properties_from_transport(transport_common, &mtu, &is_streamed, &is_reliable);

    _z_info_link_event_t event = {0};
    event.kind = Z_SAMPLE_KIND_PUT;
    if (_z_connectivity_link_fill(&event.link, &peer_event_data, mtu, is_streamed, is_reliable) != _Z_RES_OK) {
        _z_connectivity_link_event_clear(&event);
        return false;
    }

    callback->call(&event, callback->context);
    _z_connectivity_link_event_clear(&event);
    return true;
}

typedef struct {
    _z_closure_transport_event_t _closure;
    _z_sync_group_notifier_t _session_callback_drop_notifier;
    _z_sync_group_notifier_t _listener_callback_drop_notifier;
} _z_connectivity_transport_cb_state_t;

typedef struct {
    _z_closure_link_event_t _closure;
    _z_sync_group_notifier_t _session_callback_drop_notifier;
    _z_sync_group_notifier_t _listener_callback_drop_notifier;
} _z_connectivity_link_cb_state_t;

static void _z_connectivity_transport_cb_state_clear(_z_connectivity_transport_cb_state_t *state) {
    if (state == NULL) {
        return;
    }
    if (state->_closure.drop != NULL) {
        state->_closure.drop(state->_closure.context);
    }
    state->_closure.call = NULL;
    state->_closure.drop = NULL;
    state->_closure.context = NULL;
    _z_sync_group_notifier_drop(&state->_session_callback_drop_notifier);
    _z_sync_group_notifier_drop(&state->_listener_callback_drop_notifier);
}

static void _z_connectivity_link_cb_state_clear(_z_connectivity_link_cb_state_t *state) {
    if (state == NULL) {
        return;
    }
    if (state->_closure.drop != NULL) {
        state->_closure.drop(state->_closure.context);
    }
    state->_closure.call = NULL;
    state->_closure.drop = NULL;
    state->_closure.context = NULL;
    _z_sync_group_notifier_drop(&state->_session_callback_drop_notifier);
    _z_sync_group_notifier_drop(&state->_listener_callback_drop_notifier);
}

static void _z_connectivity_transport_event_callback_drop(void *callback) {
    _z_connectivity_transport_cb_state_t *state = (_z_connectivity_transport_cb_state_t *)callback;
    _z_connectivity_transport_cb_state_clear(state);
}

static void _z_connectivity_link_event_callback_drop(void *callback) {
    _z_connectivity_link_cb_state_t *state = (_z_connectivity_link_cb_state_t *)callback;
    _z_connectivity_link_cb_state_clear(state);
}

static z_result_t _z_connectivity_take_transport_callback(
    _z_void_rc_t *out, z_moved_closure_transport_event_t *callback,
    const _z_sync_group_t *session_callback_drop_sync_group,
    const _z_sync_group_t *opt_listener_callback_drop_sync_group) {
    *out = _z_void_rc_null();

    _z_closure_transport_event_t closure = callback->_this._val;
    z_internal_closure_transport_event_null(&callback->_this);

    _z_connectivity_transport_cb_state_t *stored =
        (_z_connectivity_transport_cb_state_t *)z_malloc(sizeof(_z_connectivity_transport_cb_state_t));
    if (stored == NULL) {
        if (closure.drop != NULL) {
            closure.drop(closure.context);
        }
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    *stored = (_z_connectivity_transport_cb_state_t){
        ._closure = closure,
        ._session_callback_drop_notifier = _z_sync_group_notifier_null(),
        ._listener_callback_drop_notifier = _z_sync_group_notifier_null(),
    };

    z_result_t ret =
        _z_sync_group_create_notifier(session_callback_drop_sync_group, &stored->_session_callback_drop_notifier);
    if (ret == _Z_RES_OK && opt_listener_callback_drop_sync_group != NULL &&
        _z_sync_group_check(opt_listener_callback_drop_sync_group)) {
        ret = _z_sync_group_create_notifier(opt_listener_callback_drop_sync_group,
                                            &stored->_listener_callback_drop_notifier);
    }
    if (ret != _Z_RES_OK) {
        _z_connectivity_transport_cb_state_clear(stored);
        z_free(stored);
        return ret;
    }

    *out = _z_void_rc_rc_new(stored, _z_connectivity_transport_event_callback_drop);
    if (_Z_RC_IS_NULL(out)) {
        _z_connectivity_transport_cb_state_clear(stored);
        z_free(stored);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    return _Z_RES_OK;
}

static z_result_t _z_connectivity_take_link_callback(_z_void_rc_t *out, z_moved_closure_link_event_t *callback,
                                                     const _z_sync_group_t *session_callback_drop_sync_group,
                                                     const _z_sync_group_t *opt_listener_callback_drop_sync_group) {
    *out = _z_void_rc_null();

    _z_closure_link_event_t closure = callback->_this._val;
    z_internal_closure_link_event_null(&callback->_this);

    _z_connectivity_link_cb_state_t *stored =
        (_z_connectivity_link_cb_state_t *)z_malloc(sizeof(_z_connectivity_link_cb_state_t));
    if (stored == NULL) {
        if (closure.drop != NULL) {
            closure.drop(closure.context);
        }
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    *stored = (_z_connectivity_link_cb_state_t){
        ._closure = closure,
        ._session_callback_drop_notifier = _z_sync_group_notifier_null(),
        ._listener_callback_drop_notifier = _z_sync_group_notifier_null(),
    };

    z_result_t ret =
        _z_sync_group_create_notifier(session_callback_drop_sync_group, &stored->_session_callback_drop_notifier);
    if (ret == _Z_RES_OK && opt_listener_callback_drop_sync_group != NULL &&
        _z_sync_group_check(opt_listener_callback_drop_sync_group)) {
        ret = _z_sync_group_create_notifier(opt_listener_callback_drop_sync_group,
                                            &stored->_listener_callback_drop_notifier);
    }
    if (ret != _Z_RES_OK) {
        _z_connectivity_link_cb_state_clear(stored);
        z_free(stored);
        return ret;
    }

    *out = _z_void_rc_rc_new(stored, _z_connectivity_link_event_callback_drop);
    if (_Z_RC_IS_NULL(out)) {
        _z_connectivity_link_cb_state_clear(stored);
        z_free(stored);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    return _Z_RES_OK;
}

static inline _z_connectivity_transport_cb_state_t *_z_connectivity_transport_listener_state(
    const _z_connectivity_transport_listener_t *listener) {
    return (_z_connectivity_transport_cb_state_t *)listener->_callback._val;
}

static inline _z_connectivity_link_cb_state_t *_z_connectivity_link_listener_state(
    const _z_connectivity_link_listener_t *listener) {
    return (_z_connectivity_link_cb_state_t *)listener->_callback._val;
}

static inline _z_closure_transport_event_t *_z_connectivity_transport_listener_callback(
    const _z_connectivity_transport_listener_t *listener) {
    _z_connectivity_transport_cb_state_t *state = _z_connectivity_transport_listener_state(listener);
    return state != NULL ? &state->_closure : NULL;
}

static inline _z_closure_link_event_t *_z_connectivity_link_listener_callback(
    const _z_connectivity_link_listener_t *listener) {
    _z_connectivity_link_cb_state_t *state = _z_connectivity_link_listener_state(listener);
    return state != NULL ? &state->_closure : NULL;
}

static void _z_connectivity_dispatch_transport_event(_z_session_t *session, _z_info_transport_event_t *event) {
    _z_connectivity_transport_listener_intmap_t snapshot = _z_connectivity_transport_listener_intmap_make();

    _z_session_mutex_lock(session);
    snapshot = _z_connectivity_transport_listener_intmap_clone(&session->_connectivity_transport_event_listeners);
    _z_session_mutex_unlock(session);

    _z_connectivity_transport_listener_intmap_iterator_t it =
        _z_connectivity_transport_listener_intmap_iterator_make(&snapshot);
    while (_z_connectivity_transport_listener_intmap_iterator_next(&it)) {
        _z_connectivity_transport_listener_t *listener = _z_connectivity_transport_listener_intmap_iterator_value(&it);
        _z_closure_transport_event_t *closure = _z_connectivity_transport_listener_callback(listener);
        if (closure != NULL && closure->call != NULL) {
            closure->call(event, closure->context);
        }
    }

    _z_connectivity_transport_listener_intmap_clear(&snapshot);
}

static void _z_connectivity_dispatch_link_event(_z_session_t *session, _z_info_link_event_t *event, bool is_multicast) {
    _z_connectivity_link_listener_intmap_t snapshot = _z_connectivity_link_listener_intmap_make();

    _z_session_mutex_lock(session);
    snapshot = _z_connectivity_link_listener_intmap_clone(&session->_connectivity_link_event_listeners);
    _z_session_mutex_unlock(session);

    _z_connectivity_link_listener_intmap_iterator_t it = _z_connectivity_link_listener_intmap_iterator_make(&snapshot);
    while (_z_connectivity_link_listener_intmap_iterator_next(&it)) {
        _z_connectivity_link_listener_t *listener = _z_connectivity_link_listener_intmap_iterator_value(&it);
        if (listener->_has_transport_filter && (!_z_id_eq(&listener->_transport_zid, &event->link._zid) ||
                                                listener->_transport_is_multicast != is_multicast)) {
            continue;
        }

        _z_closure_link_event_t *closure = _z_connectivity_link_listener_callback(listener);
        if (closure != NULL && closure->call != NULL) {
            closure->call(event, closure->context);
        }
    }

    _z_connectivity_link_listener_intmap_clear(&snapshot);
}

static void _z_connectivity_replay_transport_history(_z_session_t *session,
                                                     _z_connectivity_transport_cb_state_t *callback_state) {
    if (callback_state == NULL || callback_state->_closure.call == NULL) {
        return;
    }
    _z_closure_transport_event_t *callback = &callback_state->_closure;

    _z_transport_t *transport = &session->_tp;
    _z_transport_common_t *transport_common = _z_transport_get_common(transport);
    if (transport_common != NULL) {
        _z_transport_peer_mutex_lock(transport_common);
    }

    switch (transport->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE: {
            _z_transport_peer_unicast_slist_t *curr = transport->_transport._unicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_unicast_slist_next(curr)) {
                _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(curr);
                _z_info_transport_event_t event = {0};
                event.kind = Z_SAMPLE_KIND_PUT;
                _z_info_transport_from_peer(&event.transport, &peer->common, false);
                callback->call(&event, callback->context);
            }
            break;
        }
        case _Z_TRANSPORT_MULTICAST_TYPE:
        case _Z_TRANSPORT_RAWETH_TYPE: {
            _z_transport_peer_multicast_slist_t *curr = transport->_transport._multicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_multicast_slist_next(curr)) {
                _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(curr);
                _z_info_transport_event_t event = {0};
                event.kind = Z_SAMPLE_KIND_PUT;
                _z_info_transport_from_peer(&event.transport, &peer->common, true);
                callback->call(&event, callback->context);
            }
            break;
        }
        default:
            break;
    }

    if (transport_common != NULL) {
        _z_transport_peer_mutex_unlock(transport_common);
    }
}

static void _z_connectivity_replay_link_history(_z_session_t *session, _z_connectivity_link_cb_state_t *callback_state,
                                                bool has_transport_filter,
                                                const _z_info_transport_t *transport_filter) {
    if (callback_state == NULL || callback_state->_closure.call == NULL) {
        return;
    }
    _z_closure_link_event_t *callback = &callback_state->_closure;

    _z_transport_t *transport = &session->_tp;
    _z_transport_common_t *transport_common = _z_transport_get_common(transport);
    if (transport_common != NULL) {
        _z_transport_peer_mutex_lock(transport_common);
    }

    switch (transport->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE: {
            _z_transport_peer_unicast_slist_t *curr = transport->_transport._unicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_unicast_slist_next(curr)) {
                _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(curr);
                if (!_z_connectivity_dispatch_link_put_for_peer(callback, transport_common, &peer->common, false,
                                                                has_transport_filter, transport_filter)) {
                    break;
                }
            }
            break;
        }
        case _Z_TRANSPORT_MULTICAST_TYPE:
        case _Z_TRANSPORT_RAWETH_TYPE: {
            _z_transport_peer_multicast_slist_t *curr = transport->_transport._multicast._peers;
            for (; curr != NULL; curr = _z_transport_peer_multicast_slist_next(curr)) {
                _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(curr);
                if (!_z_connectivity_dispatch_link_put_for_peer(callback, transport_common, &peer->common, true,
                                                                has_transport_filter, transport_filter)) {
                    break;
                }
            }
            break;
        }
        default:
            break;
    }

    if (transport_common != NULL) {
        _z_transport_peer_mutex_unlock(transport_common);
    }
}

bool _z_transport_events_listener_check(const _z_transport_events_listener_t *listener) {
    return !_Z_RC_IS_NULL(&listener->_session);
}

_z_transport_events_listener_t _z_transport_events_listener_null(void) { return (_z_transport_events_listener_t){0}; }

void _z_transport_events_listener_clear(_z_transport_events_listener_t *listener) {
    _z_session_weak_drop(&listener->_session);
    _z_sync_group_drop(&listener->_callback_drop_sync_group);
    *listener = _z_transport_events_listener_null();
}

static z_result_t _z_transport_events_listener_undeclare(_z_transport_events_listener_t *listener) {
    _z_session_rc_t session_rc = _z_session_weak_upgrade(&listener->_session);
    if (!_Z_RC_IS_NULL(&session_rc)) {
        _z_session_t *session = _Z_RC_IN_VAL(&session_rc);
        _z_session_mutex_lock(session);
        _z_connectivity_transport_listener_intmap_remove(&session->_connectivity_transport_event_listeners,
                                                         listener->_id);
        _z_session_mutex_unlock(session);
        _z_session_rc_drop(&session_rc);
    }

    if (_z_sync_group_check(&listener->_callback_drop_sync_group)) {
        return _z_sync_group_wait(&listener->_callback_drop_sync_group);
    }
    return _Z_RES_OK;
}

void _z_transport_events_listener_drop(_z_transport_events_listener_t *listener) {
    _z_transport_events_listener_undeclare(listener);
    _z_transport_events_listener_clear(listener);
}

bool _z_link_events_listener_check(const _z_link_events_listener_t *listener) {
    return !_Z_RC_IS_NULL(&listener->_session);
}

_z_link_events_listener_t _z_link_events_listener_null(void) { return (_z_link_events_listener_t){0}; }

void _z_link_events_listener_clear(_z_link_events_listener_t *listener) {
    _z_session_weak_drop(&listener->_session);
    _z_sync_group_drop(&listener->_callback_drop_sync_group);
    *listener = _z_link_events_listener_null();
}

static z_result_t _z_link_events_listener_undeclare(_z_link_events_listener_t *listener) {
    _z_session_rc_t session_rc = _z_session_weak_upgrade(&listener->_session);
    if (!_Z_RC_IS_NULL(&session_rc)) {
        _z_session_t *session = _Z_RC_IN_VAL(&session_rc);
        _z_session_mutex_lock(session);
        _z_connectivity_link_listener_intmap_remove(&session->_connectivity_link_event_listeners, listener->_id);
        _z_session_mutex_unlock(session);
        _z_session_rc_drop(&session_rc);
    }

    if (_z_sync_group_check(&listener->_callback_drop_sync_group)) {
        return _z_sync_group_wait(&listener->_callback_drop_sync_group);
    }
    return _Z_RES_OK;
}

void _z_link_events_listener_drop(_z_link_events_listener_t *listener) {
    _z_link_events_listener_undeclare(listener);
    _z_link_events_listener_clear(listener);
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_transport_events_listener_t, transport_events_listener,
                                              _z_transport_events_listener_check, _z_transport_events_listener_null,
                                              _z_transport_events_listener_drop)

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL(_z_link_events_listener_t, link_events_listener,
                                              _z_link_events_listener_check, _z_link_events_listener_null,
                                              _z_link_events_listener_drop)

void z_transport_events_listener_options_default(z_transport_events_listener_options_t *options) {
    options->history = false;
}

void z_link_events_listener_options_default(z_link_events_listener_options_t *options) {
    options->history = false;
    options->transport = NULL;
}

z_result_t z_declare_transport_events_listener(const z_loaned_session_t *zs,
                                               z_owned_transport_events_listener_t *listener,
                                               z_moved_closure_transport_event_t *callback,
                                               const z_transport_events_listener_options_t *options) {
    listener->_val = _z_transport_events_listener_null();

    if (zs == NULL || _Z_RC_IS_NULL(zs)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }

    z_transport_events_listener_options_t opt;
    z_transport_events_listener_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    _z_sync_group_t callback_drop_sync_group = _z_sync_group_null();
    _Z_RETURN_IF_ERR(_z_sync_group_create(&callback_drop_sync_group));

    _z_void_rc_t callback_rc;
    _Z_CLEAN_RETURN_IF_ERR(
        _z_connectivity_take_transport_callback(&callback_rc, callback, &_Z_RC_IN_VAL(zs)->_callback_drop_sync_group,
                                                &callback_drop_sync_group),
        _z_sync_group_drop(&callback_drop_sync_group));

    _z_connectivity_transport_listener_t *listener_state =
        (_z_connectivity_transport_listener_t *)z_malloc(sizeof(_z_connectivity_transport_listener_t));
    if (listener_state == NULL) {
        _z_void_rc_drop(&callback_rc);
        _z_sync_group_drop(&callback_drop_sync_group);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    *listener_state = (_z_connectivity_transport_listener_t){._callback = callback_rc};

    _z_session_t *session = _Z_RC_IN_VAL(zs);
    _z_transport_common_t *locked_transport_common = NULL;
    z_result_t ret = _Z_RES_OK;
    size_t id = 0;
    bool listener_registered = false;
    if (opt.history) {
        locked_transport_common = _z_transport_get_common(&session->_tp);
        if (locked_transport_common != NULL) {
            _z_transport_peer_mutex_lock(locked_transport_common);
        }
    }

    if (opt.history) {
        _z_void_rc_t callback_snapshot = _z_void_rc_clone(&callback_rc);
        if (_Z_RC_IS_NULL(&callback_snapshot)) {
            ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            goto exit;
        }

        _z_connectivity_transport_cb_state_t *callback_state =
            (_z_connectivity_transport_cb_state_t *)callback_snapshot._val;
        _z_connectivity_replay_transport_history(session, callback_state);
        _z_void_rc_drop(&callback_snapshot);
    }

    ret = _z_session_mutex_lock_if_open(session);
    if (ret != _Z_RES_OK) {
        goto exit;
    }
    id = session->_connectivity_next_listener_id++;
    if (_z_connectivity_transport_listener_intmap_insert(&session->_connectivity_transport_event_listeners, id,
                                                         listener_state) == NULL) {
        _z_session_mutex_unlock(session);
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto exit;
    }
    listener_registered = true;
    _z_session_mutex_unlock(session);

    _z_session_weak_t weak = _z_session_rc_clone_as_weak(zs);
    if (_Z_RC_IS_NULL(&weak)) {
        _z_session_mutex_lock(session);
        _z_connectivity_transport_listener_intmap_remove(&session->_connectivity_transport_event_listeners, id);
        _z_session_mutex_unlock(session);
        listener_registered = false;
        listener_state = NULL;
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto exit;
    }

    listener->_val = (_z_transport_events_listener_t){
        ._id = id,
        ._session = weak,
        ._callback_drop_sync_group = callback_drop_sync_group,
    };
    callback_drop_sync_group = _z_sync_group_null();

exit:
    if (!listener_registered && listener_state != NULL) {
        _z_connectivity_transport_listener_clear(listener_state);
        z_free(listener_state);
    }
    if (locked_transport_common != NULL) {
        _z_transport_peer_mutex_unlock(locked_transport_common);
    }
    _z_sync_group_drop(&callback_drop_sync_group);
    return ret;
}

z_result_t z_declare_background_transport_events_listener(const z_loaned_session_t *zs,
                                                          z_moved_closure_transport_event_t *callback,
                                                          const z_transport_events_listener_options_t *options) {
    z_owned_transport_events_listener_t listener;
    _Z_RETURN_IF_ERR(z_declare_transport_events_listener(zs, &listener, callback, options));
    _z_transport_events_listener_clear(&listener._val);
    return _Z_RES_OK;
}

z_result_t z_undeclare_transport_events_listener(z_moved_transport_events_listener_t *listener) {
    z_result_t ret = _z_transport_events_listener_undeclare(&listener->_this._val);
    _z_transport_events_listener_clear(&listener->_this._val);
    return ret;
}

z_result_t z_declare_link_events_listener(const z_loaned_session_t *zs, z_owned_link_events_listener_t *listener,
                                          z_moved_closure_link_event_t *callback,
                                          z_link_events_listener_options_t *options) {
    listener->_val = _z_link_events_listener_null();

    if (zs == NULL || _Z_RC_IS_NULL(zs)) {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }

    z_link_events_listener_options_t opt;
    z_link_events_listener_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    _z_sync_group_t callback_drop_sync_group = _z_sync_group_null();
    _Z_RETURN_IF_ERR(_z_sync_group_create(&callback_drop_sync_group));

    _z_void_rc_t callback_rc;
    _Z_CLEAN_RETURN_IF_ERR(
        _z_connectivity_take_link_callback(&callback_rc, callback, &_Z_RC_IN_VAL(zs)->_callback_drop_sync_group,
                                           &callback_drop_sync_group),
        _z_sync_group_drop(&callback_drop_sync_group));

    bool has_transport_filter = false;
    _z_id_t transport_filter_zid = {0};
    bool transport_filter_is_multicast = false;
    z_result_t ret = _Z_RES_OK;

    if (opt.transport != NULL) {
        if (!z_internal_transport_check(&opt.transport->_this)) {
            ret = _Z_ERR_INVALID;
        } else {
            const z_loaned_transport_t *transport = z_transport_loan(&opt.transport->_this);
            has_transport_filter = true;
            transport_filter_zid = transport->_zid;
            transport_filter_is_multicast = transport->_is_multicast;
        }
    }

    z_transport_drop(opt.transport);

    if (ret != _Z_RES_OK) {
        _z_void_rc_drop(&callback_rc);
        _z_sync_group_drop(&callback_drop_sync_group);
        return ret;
    }

    _z_connectivity_link_listener_t *listener_state =
        (_z_connectivity_link_listener_t *)z_malloc(sizeof(_z_connectivity_link_listener_t));
    if (listener_state == NULL) {
        _z_void_rc_drop(&callback_rc);
        _z_sync_group_drop(&callback_drop_sync_group);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }

    *listener_state = (_z_connectivity_link_listener_t){
        ._callback = callback_rc,
        ._has_transport_filter = has_transport_filter,
        ._transport_zid = transport_filter_zid,
        ._transport_is_multicast = transport_filter_is_multicast,
    };

    _z_session_t *session = _Z_RC_IN_VAL(zs);
    _z_transport_common_t *locked_transport_common = NULL;
    size_t id = 0;
    bool listener_registered = false;
    if (opt.history) {
        locked_transport_common = _z_transport_get_common(&session->_tp);
        if (locked_transport_common != NULL) {
            _z_transport_peer_mutex_lock(locked_transport_common);
        }
    }

    if (opt.history) {
        _z_void_rc_t callback_snapshot = _z_void_rc_clone(&callback_rc);
        if (_Z_RC_IS_NULL(&callback_snapshot)) {
            ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            goto exit;
        }

        _z_info_transport_t transport_filter = {0};
        transport_filter._zid = transport_filter_zid;
        transport_filter._is_multicast = transport_filter_is_multicast;
        _z_connectivity_link_cb_state_t *callback_state = (_z_connectivity_link_cb_state_t *)callback_snapshot._val;
        _z_connectivity_replay_link_history(session, callback_state, has_transport_filter, &transport_filter);
        _z_void_rc_drop(&callback_snapshot);
    }

    ret = _z_session_mutex_lock_if_open(session);
    if (ret != _Z_RES_OK) {
        goto exit;
    }
    id = session->_connectivity_next_listener_id++;
    if (_z_connectivity_link_listener_intmap_insert(&session->_connectivity_link_event_listeners, id, listener_state) ==
        NULL) {
        _z_session_mutex_unlock(session);
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto exit;
    }
    listener_registered = true;
    _z_session_mutex_unlock(session);

    _z_session_weak_t weak = _z_session_rc_clone_as_weak(zs);
    if (_Z_RC_IS_NULL(&weak)) {
        _z_session_mutex_lock(session);
        _z_connectivity_link_listener_intmap_remove(&session->_connectivity_link_event_listeners, id);
        _z_session_mutex_unlock(session);
        listener_registered = false;
        listener_state = NULL;
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto exit;
    }

    listener->_val = (_z_link_events_listener_t){
        ._id = id,
        ._session = weak,
        ._callback_drop_sync_group = callback_drop_sync_group,
    };
    callback_drop_sync_group = _z_sync_group_null();

exit:
    if (!listener_registered && listener_state != NULL) {
        _z_connectivity_link_listener_clear(listener_state);
        z_free(listener_state);
    }
    if (locked_transport_common != NULL) {
        _z_transport_peer_mutex_unlock(locked_transport_common);
    }
    _z_sync_group_drop(&callback_drop_sync_group);
    return ret;
}

z_result_t z_declare_background_link_events_listener(const z_loaned_session_t *zs,
                                                     z_moved_closure_link_event_t *callback,
                                                     z_link_events_listener_options_t *options) {
    z_owned_link_events_listener_t listener;
    _Z_RETURN_IF_ERR(z_declare_link_events_listener(zs, &listener, callback, options));
    _z_link_events_listener_clear(&listener._val);
    return _Z_RES_OK;
}

z_result_t z_undeclare_link_events_listener(z_moved_link_events_listener_t *listener) {
    z_result_t ret = _z_link_events_listener_undeclare(&listener->_this._val);
    _z_link_events_listener_clear(&listener->_this._val);
    return ret;
}

void _z_connectivity_peer_connected(_z_session_t *session, const _z_connectivity_peer_event_data_t *peer,
                                    bool is_multicast, uint16_t mtu, bool is_streamed, bool is_reliable) {
    if (session == NULL || peer == NULL) {
        return;
    }

    _z_info_transport_event_t transport_event = {0};
    transport_event.kind = Z_SAMPLE_KIND_PUT;
    _z_connectivity_transport_from_event_data(&transport_event.transport, peer, is_multicast);
    _z_connectivity_dispatch_transport_event(session, &transport_event);

    _z_info_link_event_t link_event = {0};
    link_event.kind = Z_SAMPLE_KIND_PUT;
    if (_z_connectivity_link_fill(&link_event.link, peer, mtu, is_streamed, is_reliable) == _Z_RES_OK) {
        _z_connectivity_dispatch_link_event(session, &link_event, is_multicast);
    }
    _z_connectivity_link_event_clear(&link_event);
}

void _z_connectivity_peer_disconnected(_z_session_t *session, const _z_connectivity_peer_event_data_t *peer,
                                       bool is_multicast, uint16_t mtu, bool is_streamed, bool is_reliable) {
    if (session == NULL || peer == NULL) {
        return;
    }

    _z_info_link_event_t link_event = {0};
    link_event.kind = Z_SAMPLE_KIND_DELETE;
    if (_z_connectivity_link_fill(&link_event.link, peer, mtu, is_streamed, is_reliable) == _Z_RES_OK) {
        _z_connectivity_dispatch_link_event(session, &link_event, is_multicast);
    }
    _z_connectivity_link_event_clear(&link_event);

    _z_info_transport_event_t transport_event = {0};
    transport_event.kind = Z_SAMPLE_KIND_DELETE;
    _z_connectivity_transport_from_event_data(&transport_event.transport, peer, is_multicast);
    _z_connectivity_dispatch_transport_event(session, &transport_event);
}

void _z_connectivity_peer_disconnected_from_transport(_z_session_t *session, const _z_transport_common_t *transport,
                                                      const _z_connectivity_peer_event_data_t *peer,
                                                      bool is_multicast) {
    if (peer == NULL) {
        return;
    }

    uint16_t mtu = 0;
    bool is_streamed = false;
    bool is_reliable = false;
    _z_transport_link_properties_from_transport(transport, &mtu, &is_streamed, &is_reliable);

    _z_connectivity_peer_disconnected(session, peer, is_multicast, mtu, is_streamed, is_reliable);
}

#endif
