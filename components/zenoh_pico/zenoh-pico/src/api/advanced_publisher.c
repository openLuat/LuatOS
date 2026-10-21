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

#include "zenoh-pico/api/advanced_publisher.h"

#include <stdio.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/api/serialization.h"
#include "zenoh-pico/collections/atomic.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_ADVANCED_PUBLICATION == 1

// Space for 10 digits + NULL
#define ZE_ADVANCED_PUBLISHER_UINT32_STR_BUF_LEN 11

static void _ze_advanced_publisher_state_init(_ze_advanced_publisher_state_t *state) {
    state->_heartbeat_mode = ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE;
    state->_last_published_sn = 0;
    z_internal_publisher_null(&state->_publisher);
    state->_state_publisher_task_handle = _z_fut_handle_null();
    state->_zn = _z_session_weak_null();
    _z_atomic_size_init(&state->_seqnumber, 0);
}

static bool _ze_advanced_publisher_state_check(const _ze_advanced_publisher_state_t *state) {
    return state->_heartbeat_mode == ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE ||
           z_internal_publisher_check(&state->_publisher);
}

void _ze_advanced_publisher_state_clear(_ze_advanced_publisher_state_t *state) {
    if (state->_heartbeat_mode != ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE &&
        !_z_fut_handle_is_null(state->_state_publisher_task_handle)) {
        _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&state->_zn);
        if (!_Z_RC_IS_NULL(&sess_rc)) {
            _z_runtime_cancel_fut(&_Z_RC_IN_VAL(&sess_rc)->_runtime, &state->_state_publisher_task_handle);
            _z_session_rc_drop(&sess_rc);
        }
        state->_state_publisher_task_handle = _z_fut_handle_null();
        z_undeclare_publisher(z_publisher_move(&state->_publisher));
    }
    _z_session_weak_drop(&state->_zn);
    state->_heartbeat_mode = ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE;
    state->_last_published_sn = 0;
}

bool _ze_advanced_publisher_check(const _ze_advanced_publisher_t *pub) {
    return z_internal_publisher_check(&pub->_publisher) &&
           (!pub->_has_liveliness || z_internal_liveliness_token_check(&pub->_liveliness)) &&
           (_Z_RC_IS_NULL(&pub->_state) || _ze_advanced_publisher_state_check(_Z_RC_IN_VAL(&pub->_state)));
}

_ze_advanced_publisher_t _ze_advanced_publisher_null(void) {
    _ze_advanced_publisher_t publisher = {0};
    z_internal_publisher_null(&publisher._publisher);
    z_internal_liveliness_token_null(&publisher._liveliness);
    publisher._state = _ze_advanced_publisher_state_rc_null();
    return publisher;
}

z_result_t _ze_undeclare_advanced_publisher_clear(_ze_advanced_publisher_t *pub) {
    if (pub == NULL || !_ze_advanced_publisher_check(pub)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }

    z_result_t ret = z_undeclare_publisher(z_publisher_move(&pub->_publisher));

    if (pub->_has_liveliness) {
        z_liveliness_token_drop(z_liveliness_token_move(&pub->_liveliness));
        pub->_has_liveliness = false;
    }

    if (!_Z_RC_IS_NULL(&pub->_state)) {
        _ze_advanced_publisher_state_rc_drop(&pub->_state);
    }

    if (pub->_cache != NULL) {
        _ze_advanced_cache_free(&pub->_cache);
    }
    *pub = _ze_advanced_publisher_null();
    return ret;
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX(ze, _ze_advanced_publisher_t, advanced_publisher,
                                                     _ze_advanced_publisher_check, _ze_advanced_publisher_null,
                                                     _ze_undeclare_advanced_publisher_clear)

void ze_advanced_publisher_cache_options_default(ze_advanced_publisher_cache_options_t *options) {
    options->is_enabled = true;
    options->max_samples = 1;
    options->congestion_control = z_internal_congestion_control_default_push();
    options->priority = z_priority_default();
    options->is_express = false;
    options->_liveliness = false;
}

void ze_advanced_publisher_sample_miss_detection_options_default(
    ze_advanced_publisher_sample_miss_detection_options_t *options) {
    options->is_enabled = true;
    options->heartbeat_mode = ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_DEFAULT;
    options->heartbeat_period_ms = 0;
}

void ze_advanced_publisher_options_default(ze_advanced_publisher_options_t *options) {
    z_publisher_options_default(&options->publisher_options);
    ze_advanced_publisher_cache_options_default(&options->cache);
    options->cache.is_enabled = false;
    ze_advanced_publisher_sample_miss_detection_options_default(&options->sample_miss_detection);
    options->sample_miss_detection.is_enabled = false;
    options->publisher_detection = false;
    options->publisher_detection_metadata = NULL;
}

void ze_advanced_publisher_put_options_default(ze_advanced_publisher_put_options_t *options) {
    z_publisher_put_options_default(&options->put_options);
}

void ze_advanced_publisher_delete_options_default(ze_advanced_publisher_delete_options_t *options) {
    z_publisher_delete_options_default(&options->delete_options);
}

// suffix = KE_ADV_PREFIX / KE_PUB / ZID / [ EID | KE_UHLC ] / [ meta | KE_EMPTY]
static z_result_t _ze_advanced_publisher_ke_suffix(z_owned_keyexpr_t *suffix, const z_entity_global_id_t *id,
                                                   const _ze_advanced_publisher_sequencing_t sequencing,
                                                   const z_loaned_keyexpr_t *metadata) {
    z_internal_keyexpr_null(suffix);
    _Z_RETURN_IF_ERR(_Z_KEYEXPR_APPEND_STR_ARRAY(suffix, _Z_KEYEXPR_ADV_PREFIX, _Z_KEYEXPR_PUB));

    z_id_t zid = z_entity_global_id_zid(id);
    z_owned_string_t zid_str;
    _Z_CLEAN_RETURN_IF_ERR(z_id_to_string(&zid, &zid_str), z_keyexpr_drop(z_keyexpr_move(suffix)));

    _Z_CLEAN_RETURN_IF_ERR(
        _z_keyexpr_append_substr(suffix, z_string_data(z_string_loan(&zid_str)), z_string_len(z_string_loan(&zid_str))),
        z_string_drop(z_string_move(&zid_str));
        z_keyexpr_drop(z_keyexpr_move(suffix)));
    z_string_drop(z_string_move(&zid_str));

    if (sequencing == _ZE_ADVANCED_PUBLISHER_SEQUENCING_SEQUENCE_NUMBER) {
        char buffer[ZE_ADVANCED_PUBLISHER_UINT32_STR_BUF_LEN];
        uint32_t eid = z_entity_global_id_eid(id);
        snprintf(buffer, sizeof(buffer), "%u", eid);
        _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_str(suffix, buffer), z_keyexpr_drop(z_keyexpr_move(suffix)));
    } else {
        _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_str(suffix, _Z_KEYEXPR_UHLC), z_keyexpr_drop(z_keyexpr_move(suffix)));
    }

    if (metadata != NULL) {
        _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_suffix(suffix, metadata), z_keyexpr_drop(z_keyexpr_move(suffix)));
    } else {
        _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_str(suffix, _Z_KEYEXPR_EMPTY), z_keyexpr_drop(z_keyexpr_move(suffix)));
    }
    return _Z_RES_OK;
}

static _z_fut_fn_result_t _ze_advanced_publisher_heartbeat_handler(void *ctx, _z_executor_t *executor) {
    _ZP_UNUSED(executor);
    _ze_advanced_publisher_state_weak_t *state_weak_rc = (_ze_advanced_publisher_state_weak_t *)ctx;
    _ze_advanced_publisher_state_rc_t state_rc = _ze_advanced_publisher_state_weak_upgrade(state_weak_rc);

    if (_Z_RC_IS_NULL(&state_rc)) {
        // State has been dropped, nothing to do
        return _z_fut_fn_result_ready();
    }
    unsigned long heartbeat_period_ms = state_rc._val->_heartbeat_period_ms;
    _ze_advanced_publisher_state_t *state = _Z_RC_IN_VAL(&state_rc);

    bool publish = false;
    uint32_t next_seq = (uint32_t)_z_atomic_size_load(&state->_seqnumber, _z_memory_order_relaxed);

    switch (state->_heartbeat_mode) {
        case ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_PERIODIC:
            publish = true;
            break;
        case ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_SPORADIC:
            // TODO: This doesn't account for sn wraparound
            publish = (next_seq > state->_last_published_sn) ? true : false;
            break;
        default:
            _Z_WARN("Failed to publish heartbeat, invalid mode: %d", state->_heartbeat_mode);
            return _z_fut_fn_result_ready();
    };

    if (publish) {
        z_owned_bytes_t payload;
        z_bytes_empty(&payload);
        ze_owned_serializer_t serializer;
        ze_serializer_empty(&serializer);
        ze_serializer_serialize_uint32(ze_serializer_loan_mut(&serializer), _z_seqnumber_prev(next_seq));
        ze_serializer_finish(ze_serializer_move(&serializer), &payload);
        z_result_t res = z_publisher_put(z_publisher_loan(&state->_publisher), z_bytes_move(&payload), NULL);
        if (res != _Z_RES_OK) {
            _Z_WARN("Failed to publish heartbeat: %d", res);
        }
        state->_last_published_sn = next_seq;
    }

    _ze_advanced_publisher_state_rc_drop(&state_rc);
    return _z_fut_fn_result_wake_up_after(heartbeat_period_ms);
}

static void _ze_advanced_publisher_heartbeat_dropper(void *ctx) {
    _ze_advanced_publisher_state_weak_t *state_rc = (_ze_advanced_publisher_state_weak_t *)ctx;
    _ze_advanced_publisher_state_weak_drop(state_rc);
    z_free(state_rc);
}

z_result_t ze_declare_advanced_publisher(const z_loaned_session_t *zs, ze_owned_advanced_publisher_t *pub,
                                         const z_loaned_keyexpr_t *keyexpr,
                                         const ze_advanced_publisher_options_t *options) {
    pub->_val = _ze_advanced_publisher_null();

    // Set options
    ze_advanced_publisher_options_t opt;
    ze_advanced_publisher_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    // Validate options early
    if (opt.sample_miss_detection.is_enabled &&
        opt.sample_miss_detection.heartbeat_mode != ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE) {
        if (opt.sample_miss_detection.heartbeat_period_ms == 0) {
            _Z_ERROR("Failed to create advanced publisher: heatbeat_period_ms must be > 0");
            return _Z_ERR_INVALID;
        }
    }

    _Z_RETURN_IF_ERR(z_declare_publisher(zs, &pub->_val._publisher, keyexpr, &opt.publisher_options));

    z_entity_global_id_t id = z_publisher_id(z_publisher_loan(&pub->_val._publisher));

    if (opt.sample_miss_detection.is_enabled) {
        pub->_val._sequencing = _ZE_ADVANCED_PUBLISHER_SEQUENCING_SEQUENCE_NUMBER;

        _ze_advanced_publisher_state_t *state = z_malloc(sizeof(_ze_advanced_publisher_state_t));
        if (state == NULL) {
            z_publisher_drop(z_publisher_move(&pub->_val._publisher));
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
        _ze_advanced_publisher_state_init(state);

        pub->_val._state = _ze_advanced_publisher_state_rc_new(state);
        if (_Z_RC_IS_NULL(&pub->_val._state)) {
            _ze_advanced_publisher_state_clear(state);
            z_free(state);
            z_publisher_drop(z_publisher_move(&pub->_val._publisher));
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }
    } else if (opt.cache.is_enabled) {
        pub->_val._sequencing = _ZE_ADVANCED_PUBLISHER_SEQUENCING_TIMESTAMP;
    } else {
        pub->_val._sequencing = _ZE_ADVANCED_PUBLISHER_SEQUENCING_NONE;
    }

    z_owned_keyexpr_t suffix;
    _Z_CLEAN_RETURN_IF_ERR(
        _ze_advanced_publisher_ke_suffix(&suffix, &id, pub->_val._sequencing, opt.publisher_detection_metadata),
        _ze_advanced_publisher_state_rc_drop(&pub->_val._state);
        z_publisher_drop(z_publisher_move(&pub->_val._publisher)));

    if (opt.cache.is_enabled) {
        _ze_advanced_cache_t *cache = _ze_advanced_cache_new(zs, keyexpr, z_keyexpr_loan(&suffix), opt.cache);

        if (cache == NULL) {
            _ze_advanced_publisher_state_rc_drop(&pub->_val._state);
            z_publisher_drop(z_publisher_move(&pub->_val._publisher));
            z_keyexpr_drop(z_keyexpr_move(&suffix));
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
        }
        pub->_val._cache = cache;
    }

    // Create joined key expression only if needed for liveliness token or state publisher
    if (opt.publisher_detection ||
        (opt.sample_miss_detection.is_enabled &&
         opt.sample_miss_detection.heartbeat_mode != ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE)) {
        z_owned_keyexpr_t ke;
        _Z_CLEAN_RETURN_IF_ERR(z_keyexpr_join(&ke, keyexpr, z_keyexpr_loan(&suffix)),
                               _ze_advanced_publisher_state_rc_drop(&pub->_val._state);
                               z_publisher_drop(z_publisher_move(&pub->_val._publisher));
                               z_keyexpr_drop(z_keyexpr_move(&suffix)); _ze_advanced_cache_free(&pub->_val._cache));

        // Declare liveliness token on keyexpr/suffix
        if (opt.publisher_detection) {
            _Z_CLEAN_RETURN_IF_ERR(z_liveliness_declare_token(zs, &pub->_val._liveliness, z_keyexpr_loan(&ke), NULL),
                                   z_keyexpr_drop(z_keyexpr_move(&ke));
                                   _ze_advanced_publisher_state_rc_drop(&pub->_val._state);
                                   z_publisher_drop(z_publisher_move(&pub->_val._publisher));
                                   z_keyexpr_drop(z_keyexpr_move(&suffix)); _ze_advanced_cache_free(&pub->_val._cache));
            pub->_val._has_liveliness = true;
        }

        // Declare state publisher on keyexpr/suffix
        if (opt.sample_miss_detection.is_enabled &&
            opt.sample_miss_detection.heartbeat_mode != ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_NONE) {
            _ze_advanced_publisher_state_t *state = _Z_RC_IN_VAL(&pub->_val._state);
            state->_heartbeat_period_ms = opt.sample_miss_detection.heartbeat_period_ms;
            state->_heartbeat_mode = opt.sample_miss_detection.heartbeat_mode;
            state->_zn = _z_session_rc_clone_as_weak(zs);
            state->_last_published_sn = (uint32_t)_z_atomic_size_load(&state->_seqnumber, _z_memory_order_relaxed);

            z_publisher_options_t heatbeat_opts;
            z_publisher_options_default(&heatbeat_opts);
            if (opt.sample_miss_detection.heartbeat_mode == ZE_ADVANCED_PUBLISHER_HEARTBEAT_MODE_SPORADIC) {
                heatbeat_opts.congestion_control = Z_CONGESTION_CONTROL_BLOCK;
            }
            _Z_CLEAN_RETURN_IF_ERR(z_declare_publisher(zs, &state->_publisher, z_keyexpr_loan(&ke), &heatbeat_opts),
                                   z_keyexpr_drop(z_keyexpr_move(&ke));
                                   _ze_advanced_publisher_state_rc_drop(&pub->_val._state);
                                   z_publisher_drop(z_publisher_move(&pub->_val._publisher));
                                   z_liveliness_token_drop(z_liveliness_token_move(&pub->_val._liveliness));
                                   z_keyexpr_drop(z_keyexpr_move(&suffix)); _ze_advanced_cache_free(&pub->_val._cache));

            _ze_advanced_publisher_state_weak_t *ctx =
                _ze_advanced_publisher_state_rc_clone_as_weak_ptr(&pub->_val._state);
            if (_Z_RC_IS_NULL(ctx)) {
                z_keyexpr_drop(z_keyexpr_move(&ke));
                _ze_advanced_publisher_state_rc_drop(&pub->_val._state);
                z_publisher_drop(z_publisher_move(&pub->_val._publisher));
                z_liveliness_token_drop(z_liveliness_token_move(&pub->_val._liveliness));
                z_keyexpr_drop(z_keyexpr_move(&suffix));
                _ze_advanced_cache_free(&pub->_val._cache);
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
            _z_fut_t f = _z_fut_null();
            f._destroy_fn = _ze_advanced_publisher_heartbeat_dropper;
            f._fut_fn = _ze_advanced_publisher_heartbeat_handler;
            f._fut_arg = ctx;

            state->_state_publisher_task_handle = _z_runtime_spawn(&_Z_RC_IN_VAL(zs)->_runtime, &f);
            if (_z_fut_handle_is_null(state->_state_publisher_task_handle)) {
                z_keyexpr_drop(z_keyexpr_move(&ke));
                _ze_advanced_publisher_state_rc_drop(&pub->_val._state);
                z_publisher_drop(z_publisher_move(&pub->_val._publisher));
                z_liveliness_token_drop(z_liveliness_token_move(&pub->_val._liveliness));
                z_keyexpr_drop(z_keyexpr_move(&suffix));
                _ze_advanced_cache_free(&pub->_val._cache);
                return _Z_ERR_FAILED_TO_SPAWN_TASK;
            }
        }

        z_keyexpr_drop(z_keyexpr_move(&ke));
    }

    z_keyexpr_drop(z_keyexpr_move(&suffix));
    return _Z_RES_OK;
}

static z_result_t _ze_advanced_publisher_sequencing_options(const ze_loaned_advanced_publisher_t *pub,
                                                            z_source_info_t *source_info, z_timestamp_t *timestamp) {
    if (source_info == NULL || timestamp == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }

    const z_loaned_publisher_t *publisher = z_publisher_loan(&pub->_publisher);

    // Set sequence number if required
    if (pub->_sequencing == _ZE_ADVANCED_PUBLISHER_SEQUENCING_SEQUENCE_NUMBER) {
        z_entity_global_id_t publisher_id = z_publisher_id(publisher);
        uint32_t seqnumber =
            (uint32_t)_z_atomic_size_fetch_add(&_Z_RC_IN_VAL(&pub->_state)->_seqnumber, 1, _z_memory_order_relaxed);
        *source_info = z_source_info_new(&publisher_id, seqnumber);
    }

    // Set timestamp
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&publisher->_zn);
    if (!_Z_RC_IS_NULL(&sess_rc)) {
        _Z_CLEAN_RETURN_IF_ERR(z_timestamp_new(timestamp, &sess_rc), _z_session_rc_drop(&sess_rc));
        _z_session_rc_drop(&sess_rc);
    } else {
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }
    return _Z_RES_OK;
}

z_result_t ze_undeclare_advanced_publisher(ze_moved_advanced_publisher_t *pub) {
    return _ze_undeclare_advanced_publisher_clear(&pub->_this._val);
}

z_result_t ze_advanced_publisher_put(const ze_loaned_advanced_publisher_t *pub, z_moved_bytes_t *payload,
                                     const ze_advanced_publisher_put_options_t *options) {
    ze_advanced_publisher_put_options_t opt;
    ze_advanced_publisher_put_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    z_timestamp_t timestamp = _z_timestamp_null();
    z_source_info_t si = _z_source_info_null();
    _Z_RETURN_IF_ERR(_ze_advanced_publisher_sequencing_options(pub, &si, &timestamp));
    opt.put_options.timestamp = &timestamp;
    opt.put_options.source_info = &si;
    return _z_publisher_put_impl(z_publisher_loan(&pub->_publisher), payload, &opt.put_options, pub->_cache);
}

z_result_t ze_advanced_publisher_delete(const ze_loaned_advanced_publisher_t *pub,
                                        const ze_advanced_publisher_delete_options_t *options) {
    ze_advanced_publisher_delete_options_t opt;
    ze_advanced_publisher_delete_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    z_timestamp_t timestamp = _z_timestamp_null();
    z_source_info_t si = _z_source_info_null();
    _Z_RETURN_IF_ERR(_ze_advanced_publisher_sequencing_options(pub, &si, &timestamp));
    opt.delete_options.timestamp = &timestamp;
    opt.delete_options.source_info = &si;
    return _z_publisher_delete_impl(z_publisher_loan(&pub->_publisher), &opt.delete_options, pub->_cache);
}

const z_loaned_keyexpr_t *ze_advanced_publisher_keyexpr(const ze_loaned_advanced_publisher_t *pub) {
    return z_publisher_keyexpr(z_publisher_loan(&pub->_publisher));
}

z_entity_global_id_t ze_advanced_publisher_id(const ze_loaned_advanced_publisher_t *pub) {
    return z_publisher_id(z_publisher_loan(&pub->_publisher));
}

z_result_t ze_advanced_publisher_get_matching_status(const ze_loaned_advanced_publisher_t *pub,
                                                     z_matching_status_t *matching_status) {
    return z_publisher_get_matching_status(z_publisher_loan(&pub->_publisher), matching_status);
}

z_result_t ze_advanced_publisher_declare_matching_listener(const ze_loaned_advanced_publisher_t *publisher,
                                                           z_owned_matching_listener_t *matching_listener,
                                                           z_moved_closure_matching_status_t *callback) {
    return z_publisher_declare_matching_listener(z_publisher_loan(&publisher->_publisher), matching_listener, callback);
}

z_result_t ze_advanced_publisher_declare_background_matching_listener(const ze_loaned_advanced_publisher_t *publisher,
                                                                      z_moved_closure_matching_status_t *callback) {
    return z_publisher_declare_background_matching_listener(z_publisher_loan(&publisher->_publisher), callback);
}

#endif
