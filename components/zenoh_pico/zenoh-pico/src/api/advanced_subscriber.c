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

#include "zenoh-pico/api/advanced_subscriber.h"

#include <ctype.h>
#include <stdlib.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/api/liveliness.h"
#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/api/serialization.h"
#include "zenoh-pico/collections/seqnumber.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/utils/query_params.h"
#include "zenoh-pico/utils/string.h"
#include "zenoh-pico/utils/time_range.h"
#include "zenoh-pico/utils/uuid.h"

#if Z_FEATURE_ADVANCED_SUBSCRIPTION == 1

#define ZE_ADVANCED_SUBSCRIBER_QUERY_PARAM_BUF_SIZE 256

// Space for 10 digits + NULL
#define ZE_ADVANCED_SUBSCRIBER_UINT32_STR_BUF_LEN 11

z_result_t _ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(_ze_advanced_subscriber_state_t *state) {
#if Z_FEATURE_MULTI_THREAD == 1
    _Z_RETURN_IF_ERR(z_mutex_lock(z_mutex_loan_mut(&state->_mutex)));
#endif
    if (state->_is_undeclaring) {
#if Z_FEATURE_MULTI_THREAD == 1
        z_mutex_unlock(z_mutex_loan_mut(&state->_mutex));
#endif
        return Z_ERR_CANCELLED;
    }
    return _Z_RES_OK;
}

void _ze_advanced_subscriber_state_unlock_mutex(_ze_advanced_subscriber_state_t *state) {
#if Z_FEATURE_MULTI_THREAD == 1
    z_mutex_unlock(z_mutex_loan_mut(&state->_mutex));
#endif
}

void _ze_sample_miss_listener_clear(_ze_sample_miss_listener_t *listener) {
    _ze_advanced_subscriber_state_weak_drop(&listener->_statesref);
    *listener = _ze_sample_miss_listener_null();
}

z_result_t _ze_sample_miss_listener_drop(_ze_sample_miss_listener_t *listener) {
    if (listener == NULL) {
        return _Z_ERR_INVALID;
    }

    _ze_advanced_subscriber_state_rc_t state_rc = _ze_advanced_subscriber_state_weak_upgrade(&listener->_statesref);
    if (_Z_RC_IS_NULL(&state_rc)) {
        return _Z_ERR_INVALID;
    }

    _ze_advanced_subscriber_state_t *state = _Z_RC_IN_VAL(&state_rc);
    z_result_t ret = _ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(state);
    if (ret != _Z_RES_OK) {
        _ze_advanced_subscriber_state_rc_drop(&state_rc);
        _ze_sample_miss_listener_clear(listener);
        return ret == Z_ERR_CANCELLED ? _Z_RES_OK : ret;
    }
    _ze_closure_miss_intmap_remove(&state->_miss_handlers, listener->_id);
    _ze_advanced_subscriber_state_unlock_mutex(state);
    _ze_advanced_subscriber_state_rc_drop(&state_rc);
    _ze_sample_miss_listener_clear(listener);
    return _Z_RES_OK;
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX(ze, _ze_sample_miss_listener_t, sample_miss_listener,
                                                     _ze_sample_miss_listener_check, _ze_sample_miss_listener_null,
                                                     _ze_sample_miss_listener_drop)

static z_result_t _ze_advanced_subscriber_sequenced_state_init(_ze_advanced_subscriber_sequenced_state_t *state,
                                                               const _z_session_weak_t *zn,
                                                               const z_loaned_keyexpr_t *keyexpr,
                                                               const _z_entity_global_id_t *id) {
    (void)(id);
    state->_zn = _z_session_weak_clone(zn);
    state->_has_last_delivered = false;
    state->_last_delivered = 0;
    state->_pending_queries = 0;
    state->_periodic_query_handle = _z_fut_handle_null();
    _z_uint32__z_sample_sortedmap_init(&state->_pending_samples);

    z_id_t zid = z_entity_global_id_zid(id);
    z_owned_string_t zid_str;
    _Z_RETURN_IF_ERR(z_id_to_string(&zid, &zid_str));

    char buffer[ZE_ADVANCED_SUBSCRIBER_UINT32_STR_BUF_LEN];
    uint32_t eid = z_entity_global_id_eid(id);
    snprintf(buffer, sizeof(buffer), "%u", eid);

    // Initialize query_keyexpr to: keyexpr / _Z_KEYEXPR_ADV_PREFIX / _Z_KEYEXPR_STAR / ZID / EID / _Z_KEYEXPR_STARSTAR
    z_internal_keyexpr_null(&state->_query_keyexpr);
    _Z_CLEAN_RETURN_IF_ERR(z_keyexpr_clone(&state->_query_keyexpr, keyexpr), z_string_drop(z_string_move(&zid_str)));
    _Z_CLEAN_RETURN_IF_ERR(_Z_KEYEXPR_APPEND_STR_ARRAY(&state->_query_keyexpr, _Z_KEYEXPR_ADV_PREFIX, _Z_KEYEXPR_STAR),
                           z_string_drop(z_string_move(&zid_str));
                           z_keyexpr_drop(z_keyexpr_move(&state->_query_keyexpr)));
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_substr(&state->_query_keyexpr, z_string_data(z_string_loan(&zid_str)),
                                                    z_string_len(z_string_loan(&zid_str))),
                           z_string_drop(z_string_move(&zid_str));
                           z_keyexpr_drop(z_keyexpr_move(&state->_query_keyexpr)));
    z_string_drop(z_string_move(&zid_str));
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_str(&state->_query_keyexpr, buffer),
                           z_keyexpr_drop(z_keyexpr_move(&state->_query_keyexpr)));
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_str(&state->_query_keyexpr, _Z_KEYEXPR_STARSTAR),
                           z_keyexpr_drop(z_keyexpr_move(&state->_query_keyexpr)));

    return _Z_RES_OK;
}

void _ze_advanced_subscriber_sequenced_state_clear(_ze_advanced_subscriber_sequenced_state_t *state) {
    state->_has_last_delivered = false;
    state->_last_delivered = 0;
    state->_pending_queries = 0;

    if (!_z_fut_handle_is_null(state->_periodic_query_handle)) {
        _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&state->_zn);
        if (!_Z_RC_IS_NULL(&sess_rc)) {
            z_result_t res = _z_runtime_cancel_fut(&_Z_RC_IN_VAL(&sess_rc)->_runtime, &state->_periodic_query_handle);
            if (res != _Z_RES_OK) {
                _Z_WARN("Failed to remove periodic task, res: %d", res);
            }
            state->_periodic_query_handle = _z_fut_handle_null();
            _z_session_rc_drop(&sess_rc);
        }
    }
    _z_session_weak_drop(&state->_zn);
    state->_zn = _z_session_weak_null();
    _z_uint32__z_sample_sortedmap_clear(&state->_pending_samples);
    z_keyexpr_drop(z_keyexpr_move(&state->_query_keyexpr));
}

static void _ze_advanced_subscriber_timestamped_state_init(_ze_advanced_subscriber_timestamped_state_t *state) {
    state->_has_last_delivered = false;
    state->_last_delivered = _z_timestamp_null();
    state->_pending_queries = 0;
    _z_timestamp__z_sample_sortedmap_init(&state->_pending_samples);
}

void _ze_advanced_subscriber_timestamped_state_clear(_ze_advanced_subscriber_timestamped_state_t *state) {
    state->_has_last_delivered = false;
    _z_timestamp_clear(&state->_last_delivered);
    state->_pending_queries = 0;
    _z_timestamp__z_sample_sortedmap_clear(&state->_pending_samples);
}

_ze_advanced_subscriber_state_t _ze_advanced_subscriber_state_null(void) {
    _ze_advanced_subscriber_state_t state = {0};
    state._zn = _z_session_weak_null();
    z_internal_keyexpr_null(&state._keyexpr);
    z_internal_liveliness_token_null(&state._token);
    z_internal_cancellation_token_null(&state._cancellation_token);
    return state;
}

static z_result_t _ze_advanced_subscriber_state_init(_ze_advanced_subscriber_state_t *state, const _z_session_rc_t *zn,
                                                     z_moved_closure_sample_t *callback,
                                                     const z_loaned_keyexpr_t *keyexpr,
                                                     const ze_advanced_subscriber_options_t *options) {
    *state = _ze_advanced_subscriber_state_null();
    state->_next_id = 0;
    state->_global_pending_queries = options->history.is_enabled ? 1 : 0;
    _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_init(&state->_sequenced_states);
    _z_id__ze_advanced_subscriber_timestamped_state_hashmap_init(&state->_timestamped_states);
    state->_zn = _z_session_rc_clone_as_weak(zn);
    state->_retransmission = options->recovery.is_enabled;
    state->_has_period = options->recovery.last_sample_miss_detection.periodic_queries_period_ms != 0;
    state->_period_ms = options->recovery.last_sample_miss_detection.periodic_queries_period_ms;
    state->_history_depth = options->history.is_enabled ? options->history.max_samples : 0;
    state->_history_age = options->history.is_enabled ? options->history.max_age_ms : 0;
    state->_query_target = Z_QUERY_TARGET_DEFAULT;
    // Use default query timeout if not specified in options
    state->_query_timeout = (options->query_timeout_ms > 0) ? options->query_timeout_ms : Z_GET_TIMEOUT_DEFAULT;
    state->_callback = callback->_this._val.call;
    state->_dropper = callback->_this._val.drop;
    state->_ctx = callback->_this._val.context;
    z_internal_closure_sample_null(&callback->_this);
    _ze_closure_miss_intmap_init(&state->_miss_handlers);
    state->_has_token = false;
#if Z_FEATURE_MULTI_THREAD == 1
    z_result_t ret = z_mutex_init(&state->_mutex);
    if (ret != _Z_RES_OK) {
        if (state->_dropper != NULL) {
            state->_dropper(state->_ctx);
        }
        return ret;
    }
#endif
    _Z_CLEAN_RETURN_IF_ERR(z_keyexpr_clone(&state->_keyexpr, keyexpr), _ze_advanced_subscriber_state_clear(state));
    _Z_CLEAN_RETURN_IF_ERR(z_cancellation_token_new(&state->_cancellation_token),
                           _ze_advanced_subscriber_state_clear(state));
    return _Z_RES_OK;
}

static z_result_t _ze_advanced_subscriber_state_new(_ze_advanced_subscriber_state_rc_t *rc_state,
                                                    const _z_session_rc_t *zn, z_moved_closure_sample_t *callback,
                                                    const z_loaned_keyexpr_t *keyexpr,
                                                    const ze_advanced_subscriber_options_t *options) {
    _ze_advanced_subscriber_state_t state;
    _Z_RETURN_IF_ERR(_ze_advanced_subscriber_state_init(&state, zn, callback, keyexpr, options));

    *rc_state = _ze_advanced_subscriber_state_rc_new_from_val(&state);
    if (_Z_RC_IS_NULL(rc_state)) {
        _ze_advanced_subscriber_state_clear(&state);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }

    return _Z_RES_OK;
}

void _ze_advanced_subscriber_state_clear(_ze_advanced_subscriber_state_t *state) {
    _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_clear(&state->_sequenced_states);
    _z_id__ze_advanced_subscriber_timestamped_state_hashmap_clear(&state->_timestamped_states);
    _ze_closure_miss_intmap_clear(&state->_miss_handlers);
    z_keyexpr_drop(z_keyexpr_move(&state->_keyexpr));
    z_cancellation_token_drop(z_cancellation_token_move(&state->_cancellation_token));
    if (state->_has_token) {
        z_liveliness_token_drop(z_liveliness_token_move(&state->_token));
    }
#if Z_FEATURE_MULTI_THREAD == 1
    z_mutex_drop(z_mutex_move(&state->_mutex));
#endif
    _z_session_weak_drop(&state->_zn);

    *state = _ze_advanced_subscriber_state_null();
}

static bool _ze_advanced_subscriber_state_check(const _ze_advanced_subscriber_state_t *state) {
    return (!_Z_RC_IS_NULL(&state->_zn) && z_internal_keyexpr_check(&state->_keyexpr) &&
            (!state->_has_token || z_internal_liveliness_token_check(&state->_token)));
}

bool _ze_advanced_subscriber_check(const _ze_advanced_subscriber_t *sub) {
    return (z_internal_subscriber_check(&sub->_subscriber) &&
            (!sub->_has_liveliness_subscriber || z_internal_subscriber_check(&sub->_liveliness_subscriber)) &&
            (!sub->_has_heartbeat_subscriber || z_internal_subscriber_check(&sub->_heartbeat_subscriber)) &&
            !_Z_RC_IS_NULL(&sub->_state) && _ze_advanced_subscriber_state_check(_Z_RC_IN_VAL(&sub->_state)));
}

_ze_advanced_subscriber_t _ze_advanced_subscriber_null(void) {
    _ze_advanced_subscriber_t subscriber = {0};
    z_internal_subscriber_null(&subscriber._subscriber);
    z_internal_subscriber_null(&subscriber._liveliness_subscriber);
    z_internal_subscriber_null(&subscriber._heartbeat_subscriber);
    subscriber._state = _ze_advanced_subscriber_state_rc_null();

    return subscriber;
}

z_result_t _ze_advanced_subscriber_undeclare(_ze_advanced_subscriber_t *sub) {
    if (sub == NULL || !_ze_advanced_subscriber_check(sub)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }
    z_result_t ret = z_undeclare_subscriber(z_subscriber_move(&sub->_subscriber));
    if (sub->_has_liveliness_subscriber) {
        z_result_t ret2 = z_undeclare_subscriber(z_subscriber_move(&sub->_liveliness_subscriber));
        _Z_SET_IF_OK(ret, ret2)
    }
    if (sub->_has_heartbeat_subscriber) {
        z_result_t ret2 = z_undeclare_subscriber(z_subscriber_move(&sub->_heartbeat_subscriber));
        _Z_SET_IF_OK(ret, ret2);
    }
    _ze_advanced_subscriber_state_rc_drop(&sub->_state);

    *sub = _ze_advanced_subscriber_null();
    return ret;
}

void _ze_advanced_subscriber_clear(_ze_advanced_subscriber_t *sub) {
    if (sub == NULL || !_ze_advanced_subscriber_check(sub)) {
        return;
    }
    _z_subscriber_clear(&sub->_subscriber._val);
    if (sub->_has_liveliness_subscriber) {
        _z_subscriber_clear(&sub->_liveliness_subscriber._val);
    }
    if (sub->_has_heartbeat_subscriber) {
        _z_subscriber_clear(&sub->_heartbeat_subscriber._val);
    }
    _ze_advanced_subscriber_state_rc_drop(&sub->_state);

    *sub = _ze_advanced_subscriber_null();
}

_Z_OWNED_FUNCTIONS_VALUE_NO_COPY_NO_MOVE_IMPL_PREFIX(ze, _ze_advanced_subscriber_t, advanced_subscriber,
                                                     _ze_advanced_subscriber_check, _ze_advanced_subscriber_null,
                                                     _ze_advanced_subscriber_undeclare)

static bool _ze_advanced_subscriber_populate_query_params(char *buf, size_t buf_len, size_t max_samples,
                                                          uint64_t max_age_ms,
                                                          const _z_query_param_range_t *seq_range) {
    if (buf == NULL || buf_len == 0) {
        return false;
    }

    size_t pos = 0;
    // Allow responses for any key expression
    if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_KEY_ANYKE, _Z_QUERY_PARAMS_KEY_ANYKE_LEN)) {
        return false;  // Not enough space
    }

    if (max_samples > 0) {
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_LIST_SEPARATOR,
                               _Z_QUERY_PARAMS_LIST_SEPARATOR_LEN)) {
            return false;  // Not enough space
        }
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_KEY_MAX, _Z_QUERY_PARAMS_KEY_MAX_LEN)) {
            return false;  // Not enough space
        }
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_FIELD_SEPARATOR,
                               _Z_QUERY_PARAMS_FIELD_SEPARATOR_LEN)) {
            return false;  // Not enough space
        }

        int written = snprintf(&buf[pos], buf_len - pos, "%zu", max_samples);
        if (written < 0 || (size_t)written >= buf_len - pos) {
            return false;  // Overflow or encoding error
        }
        pos += (size_t)written;
    }
    if (max_age_ms > 0) {
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_LIST_SEPARATOR,
                               _Z_QUERY_PARAMS_LIST_SEPARATOR_LEN)) {
            return false;  // Not enough space
        }
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_KEY_TIME, _Z_QUERY_PARAMS_KEY_TIME_LEN)) {
            return false;  // Not enough space
        }
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_FIELD_SEPARATOR,
                               _Z_QUERY_PARAMS_FIELD_SEPARATOR_LEN)) {
            return false;  // Not enough space
        }

        double max_age_s = (double)max_age_ms * _Z_TIME_RANGE_MS_TO_SECS;
        _z_time_range_t range = {.start = {.bound = _Z_TIME_BOUND_INCLUSIVE, .now_offset = -max_age_s},
                                 .end = {.bound = _Z_TIME_BOUND_UNBOUNDED}};
        if (!_z_time_range_to_str(&range, &buf[pos], buf_len - pos)) {
            return false;  // Not enough space or invalid range
        }
        size_t used = strnlen(&buf[pos], buf_len - pos);
        if (used == buf_len - pos) {
            // Null terminator not found in remaining space
            return false;
        }
        pos += used;
    }
    if (seq_range != NULL) {
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_LIST_SEPARATOR,
                               _Z_QUERY_PARAMS_LIST_SEPARATOR_LEN)) {
            return false;  // Not enough space
        }
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_KEY_RANGE, _Z_QUERY_PARAMS_KEY_RANGE_LEN)) {
            return false;  // Not enough space
        }
        if (!_z_memcpy_checked(buf, buf_len, &pos, _Z_QUERY_PARAMS_FIELD_SEPARATOR,
                               _Z_QUERY_PARAMS_FIELD_SEPARATOR_LEN)) {
            return false;  // Not enough space
        }

        if (seq_range->_has_start) {
            int written = snprintf(&buf[pos], buf_len - pos, "%u", seq_range->_start);
            if (written < 0 || (size_t)written >= buf_len - pos) {
                return false;  // Overflow or encoding error
            }
            pos += (size_t)written;
        }

        if (buf_len - pos < 2) {
            return false;  // Not enough room for ".."
        }
        buf[pos++] = '.';
        buf[pos++] = '.';

        if (seq_range->_has_end) {
            int written = snprintf(&buf[pos], buf_len - pos, "%u", seq_range->_end);
            if (written < 0 || (size_t)written >= buf_len - pos) {
                return false;  // Overflow or encoding error
            }
            pos += (size_t)written;
        }
    }

    if (pos >= buf_len) {
        return false;  // Not enough space for '\0'
    }
    buf[pos] = '\0';
    return true;
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
static inline void __unsafe_ze_advanced_subscriber_trigger_miss_handler_callbacks(
    const _ze_closure_miss_intmap_t *miss_handlers, const z_entity_global_id_t *source_id, uint32_t nb) {
    _ze_closure_miss_intmap_iterator_t it = _ze_closure_miss_intmap_iterator_make(miss_handlers);

    ze_miss_t miss = {.source = *source_id, .nb = nb};

    while (_ze_closure_miss_intmap_iterator_next(&it)) {
        _ze_closure_miss_t *closure = _ze_closure_miss_intmap_iterator_value(&it);
        if (closure != NULL && closure->call != NULL) {
            (closure->call)(&miss, closure->context);
        }
    }
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
static inline void __unsafe_ze_advanced_subscriber_deliver_and_flush(_z_sample_t *sample, uint32_t source_sn,
                                                                     _z_closure_sample_callback_t callback, void *ctx,
                                                                     _ze_advanced_subscriber_sequenced_state_t *state) {
    if (callback != NULL) {
        callback(sample, ctx);
    }
    state->_last_delivered = source_sn;
    state->_has_last_delivered = true;

    uint32_t next_sn = _z_seqnumber_next(source_sn);
    _z_sample_t *next_sample = _z_uint32__z_sample_sortedmap_get(&state->_pending_samples, &next_sn);
    while (next_sample != NULL) {
        if (callback != NULL) {
            callback(next_sample, ctx);
        }
        _z_uint32__z_sample_sortedmap_remove(&state->_pending_samples, &next_sn);
        state->_last_delivered = next_sn;
        next_sn = _z_seqnumber_next(next_sn);
        next_sample = _z_uint32__z_sample_sortedmap_get(&state->_pending_samples, &next_sn);
    }
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
// TODO: Handle sn wraparound
static inline void __unsafe_ze_advanced_subscriber_flush_sequenced_source(
    _ze_advanced_subscriber_sequenced_state_t *state, _z_closure_sample_callback_t callback, void *ctx,
    const _z_entity_global_id_t *source_id, _ze_closure_miss_intmap_t *miss_handlers) {
    if (state->_pending_queries != 0 || _z_uint32__z_sample_sortedmap_is_empty(&state->_pending_samples)) {
        return;  // Pending queries or no samples to deliver
    }

    _z_uint32__z_sample_sortedmap_iterator_t it = _z_uint32__z_sample_sortedmap_iterator_make(&state->_pending_samples);
    while (_z_uint32__z_sample_sortedmap_iterator_next(&it)) {
        const uint32_t *source_sn = _z_uint32__z_sample_sortedmap_iterator_key(&it);
        _z_sample_t *sample = _z_uint32__z_sample_sortedmap_iterator_value(&it);

        if (!state->_has_last_delivered) {
            state->_last_delivered = *source_sn;
            state->_has_last_delivered = true;
            if (callback != NULL) {
                callback(sample, ctx);
            }
        } else {
            uint32_t next_sn = _z_seqnumber_next(state->_last_delivered);
            int64_t diff = _z_seqnumber_diff(*source_sn, next_sn);
            if (diff >= 0) {
                if (diff > 0) {
                    __unsafe_ze_advanced_subscriber_trigger_miss_handler_callbacks(miss_handlers, source_id,
                                                                                   (uint32_t)diff);
                }
                state->_last_delivered = *source_sn;
                if (callback != NULL) {
                    callback(sample, ctx);
                }
            }  // else older or duplicate sample
        }
    }
    _z_uint32__z_sample_sortedmap_clear(&state->_pending_samples);
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
static inline void __unsafe_ze_advanced_subscriber_flush_timestamped_source(
    _ze_advanced_subscriber_timestamped_state_t *state, _z_closure_sample_callback_t callback, void *ctx) {
    if (state->_pending_queries == 0 && !_z_timestamp__z_sample_sortedmap_is_empty(&state->_pending_samples)) {
        _z_timestamp__z_sample_sortedmap_iterator_t it =
            _z_timestamp__z_sample_sortedmap_iterator_make(&state->_pending_samples);

        while (_z_timestamp__z_sample_sortedmap_iterator_next(&it)) {
            _z_timestamp_t *timestamp = _z_timestamp__z_sample_sortedmap_iterator_key(&it);
            _z_sample_t *sample = _z_timestamp__z_sample_sortedmap_iterator_value(&it);

            if (!state->_has_last_delivered || _z_timestamp_cmp(timestamp, &state->_last_delivered) > 0) {
                _z_timestamp_copy(&state->_last_delivered, timestamp);
                state->_has_last_delivered = true;
                if (callback != NULL) {
                    callback(sample, ctx);
                }
            }
        }
        _z_timestamp__z_sample_sortedmap_clear(&state->_pending_samples);
    }
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
// Sets new_sequenced_source to true for new sequenced sources, false otherwise
static z_result_t __unsafe_ze_advanced_subscriber_handle_sample(_ze_advanced_subscriber_state_t *states,
                                                                z_loaned_sample_t *sample, bool *new_sequenced_source) {
    if (states == NULL || sample == NULL || new_sequenced_source == NULL) {
        _Z_ERROR("Invalid arguments to __unsafe_ze_advanced_subscriber_handle_sample");
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }
    *new_sequenced_source = false;

    const z_source_info_t *source_info = z_sample_source_info(sample);
    const z_timestamp_t *timestamp = z_sample_timestamp(sample);

    if (source_info != NULL) {
        z_entity_global_id_t id = z_source_info_id(source_info);
        uint32_t source_sn = z_source_info_sn(source_info);
        _ze_advanced_subscriber_sequenced_state_t *state =
            _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states, &id);
        if (state == NULL) {
            *new_sequenced_source = true;

            z_entity_global_id_t *new_id = z_malloc(sizeof(z_entity_global_id_t));
            if (new_id == NULL) {
                _Z_ERROR("Failed to allocate memory for new sequenced state ID");
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
            *new_id = id;

            _ze_advanced_subscriber_sequenced_state_t *new_state =
                z_malloc(sizeof(_ze_advanced_subscriber_sequenced_state_t));
            if (new_state == NULL) {
                _Z_ERROR("Failed to allocate memory for new sequenced state");
                z_free(new_id);
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
            _Z_CLEAN_RETURN_IF_ERR(_ze_advanced_subscriber_sequenced_state_init(new_state, &states->_zn,
                                                                                z_keyexpr_loan(&states->_keyexpr), &id),
                                   z_free(new_id);
                                   z_free(new_state));
            state = _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_insert(
                &states->_sequenced_states, new_id, new_state);
            if (state == NULL) {
                _Z_ERROR("Failed to insert new sequenced state into hashmap");
                z_free(new_id);
                z_free(new_state);
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
        }
        if (!state->_has_last_delivered && states->_global_pending_queries != 0) {
            // Avoid going through the map if history_depth == 1
            if (states->_history_depth == 1) {
                state->_last_delivered = source_sn;
                state->_has_last_delivered = true;
                if (states->_callback != NULL) {
                    states->_callback(sample, states->_ctx);
                }
            } else {
                uint32_t *new_source_sn = z_malloc(sizeof(uint32_t));
                if (new_source_sn == NULL) {
                    _Z_ERROR("Failed to allocate memory for new source_sn");
                    _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                }
                *new_source_sn = source_sn;

                _z_sample_t *new_sample = z_malloc(sizeof(_z_sample_t));
                if (new_sample == NULL) {
                    _Z_ERROR("Failed to allocate memory for new sample");
                    z_free(new_source_sn);
                    _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                }
                _Z_CLEAN_RETURN_IF_ERR(_z_sample_copy(new_sample, sample), z_free(new_source_sn); z_free(new_sample));

                _z_sample_t *entry =
                    _z_uint32__z_sample_sortedmap_insert(&state->_pending_samples, new_source_sn, new_sample);
                if (entry == NULL) {
                    _Z_ERROR("Failed to insert sample into sequenced state");
                    z_free(new_source_sn);
                    z_free(new_sample);
                    _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                }

                // _history_depth = 0 = wait for all global queries to complete
                if (states->_history_depth > 0 &&
                    _z_uint32__z_sample_sortedmap_len(&state->_pending_samples) >= states->_history_depth) {
                    _z_uint32__z_sample_sortedmap_entry_t *first_entry =
                        _z_uint32__z_sample_sortedmap_pop_first(&state->_pending_samples);
                    if (first_entry != NULL) {
                        uint32_t *first_source_sn = _z_uint32__z_sample_sortedmap_entry_key(first_entry);
                        _z_sample_t *first_sample = _z_uint32__z_sample_sortedmap_entry_val(first_entry);
                        __unsafe_ze_advanced_subscriber_deliver_and_flush(first_sample, *first_source_sn,
                                                                          states->_callback, states->_ctx, state);
                        _z_uint32__z_sample_sortedmap_entry_free(&first_entry);
                    }
                }
            }
        } else if (state->_has_last_delivered) {
            uint32_t next_sn = _z_seqnumber_next(state->_last_delivered);
            if (source_sn == next_sn) {
                __unsafe_ze_advanced_subscriber_deliver_and_flush(sample, source_sn, states->_callback, states->_ctx,
                                                                  state);
            } else if (_z_seqnumber_diff(source_sn, next_sn) > 0) {
                if (states->_retransmission) {
                    uint32_t *new_source_sn = z_malloc(sizeof(uint32_t));
                    if (new_source_sn == NULL) {
                        _Z_ERROR("Failed to allocate memory for new source_sn");
                        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                    }
                    *new_source_sn = source_sn;

                    _z_sample_t *new_sample = z_malloc(sizeof(_z_sample_t));
                    if (new_sample == NULL) {
                        _Z_ERROR("Failed to allocate memory for new sample");
                        z_free(new_source_sn);
                        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                    }
                    _Z_CLEAN_RETURN_IF_ERR(_z_sample_copy(new_sample, sample), z_free(new_source_sn);
                                           z_free(new_sample));

                    _z_sample_t *entry =
                        _z_uint32__z_sample_sortedmap_insert(&state->_pending_samples, new_source_sn, new_sample);
                    if (entry == NULL) {
                        _Z_ERROR("Failed to insert sample into sequenced state");
                        z_free(new_source_sn);
                        z_free(new_sample);
                        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                    }
                } else {
                    uint32_t nb = (uint32_t)_z_seqnumber_diff(source_sn, next_sn);
                    if (nb > 0) {
                        __unsafe_ze_advanced_subscriber_trigger_miss_handler_callbacks(&states->_miss_handlers, &id,
                                                                                       nb);
                    }
                    state->_last_delivered = source_sn;
                    if (states->_callback != NULL) {
                        states->_callback(sample, states->_ctx);
                    }
                }
            }
        } else {
            __unsafe_ze_advanced_subscriber_deliver_and_flush(sample, source_sn, states->_callback, states->_ctx,
                                                              state);
        }
    } else if (timestamp != NULL) {
        z_id_t id = z_timestamp_id(timestamp);
        _ze_advanced_subscriber_timestamped_state_t *state =
            _z_id__ze_advanced_subscriber_timestamped_state_hashmap_get(&states->_timestamped_states, &id);
        if (state == NULL) {
            z_id_t *new_id = z_malloc(sizeof(z_id_t));
            if (new_id == NULL) {
                _Z_ERROR("Failed to allocate memory for new timestamped state ID");
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
            *new_id = id;
            _ze_advanced_subscriber_timestamped_state_t *new_state =
                z_malloc(sizeof(_ze_advanced_subscriber_timestamped_state_t));
            if (new_state == NULL) {
                _Z_ERROR("Failed to allocate memory for new timestamped state");
                z_free(new_id);
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
            _ze_advanced_subscriber_timestamped_state_init(new_state);
            state = _z_id__ze_advanced_subscriber_timestamped_state_hashmap_insert(&states->_timestamped_states, new_id,
                                                                                   new_state);
            if (state == NULL) {
                _Z_ERROR("Failed to insert new timestamped state into hashmap");
                z_free(new_id);
                z_free(new_state);
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }
        }
        if (!state->_has_last_delivered || _z_timestamp_cmp(&state->_last_delivered, timestamp) < 0) {
            if ((states->_global_pending_queries == 0 && state->_pending_queries == 0) || states->_history_depth == 1) {
                state->_last_delivered = *timestamp;
                state->_has_last_delivered = true;
                if (states->_callback != NULL) {
                    states->_callback(sample, states->_ctx);
                }
            } else {
                _z_sample_t *entry = _z_timestamp__z_sample_sortedmap_get(&state->_pending_samples, timestamp);
                if (entry == NULL) {
                    z_timestamp_t *new_timestamp = z_malloc(sizeof(z_timestamp_t));
                    if (new_timestamp == NULL) {
                        _Z_ERROR("Failed to allocate memory for new timestamp");
                        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                    }
                    _z_timestamp_copy(new_timestamp, timestamp);

                    _z_sample_t *new_sample = z_malloc(sizeof(_z_sample_t));
                    if (new_sample == NULL) {
                        _Z_ERROR("Failed to allocate memory for new sample");
                        z_free(new_timestamp);
                        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                    }
                    _Z_CLEAN_RETURN_IF_ERR(_z_sample_copy(new_sample, sample), z_free(new_timestamp);
                                           z_free(new_sample));

                    entry =
                        _z_timestamp__z_sample_sortedmap_insert(&state->_pending_samples, new_timestamp, new_sample);
                    if (entry == NULL) {
                        _Z_ERROR("Failed to insert sample into timestamped state");
                        z_free(new_timestamp);
                        z_free(new_sample);
                        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                    }
                }
                // _history_depth = 0 = query all history
                if (states->_history_depth > 0 &&
                    _z_timestamp__z_sample_sortedmap_len(&state->_pending_samples) >= states->_history_depth) {
                    __unsafe_ze_advanced_subscriber_flush_timestamped_source(state, states->_callback, states->_ctx);
                }
            }
        }
    } else {
        if (states->_callback != NULL) {
            states->_callback(sample, states->_ctx);
        }
    }
    return _Z_RES_OK;
}

typedef enum {
    _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_INITIAL,
    _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_SEQUENCED,
    _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_TIMESTAMPED
} _ze_advanced_subscriber_query_ctx_kind_t;

typedef struct {
    _ze_advanced_subscriber_state_rc_t _statesref;
    _ze_advanced_subscriber_query_ctx_kind_t _kind;

    union {
        z_entity_global_id_t _source_id;
        z_id_t _id;
    };
} _ze_advanced_subscriber_query_ctx_t;

static inline _ze_advanced_subscriber_query_ctx_t _ze_advanced_subscriber_query_ctx_null(void) {
    _ze_advanced_subscriber_query_ctx_t ctx = {0};
    ctx._statesref = _ze_advanced_subscriber_state_rc_null();
    return ctx;
}

void _ze_advanced_subscriber_query_reply_handler(z_loaned_reply_t *reply, void *ctx) {
    if (!z_reply_is_ok(reply)) {
        const z_loaned_reply_err_t *err = z_reply_err(reply);
        z_owned_string_t errstr;
        z_bytes_to_string(z_reply_err_payload(err), &errstr);
        _Z_ERROR("Failed to query samples: %.*s", (int)z_string_len(z_string_loan(&errstr)),
                 z_string_data(z_string_loan(&errstr)));
        z_string_drop(z_string_move(&errstr));
        return;
    }

    _ze_advanced_subscriber_query_ctx_t *query_ctx = (_ze_advanced_subscriber_query_ctx_t *)ctx;

    if (!_Z_RC_IS_NULL(&query_ctx->_statesref)) {
        _ze_advanced_subscriber_state_t *states = _Z_RC_IN_VAL(&query_ctx->_statesref);

        const z_loaned_sample_t *sample = z_reply_ok(reply);
        const z_loaned_keyexpr_t *keyexpr = z_sample_keyexpr(sample);

        if (z_keyexpr_intersects(z_keyexpr_loan(&states->_keyexpr), keyexpr)) {
            if (_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states) != _Z_RES_OK) {
                _Z_WARN("Failed to lock mutex for query reply handling");
                return;
            }
            z_owned_sample_t sample_copy;
            if (z_sample_clone(&sample_copy, sample) == _Z_RES_OK) {
                bool new_source = false;
                z_result_t ret =
                    __unsafe_ze_advanced_subscriber_handle_sample(states, z_sample_loan_mut(&sample_copy), &new_source);
                if (ret != _Z_RES_OK) {
                    _Z_ERROR("Failed to handle sample: %i", ret);
                }
                z_sample_drop(z_sample_move(&sample_copy));
            } else {
                _Z_ERROR("Failed to clone sample for query reply handling");
            }
            _ze_advanced_subscriber_state_unlock_mutex(states);
        }
    }
}

// Forward declaration
static z_result_t __unsafe_ze_advanced_subscriber_spawn_periodic_query(_ze_advanced_subscriber_sequenced_state_t *state,
                                                                       _ze_advanced_subscriber_state_rc_t *states_rc,
                                                                       const z_entity_global_id_t *source_id);

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
void __unsafe_ze_advanced_subscriber_initial_query_drop_handler(_ze_advanced_subscriber_state_t *states,
                                                                _ze_advanced_subscriber_state_rc_t *rc_states) {
    states->_global_pending_queries = (states->_global_pending_queries > 0) ? (states->_global_pending_queries - 1) : 0;
    if (states->_global_pending_queries == 0) {
        for (_z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_iterator_t it =
                 _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_iterator_make(
                     &states->_sequenced_states);
             _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_iterator_next(&it);) {
            _z_entity_global_id_t *source_id =
                _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_iterator_key(&it);
            _ze_advanced_subscriber_sequenced_state_t *sequenced_state =
                _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_iterator_value(&it);

            __unsafe_ze_advanced_subscriber_flush_sequenced_source(sequenced_state, states->_callback, states->_ctx,
                                                                   source_id, &states->_miss_handlers);

            if (_z_fut_handle_is_null(sequenced_state->_periodic_query_handle)) {
                __unsafe_ze_advanced_subscriber_spawn_periodic_query(sequenced_state, rc_states, source_id);
            }
        }
        for (_z_id__ze_advanced_subscriber_timestamped_state_hashmap_iterator_t it =
                 _z_id__ze_advanced_subscriber_timestamped_state_hashmap_iterator_make(&states->_timestamped_states);
             _z_id__ze_advanced_subscriber_timestamped_state_hashmap_iterator_next(&it);) {
            _ze_advanced_subscriber_timestamped_state_t *timestamped_state =
                _z_id__ze_advanced_subscriber_timestamped_state_hashmap_iterator_value(&it);

            __unsafe_ze_advanced_subscriber_flush_timestamped_source(timestamped_state, states->_callback,
                                                                     states->_ctx);
        }
    }
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
void __unsafe_ze_advanced_subscriber_sequenced_query_drop_handler(_ze_advanced_subscriber_state_t *states,
                                                                  const z_entity_global_id_t *source_id) {
    _ze_advanced_subscriber_sequenced_state_t *state =
        _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states, source_id);
    if (state != NULL) {
        state->_pending_queries = (state->_pending_queries > 0) ? (state->_pending_queries - 1) : 0;
        if (states->_global_pending_queries == 0) {
            __unsafe_ze_advanced_subscriber_flush_sequenced_source(state, states->_callback, states->_ctx, source_id,
                                                                   &states->_miss_handlers);
        }
    }
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
void __unsafe_ze_advanced_subscriber_timestamped_query_drop_handler(_ze_advanced_subscriber_state_t *states,
                                                                    const z_id_t *id) {
    _ze_advanced_subscriber_timestamped_state_t *state =
        _z_id__ze_advanced_subscriber_timestamped_state_hashmap_get(&states->_timestamped_states, id);
    if (state != NULL) {
        state->_pending_queries = (state->_pending_queries > 0) ? (state->_pending_queries - 1) : 0;
        if (states->_global_pending_queries == 0) {
            __unsafe_ze_advanced_subscriber_flush_timestamped_source(state, states->_callback, states->_ctx);
        }
    }
}

void _ze_advanced_subscriber_query_drop_handler(void *ctx) {
    _ze_advanced_subscriber_query_ctx_t *query_ctx = (_ze_advanced_subscriber_query_ctx_t *)ctx;

    if (!_Z_RC_IS_NULL(&query_ctx->_statesref)) {
        _ze_advanced_subscriber_state_t *states = _Z_RC_IN_VAL(&query_ctx->_statesref);
#if Z_FEATURE_MULTI_THREAD == 1
        if (z_mutex_lock(z_mutex_loan_mut(&states->_mutex)) == _Z_RES_OK) {
#endif
            switch (query_ctx->_kind) {
                case _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_INITIAL:
                    __unsafe_ze_advanced_subscriber_initial_query_drop_handler(states, &query_ctx->_statesref);
                    break;
                case _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_SEQUENCED:
                    __unsafe_ze_advanced_subscriber_sequenced_query_drop_handler(states, &query_ctx->_source_id);
                    break;
                case _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_TIMESTAMPED:
                    __unsafe_ze_advanced_subscriber_timestamped_query_drop_handler(states, &query_ctx->_id);
                    break;
                default:
                    _Z_ERROR("Drop handler called for unknown query kind.");
            };
#if Z_FEATURE_MULTI_THREAD == 1
            z_mutex_unlock(z_mutex_loan_mut(&states->_mutex));
        }
#endif
        _ze_advanced_subscriber_state_rc_drop(&query_ctx->_statesref);
    }
    z_free(ctx);
}

static z_result_t _ze_advanced_subscriber_run_query(_ze_advanced_subscriber_query_ctx_t *ctx,
                                                    _ze_advanced_subscriber_state_rc_t *rc_state,
                                                    const z_loaned_keyexpr_t *keyexpr, const char *params) {
    if (_Z_RC_IS_NULL(rc_state)) {
        _Z_ERROR("Failed to run query - state is NULL");
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }

    _ze_advanced_subscriber_state_t *state = _Z_RC_IN_VAL(rc_state);
    _Z_RETURN_IF_ERR(_ze_advanced_subscriber_state_rc_copy(&ctx->_statesref, rc_state));

    z_owned_closure_reply_t callback;
    z_closure_reply(&callback, _ze_advanced_subscriber_query_reply_handler, _ze_advanced_subscriber_query_drop_handler,
                    ctx);

    z_get_options_t get_opts;
    z_get_options_default(&get_opts);
    get_opts.consolidation.mode = Z_CONSOLIDATION_MODE_NONE;
    get_opts.target = Z_QUERY_TARGET_ALL;
    get_opts.timeout_ms = state->_query_timeout;
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&state->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        _ze_advanced_subscriber_state_rc_drop(&ctx->_statesref);
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }

    z_owned_cancellation_token_t ct;
    _Z_CLEAN_RETURN_IF_ERR(z_cancellation_token_clone(&ct, z_cancellation_token_loan(&state->_cancellation_token)),
                           _z_session_rc_drop(&sess_rc);
                           _ze_advanced_subscriber_state_rc_drop(&ctx->_statesref));
    get_opts.cancellation_token = z_cancellation_token_move(&ct);
    z_result_t ret = z_get(&sess_rc, keyexpr, params, z_closure_reply_move(&callback), &get_opts);
    _z_session_rc_drop(&sess_rc);
    return ret;
}

static inline z_result_t _ze_advanced_subscriber_initial_query(_ze_advanced_subscriber_state_rc_t *state,
                                                               const z_loaned_keyexpr_t *keyexpr, const char *params) {
    _ze_advanced_subscriber_query_ctx_t *ctx = z_malloc(sizeof(_ze_advanced_subscriber_query_ctx_t));
    if (ctx == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    *ctx = _ze_advanced_subscriber_query_ctx_null();
    ctx->_kind = _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_INITIAL;
    _Z_CLEAN_RETURN_IF_ERR(_ze_advanced_subscriber_run_query(ctx, state, keyexpr, params), z_free(ctx));
    return _Z_RES_OK;
}

static inline z_result_t _ze_advanced_subscriber_sequenced_query(_ze_advanced_subscriber_state_rc_t *state,
                                                                 const z_loaned_keyexpr_t *keyexpr, const char *params,
                                                                 const z_entity_global_id_t *source_id) {
    _ze_advanced_subscriber_query_ctx_t *ctx = z_malloc(sizeof(_ze_advanced_subscriber_query_ctx_t));
    if (ctx == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    *ctx = _ze_advanced_subscriber_query_ctx_null();
    ctx->_kind = _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_SEQUENCED;
    ctx->_source_id = *source_id;
    _Z_CLEAN_RETURN_IF_ERR(_ze_advanced_subscriber_run_query(ctx, state, keyexpr, params), z_free(ctx));
    return _Z_RES_OK;
}

static inline z_result_t _ze_advanced_subscriber_timestamped_query(_ze_advanced_subscriber_state_rc_t *state,
                                                                   const z_loaned_keyexpr_t *keyexpr,
                                                                   const char *params, const z_id_t *id) {
    _ze_advanced_subscriber_query_ctx_t *ctx = z_malloc(sizeof(_ze_advanced_subscriber_query_ctx_t));
    if (ctx == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    *ctx = _ze_advanced_subscriber_query_ctx_null();
    ctx->_kind = _ZE_ADVANCED_SUBSCRIBER_QUERY_CTX_TIMESTAMPED;
    ctx->_id = *id;
    _Z_CLEAN_RETURN_IF_ERR(_ze_advanced_subscriber_run_query(ctx, state, keyexpr, params), z_free(ctx));
    return _Z_RES_OK;
}

typedef struct {
    z_entity_global_id_t source_id;
    _ze_advanced_subscriber_state_rc_t _statesref;
    _z_sync_group_notifier_t _task_finished_notifier;
} _ze_advanced_subscriber_periodic_query_ctx_t;

_ze_advanced_subscriber_periodic_query_ctx_t _ze_advanced_subscriber_periodic_query_ctx_null(void) {
    _ze_advanced_subscriber_periodic_query_ctx_t ctx = {0};
    return ctx;
}

void _ze_advanced_subscriber_periodic_query_ctx_drop(_ze_advanced_subscriber_periodic_query_ctx_t *ctx) {
    if (ctx == NULL) {
        return;
    }
    _ze_advanced_subscriber_state_rc_drop(&ctx->_statesref);
    _z_sync_group_notifier_drop(&ctx->_task_finished_notifier);
}

void _ze_advanced_subscriber_periodic_query_ctx_free(_ze_advanced_subscriber_periodic_query_ctx_t **ctx) {
    if (ctx == NULL) {
        return;
    }
    _ze_advanced_subscriber_periodic_query_ctx_drop(*ctx);
    z_free(*ctx);
    *ctx = NULL;
}

static _z_fut_fn_result_t _ze_advanced_subscriber_periodic_query_handler(void *ctx, _z_executor_t *executor) {
    _ZP_UNUSED(executor);
    _ze_advanced_subscriber_periodic_query_ctx_t *query_ctx = (_ze_advanced_subscriber_periodic_query_ctx_t *)ctx;
    if (_Z_RC_IS_NULL(&query_ctx->_statesref)) {
        return _z_fut_fn_result_ready();
    }
    _ze_advanced_subscriber_state_t *states = _Z_RC_IN_VAL(&query_ctx->_statesref);

    z_result_t res = _ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states);
    if (res != _Z_RES_OK) {
        _Z_WARN("Failed to lock mutex when running periodic query: %d", res);
        return _z_fut_fn_result_ready();
    }

    // Global history still running? Don’t schedule a per-source query yet.
    if (states->_global_pending_queries != 0) {
        _ze_advanced_subscriber_state_unlock_mutex(states);
        return _z_fut_fn_result_wake_up_after(states->_period_ms);
    }

    _ze_advanced_subscriber_sequenced_state_t *state =
        _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states,
                                                                                &query_ctx->source_id);
    if (state == NULL) {
        _ze_advanced_subscriber_state_unlock_mutex(states);
        return _z_fut_fn_result_wake_up_after(states->_period_ms);
    }

    // Don’t pile up queries; wait until the previous one finishes.
    if (state->_pending_queries != 0) {
        // Nothing to do this tick.
        _ze_advanced_subscriber_state_unlock_mutex(states);
        return _z_fut_fn_result_wake_up_after(states->_period_ms);
    }

    char params[ZE_ADVANCED_SUBSCRIBER_QUERY_PARAM_BUF_SIZE];
    _z_query_param_range_t range = {
        ._has_start = state->_has_last_delivered,
        ._start = state->_has_last_delivered ? _z_seqnumber_next(state->_last_delivered) : 0u,
        ._has_end = false,
        ._end = 0};

    if (!_ze_advanced_subscriber_populate_query_params(params, sizeof(params), 0, 0, &range)) {
        _ze_advanced_subscriber_state_unlock_mutex(states);
        _Z_WARN("Failed to prepare periodic query");
        return _z_fut_fn_result_ready();
    }

    state->_pending_queries++;

    _ze_advanced_subscriber_state_unlock_mutex(states);
    res = _ze_advanced_subscriber_sequenced_query(&query_ctx->_statesref, z_keyexpr_loan(&state->_query_keyexpr),
                                                  params, &query_ctx->source_id);
    if (res != _Z_RES_OK) {
        _Z_WARN("Failed to run periodic query");
        res = _ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states);
        if (res != _Z_RES_OK) {
            _Z_WARN("Failed to lock mutex for periodic query failure (%d)", res);
            return _z_fut_fn_result_ready();
        }
        state = _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states,
                                                                                        &query_ctx->source_id);
        if (state != NULL) {
            state->_pending_queries--;
        }
        _ze_advanced_subscriber_state_unlock_mutex(states);
    }
    return _z_fut_fn_result_wake_up_after(states->_period_ms);
}

static void _ze_advanced_subscriber_periodic_query_dropper(void *ctx) {
    _ze_advanced_subscriber_periodic_query_ctx_t *query_ctx = (_ze_advanced_subscriber_periodic_query_ctx_t *)ctx;
    _ze_advanced_subscriber_periodic_query_ctx_free(&query_ctx);
}

// SAFETY: Must be called with _ze_advanced_subscriber_state_t mutex locked
static z_result_t __unsafe_ze_advanced_subscriber_spawn_periodic_query(_ze_advanced_subscriber_sequenced_state_t *state,
                                                                       _ze_advanced_subscriber_state_rc_t *rc_states,
                                                                       const z_entity_global_id_t *source_id) {
    if (_Z_RC_IS_NULL(rc_states)) {
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }

    _ze_advanced_subscriber_state_t *states = _Z_RC_IN_VAL(rc_states);

    // Don’t schedule while already running or while a global history query is pending.
    if (!_z_fut_handle_is_null(state->_periodic_query_handle) || states->_global_pending_queries != 0) {
        return _Z_RES_OK;
    }

    // Don't post periodic query if period is not set
    if (!states->_has_period) {
        return _Z_RES_OK;
    }
    _z_sync_group_notifier_t notifier;
    _Z_RETURN_IF_ERR(_z_cancellation_token_get_notifier(
        z_cancellation_token_loan_mut(&states->_cancellation_token)->_val, &notifier));

    _ze_advanced_subscriber_periodic_query_ctx_t *ctx = z_malloc(sizeof(_ze_advanced_subscriber_periodic_query_ctx_t));
    if (ctx == NULL) {
        _z_sync_group_notifier_drop(&notifier);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    *ctx = _ze_advanced_subscriber_periodic_query_ctx_null();
    ctx->source_id = *source_id;
    ctx->_statesref = _ze_advanced_subscriber_state_rc_clone(rc_states);
    ctx->_task_finished_notifier = notifier;
    if (_Z_RC_IS_NULL(&ctx->_statesref)) {
        _ze_advanced_subscriber_periodic_query_ctx_free(&ctx);
        _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }

#if Z_FEATURE_SESSION_CHECK == 1
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&states->_zn);
#else
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&states->_zn);
#endif
    if (_Z_RC_IS_NULL(&sess_rc)) {
        _ze_advanced_subscriber_periodic_query_ctx_free(&ctx);
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }

    _z_fut_t fut = _z_fut_null();
    fut._fut_arg = ctx;
    fut._fut_fn = _ze_advanced_subscriber_periodic_query_handler;
    fut._destroy_fn = _ze_advanced_subscriber_periodic_query_dropper;
    state->_periodic_query_handle = _z_runtime_spawn(&_Z_RC_IN_VAL(&sess_rc)->_runtime, &fut);
    _z_session_rc_drop(&sess_rc);
    if (_z_fut_handle_is_null(state->_periodic_query_handle)) {
        _Z_ERROR_RETURN(_Z_ERR_FAILED_TO_SPAWN_TASK);
    }
    return _Z_RES_OK;
}

void _ze_advanced_subscriber_subscriber_callback(z_loaned_sample_t *sample, void *ctx) {
    _ze_advanced_subscriber_state_rc_t *rc_states = (_ze_advanced_subscriber_state_rc_t *)ctx;
    if (_Z_RC_IS_NULL(rc_states)) {
        return;
    }

    _ze_advanced_subscriber_state_t *states = _Z_RC_IN_VAL(rc_states);
    if (_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states) != _Z_RES_OK) {
        _Z_WARN("Failed to lock subscriber callback mutex");
        return;
    }

    bool new_source = false;
    z_result_t ret = __unsafe_ze_advanced_subscriber_handle_sample(states, sample, &new_source);
    if (ret != _Z_RES_OK) {
        _ze_advanced_subscriber_state_unlock_mutex(states);
        _Z_ERROR("Failed to handle sample in subscriber callback: %i", ret);
        return;
    }

    const z_source_info_t *source_info = z_sample_source_info(sample);
    if (source_info == NULL) {
        _ze_advanced_subscriber_state_unlock_mutex(states);
        return;
    }
    z_entity_global_id_t source_id = z_source_info_id(source_info);

    _ze_advanced_subscriber_sequenced_state_t *state =
        _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states, &source_id);
    if (state != NULL && new_source) {
        __unsafe_ze_advanced_subscriber_spawn_periodic_query(state, rc_states, &source_id);
    }
    if (state != NULL && states->_retransmission && state->_pending_queries == 0 &&
        !_z_uint32__z_sample_sortedmap_is_empty(&state->_pending_samples)) {
        char params[ZE_ADVANCED_SUBSCRIBER_QUERY_PARAM_BUF_SIZE];
        _z_query_param_range_t range = {
            ._has_start = state->_has_last_delivered,
            ._start = state->_has_last_delivered ? _z_seqnumber_next(state->_last_delivered) : 0u,
            ._has_end = false,
            ._end = 0};

        if (!_ze_advanced_subscriber_populate_query_params(params, sizeof(params), 0, 0, &range)) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to prepare query for missing samples");
            return;
        }

        state->_pending_queries++;

        _ze_advanced_subscriber_state_unlock_mutex(states);

        z_result_t res = _ze_advanced_subscriber_sequenced_query(rc_states, z_keyexpr_loan(&state->_query_keyexpr),
                                                                 params, &source_id);
        if (res != _Z_RES_OK) {
            _Z_ERROR("Failed to query for missing samples");
            if (_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states) != _Z_RES_OK) {
                _Z_WARN("Failed to lock mutex missing sample query failure (%d)", res);
                return;
            }

            state = _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states,
                                                                                            &source_id);
            if (state != NULL) {
                state->_pending_queries--;
            }

            _ze_advanced_subscriber_state_unlock_mutex(states);
        }
        return;
    }
    _ze_advanced_subscriber_state_unlock_mutex(states);
}

void _ze_advanced_subscriber_subscriber_drop_handler(void *ctx) {
    _ze_advanced_subscriber_state_rc_t *rc_state = (_ze_advanced_subscriber_state_rc_t *)ctx;
    if (!_Z_RC_IS_NULL(rc_state)) {
        _ze_advanced_subscriber_state_t *state = _Z_RC_IN_VAL(rc_state);
        if (state->_dropper != NULL) {
            state->_dropper(state->_ctx);
        }
        if (_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(state) != _Z_RES_OK) {
            _Z_WARN("Failed to lock mutex for subscriber drop handler");
            return;
        }
        // signal undeclaring state to prevent new queries or miss handlers from being added
        state->_is_undeclaring = true;
        // clear miss handlers to release user callbacks
        _ze_closure_miss_intmap_clear(&state->_miss_handlers);
        // clear sequenced state to remove any periodic query tasks
        _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_clear(&state->_sequenced_states);
        _z_id__ze_advanced_subscriber_timestamped_state_hashmap_clear(&state->_timestamped_states);
        _ze_advanced_subscriber_state_unlock_mutex(state);
        if (z_internal_cancellation_token_check(&state->_cancellation_token)) {
            z_cancellation_token_cancel(z_cancellation_token_loan_mut(&state->_cancellation_token));
        }

        _ze_advanced_subscriber_state_rc_drop(rc_state);
        z_free(ctx);
    }
}

static bool _ze_advanced_subscriber_parse_liveliness_keyexpr_u32(const char *start, size_t len, uint32_t *out) {
    if (start == NULL || len == 0 || len >= 11 || out == NULL) {
        return false;  // 10 digits max + '\0'
    }

    char buf[ZE_ADVANCED_SUBSCRIBER_UINT32_STR_BUF_LEN];
    if (!_z_memcpy_checked(buf, sizeof(buf) - 1, NULL, start, len)) {
        return false;
    }
    buf[len] = '\0';

    char *endptr = NULL;
    unsigned long val = strtoul(buf, &endptr, 10);

    // Reject if not fully parsed or value is out of uint32_t range
    if (endptr == buf || *endptr != '\0' || val > UINT32_MAX) {
        return false;
    }

    *out = (uint32_t)val;
    return true;
}

#define _ZE_ADVANCED_SUBSCRIBER_UHLC_EID 0

// suffix = _Z_KEYEXPR_ADV_PREFIX / Entity Type / ZID / [ EID | _Z_KEYEXPR_UHLC ] / [ meta | _Z_KEYEXPR_EMPTY ]
// On successful return id will be populated with the publishers ZID and either the EID or 0 for _Z_KEYEXPR_UHLC
static bool _ze_advanced_subscriber_parse_liveliness_keyexpr(const z_loaned_keyexpr_t *ke, _z_entity_global_id_t *id) {
    z_view_string_t view;
    if (z_keyexpr_as_view_string(ke, &view) != _Z_RES_OK) {
        return false;
    }

    _z_str_se_t str;
    str.start = z_string_data(z_view_string_loan(&view));
    str.end = str.start + z_string_len(z_view_string_loan(&view));

    _z_splitstr_t segments = {.s = str, .delimiter = "/"};
    int segment_cnt = 0;
    while (segments.s.end != NULL && segment_cnt < 5) {
        _z_str_se_t segment = _z_splitstr_nextback(&segments);

        if (segment.start != NULL) {
            segment_cnt++;
            size_t segment_len = (size_t)(segment.end - segment.start);
            switch (segment_cnt) {
                case 2: {
                    // EID | _Z_KEYEXPR_UHLC
                    if ((segment_len == _Z_KEYEXPR_UHLC_LEN &&
                         strncmp(segment.start, _Z_KEYEXPR_UHLC, _Z_KEYEXPR_UHLC_LEN) == 0)) {
                        id->eid = _ZE_ADVANCED_SUBSCRIBER_UHLC_EID;
                    } else if (!_ze_advanced_subscriber_parse_liveliness_keyexpr_u32(segment.start, segment_len,
                                                                                     &id->eid) ||
                               id->eid == 0) {
                        // Invalid EID
                        *id = _z_entity_global_id_null();
                        _Z_TRACE("Received liveliness key expression with invalid EID");
                        return false;
                    }
                    break;
                }
                case 3: {
                    // ZID
                    _z_string_t zid_str = _z_string_alias_substr(segment.start, segment_len);
                    id->zid = _z_id_from_string(&zid_str);
                    if (!_z_id_check(id->zid)) {
                        // Invalid Zenoh ID
                        *id = _z_entity_global_id_null();
                        _Z_TRACE("Received liveliness key expression with invalid ZID");
                        return false;
                    }
                    break;
                }
                case 5: {
                    // _Z_KEYEXPR_ADV_PREFIX
                    if (segment_len != _Z_KEYEXPR_ADV_PREFIX_LEN ||
                        strncmp(segment.start, _Z_KEYEXPR_ADV_PREFIX, _Z_KEYEXPR_ADV_PREFIX_LEN) != 0) {
                        *id = _z_entity_global_id_null();
                        _Z_TRACE("Received liveliness key expression with invalid segment");
                        return false;
                    }
                    break;
                }
            }
        }
    }
    // Validate segment count
    if (segment_cnt < 5) {
        *id = _z_entity_global_id_null();
        return false;
    }
    return true;
}

void _ze_advanced_subscriber_liveliness_callback(z_loaned_sample_t *sample, void *ctx) {
    if (z_sample_kind(sample) != Z_SAMPLE_KIND_PUT) {
        return;
    }

    _ze_advanced_subscriber_state_rc_t *rc_states = (_ze_advanced_subscriber_state_rc_t *)ctx;
    if (_Z_RC_IS_NULL(rc_states)) {
        _Z_ERROR("Liveliness subscriber callback called with NULL state reference");
        return;
    }
    _ze_advanced_subscriber_state_t *states = _Z_RC_IN_VAL(rc_states);

    const z_loaned_keyexpr_t *ke = z_sample_keyexpr(sample);
    z_entity_global_id_t id = _z_entity_global_id_null();
    // Parse key expression to extract ZID and EID
    if (!_ze_advanced_subscriber_parse_liveliness_keyexpr(ke, &id)) {
        z_view_string_t kestr;
        z_keyexpr_as_view_string(ke, &kestr);
        _Z_WARN("Received malformed liveliness token key expression: '%.*s'\n",
                (int)z_string_len(z_view_string_loan(&kestr)), z_string_data(z_view_string_loan(&kestr)));
        return;
    }

    if (id.eid == _ZE_ADVANCED_SUBSCRIBER_UHLC_EID) {
        if (_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states) != _Z_RES_OK) {
            _Z_WARN("Failed to lock liveliness subscriber callback mutex");
            return;
        }

        _ze_advanced_subscriber_timestamped_state_t *state =
            _z_id__ze_advanced_subscriber_timestamped_state_hashmap_get(&states->_timestamped_states, &id.zid);
        if (state == NULL) {
            z_id_t *new_zid = z_malloc(sizeof(z_id_t));
            if (new_zid == NULL) {
                _Z_ERROR("Failed to allocate memory for new timestamped state ID");
                _ze_advanced_subscriber_state_unlock_mutex(states);
                return;
            }
            *new_zid = id.zid;
            _ze_advanced_subscriber_timestamped_state_t *new_state =
                z_malloc(sizeof(_ze_advanced_subscriber_timestamped_state_t));
            if (new_state == NULL) {
                _Z_ERROR("Failed to allocate memory for new timestamped state");
                _ze_advanced_subscriber_state_unlock_mutex(states);
                z_free(new_zid);
                return;
            }
            _ze_advanced_subscriber_timestamped_state_init(new_state);
            state = _z_id__ze_advanced_subscriber_timestamped_state_hashmap_insert(&states->_timestamped_states,
                                                                                   new_zid, new_state);
            if (state == NULL) {
                _Z_ERROR("Failed to insert new timestamped state into hashmap");
                _ze_advanced_subscriber_state_unlock_mutex(states);
                z_free(new_zid);
                z_free(new_state);
                return;
            }
        }

        char params[ZE_ADVANCED_SUBSCRIBER_QUERY_PARAM_BUF_SIZE];
        if (!_ze_advanced_subscriber_populate_query_params(params, sizeof(params), states->_history_depth,
                                                           states->_history_age, NULL)) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to prepare query for timestamped samples");
            return;
        }

        state->_pending_queries++;

        _ze_advanced_subscriber_state_unlock_mutex(states);
        if (_ze_advanced_subscriber_timestamped_query(rc_states, ke, params, &id.zid) != _Z_RES_OK) {
            _Z_ERROR("Failed to query for timestamped samples");
            z_result_t res = _ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states);
            if (res != _Z_RES_OK) {
                _Z_WARN("Failed to lock mutex to relock mutex after timestamped sample query failure (%d)", res);
                return;
            }

            state = _z_id__ze_advanced_subscriber_timestamped_state_hashmap_get(&states->_timestamped_states, &id.zid);
            if (state != NULL) {
                state->_pending_queries--;
            }

            _ze_advanced_subscriber_state_unlock_mutex(states);
        }
        return;
    } else {
        if (_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states) != _Z_RES_OK) {
            _Z_WARN("Failed to lock mutex when processing liveliness subscriber callback");
            return;
        }

        _ze_advanced_subscriber_sequenced_state_t *state =
            _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states, &id);
        bool new_source = false;
        if (state == NULL) {
            new_source = true;

            z_entity_global_id_t *new_id = z_malloc(sizeof(z_entity_global_id_t));
            if (new_id == NULL) {
                _Z_ERROR("Failed to allocate memory for new sequenced state ID");
                _ze_advanced_subscriber_state_unlock_mutex(states);
                return;
            }
            *new_id = id;

            _ze_advanced_subscriber_sequenced_state_t *new_state =
                z_malloc(sizeof(_ze_advanced_subscriber_sequenced_state_t));
            if (new_state == NULL) {
                _Z_ERROR("Failed to allocate memory for new sequenced state");
                _ze_advanced_subscriber_state_unlock_mutex(states);
                z_free(new_id);
                return;
            }
            if (_ze_advanced_subscriber_sequenced_state_init(new_state, &states->_zn, z_keyexpr_loan(&states->_keyexpr),
                                                             &id) != _Z_RES_OK) {
                _Z_ERROR("Failed to initialize new sequenced state");
                _ze_advanced_subscriber_state_unlock_mutex(states);
                z_free(new_id);
                z_free(new_state);
                return;
            }
            state = _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_insert(
                &states->_sequenced_states, new_id, new_state);
            if (state == NULL) {
                _Z_ERROR("Failed to insert new sequenced state into hashmap");
                _ze_advanced_subscriber_state_unlock_mutex(states);
                z_free(new_id);
                z_free(new_state);
                return;
            }
        }

        char params[ZE_ADVANCED_SUBSCRIBER_QUERY_PARAM_BUF_SIZE];
        if (!_ze_advanced_subscriber_populate_query_params(params, sizeof(params), states->_history_depth,
                                                           states->_history_age, NULL)) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to prepare query for sequenced samples");
            return;
        }

        if (state != NULL && new_source) {
            __unsafe_ze_advanced_subscriber_spawn_periodic_query(state, rc_states, &id);
        }

        state->_pending_queries++;

        _ze_advanced_subscriber_state_unlock_mutex(states);
        z_result_t res =
            _ze_advanced_subscriber_sequenced_query(rc_states, z_keyexpr_loan(&state->_query_keyexpr), params, &id);
        if (res != _Z_RES_OK) {
            _Z_ERROR("Failed to query for sequenced samples");
            res = _ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states);
            if (res != _Z_RES_OK) {
                _Z_WARN("Failed to relock mutex after sequenced sample query failure (%d)", res);
                return;
            }
            state = _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states,
                                                                                            &id);
            if (state != NULL) {
                state->_pending_queries--;
            }
            _ze_advanced_subscriber_state_unlock_mutex(states);
        }
        return;
    }
}

void _ze_advanced_subscriber_liveliness_drop_handler(void *ctx) {
    _ze_advanced_subscriber_state_rc_t *rc_state = (_ze_advanced_subscriber_state_rc_t *)ctx;
    if (!_Z_RC_IS_NULL(rc_state)) {
        _ze_advanced_subscriber_state_rc_drop(rc_state);
        z_free(ctx);
    }
}

void _ze_advanced_subscriber_heartbeat_callback(z_loaned_sample_t *sample, void *ctx) {
    if (z_sample_kind(sample) != Z_SAMPLE_KIND_PUT) {
        return;
    }

    _ze_advanced_subscriber_state_rc_t *rc_states = (_ze_advanced_subscriber_state_rc_t *)ctx;
    if (_Z_RC_IS_NULL(rc_states)) {
        _Z_ERROR("Heartbeat subscriber callback called with NULL state reference");
        return;
    }
    _ze_advanced_subscriber_state_t *states = _Z_RC_IN_VAL(rc_states);

    const z_loaned_keyexpr_t *ke = z_sample_keyexpr(sample);
    z_entity_global_id_t id = _z_entity_global_id_null();
    // Parse key expression to extract ZID and EID
    if (!_ze_advanced_subscriber_parse_liveliness_keyexpr(ke, &id)) {
        z_view_string_t kestr;
        z_keyexpr_as_view_string(ke, &kestr);
        _Z_WARN("Received malformed heartbeat key expression: '%.*s'\n", (int)z_string_len(z_view_string_loan(&kestr)),
                z_string_data(z_view_string_loan(&kestr)));
        return;
    }

    const z_loaned_bytes_t *payload = z_sample_payload(sample);
    if (payload == NULL) {
        _Z_WARN("Received heartbeat with no payload");
        return;
    }
    if (z_bytes_len(payload) < 4) {
        _Z_WARN("Received heartbeat with invalid payload length: %zu", z_bytes_len(payload));
        return;
    }

    ze_deserializer_t deserializer = ze_deserializer_from_bytes(payload);
    uint32_t heartbeat_sn;
    if (ze_deserializer_deserialize_uint32(&deserializer, &heartbeat_sn) != _Z_RES_OK) {
        _Z_WARN("Failed to deserialize heartbeat sequence number");
        return;
    }
    if (!ze_deserializer_is_done(&deserializer)) {
        _Z_WARN("Heartbeat payload contains unexpected data after sequence number");
        return;
    }

    if (_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states) != _Z_RES_OK) {
        _Z_WARN("Failed to lock heartbeat subscriber callback mutex");
        return;
    }

    _ze_advanced_subscriber_sequenced_state_t *state =
        _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states, &id);
    if (state == NULL) {
        if (states->_global_pending_queries > 0) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_TRACE("Skipping heartbeat due to pending global query");
            return;
        }

        z_entity_global_id_t *new_id = z_malloc(sizeof(z_entity_global_id_t));
        if (new_id == NULL) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to allocate memory for new sequenced state ID");
            return;
        }
        *new_id = id;

        _ze_advanced_subscriber_sequenced_state_t *new_state =
            z_malloc(sizeof(_ze_advanced_subscriber_sequenced_state_t));
        if (new_state == NULL) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to allocate memory for new sequenced state");
            z_free(new_id);
            return;
        }
        z_result_t res = _ze_advanced_subscriber_sequenced_state_init(new_state, &states->_zn,
                                                                      z_keyexpr_loan(&states->_keyexpr), &id);
        if (res != _Z_RES_OK) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to initialize new sequenced state: %i", res);
            z_free(new_id);
            z_free(new_state);
            return;
        }
        state = _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_insert(&states->_sequenced_states,
                                                                                           new_id, new_state);
        if (state == NULL) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to insert new sequenced state into hashmap");
            z_free(new_id);
            z_free(new_state);
            return;
        }
    }

    if (!state->_has_last_delivered ||
        (_z_seqnumber_diff(heartbeat_sn, state->_last_delivered) > 0 && state->_pending_queries == 0)) {
        char params[ZE_ADVANCED_SUBSCRIBER_QUERY_PARAM_BUF_SIZE];
        _z_query_param_range_t range = {
            ._has_start = state->_has_last_delivered,
            ._start = state->_has_last_delivered ? _z_seqnumber_next(state->_last_delivered) : 0u,
            ._has_end = true,
            ._end = heartbeat_sn};

        if (!_ze_advanced_subscriber_populate_query_params(params, sizeof(params), 0, 0, &range)) {
            _ze_advanced_subscriber_state_unlock_mutex(states);
            _Z_ERROR("Failed to prepare query for missing samples");
            return;
        }

        state->_pending_queries++;

        _ze_advanced_subscriber_state_unlock_mutex(states);
        z_result_t res =
            _ze_advanced_subscriber_sequenced_query(rc_states, z_keyexpr_loan(&state->_query_keyexpr), params, &id);
        if (res != _Z_RES_OK) {
            _Z_ERROR("Failed to query for missing samples");
            res = _ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(states);
            if (res != _Z_RES_OK) {
                _Z_WARN("failed to relock mutex after missing sample query failure (%d)", res);
                return;
            }
            state = _z_entity_global_id__ze_advanced_subscriber_sequenced_state_hashmap_get(&states->_sequenced_states,
                                                                                            &id);

            if (state != NULL) {
                state->_pending_queries--;
            }
            _ze_advanced_subscriber_state_unlock_mutex(states);
        }
        return;
    }
    _ze_advanced_subscriber_state_unlock_mutex(states);
}

void _ze_advanced_subscriber_heartbeat_drop_handler(void *ctx) {
    _ze_advanced_subscriber_state_rc_t *rc_state = (_ze_advanced_subscriber_state_rc_t *)ctx;
    if (!_Z_RC_IS_NULL(rc_state)) {
        _ze_advanced_subscriber_state_rc_drop(rc_state);
        z_free(ctx);
    }
}

// suffix = KE_ADV_PREFIX / KE_SUB / ZID / EID / [ metadata | KE_EMPTY ]
static z_result_t _ze_advanced_subscriber_ke_suffix(z_owned_keyexpr_t *suffix, const z_entity_global_id_t id,
                                                    const z_loaned_keyexpr_t *metadata) {
    z_internal_keyexpr_null(suffix);
    _Z_RETURN_IF_ERR(_Z_KEYEXPR_APPEND_STR_ARRAY(suffix, _Z_KEYEXPR_ADV_PREFIX, _Z_KEYEXPR_SUB));

    z_id_t zid = z_entity_global_id_zid(&id);
    z_owned_string_t zid_str;
    _Z_CLEAN_RETURN_IF_ERR(z_id_to_string(&zid, &zid_str), z_keyexpr_drop(z_keyexpr_move(suffix)));

    _Z_CLEAN_RETURN_IF_ERR(
        _z_keyexpr_append_substr(suffix, z_string_data(z_string_loan(&zid_str)), z_string_len(z_string_loan(&zid_str))),
        z_string_drop(z_string_move(&zid_str));
        z_keyexpr_drop(z_keyexpr_move(suffix)));
    z_string_drop(z_string_move(&zid_str));

    char buffer[ZE_ADVANCED_SUBSCRIBER_UINT32_STR_BUF_LEN];
    uint32_t eid = z_entity_global_id_eid(&id);
    snprintf(buffer, sizeof(buffer), "%u", eid);
    _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_str(suffix, buffer), z_keyexpr_drop(z_keyexpr_move(suffix)));

    if (metadata != NULL) {
        _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_suffix(suffix, metadata), z_keyexpr_drop(z_keyexpr_move(suffix)));
    } else {
        _Z_CLEAN_RETURN_IF_ERR(_z_keyexpr_append_str(suffix, _Z_KEYEXPR_EMPTY), z_keyexpr_drop(z_keyexpr_move(suffix)));
    }

    return _Z_RES_OK;
}

z_result_t ze_declare_advanced_subscriber(const z_loaned_session_t *zs, ze_owned_advanced_subscriber_t *sub,
                                          const z_loaned_keyexpr_t *keyexpr, z_moved_closure_sample_t *callback,
                                          ze_advanced_subscriber_options_t *options) {
    sub->_val = _ze_advanced_subscriber_null();

    // Set options
    ze_advanced_subscriber_options_t opt;
    ze_advanced_subscriber_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    // Create Advanced Subscriber state
    _Z_RETURN_IF_ERR(_ze_advanced_subscriber_state_new(&sub->_val._state, zs, callback, keyexpr, &opt));

    // Common keyexpr for subscribing to publisher liveliness and heartbeat
    z_owned_keyexpr_t ke_pub;
    _Z_CLEAN_RETURN_IF_ERR(z_keyexpr_clone(&ke_pub, keyexpr), _ze_advanced_subscriber_state_rc_drop(&sub->_val._state));
    _Z_CLEAN_RETURN_IF_ERR(
        _Z_KEYEXPR_APPEND_STR_ARRAY(&ke_pub, _Z_KEYEXPR_ADV_PREFIX, _Z_KEYEXPR_PUB, _Z_KEYEXPR_STARSTAR),
        z_keyexpr_drop(z_keyexpr_move(&ke_pub));
        _ze_advanced_subscriber_state_rc_drop(&sub->_val._state));

    // Declare subscriber
    _ze_advanced_subscriber_state_rc_t *sub_state = _ze_advanced_subscriber_state_rc_clone_as_ptr(&sub->_val._state);
    if (_Z_RC_IS_NULL(sub_state)) {
        _ze_advanced_subscriber_state_rc_drop(&sub->_val._state);
        z_keyexpr_drop(z_keyexpr_move(&ke_pub));
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }

    z_owned_closure_sample_t subscriber_callback;
    z_closure_sample(&subscriber_callback, _ze_advanced_subscriber_subscriber_callback,
                     _ze_advanced_subscriber_subscriber_drop_handler, sub_state);
    _Z_CLEAN_RETURN_IF_ERR(z_declare_subscriber(zs, &sub->_val._subscriber, keyexpr,
                                                z_closure_sample_move(&subscriber_callback), &opt.subscriber_options),
                           z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                           _ze_advanced_subscriber_state_rc_drop(&sub->_val._state));

    if (opt.history.is_enabled) {
        // Query initial history
        char params[ZE_ADVANCED_SUBSCRIBER_QUERY_PARAM_BUF_SIZE];
        if (!_ze_advanced_subscriber_populate_query_params(params, sizeof(params), opt.history.max_samples,
                                                           opt.history.max_age_ms, NULL)) {
            z_keyexpr_drop(z_keyexpr_move(&ke_pub));
            _ze_advanced_subscriber_undeclare(&sub->_val);
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
        }

        z_owned_keyexpr_t query_keyexpr;
        _Z_CLEAN_RETURN_IF_ERR(z_keyexpr_clone(&query_keyexpr, keyexpr), z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                               _ze_advanced_subscriber_undeclare(&sub->_val));
        _Z_CLEAN_RETURN_IF_ERR(_Z_KEYEXPR_APPEND_STR_ARRAY(&query_keyexpr, _Z_KEYEXPR_ADV_PREFIX, _Z_KEYEXPR_STARSTAR),
                               z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                               z_keyexpr_drop(z_keyexpr_move(&query_keyexpr));
                               _ze_advanced_subscriber_undeclare(&sub->_val));

        _Z_CLEAN_RETURN_IF_ERR(
            _ze_advanced_subscriber_initial_query(&sub->_val._state, z_keyexpr_loan(&query_keyexpr), params),
            z_keyexpr_drop(z_keyexpr_move(&ke_pub));
            z_keyexpr_drop(z_keyexpr_move(&query_keyexpr)); _ze_advanced_subscriber_undeclare(&sub->_val));
        z_keyexpr_drop(z_keyexpr_move(&query_keyexpr));

        // Declare liveliness subscriber on keyexpr / KE_ADV_PREFIX / KE_PUB / KE_STARSTAR
        if (opt.history.detect_late_publishers) {
            z_liveliness_subscriber_options_t liveliness_options;
            z_liveliness_subscriber_options_default(&liveliness_options);
            liveliness_options.history = true;

            _ze_advanced_subscriber_state_rc_t *liveliness_sub_state =
                _ze_advanced_subscriber_state_rc_clone_as_ptr(&sub->_val._state);
            if (_Z_RC_IS_NULL(liveliness_sub_state)) {
                z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                _ze_advanced_subscriber_undeclare(&sub->_val);
                _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            }

            z_owned_closure_sample_t liveliness_callback;
            _Z_CLEAN_RETURN_IF_ERR(
                z_closure_sample(&liveliness_callback, _ze_advanced_subscriber_liveliness_callback,
                                 _ze_advanced_subscriber_liveliness_drop_handler, liveliness_sub_state),
                _ze_advanced_subscriber_state_rc_drop(liveliness_sub_state);
                z_free(liveliness_sub_state); z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                _ze_advanced_subscriber_undeclare(&sub->_val));
            _Z_CLEAN_RETURN_IF_ERR(
                z_liveliness_declare_subscriber(zs, &sub->_val._liveliness_subscriber, z_keyexpr_loan(&ke_pub),
                                                z_closure_sample_move(&liveliness_callback), &liveliness_options),
                _ze_advanced_subscriber_state_rc_drop(liveliness_sub_state);
                z_free(liveliness_sub_state); z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                _ze_advanced_subscriber_undeclare(&sub->_val));
            sub->_val._has_liveliness_subscriber = true;
        }
    }

    // Heartbeat subscriber
    if (opt.recovery.is_enabled && opt.recovery.last_sample_miss_detection.is_enabled &&
        opt.recovery.last_sample_miss_detection.periodic_queries_period_ms == 0) {
        _ze_advanced_subscriber_state_rc_t *heartbeat_sub_state =
            _ze_advanced_subscriber_state_rc_clone_as_ptr(&sub->_val._state);
        if (_Z_RC_IS_NULL(heartbeat_sub_state)) {
            z_keyexpr_drop(z_keyexpr_move(&ke_pub));
            _ze_advanced_subscriber_undeclare(&sub->_val);
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
        }

        z_owned_closure_sample_t heartbeat_callback;
        _Z_CLEAN_RETURN_IF_ERR(z_closure_sample(&heartbeat_callback, _ze_advanced_subscriber_heartbeat_callback,
                                                _ze_advanced_subscriber_heartbeat_drop_handler, heartbeat_sub_state),
                               _ze_advanced_subscriber_state_rc_drop(heartbeat_sub_state);
                               z_free(heartbeat_sub_state); z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                               _ze_advanced_subscriber_undeclare(&sub->_val));
        _Z_CLEAN_RETURN_IF_ERR(z_declare_subscriber(zs, &sub->_val._heartbeat_subscriber, z_keyexpr_loan(&ke_pub),
                                                    z_closure_sample_move(&heartbeat_callback), NULL),
                               _ze_advanced_subscriber_state_rc_drop(heartbeat_sub_state);
                               z_free(heartbeat_sub_state); z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                               _ze_advanced_subscriber_undeclare(&sub->_val));
        sub->_val._has_heartbeat_subscriber = true;
    }

    // Declare liveliness token on keyexpr/suffix
    if (opt.subscriber_detection) {
        _ze_advanced_subscriber_state_t *state = _Z_RC_IN_VAL(&sub->_val._state);

        z_entity_global_id_t id = z_subscriber_id(z_subscriber_loan(&sub->_val._subscriber));
        z_owned_keyexpr_t suffix;
        _Z_CLEAN_RETURN_IF_ERR(_ze_advanced_subscriber_ke_suffix(&suffix, id, opt.subscriber_detection_metadata),
                               z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                               _ze_advanced_subscriber_undeclare(&sub->_val));
        z_owned_keyexpr_t ke;
        _Z_CLEAN_RETURN_IF_ERR(z_keyexpr_join(&ke, keyexpr, z_keyexpr_loan(&suffix)),
                               z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                               z_keyexpr_drop(z_keyexpr_move(&suffix)); _ze_advanced_subscriber_undeclare(&sub->_val));

#if Z_FEATURE_MULTI_THREAD == 1
        _Z_CLEAN_RETURN_IF_ERR(z_mutex_lock(z_mutex_loan_mut(&state->_mutex)), z_keyexpr_drop(z_keyexpr_move(&ke_pub));
                               z_keyexpr_drop(z_keyexpr_move(&suffix)); z_keyexpr_drop(z_keyexpr_move(&ke));
                               _ze_advanced_subscriber_undeclare(&sub->_val));
#endif

        z_result_t res = z_liveliness_declare_token(zs, &state->_token, z_keyexpr_loan(&ke), NULL);
        if (res != _Z_RES_OK) {
#if Z_FEATURE_MULTI_THREAD == 1
            z_mutex_unlock(z_mutex_loan_mut(&state->_mutex));
#endif
            z_keyexpr_drop(z_keyexpr_move(&ke_pub));
            z_keyexpr_drop(z_keyexpr_move(&suffix));
            z_keyexpr_drop(z_keyexpr_move(&ke));
            _ze_advanced_subscriber_undeclare(&sub->_val);
            _Z_ERROR_RETURN(res);
        }
        state->_has_token = true;
#if Z_FEATURE_MULTI_THREAD == 1
        z_mutex_unlock(z_mutex_loan_mut(&state->_mutex));
#endif
        z_keyexpr_drop(z_keyexpr_move(&ke));
        z_keyexpr_drop(z_keyexpr_move(&suffix));
    }
    z_keyexpr_drop(z_keyexpr_move(&ke_pub));

    return _Z_RES_OK;
}

z_result_t ze_declare_background_advanced_subscriber(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                                     z_moved_closure_sample_t *callback,
                                                     ze_advanced_subscriber_options_t *options) {
    ze_owned_advanced_subscriber_t sub;
    _Z_RETURN_IF_ERR(ze_declare_advanced_subscriber(zs, &sub, keyexpr, callback, options));
    _ze_advanced_subscriber_clear(&sub._val);
    return _Z_RES_OK;
}

z_result_t ze_undeclare_advanced_subscriber(ze_moved_advanced_subscriber_t *sub) {
    return _ze_advanced_subscriber_undeclare(&sub->_this._val);
}

const z_loaned_keyexpr_t *ze_advanced_subscriber_keyexpr(const ze_loaned_advanced_subscriber_t *sub) {
    return z_subscriber_keyexpr(z_subscriber_loan(&sub->_subscriber));
}

z_entity_global_id_t ze_advanced_subscriber_id(const ze_loaned_advanced_subscriber_t *sub) {
    return z_subscriber_id(z_subscriber_loan(&sub->_subscriber));
}

z_result_t ze_advanced_subscriber_declare_sample_miss_listener(const ze_loaned_advanced_subscriber_t *subscriber,
                                                               ze_owned_sample_miss_listener_t *sample_miss_listener,
                                                               ze_moved_closure_miss_t *callback) {
    if (subscriber == NULL || _Z_RC_IS_NULL(&subscriber->_state)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }

    ze_internal_sample_miss_listener_null(sample_miss_listener);

    _ze_advanced_subscriber_state_t *state = _Z_RC_IN_VAL(&subscriber->_state);

    _Z_CLEAN_RETURN_IF_ERR(_ze_advanced_subscriber_state_lock_mutex_if_not_cancelled(state),
                           _ze_closure_miss_drop(&callback->_this._val));

    sample_miss_listener->_val._statesref = _ze_advanced_subscriber_state_rc_clone_as_weak(&subscriber->_state);
    if (_Z_RC_IS_NULL(&sample_miss_listener->_val._statesref)) {
        _ze_closure_miss_drop(&callback->_this._val);
        _ze_advanced_subscriber_state_unlock_mutex(state);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    sample_miss_listener->_val._id = state->_next_id++;

    _ze_closure_miss_t *closure = z_malloc(sizeof(_ze_closure_miss_t));
    if (closure == NULL ||
        _ze_closure_miss_intmap_insert(&state->_miss_handlers, sample_miss_listener->_val._id, closure) == NULL) {
        z_free(closure);
        _ze_closure_miss_drop(&callback->_this._val);
        _ze_sample_miss_listener_clear(&sample_miss_listener->_val);
        _ze_advanced_subscriber_state_unlock_mutex(state);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    _ze_closure_miss_move(closure, &callback->_this._val);
    _ze_advanced_subscriber_state_unlock_mutex(state);
    return _Z_RES_OK;
}

z_result_t ze_advanced_subscriber_declare_background_sample_miss_listener(
    const ze_loaned_advanced_subscriber_t *subscriber, ze_moved_closure_miss_t *callback) {
    ze_owned_sample_miss_listener_t listener;
    _Z_RETURN_IF_ERR(ze_advanced_subscriber_declare_sample_miss_listener(subscriber, &listener, callback));
    _ze_sample_miss_listener_clear(&listener._val);
    return _Z_RES_OK;
}

z_result_t ze_undeclare_sample_miss_listener(ze_moved_sample_miss_listener_t *sample_miss_listener) {
    return _ze_sample_miss_listener_drop(&sample_miss_listener->_this._val);
}

z_result_t ze_advanced_subscriber_detect_publishers(const ze_loaned_advanced_subscriber_t *subscriber,
                                                    z_owned_subscriber_t *liveliness_subscriber,
                                                    z_moved_closure_sample_t *callback,
                                                    z_liveliness_subscriber_options_t *options) {
    // Set options
    z_liveliness_subscriber_options_t opt;
    z_liveliness_subscriber_options_default(&opt);
    if (options != NULL) {
        opt = *options;
    }

    if (subscriber == NULL || _Z_RC_IS_NULL(&subscriber->_state)) {
        _Z_ERROR_RETURN(_Z_ERR_ENTITY_UNKNOWN);
    }

    _ze_advanced_subscriber_state_t *state = _Z_RC_IN_VAL(&subscriber->_state);

    z_owned_keyexpr_t keyexpr;
    _Z_RETURN_IF_ERR(z_keyexpr_clone(&keyexpr, z_keyexpr_loan(&state->_keyexpr)));
    _Z_CLEAN_RETURN_IF_ERR(
        _Z_KEYEXPR_APPEND_STR_ARRAY(&keyexpr, _Z_KEYEXPR_ADV_PREFIX, _Z_KEYEXPR_PUB, _Z_KEYEXPR_STARSTAR),
        z_keyexpr_drop(z_keyexpr_move(&keyexpr)));
    _z_session_rc_t sess_rc = _z_session_weak_upgrade_if_open(&state->_zn);
    if (_Z_RC_IS_NULL(&sess_rc)) {
        z_keyexpr_drop(z_keyexpr_move(&keyexpr));
        _Z_ERROR_RETURN(_Z_ERR_SESSION_CLOSED);
    }

    z_result_t ret =
        z_liveliness_declare_subscriber(&sess_rc, liveliness_subscriber, z_keyexpr_loan(&keyexpr), callback, &opt);
    z_keyexpr_drop(z_keyexpr_move(&keyexpr));
    _z_session_rc_drop(&sess_rc);
    return ret;
}

z_result_t ze_advanced_subscriber_detect_publishers_background(const ze_loaned_advanced_subscriber_t *subscriber,
                                                               z_moved_closure_sample_t *callback,
                                                               z_liveliness_subscriber_options_t *options) {
    z_owned_subscriber_t liveliness_subscriber;
    _Z_RETURN_IF_ERR(ze_advanced_subscriber_detect_publishers(subscriber, &liveliness_subscriber, callback, options));
    _z_subscriber_clear(&liveliness_subscriber._val);
    return _Z_RES_OK;
}

void ze_advanced_subscriber_history_options_default(ze_advanced_subscriber_history_options_t *options) {
    options->is_enabled = true;
    options->detect_late_publishers = false;
    options->max_samples = 0;
    options->max_age_ms = 0;
}

void ze_advanced_subscriber_last_sample_miss_detection_options_default(
    ze_advanced_subscriber_last_sample_miss_detection_options_t *options) {
    options->is_enabled = true;
    options->periodic_queries_period_ms = 0;
}

void ze_advanced_subscriber_recovery_options_default(ze_advanced_subscriber_recovery_options_t *options) {
    options->is_enabled = true;
    ze_advanced_subscriber_last_sample_miss_detection_options_default(&options->last_sample_miss_detection);
    options->last_sample_miss_detection.is_enabled = false;
}

void ze_advanced_subscriber_options_default(ze_advanced_subscriber_options_t *options) {
    z_subscriber_options_default(&options->subscriber_options);

    ze_advanced_subscriber_history_options_default(&options->history);
    options->history.is_enabled = false;

    ze_advanced_subscriber_recovery_options_default(&options->recovery);
    options->recovery.is_enabled = false;

    options->query_timeout_ms = 0;
    options->subscriber_detection = false;
    options->subscriber_detection_metadata = NULL;
}

#endif
