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
//   Błażej Sowa, <blazej@fictionlab.pl>

#include "zenoh-pico/net/session.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/declarations.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/session/interest.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/transport/common/lease.h"
#include "zenoh-pico/transport/common/read.h"
#include "zenoh-pico/transport/common/tx.h"
#include "zenoh-pico/transport/multicast.h"
#include "zenoh-pico/transport/multicast/lease.h"
#include "zenoh-pico/transport/multicast/read.h"
#include "zenoh-pico/transport/raweth/read.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast.h"
#include "zenoh-pico/transport/unicast/lease.h"
#include "zenoh-pico/transport/unicast/read.h"
#include "zenoh-pico/utils/config.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/result.h"
#include "zenoh-pico/utils/uuid.h"

#if Z_FEATURE_SCOUTING == 1
static z_result_t _z_locators_by_scout(const _z_config_t *config, const _z_id_t *zid, _z_string_svec_t *locators) {
    z_result_t ret = _Z_RES_OK;

    char *opt_as_str = _z_config_get(config, Z_CONFIG_SCOUTING_WHAT_KEY);
    if (opt_as_str == NULL) {
        opt_as_str = (char *)Z_CONFIG_SCOUTING_WHAT_DEFAULT;
    }
    z_what_t what = strtol(opt_as_str, NULL, 10);

    opt_as_str = _z_config_get(config, Z_CONFIG_MULTICAST_LOCATOR_KEY);
    if (opt_as_str == NULL) {
        opt_as_str = (char *)Z_CONFIG_MULTICAST_LOCATOR_DEFAULT;
    }
    _z_string_t mcast_locator = _z_string_alias_str(opt_as_str);

    opt_as_str = _z_config_get(config, Z_CONFIG_SCOUTING_TIMEOUT_KEY);
    if (opt_as_str == NULL) {
        opt_as_str = (char *)Z_CONFIG_SCOUTING_TIMEOUT_DEFAULT;
    }
    uint32_t timeout = (uint32_t)strtoul(opt_as_str, NULL, 10);

    // Scout and return upon the first result
    _z_hello_slist_t *hellos = _z_scout_inner(what, *zid, &mcast_locator, timeout, true);
    if (hellos != NULL) {
        _z_hello_t *hello = _z_hello_slist_value(hellos);
        _z_string_svec_copy(locators, &hello->_locators, true);
    }
    _z_hello_slist_free(&hellos);
    return ret;
}
#else
static z_result_t _z_locators_by_scout(const _z_config_t *config, const _z_id_t *zid, _z_string_svec_t *locators) {
    _ZP_UNUSED(config);
    _ZP_UNUSED(zid);
    _ZP_UNUSED(locators);
    _Z_ERROR("Cannot scout as Z_FEATURE_SCOUTING was deactivated");
    _Z_ERROR_RETURN(_Z_ERR_SCOUT_NO_RESULTS);
}
#endif

static z_result_t _z_locators_by_config(_z_config_t *config, _z_string_svec_t *locators, int *peer_op) {
    char *connect = _z_config_get(config, Z_CONFIG_CONNECT_KEY);
    char *listen = _z_config_get(config, Z_CONFIG_LISTEN_KEY);
    if (connect == NULL && listen == NULL) {
        return _Z_RES_OK;
    }
#if Z_FEATURE_UNICAST_PEER == 1
    if (listen != NULL) {
        // Add listen as first endpoint
        _z_string_t s = _z_string_copy_from_str(listen);
        _Z_RETURN_IF_ERR(_z_string_svec_append(locators, &s, true));
        _zp_config_insert(config, Z_CONFIG_MODE_KEY, Z_CONFIG_MODE_PEER);
    } else {
        *peer_op = _Z_PEER_OP_OPEN;
    }
    // Add open endpoints
    return _z_config_get_all(config, locators, Z_CONFIG_CONNECT_KEY);
#else
    uint_fast8_t key = Z_CONFIG_CONNECT_KEY;
    if (listen != NULL) {
        if (connect == NULL) {
            key = Z_CONFIG_LISTEN_KEY;
            _zp_config_insert(config, Z_CONFIG_MODE_KEY, Z_CONFIG_MODE_PEER);
        } else {
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
        }
    } else {
        *peer_op = _Z_PEER_OP_OPEN;
    }
    return _z_config_get_all(config, locators, key);
#endif
}

static z_result_t _z_config_get_mode(const _z_config_t *config, z_whatami_t *mode) {
    z_result_t ret = _Z_RES_OK;
    char *s_mode = _z_config_get(config, Z_CONFIG_MODE_KEY);
    *mode = Z_WHATAMI_CLIENT;  // By default, zenoh-pico will operate as a client
    if (s_mode != NULL) {
        if (_z_str_eq(s_mode, Z_CONFIG_MODE_CLIENT) == true) {
            *mode = Z_WHATAMI_CLIENT;
        } else if (_z_str_eq(s_mode, Z_CONFIG_MODE_PEER) == true) {
            *mode = Z_WHATAMI_PEER;
        } else {
            _Z_ERROR("Trying to configure an invalid mode: %s", s_mode);
            _Z_ERROR_LOG(_Z_ERR_CONFIG_INVALID_MODE);
            ret = _Z_ERR_CONFIG_INVALID_MODE;
        }
    }
    return ret;
}

static z_result_t _z_open_inner(_z_session_rc_t *zs, _z_string_t *locator, const _z_id_t *zid, int peer_op,
                                const _z_config_t *config) {
    z_result_t ret = _Z_RES_OK;
    _z_session_t *zn = _Z_RC_IN_VAL(zs);

    ret = _z_new_transport(&zn->_tp, zid, locator, zn->_mode, peer_op, config, &_Z_RC_IN_VAL(zs)->_runtime);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    _z_transport_get_common(&zn->_tp)->_session = _z_session_rc_clone_as_weak(zs);
    _z_transport_get_common(&zn->_tp)->_state = _Z_TRANSPORT_STATE_OPEN;
#if Z_FEATURE_MULTICAST_DECLARATIONS == 1
    if (zn->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE) {
        ret = _z_interest_pull_resource_from_peers(zn);
    }
#endif
    return ret;
}

z_result_t _z_open(_z_session_rc_t *zn, _z_config_t *config, const _z_id_t *zid) {
    z_result_t ret = _Z_RES_OK;
    _Z_RC_IN_VAL(zn)->_tp._type = _Z_TRANSPORT_NONE;

    int peer_op = _Z_PEER_OP_LISTEN;
    _z_string_svec_t locators = _z_string_svec_null();
    // Try getting locators from config
    _Z_RETURN_IF_ERR(_z_locators_by_config(config, &locators, &peer_op));
    size_t len = _z_string_svec_len(&locators);

    z_whatami_t mode;
    ret = _z_config_get_mode(config, &mode);
    if (ret != _Z_RES_OK) {
        return ret;
    }
    _Z_RC_IN_VAL(zn)->_mode = mode;

    if (len > 0) {
        // Use first locator to open session
        _z_string_t *locator = _z_string_svec_get(&locators, 0);
        ret = _z_open_inner(zn, locator, zid, peer_op, config);
#if Z_FEATURE_UNICAST_PEER == 1
        // Add other locators as peers if applicable
        if ((ret == _Z_RES_OK) && (mode == Z_WHATAMI_PEER)) {
            for (size_t i = 1; i < len; i++) {
                // Add peer
                locator = _z_string_svec_get(&locators, i);
                ret = _z_new_peer(&_Z_RC_IN_VAL(zn)->_tp, &_Z_RC_IN_VAL(zn)->_local_zid, locator, config);
                if (ret != _Z_RES_OK) {
                    break;
                }
            }
        }
#endif
    } else {  // No locators in config, scout
        _Z_RETURN_IF_ERR(_z_locators_by_scout(config, zid, &locators));
        len = _z_string_svec_len(&locators);
        if (len == 0) {
            _Z_ERROR_RETURN(_Z_ERR_SCOUT_NO_RESULTS);
        }
        // We can only open on scout locators
        peer_op = _Z_PEER_OP_OPEN;
        // Loop on locators until we successfully open one
        for (size_t i = 0; i < len; i++) {
            _z_string_t *locator = _z_string_svec_get(&locators, i);
            ret = _z_open_inner(zn, locator, zid, peer_op, config);
            if (ret == _Z_RES_OK) {
                break;
            }
        }
    }
    _z_string_svec_clear(&locators);
    return ret;
}

#if Z_FEATURE_AUTO_RECONNECT == 1
void _z_client_reopen_task_drop(void *ztc_arg) {
    _z_transport_common_t *tc = (_z_transport_common_t *)ztc_arg;
    if (tc->_state == _Z_TRANSPORT_STATE_RECONNECTING) {
        // Drop the weak session reference as the task is being dropped in the middle of reconnection.
        _z_session_weak_drop(&tc->_session);
        tc->_state = _Z_TRANSPORT_STATE_CLOSED;
    }
}

_z_fut_fn_result_t _z_client_reopen_task_fn(void *ztc_arg, _z_executor_t *executor) {
    _z_transport_common_t *tc = (_z_transport_common_t *)ztc_arg;
    _z_transport_tasks_t tasks_handles = tc->_tasks;
    _z_session_rc_t zs = _z_session_weak_upgrade(&tc->_session);  // should not fail
    _z_session_t *s = _Z_RC_IN_VAL(&zs);
    _z_session_weak_drop(&tc->_session);

    if (_z_config_is_empty(&s->_config)) {
        _z_session_rc_drop(&zs);
        return _z_fut_fn_result_ready();
    }
    _z_session_transport_mutex_lock(s);
    z_result_t ret = _z_open(&zs, &s->_config, &s->_local_zid);
    _z_session_transport_mutex_unlock(s);
    if (ret != _Z_RES_OK) {
        if (ret == _Z_ERR_TRANSPORT_OPEN_FAILED || ret == _Z_ERR_SCOUT_NO_RESULTS ||
            ret == _Z_ERR_TRANSPORT_TX_FAILED || ret == _Z_ERR_TRANSPORT_RX_FAILED) {
            _Z_DEBUG("Reopen failed, next try in 1s");
            tc->_session = _z_session_rc_clone_as_weak(&zs);
            tc->_state = _Z_TRANSPORT_STATE_RECONNECTING;
            tc->_tasks = tasks_handles;
            _z_session_rc_drop(&zs);
            return _z_fut_fn_result_wake_up_after(1000);
        } else {
            _Z_ERROR("Reopen failed, will not retry");
            tc->_state = _Z_TRANSPORT_STATE_CLOSED;
            _z_session_rc_drop(&zs);
            return _z_fut_fn_result_ready();
        }
    }

    tc->_tasks = tasks_handles;
    if (!_z_network_message_slist_is_empty(s->_declaration_cache)) {
        _z_network_message_slist_t *iter = s->_declaration_cache;
        while (iter != NULL) {
            _z_network_message_t *n_msg = _z_network_message_slist_value(iter);
            ret = _z_send_n_msg(s, n_msg, Z_RELIABILITY_RELIABLE, Z_CONGESTION_CONTROL_BLOCK, NULL);
            if (ret != _Z_RES_OK) {
                _Z_DEBUG("Send message during reopen failed: %i", ret);
                _z_transport_clear(&s->_tp);
                tc->_session = _z_session_rc_clone_as_weak(&zs);
                tc->_state = _Z_TRANSPORT_STATE_RECONNECTING;
                _z_session_rc_drop(&zs);
                return _z_fut_fn_result_continue();
            }

            iter = _z_network_message_slist_next(iter);
        }
    }
    _z_session_rc_drop(&zs);
    _Z_DEBUG("Reconnected successfully");
    // Resume all sibling tasks that suspended themselves while waiting for reconnection.
    for (size_t i = 0; i < _Z_TRANSPORT_TASK_COUNT; i++) {
        _z_executor_resume_suspended_fut(executor, &tc->_tasks._task_handles[i]);
    }
    return _z_fut_fn_result_ready();
}

void _z_cache_declaration(_z_session_t *zs, const _z_network_message_t *n_msg) {
    if (_z_config_is_empty(&zs->_config)) {
        return;
    }
    zs->_declaration_cache = _z_network_message_slist_push_back(zs->_declaration_cache, n_msg);
}

#define _Z_CACHE_DECLARATION_UNDECLARE_FILTER(tp)                                                                     \
    static bool _z_cache_declaration_undeclare_filter_##tp(const _z_network_message_t *left,                          \
                                                           const _z_network_message_t *right) {                       \
        return left->_tag == _Z_N_DECLARE && right->_tag == _Z_N_DECLARE &&                                           \
               left->_body._declare._decl._body._undecl_##tp._id == right->_body._declare._decl._body._decl_##tp._id; \
    }
_Z_CACHE_DECLARATION_UNDECLARE_FILTER(kexpr)
_Z_CACHE_DECLARATION_UNDECLARE_FILTER(subscriber)
_Z_CACHE_DECLARATION_UNDECLARE_FILTER(queryable)
_Z_CACHE_DECLARATION_UNDECLARE_FILTER(token)

static bool _z_cache_declaration_undeclare_filter_interest(const _z_network_message_t *left,
                                                           const _z_network_message_t *right) {
    return left->_tag == _Z_N_INTEREST && right->_tag == _Z_N_INTEREST &&
           left->_body._interest._interest._id == right->_body._interest._interest._id;
}

void _z_prune_declaration(_z_session_t *zs, const _z_network_message_t *n_msg) {
#ifdef Z_BUILD_DEBUG
    size_t cnt_before = _z_network_message_slist_len(zs->_declaration_cache);
#endif
    switch (n_msg->_tag) {
        case _Z_N_DECLARE: {
            const _z_declaration_t *decl = &n_msg->_body._declare._decl;
            switch (decl->_tag) {
                case _Z_UNDECL_KEXPR:
                    zs->_declaration_cache = _z_network_message_slist_drop_first_filter(
                        zs->_declaration_cache, _z_cache_declaration_undeclare_filter_kexpr, n_msg);
                    break;
                case _Z_UNDECL_SUBSCRIBER:
                    zs->_declaration_cache = _z_network_message_slist_drop_first_filter(
                        zs->_declaration_cache, _z_cache_declaration_undeclare_filter_subscriber, n_msg);
                    break;
                case _Z_UNDECL_QUERYABLE:
                    zs->_declaration_cache = _z_network_message_slist_drop_first_filter(
                        zs->_declaration_cache, _z_cache_declaration_undeclare_filter_queryable, n_msg);
                    break;
                case _Z_UNDECL_TOKEN:
                    zs->_declaration_cache = _z_network_message_slist_drop_first_filter(
                        zs->_declaration_cache, _z_cache_declaration_undeclare_filter_token, n_msg);
                    break;
                default:
                    _Z_ERROR("Invalid decl for _z_prune_declaration: %i", decl->_tag);
            };
            break;
        }
        case _Z_N_INTEREST:
            zs->_declaration_cache = _z_network_message_slist_drop_first_filter(
                zs->_declaration_cache, _z_cache_declaration_undeclare_filter_interest, n_msg);
            break;
        default:
            _Z_ERROR("Invalid net message for _z_prune_declaration: %i", n_msg->_tag);
            return;
    };
#ifdef Z_BUILD_DEBUG
    size_t cnt_after = _z_network_message_slist_len(zs->_declaration_cache);
    assert(cnt_before == cnt_after + 1);
#endif
}
#endif  // Z_FEATURE_AUTO_RECONNECT == 1

bool _z_session_is_closed(const _z_session_t *session) {
    return _z_atomic_bool_load((_z_atomic_bool_t *)&session->_is_closed, _z_memory_order_acquire);
}

bool _z_session_has_router_peer(const _z_session_t *session) {
    if (session->_tp._type == _Z_TRANSPORT_UNICAST_TYPE) {
        _z_transport_peer_unicast_slist_t *peers = session->_tp._transport._unicast._peers;
        while (peers != NULL) {
            _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(peers);
            if (peer->common._remote_whatami == Z_WHATAMI_ROUTER) {
                return true;
            }
            peers = _z_transport_peer_unicast_slist_next(peers);
        }
    } else if (session->_tp._type == _Z_TRANSPORT_MULTICAST_TYPE) {
        _z_transport_peer_multicast_slist_t *peers = session->_tp._transport._multicast._peers;
        while (peers != NULL) {
            _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(peers);
            if (peer->common._remote_whatami == Z_WHATAMI_ROUTER) {
                return true;
            }
            peers = _z_transport_peer_multicast_slist_next(peers);
        }
    }
    return false;
}

_z_session_rc_t _z_session_weak_upgrade_if_open(const _z_session_weak_t *weak) {
    _z_session_rc_t sess_rc = _z_session_weak_upgrade(weak);
    if (!_Z_RC_IS_NULL(&sess_rc) && _z_session_is_closed(_Z_RC_IN_VAL(&sess_rc))) {
        _z_session_rc_drop(&sess_rc);
    }
    return sess_rc;
}

_z_config_t *_z_info(const _z_session_t *zn) {
    _z_config_t *ps = (_z_config_t *)z_malloc(sizeof(_z_config_t));
    if (ps != NULL) {
        _z_config_init(ps);
        _z_string_t s = _z_id_to_string(&zn->_local_zid);
        _zp_config_insert_string(ps, Z_INFO_PID_KEY, &s);
        _z_string_clear(&s);

        switch (zn->_tp._type) {
            case _Z_TRANSPORT_UNICAST_TYPE:
                _zp_unicast_info_session(&zn->_tp, ps, zn->_mode);
                break;
            case _Z_TRANSPORT_MULTICAST_TYPE:
            case _Z_TRANSPORT_RAWETH_TYPE:
                _zp_multicast_info_session(&zn->_tp, ps);
                break;
            default:
                break;
        }
    }

    return ps;
}

z_result_t _zp_read(_z_session_t *zn, bool single_read) { return _z_read(&zn->_tp, single_read); }

z_result_t _zp_send_keep_alive(_z_session_t *zn) { return _z_send_keep_alive(&zn->_tp); }

z_result_t _zp_send_join(_z_session_t *zn) { return _z_send_join(&zn->_tp); }

z_result_t _zp_start_transport_tasks(_z_session_t *zn) {
    switch (zn->_tp._type) {
#if Z_FEATURE_UNICAST_TRANSPORT == 1
        case _Z_TRANSPORT_UNICAST_TYPE: {
            _z_transport_common_t *tc = &zn->_tp._transport._unicast._common;
            // Order must match _Z_TRANSPORT_TASK_* index constants.
            _z_fut_fn_t tasks[_Z_TRANSPORT_TASK_COUNT] = {0};
            tasks[_Z_TRANSPORT_TASK_KEEP_ALIVE] = _zp_unicast_keep_alive_task_fn;
            tasks[_Z_TRANSPORT_TASK_LEASE] = _zp_unicast_lease_task_fn;
            tasks[_Z_TRANSPORT_TASK_READ] = _zp_unicast_read_task_fn;

            for (size_t i = 0; i < _ZP_ARRAY_SIZE(tasks); i++) {
                if (tasks[i] == NULL) continue;
                _z_fut_t f = _z_fut_null();
                f._fut_arg = &zn->_tp._transport._unicast;
                f._fut_fn = tasks[i];
                _z_fut_handle_t h = _z_runtime_spawn(&zn->_runtime, &f);
                if (_z_fut_handle_is_null(h)) {
                    _Z_ERROR_RETURN(_Z_ERR_FAILED_TO_SPAWN_TASK);
                }
#if Z_FEATURE_AUTO_RECONNECT == 1
                tc->_tasks._task_handles[i] = h;
#endif
            }
            break;
        }
#endif
#if Z_FEATURE_MULTICAST_TRANSPORT == 1
        case _Z_TRANSPORT_MULTICAST_TYPE: {
            _z_transport_common_t *tc = &zn->_tp._transport._multicast._common;
            // Order must match _Z_TRANSPORT_TASK_* index constants.
            _z_fut_fn_t tasks[_Z_TRANSPORT_TASK_COUNT] = {0};
            tasks[_Z_TRANSPORT_TASK_KEEP_ALIVE] = _zp_multicast_keep_alive_task_fn;
            tasks[_Z_TRANSPORT_TASK_LEASE] = _zp_multicast_lease_task_fn;
            tasks[_Z_TRANSPORT_TASK_READ] = _zp_multicast_read_task_fn;
            tasks[_Z_TRANSPORT_TASK_SEND_JOIN] = _zp_multicast_send_join_task_fn;

            for (size_t i = 0; i < _ZP_ARRAY_SIZE(tasks); i++) {
                if (tasks[i] == NULL) continue;
                _z_fut_t f = _z_fut_null();
                f._fut_arg = &zn->_tp._transport._multicast;
                f._fut_fn = tasks[i];
                _z_fut_handle_t h = _z_runtime_spawn(&zn->_runtime, &f);
                if (_z_fut_handle_is_null(h)) {
                    _Z_ERROR_RETURN(_Z_ERR_FAILED_TO_SPAWN_TASK);
                }
#if Z_FEATURE_AUTO_RECONNECT == 1
                tc->_tasks._task_handles[i] = h;
#endif
            }
            break;
        }
#endif
#if Z_FEATURE_RAWETH_TRANSPORT == 1
        case _Z_TRANSPORT_RAWETH_TYPE: {
            _z_transport_common_t *tc = &zn->_tp._transport._raweth._common;
            // Order must match _Z_TRANSPORT_TASK_* index constants.
            _z_fut_fn_t tasks[_Z_TRANSPORT_TASK_COUNT] = {0};
            tasks[_Z_TRANSPORT_TASK_KEEP_ALIVE] = _zp_multicast_keep_alive_task_fn;
            tasks[_Z_TRANSPORT_TASK_LEASE] = _zp_multicast_lease_task_fn;
            tasks[_Z_TRANSPORT_TASK_READ] = _zp_raweth_read_task_fn;
            tasks[_Z_TRANSPORT_TASK_SEND_JOIN] = _zp_multicast_send_join_task_fn;

            for (size_t i = 0; i < _ZP_ARRAY_SIZE(tasks); i++) {
                if (tasks[i] == NULL) continue;
                _z_fut_t f = _z_fut_null();
                f._fut_arg = &zn->_tp._transport._raweth;
                f._fut_fn = tasks[i];
                _z_fut_handle_t h = _z_runtime_spawn(&zn->_runtime, &f);
                if (_z_fut_handle_is_null(h)) {
                    _Z_ERROR_RETURN(_Z_ERR_FAILED_TO_SPAWN_TASK);
                }
#if Z_FEATURE_AUTO_RECONNECT == 1
                tc->_tasks._task_handles[i] = h;
#endif
            }
            break;
        }
#endif
        default:
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NOT_AVAILABLE);
            return _Z_ERR_TRANSPORT_NOT_AVAILABLE;
            break;
    }
    return _Z_RES_OK;
}
