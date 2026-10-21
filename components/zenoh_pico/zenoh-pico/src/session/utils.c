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

#include "zenoh-pico/session/utils.h"

#include <stddef.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/session/interest.h"
#include "zenoh-pico/session/liveliness.h"
#include "zenoh-pico/session/matching.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/session/queryable.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/subscription.h"
#include "zenoh-pico/transport/multicast/transport.h"
#include "zenoh-pico/transport/transport.h"
#include "zenoh-pico/transport/unicast/transport.h"
#include "zenoh-pico/utils/config.h"
#include "zenoh-pico/utils/result.h"

/*------------------ clone helpers ------------------*/
void _z_timestamp_copy(_z_timestamp_t *dst, const _z_timestamp_t *src) { *dst = *src; }

_z_timestamp_t _z_timestamp_duplicate(const _z_timestamp_t *tstamp) { return *tstamp; }

void _z_timestamp_move(_z_timestamp_t *dst, _z_timestamp_t *src) {
    *dst = *src;
    _z_timestamp_clear(src);
}

void _z_timestamp_clear(_z_timestamp_t *tstamp) {
    tstamp->valid = false;
    tstamp->time = 0;
}

z_result_t _z_session_generate_zid(_z_id_t *bs, uint8_t size) {
    z_result_t ret = _Z_RES_OK;
    z_random_fill((uint8_t *)bs->id, size);
    return ret;
}

/*------------------ Init/Free/Close session ------------------*/
z_result_t _z_session_init(_z_session_t *zn, const _z_id_t *zid) {
    z_result_t ret = _Z_RES_OK;
    _z_atomic_bool_init(&zn->_is_closed, true);
    _z_runtime_null(&zn->_runtime);
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(_z_mutex_init(&zn->_mutex_inner));
    ret = _z_mutex_rec_init(&zn->_mutex_transport);
    if (ret != _Z_RES_OK) {
        _z_mutex_drop(&zn->_mutex_inner);
        _Z_ERROR_RETURN(ret);
    }
#if Z_FEATURE_ADMIN_SPACE == 1
    ret = _z_mutex_init(&zn->_mutex_admin_space);
    if (ret != _Z_RES_OK) {
        _z_mutex_rec_drop(&zn->_mutex_transport);
        _z_mutex_drop(&zn->_mutex_inner);
        _Z_ERROR_RETURN(ret);
    }
#endif
#endif
    zn->_mode = Z_WHATAMI_CLIENT;
    zn->_tp._type = _Z_TRANSPORT_NONE;
    // Initialize the counters to 1
    zn->_entity_id = 1;
    zn->_resource_id = 1;
    zn->_query_id = 1;

#if Z_FEATURE_AUTO_RECONNECT == 1
    _z_config_init(&zn->_config);
    zn->_declaration_cache = NULL;
#endif

    // Initialize the data structs
    zn->_local_resources = NULL;
#if Z_FEATURE_SUBSCRIPTION == 1
    zn->_subscriptions = NULL;
    zn->_liveliness_subscriptions = NULL;
#if Z_FEATURE_RX_CACHE == 1
    zn->_subscription_cache = _z_subscription_lru_cache_init(Z_RX_CACHE_SIZE);
#endif
#endif
#if Z_FEATURE_QUERYABLE == 1
    zn->_local_queryable = NULL;
#if Z_FEATURE_RX_CACHE == 1
    zn->_queryable_cache = _z_queryable_lru_cache_init(Z_RX_CACHE_SIZE);
#endif
#endif
#if Z_FEATURE_QUERY == 1
    zn->_pending_queries = NULL;
#endif

#if Z_FEATURE_LIVELINESS == 1
    _z_liveliness_init(zn);
#endif

#if Z_FEATURE_INTEREST == 1
    zn->_write_filters = NULL;
#endif

#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_ADMIN_SPACE == 1
    zn->_admin_space_queryable_id = 0;
#if Z_FEATURE_CONNECTIVITY == 1
#if Z_FEATURE_QUERYABLE == 1
    zn->_admin_space_session_queryable_id = 0;
#endif
#if Z_FEATURE_PUBLICATION == 1
    zn->_admin_space_transport_listener_id = 0;
    zn->_admin_space_link_listener_id = 0;
#endif
#endif
#endif

#if Z_FEATURE_CONNECTIVITY == 1
    zn->_connectivity_next_listener_id = 1;
    _z_connectivity_transport_listener_intmap_init(&zn->_connectivity_transport_event_listeners);
    _z_connectivity_link_listener_intmap_init(&zn->_connectivity_link_event_listeners);
#endif
#endif
    zn->_callback_drop_sync_group = _z_sync_group_null();
    _Z_SET_IF_OK(ret, _z_sync_group_create(&zn->_callback_drop_sync_group));
    _Z_SET_IF_OK(ret, _z_runtime_init(&zn->_runtime));
#if Z_FEATURE_QUERY
    if (ret == _Z_RES_OK) {
        _z_fut_t fut = _z_fut_null();
        fut._fut_fn = _z_pending_query_process_timeout_task_fn;
        fut._fut_arg = zn;
        ret = _z_fut_handle_is_null(_z_runtime_spawn(&zn->_runtime, &fut)) ? _Z_ERR_FAILED_TO_SPAWN_TASK : _Z_RES_OK;
    }
#endif
    if (ret != _Z_RES_OK) {
#if Z_FEATURE_MULTI_THREAD == 1
#if Z_FEATURE_ADMIN_SPACE == 1
        _z_mutex_drop(&zn->_mutex_admin_space);
#endif
        _z_mutex_rec_drop(&zn->_mutex_transport);
        _z_mutex_drop(&zn->_mutex_inner);
#endif
        _z_sync_group_drop(&zn->_callback_drop_sync_group);
        _z_runtime_clear(&zn->_runtime);
        _Z_ERROR_RETURN(ret);
    }

    _z_interest_init(zn);

    zn->_local_zid = *zid;
    _z_atomic_bool_store(&zn->_is_closed, false, _z_memory_order_release);
    return ret;
}

z_result_t _z_session_close(_z_session_t *zn) {
    // Need to run close sequence unconditionally, since
    // this is the only way to guarantee that after _z_session_close returns,
    // no more callbacks will be running
    _Z_RETURN_IF_ERR(_z_session_mutex_lock(zn));
    _z_atomic_bool_store(&zn->_is_closed, true, _z_memory_order_release);
    _z_session_mutex_unlock(zn);
    // stop the runtime to prevent spawning new tasks
    // this will also ensure that no callbacks can be called in response to message reception inside read task,
    // session sync group at the end of the call might still be needed in case there are any historical
    // callbacks currently executing, like in the case of liveliness subscribers/ matching listeners / connectivity
    // events
    _Z_RETURN_IF_ERR(_z_runtime_stop(&zn->_runtime));
    _Z_RETURN_IF_ERR(_z_session_mutex_lock(zn));
#if Z_FEATURE_AUTO_RECONNECT == 1
    _z_network_message_slist_free(&zn->_declaration_cache);
#endif
    _z_session_mutex_unlock(zn);
    _z_flush_local_resources(zn);
#if Z_FEATURE_SUBSCRIPTION == 1
    _z_flush_subscriptions(zn);
#endif
#if Z_FEATURE_QUERYABLE == 1
    // Admin space querable cleanup will occur as part of queryable cleanup
    _z_flush_session_queryable(zn);
#endif
#if Z_FEATURE_QUERY == 1
    _z_flush_pending_queries(zn);
#endif
#if Z_FEATURE_LIVELINESS == 1
    _z_liveliness_clear(zn);
#endif
    _z_flush_interest(zn);
#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_CONNECTIVITY == 1
    _Z_RETURN_IF_ERR(_z_session_mutex_lock(zn));
    _z_connectivity_transport_listener_intmap_clear(&zn->_connectivity_transport_event_listeners);
    _z_connectivity_link_listener_intmap_clear(&zn->_connectivity_link_event_listeners);
    zn->_connectivity_next_listener_id = 1;
    _z_session_mutex_unlock(zn);
#endif
#if Z_FEATURE_ADMIN_SPACE == 1
    _z_session_admin_space_mutex_lock(zn);
    zn->_admin_space_queryable_id = 0;
#if Z_FEATURE_CONNECTIVITY == 1
#if Z_FEATURE_QUERYABLE == 1
    zn->_admin_space_session_queryable_id = 0;
#endif
#if Z_FEATURE_PUBLICATION == 1
    zn->_admin_space_transport_listener_id = 0;
    zn->_admin_space_link_listener_id = 0;
#endif
#endif
    _z_session_admin_space_mutex_unlock(zn);
#endif
#endif
    // Despite stopping runtime at the very beginning, we still need to wait for possible historical callbacks
    // from liveliness subscribers, matching listeners, connectivity events listeners, etc
    // to finish
    _z_sync_group_wait(&zn->_callback_drop_sync_group);
    return _Z_RES_OK;
}

void _z_session_clear(_z_session_t *zn) {
    _z_session_close(zn);
    _z_runtime_clear(&zn->_runtime);
#if Z_FEATURE_AUTO_RECONNECT == 1
    _z_config_clear(&zn->_config);
#endif
    _z_session_transport_mutex_lock(zn);
    _z_transport_clear(&zn->_tp);
    _z_session_transport_mutex_unlock(zn);

#if Z_FEATURE_MULTI_THREAD == 1
#if Z_FEATURE_ADMIN_SPACE == 1
    _z_mutex_drop(&zn->_mutex_admin_space);
#endif
    _z_mutex_rec_drop(&zn->_mutex_transport);
    _z_mutex_drop(&zn->_mutex_inner);
#endif  // Z_FEATURE_MULTI_THREAD == 1
    _z_sync_group_drop(&zn->_callback_drop_sync_group);
}
