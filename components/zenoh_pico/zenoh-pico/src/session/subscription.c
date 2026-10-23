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

#include "zenoh-pico/session/subscription.h"

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/api/constants.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/net/filtering.h"
#include "zenoh-pico/net/sample.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/definitions/network.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/resource.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/utils/locality.h"
#include "zenoh-pico/utils/logging.h"

#if Z_FEATURE_SUBSCRIPTION == 1

#define _Z_SUBINFOS_VEC_SIZE 4  // Arbitrary initial size

void _z_unsafe_subscription_cache_invalidate(_z_session_t *zn) {
#if Z_FEATURE_RX_CACHE == 1
    _z_subscription_lru_cache_clear(&zn->_subscription_cache);
#else
    _ZP_UNUSED(zn);
#endif
}

#if Z_FEATURE_RX_CACHE == 1
int _z_subscription_cache_data_compare(const void *first, const void *second) {
    const _z_subscription_cache_data_t *first_data = (const _z_subscription_cache_data_t *)first;
    const _z_subscription_cache_data_t *second_data = (const _z_subscription_cache_data_t *)second;
    if (first_data->is_remote != second_data->is_remote) {
        return (int)first_data->is_remote - (int)second_data->is_remote;
    }
    return _z_keyexpr_compare(&first_data->ke, &second_data->ke);
}
#endif  // Z_FEATURE_RX_CACHE == 1

void _z_subscription_cache_data_clear(_z_subscription_cache_data_t *val) {
    _z_subscription_rc_svec_rc_drop(&val->infos);
    _z_keyexpr_clear(&val->ke);
}

bool _z_subscription_eq(const _z_subscription_t *other, const _z_subscription_t *this_) {
    return this_->_id == other->_id;
}

void _z_subscription_clear(_z_subscription_t *sub) {
    if (sub->_dropper != NULL) {
        sub->_dropper(sub->_arg);
        sub->_dropper = NULL;
    }
    _z_declared_keyexpr_clear(&sub->_key);
    _z_sync_group_notifier_drop(&sub->_session_callback_drop_notifier);
    _z_sync_group_notifier_drop(&sub->_subscriber_callback_drop_notifier);
}

_z_subscription_rc_t *__z_get_subscription_by_id(_z_subscription_rc_slist_t *subs, const _z_zint_t id) {
    _z_subscription_rc_t *ret = NULL;

    _z_subscription_rc_slist_t *xs = subs;
    while (xs != NULL) {
        _z_subscription_rc_t *sub = _z_subscription_rc_slist_value(xs);
        if (id == _Z_RC_IN_VAL(sub)->_id) {
            ret = sub;
            break;
        }
        xs = _z_subscription_rc_slist_next(xs);
    }

    return ret;
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
_z_subscription_rc_t *__unsafe_z_get_subscription_by_id(_z_session_t *zn, _z_subscriber_kind_t kind,
                                                        const _z_zint_t id) {
    _z_subscription_rc_slist_t *subs =
        (kind == _Z_SUBSCRIBER_KIND_SUBSCRIBER) ? zn->_subscriptions : zn->_liveliness_subscriptions;
    return __z_get_subscription_by_id(subs, id);
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
static z_result_t __unsafe_z_get_subscriptions_by_key(_z_session_t *zn, _z_subscriber_kind_t kind,
                                                      const _z_keyexpr_t *key, bool is_remote,
                                                      _z_subscription_rc_svec_t *sub_infos) {
    _z_subscription_rc_slist_t *subs =
        (kind == _Z_SUBSCRIBER_KIND_SUBSCRIBER) ? zn->_subscriptions : zn->_liveliness_subscriptions;

    *sub_infos = _z_subscription_rc_svec_make(_Z_SUBINFOS_VEC_SIZE);
    _Z_RETURN_ERR_OOM_IF_TRUE(sub_infos->_val == NULL);
    _z_subscription_rc_slist_t *xs = subs;
    while (xs != NULL) {
        // Parse subscription list
        _z_subscription_rc_t *sub = _z_subscription_rc_slist_value(xs);
        const _z_subscription_t *sub_val = _Z_RC_IN_VAL(sub);
        bool origin_allowed = is_remote ? _z_locality_allows_remote(sub_val->_allowed_origin)
                                        : _z_locality_allows_local(sub_val->_allowed_origin);
        if (origin_allowed && _z_keyexpr_intersects(&sub_val->_key._inner, key)) {
            _z_subscription_rc_t sub_clone = _z_subscription_rc_clone(sub);
            _Z_CLEAN_RETURN_IF_ERR(_z_subscription_rc_svec_append(sub_infos, &sub_clone, false),
                                   _z_subscription_rc_svec_clear(sub_infos));
        }
        xs = _z_subscription_rc_slist_next(xs);
    }
    return _Z_RES_OK;
}

/**
 * This function is unsafe because it operates in potentially concurrent data.
 * Make sure that the following mutexes are locked before calling this function:
 *  - zn->_mutex_inner
 */
static z_result_t __unsafe_z_get_subscriptions_rc_by_key(_z_session_t *zn, _z_subscriber_kind_t kind,
                                                         const _z_keyexpr_t *key, bool is_remote,
                                                         _z_subscription_rc_svec_rc_t *sub_infos) {
    *sub_infos = _z_subscription_rc_svec_rc_new_undefined();
    z_result_t ret = !_Z_RC_IS_NULL(sub_infos) ? _Z_RES_OK : _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    _Z_SET_IF_OK(ret, __unsafe_z_get_subscriptions_by_key(zn, kind, key, is_remote, _Z_RC_IN_VAL(sub_infos)));
    if (ret != _Z_RES_OK) {
        _z_subscription_rc_svec_rc_drop(sub_infos);
    }
    return _Z_RES_OK;
}

_z_subscription_rc_t _z_get_subscription_by_id(_z_session_t *zn, _z_subscriber_kind_t kind, const _z_zint_t id) {
    _z_subscription_rc_t out = _z_subscription_rc_null();
    _z_session_mutex_lock(zn);

    _z_subscription_rc_t *sub = __unsafe_z_get_subscription_by_id(zn, kind, id);
    if (sub != NULL) {
        out = _z_subscription_rc_clone(sub);
    }
    _z_session_mutex_unlock(zn);

    return out;
}

_z_subscription_rc_t _z_register_subscription(_z_session_t *zn, _z_subscriber_kind_t kind, _z_subscription_t *s) {
    _Z_DEBUG(">>> Allocating sub decl for (%.*s)", (int)_z_string_len(&s->_key._inner._keyexpr),
             _z_string_data(&s->_key._inner._keyexpr));

    _z_subscription_rc_t *ret = NULL;
    _z_subscription_rc_t out = _z_subscription_rc_new_from_val(s);
    if (_Z_RC_IS_NULL(&out)) {
        return out;
    }
    if (_z_session_mutex_lock_if_open(zn) != _Z_RES_OK) {
        _z_subscription_rc_drop(&out);
        *s = _z_subscription_null();
        return _z_subscription_rc_null();
    }
    if (kind == _Z_SUBSCRIBER_KIND_SUBSCRIBER) {
        zn->_subscriptions = _z_subscription_rc_slist_push_empty(zn->_subscriptions);
        ret = _z_subscription_rc_slist_value(zn->_subscriptions);
    } else {
        zn->_liveliness_subscriptions = _z_subscription_rc_slist_push_empty(zn->_liveliness_subscriptions);
        ret = _z_subscription_rc_slist_value(zn->_liveliness_subscriptions);
    }
    if (ret == NULL) {
        _z_subscription_rc_drop(&out);
    } else {
        // immediately increase reference count to prevent eventual drop by concurrent session close
        *ret = _z_subscription_rc_clone(&out);
    }
    _z_session_mutex_unlock(zn);

#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    if (!_Z_RC_IS_NULL(&out) && kind == _Z_SUBSCRIBER_KIND_SUBSCRIBER) {
        _z_subscription_t *sub_val = _Z_RC_IN_VAL(&out);
        if (_z_locality_allows_local(sub_val->_allowed_origin)) {
            _z_write_filter_notify_subscriber(zn, &sub_val->_key._inner, sub_val->_allowed_origin, true);
        }
    }
#endif

    return out;
}

z_result_t _z_trigger_liveliness_subscriptions_declare(_z_session_t *zn, const _z_wireexpr_t *wireexpr,
                                                       const _z_timestamp_t *timestamp,
                                                       _z_transport_peer_common_t *peer) {
    _z_encoding_t encoding = _z_encoding_null();
    _z_bytes_t payload = _z_bytes_null();
    _z_bytes_t attachment = _z_bytes_null();
    _z_source_info_t source_info = _z_source_info_null();
    _z_wireexpr_t wireexpr2 = _z_wireexpr_alias(wireexpr);
    return _z_trigger_subscriptions_impl(zn, _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER, &wireexpr2, &payload, &encoding,
                                         Z_SAMPLE_KIND_PUT, timestamp, _Z_N_QOS_DEFAULT, &attachment,
                                         Z_RELIABILITY_RELIABLE, &source_info, peer);
}

z_result_t _z_trigger_liveliness_subscriptions_undeclare(_z_session_t *zn, const _z_keyexpr_t *keyexpr,
                                                         const _z_timestamp_t *timestamp) {
    _z_encoding_t encoding = _z_encoding_null();
    _z_bytes_t payload = _z_bytes_null();
    _z_bytes_t attachment = _z_bytes_null();
    _z_wireexpr_t wireexpr = _z_keyexpr_alias_to_wire(keyexpr);
    _z_source_info_t source_info = _z_source_info_null();
    return _z_trigger_subscriptions_impl(zn, _Z_SUBSCRIBER_KIND_LIVELINESS_SUBSCRIBER, &wireexpr, &payload, &encoding,
                                         Z_SAMPLE_KIND_DELETE, timestamp, _Z_N_QOS_DEFAULT, &attachment,
                                         Z_RELIABILITY_RELIABLE, &source_info, NULL);
}

static z_result_t _z_subscription_get_infos(_z_session_t *zn, _z_subscriber_kind_t kind,
                                            _z_subscription_cache_data_t *out, const _z_wireexpr_t *wireexpr,
                                            _z_transport_peer_common_t *peer) {
    out->is_remote = (peer != NULL);
    _Z_RETURN_IF_ERR(_z_get_keyexpr_from_wireexpr(zn, &out->ke, wireexpr, peer, true));
    _Z_CLEAN_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn), _z_keyexpr_clear(&out->ke));
    _z_subscription_cache_data_t *cache_entry = NULL;
    z_result_t ret = _Z_RES_OK;
#if Z_FEATURE_RX_CACHE == 1
    cache_entry = _z_subscription_lru_cache_get(&zn->_subscription_cache, out);
    if (cache_entry != NULL && cache_entry->is_remote != out->is_remote) {
        cache_entry = NULL;
    }
#endif
    if (cache_entry != NULL) {  // Copy cache entry
        out->infos = _z_subscription_rc_svec_rc_clone(&cache_entry->infos);
    } else {  // Construct data and add to cache
        _Z_SET_IF_OK(ret, __unsafe_z_get_subscriptions_rc_by_key(zn, kind, &out->ke, out->is_remote, &out->infos));
#if Z_FEATURE_RX_CACHE == 1
        _z_subscription_cache_data_t cache_storage = _z_subscription_cache_data_null();
        cache_storage.infos = _z_subscription_rc_svec_rc_clone(&out->infos);
        cache_storage.is_remote = out->is_remote;
        _Z_SET_IF_OK(ret, _z_keyexpr_copy(&cache_storage.ke, &out->ke));
        _Z_SET_IF_OK(ret, _z_subscription_lru_cache_insert(&zn->_subscription_cache, &cache_storage));
        if (ret != _Z_RES_OK) {
            _z_subscription_cache_data_clear(&cache_storage);
        }
#endif
    }
    _z_session_mutex_unlock(zn);
    if (ret != _Z_RES_OK) {
        _z_subscription_cache_data_clear(out);
    }
    return ret;
}

z_result_t _z_trigger_subscriptions_impl(_z_session_t *zn, _z_subscriber_kind_t sub_kind, _z_wireexpr_t *wireexpr,
                                         _z_bytes_t *payload, _z_encoding_t *encoding, const _z_zint_t sample_kind,
                                         const _z_timestamp_t *timestamp, const _z_n_qos_t qos, _z_bytes_t *attachment,
                                         z_reliability_t reliability, _z_source_info_t *source_info,
                                         _z_transport_peer_common_t *peer) {
    _z_subscription_cache_data_t sub_infos = _z_subscription_cache_data_null();
    _Z_CLEAN_RETURN_IF_ERR(_z_subscription_get_infos(zn, sub_kind, &sub_infos, wireexpr, peer),
                           _z_wireexpr_clear(wireexpr);
                           _z_encoding_clear(encoding); _z_bytes_drop(payload); _z_bytes_drop(attachment););
    const _z_subscription_rc_svec_t *subs = _Z_RC_IN_VAL(&sub_infos.infos);
    size_t sub_nb = _z_subscription_rc_svec_len(subs);
    _Z_DEBUG("Triggering %ju subs for key %.*s", (uintmax_t)sub_nb, (int)_z_string_len(&sub_infos.ke._keyexpr),
             _z_string_data(&sub_infos.ke._keyexpr));
    // Create sample
    z_result_t ret = _Z_RES_OK;
    _z_sample_t sample;
    _z_sample_steal_data(&sample, &sub_infos.ke, payload, timestamp, encoding, sample_kind, qos, attachment,
                         reliability, source_info);
    // Parse subscription infos svec
    if (sub_nb == 1) {
        _z_subscription_t *sub_info = _Z_RC_IN_VAL(_z_subscription_rc_svec_get(subs, 0));
        sub_info->_callback(&sample, sub_info->_arg);
    } else {
        for (size_t i = 0; i < sub_nb; i++) {
            _z_subscription_t *sub_info = _Z_RC_IN_VAL(_z_subscription_rc_svec_get(subs, i));
            if (i + 1 == sub_nb) {
                sub_info->_callback(&sample, sub_info->_arg);
            } else {
                _z_sample_t sample_copy;
                ret = _z_sample_copy(&sample_copy, &sample);
                if (ret != _Z_RES_OK) {
                    break;
                }
                sub_info->_callback(&sample_copy, sub_info->_arg);
                _z_sample_clear(&sample_copy);
            }
        }
    }
    _z_wireexpr_clear(wireexpr);
    _z_sample_clear(&sample);
    _z_subscription_cache_data_clear(&sub_infos);
    return ret;
}

void _z_unregister_subscription(_z_session_t *zn, _z_subscriber_kind_t kind, _z_subscription_rc_t *sub) {
#if Z_FEATURE_LOCAL_SUBSCRIBER == 1
    if (kind == _Z_SUBSCRIBER_KIND_SUBSCRIBER) {
        _z_subscription_t *sub_val = _Z_RC_IN_VAL(sub);
        _z_write_filter_notify_subscriber(zn, &sub_val->_key._inner, sub_val->_allowed_origin, false);
    }
#endif
    _z_session_mutex_lock(zn);
    _z_unsafe_subscription_cache_invalidate(zn);
    if (kind == _Z_SUBSCRIBER_KIND_SUBSCRIBER) {
        zn->_subscriptions = _z_subscription_rc_slist_drop_first_filter(zn->_subscriptions, _z_subscription_rc_eq, sub);
    } else {
        zn->_liveliness_subscriptions =
            _z_subscription_rc_slist_drop_first_filter(zn->_liveliness_subscriptions, _z_subscription_rc_eq, sub);
    }
    _z_session_mutex_unlock(zn);
    _z_subscription_rc_drop(sub);
}

void _z_flush_subscriptions(_z_session_t *zn) {
    _z_subscription_rc_slist_t *subscriptions, *liveliness_subscriptions;
    _z_session_mutex_lock(zn);
    _z_unsafe_subscription_cache_invalidate(zn);
    subscriptions = zn->_subscriptions;
    liveliness_subscriptions = zn->_liveliness_subscriptions;
    zn->_subscriptions = _z_subscription_rc_slist_new();
    zn->_liveliness_subscriptions = _z_subscription_rc_slist_new();
    _z_session_mutex_unlock(zn);
    _z_subscription_rc_slist_free(&subscriptions);
    _z_subscription_rc_slist_free(&liveliness_subscriptions);
}
#else  // Z_FEATURE_SUBSCRIPTION == 0
z_result_t _z_trigger_liveliness_subscriptions_declare(_z_session_t *zn, const _z_wireexpr_t *wireexpr,
                                                       const _z_timestamp_t *timestamp,
                                                       _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(wireexpr);
    _ZP_UNUSED(timestamp);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}

z_result_t _z_trigger_liveliness_subscriptions_undeclare(_z_session_t *zn, const _z_keyexpr_t *keyexpr,
                                                         const _z_timestamp_t *timestamp) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(keyexpr);
    _ZP_UNUSED(timestamp);
    return _Z_RES_OK;
}

void _z_unsafe_subscription_cache_invalidate(_z_session_t *zn) { _ZP_UNUSED(zn); }

#endif  // Z_FEATURE_SUBSCRIPTION == 1
