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

#include "zenoh-pico/transport/common/lease.h"

#include <stddef.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/session/interest.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/transport/multicast/lease.h"
#include "zenoh-pico/transport/multicast/transport.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_MULTICAST_TRANSPORT == 1 || Z_FEATURE_RAWETH_TRANSPORT == 1

z_result_t _zp_multicast_send_join(_z_transport_multicast_t *ztm) {
    _z_conduit_sn_list_t next_sn;
    next_sn._is_qos = false;
    next_sn._val._plain._best_effort = ztm->_common._sn_tx_best_effort;
    next_sn._val._plain._reliable = ztm->_common._sn_tx_reliable;

    _z_id_t zid = _z_transport_common_get_session(&ztm->_common)->_local_zid;
    _z_transport_message_t jsm = _z_t_msg_make_join(Z_WHATAMI_PEER, Z_TRANSPORT_LEASE, zid, next_sn);

    return ztm->_send_f(&ztm->_common, &jsm);
}

z_result_t _zp_multicast_send_keep_alive(_z_transport_multicast_t *ztm) {
    _z_transport_message_t t_msg = _z_t_msg_make_keep_alive();
    return ztm->_send_f(&ztm->_common, &t_msg);
}

_z_fut_fn_result_t _zp_multicast_failed_result(_z_transport_multicast_t *ztm, _z_executor_t *executor) {
    _z_session_t *session = _z_transport_common_get_session(&ztm->_common);

#if Z_FEATURE_LIVELINESS == 1 && Z_FEATURE_SUBSCRIPTION == 1
    _z_liveliness_subscription_undeclare_all(session);
#endif
    _z_session_transport_mutex_lock(session);
#if Z_FEATURE_AUTO_RECONNECT == 1
    // Store weak session, to reuse for reconnection
    _z_session_weak_t zs = _z_session_weak_clone(&ztm->_common._session);
#endif
    _z_transport_clear(&session->_tp);
    _z_session_transport_mutex_unlock(session);

#if Z_FEATURE_AUTO_RECONNECT == 1
    // Store weak session, to reuse for reconnection
    ztm->_common._state = _Z_TRANSPORT_STATE_RECONNECTING;
    ztm->_common._session = zs;
    _z_fut_t f = _z_fut_null();
    f._fut_arg = &ztm->_common;
    f._fut_fn = _z_client_reopen_task_fn;
    f._destroy_fn = _z_client_reopen_task_drop;
    if (_z_fut_handle_is_null(_z_executor_spawn(executor, &f))) {
        _Z_ERROR("Failed to spawn client reopen task after transport failure.");
        ztm->_common._state = _Z_TRANSPORT_STATE_CLOSED;
        _z_session_weak_drop(&ztm->_common._session);
        return _z_fut_fn_result_ready();
    } else {
        return _z_fut_fn_result_suspend();
    }
#else
    _ZP_UNUSED(executor);
    return _z_fut_fn_result_ready();
#endif
}

static _z_zint_t _z_get_minimum_lease(_z_transport_peer_multicast_slist_t *peers, _z_zint_t local_lease) {
    _z_zint_t ret = local_lease;

    _z_transport_peer_multicast_slist_t *it = peers;
    while (it != NULL) {
        _z_transport_peer_multicast_t *val = _z_transport_peer_multicast_slist_value(it);
        _z_zint_t lease = val->_lease;
        if (lease < ret) {
            ret = lease;
        }

        it = _z_transport_peer_multicast_slist_next(it);
    }

    return ret;
}

static bool _zp_multicast_peer_is_expired(const _z_transport_peer_multicast_t *target,
                                          const _z_transport_peer_multicast_t *peer) {
    _ZP_UNUSED(target);
    return !peer->common._received;
}

static void _zp_multicast_report_disconnected_events(_z_transport_multicast_t *ztm,
                                                     _z_transport_peer_multicast_slist_t **dropped_peers) {
    if (dropped_peers == NULL || *dropped_peers == NULL) {
        return;
    }

#if Z_FEATURE_CONNECTIVITY == 1
    uint16_t mtu = 0;
    bool is_streamed = false;
    bool is_reliable = false;
    _z_transport_get_link_properties(&ztm->_common, &mtu, &is_streamed, &is_reliable);
#endif

    _z_session_t *s = _z_transport_common_get_session(&ztm->_common);
    _z_transport_peer_multicast_slist_t *it = *dropped_peers;
    while (it != NULL) {
        _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(it);
        _Z_INFO("Deleting peer because it has expired after %zums", peer->_lease);
        _z_interest_peer_disconnected(s, &peer->common);
#if Z_FEATURE_CONNECTIVITY == 1
        _z_connectivity_peer_event_data_t disconnected_peer = {0};
        _z_connectivity_peer_event_data_alias_from_common(&disconnected_peer, &peer->common);
        _z_connectivity_peer_disconnected(s, &disconnected_peer, true, mtu, is_streamed, is_reliable);
#endif
        it = _z_transport_peer_multicast_slist_next(it);
    }
    _z_transport_peer_multicast_slist_free(dropped_peers);
}

_z_fut_fn_result_t _zp_multicast_lease_task_fn(void *ztm_arg, _z_executor_t *executor) {
    _ZP_UNUSED(executor);
    _z_transport_multicast_t *ztm = (_z_transport_multicast_t *)ztm_arg;

    if (ztm->_common._state == _Z_TRANSPORT_STATE_CLOSED) {
        return _z_fut_fn_result_ready();
    } else if (ztm->_common._state == _Z_TRANSPORT_STATE_RECONNECTING) {
        return _z_fut_fn_result_suspend();
    }

    _z_transport_peer_multicast_slist_t *dropped_peers = _z_transport_peer_multicast_slist_new();
    _z_transport_peer_mutex_lock(&ztm->_common);
    ztm->_peers = _z_transport_peer_multicast_slist_extract_all_filter(ztm->_peers, &dropped_peers,
                                                                       _zp_multicast_peer_is_expired, NULL);
    _z_transport_peer_multicast_slist_t *curr_list = ztm->_peers;
    while (curr_list != NULL) {
        _z_transport_peer_multicast_t *curr_peer = _z_transport_peer_multicast_slist_value(curr_list);
        curr_peer->common._received = false;
        curr_list = _z_transport_peer_multicast_slist_next(curr_list);
    }
    unsigned long min_lease = (unsigned long)_z_get_minimum_lease(ztm->_peers, ztm->_common._lease);
    _z_transport_peer_mutex_unlock(&ztm->_common);
    _zp_multicast_report_disconnected_events(ztm, &dropped_peers);
    return _z_fut_fn_result_wake_up_after(min_lease);
}

_z_fut_fn_result_t _zp_multicast_keep_alive_task_fn(void *ztm_arg, _z_executor_t *executor) {
    _z_transport_multicast_t *ztm = (_z_transport_multicast_t *)ztm_arg;

    if (ztm->_common._state == _Z_TRANSPORT_STATE_CLOSED) {
        return _z_fut_fn_result_ready();
    } else if (ztm->_common._state == _Z_TRANSPORT_STATE_RECONNECTING) {
        return _z_fut_fn_result_suspend();
    }

    if (ztm->_common._transmitted == false) {
        if (_zp_multicast_send_keep_alive(ztm) < 0) {
            _Z_INFO("Send keep alive failed.");
            return _zp_multicast_failed_result(ztm, executor);
        }
    }
    ztm->_common._transmitted = false;
    _z_transport_peer_mutex_lock(&ztm->_common);
    unsigned long min_lease = (unsigned long)_z_get_minimum_lease(ztm->_peers, ztm->_common._lease);
    _z_transport_peer_mutex_unlock(&ztm->_common);
    return _z_fut_fn_result_wake_up_after(min_lease / Z_TRANSPORT_LEASE_EXPIRE_FACTOR);
}

_z_fut_fn_result_t _zp_multicast_send_join_task_fn(void *ztm_arg, _z_executor_t *executor) {
    _z_transport_multicast_t *ztm = (_z_transport_multicast_t *)ztm_arg;

    if (ztm->_common._state == _Z_TRANSPORT_STATE_CLOSED) {
        return _z_fut_fn_result_ready();
    } else if (ztm->_common._state == _Z_TRANSPORT_STATE_RECONNECTING) {
        return _z_fut_fn_result_suspend();
    }
    if (_zp_multicast_send_join(ztm) < 0) {
        _Z_INFO("Send join failed.");
        return _zp_multicast_failed_result(ztm, executor);
    } else {
        ztm->_common._transmitted = true;
        return _z_fut_fn_result_wake_up_after(Z_JOIN_INTERVAL);
    }
}
#endif  // Z_FEATURE_MULTICAST_TRANSPORT == 1 || Z_FEATURE_RAWETH_TRANSPORT == 1
