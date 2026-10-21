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

#ifndef INCLUDE_ZENOH_PICO_SESSION_SUBSCRIPTION_H
#define INCLUDE_ZENOH_PICO_SESSION_SUBSCRIPTION_H

#include "zenoh-pico/collections/lru_cache.h"
#include "zenoh-pico/net/encoding.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/session.h"

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration to avoid cyclical include
typedef struct _z_session_t _z_session_t;

_Z_SVEC_DEFINE(_z_subscription_rc, _z_subscription_rc_t)
_Z_REFCOUNT_DEFINE(_z_subscription_rc_svec, _z_subscription_rc_svec)

typedef struct {
    _z_keyexpr_t ke;
    _z_subscription_rc_svec_rc_t infos;
    bool is_remote;
} _z_subscription_cache_data_t;

static inline _z_subscription_cache_data_t _z_subscription_cache_data_null(void) {
    _z_subscription_cache_data_t ret = {0};
    return ret;
}

void _z_unsafe_subscription_cache_invalidate(_z_session_t *zn);
int _z_subscription_cache_data_compare(const void *first, const void *second);
void _z_subscription_cache_data_clear(_z_subscription_cache_data_t *val);

/*------------------ Subscription ------------------*/
z_result_t _z_trigger_liveliness_subscriptions_declare(_z_session_t *zn, const _z_wireexpr_t *wireexpr,
                                                       const _z_timestamp_t *timestamp,
                                                       _z_transport_peer_common_t *peer);

z_result_t _z_trigger_liveliness_subscriptions_undeclare(_z_session_t *zn, const _z_keyexpr_t *keyexpr,
                                                         const _z_timestamp_t *timestamp);

#if Z_FEATURE_SUBSCRIPTION == 1

#if Z_FEATURE_RX_CACHE == 1
_Z_ELEM_DEFINE(_z_subscription, _z_subscription_cache_data_t, _z_noop_size, _z_subscription_cache_data_clear,
               _z_noop_copy, _z_noop_move, _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_LRU_CACHE_DEFINE(_z_subscription, _z_subscription_cache_data_t, _z_subscription_cache_data_compare)
#endif

_z_subscription_rc_t _z_get_subscription_by_id(_z_session_t *zn, _z_subscriber_kind_t kind, const _z_zint_t id);
_z_subscription_rc_t _z_register_subscription(_z_session_t *zn, _z_subscriber_kind_t kind, _z_subscription_t *sub);
z_result_t _z_trigger_subscriptions_impl(_z_session_t *zn, _z_subscriber_kind_t sub_kind, _z_wireexpr_t *wireexpr,
                                         _z_bytes_t *payload, _z_encoding_t *encoding, const _z_zint_t sample_kind,
                                         const _z_timestamp_t *timestamp, const _z_n_qos_t qos, _z_bytes_t *attachment,
                                         z_reliability_t reliability, _z_source_info_t *source_info,
                                         _z_transport_peer_common_t *peer);
void _z_unregister_subscription(_z_session_t *zn, _z_subscriber_kind_t kind, _z_subscription_rc_t *sub);
void _z_flush_subscriptions(_z_session_t *zn);

static inline z_result_t _z_trigger_subscriptions_put(_z_session_t *zn, _z_wireexpr_t *wireexpr, _z_bytes_t *payload,
                                                      _z_encoding_t *encoding, const _z_timestamp_t *timestamp,
                                                      const _z_n_qos_t qos, _z_bytes_t *attachment,
                                                      z_reliability_t reliability, _z_source_info_t *source_info,
                                                      _z_transport_peer_common_t *peer) {
    return _z_trigger_subscriptions_impl(zn, _Z_SUBSCRIBER_KIND_SUBSCRIBER, wireexpr, payload, encoding,
                                         Z_SAMPLE_KIND_PUT, timestamp, qos, attachment, reliability, source_info, peer);
}
static inline z_result_t _z_trigger_subscriptions_del(_z_session_t *zn, _z_wireexpr_t *wireexpr,
                                                      const _z_timestamp_t *timestamp, const _z_n_qos_t qos,
                                                      _z_bytes_t *attachment, z_reliability_t reliability,
                                                      _z_source_info_t *source_info, _z_transport_peer_common_t *peer) {
    _z_encoding_t encoding = _z_encoding_null();
    _z_bytes_t payload = _z_bytes_null();
    return _z_trigger_subscriptions_impl(zn, _Z_SUBSCRIBER_KIND_SUBSCRIBER, wireexpr, &payload, &encoding,
                                         Z_SAMPLE_KIND_DELETE, timestamp, qos, attachment, reliability, source_info,
                                         peer);
}
#else   // Z_FEATURE_SUBSCRIPTION == 0
static inline z_result_t _z_trigger_subscriptions_put(_z_session_t *zn, _z_wireexpr_t *wireexpr, _z_bytes_t *payload,
                                                      _z_encoding_t *encoding, const _z_timestamp_t *timestamp,
                                                      const _z_n_qos_t qos, _z_bytes_t *attachment,
                                                      z_reliability_t reliability, _z_source_info_t *source_info,
                                                      _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(wireexpr);
    _ZP_UNUSED(payload);
    _ZP_UNUSED(encoding);
    _ZP_UNUSED(qos);
    _ZP_UNUSED(timestamp);
    _ZP_UNUSED(attachment);
    _ZP_UNUSED(reliability);
    _ZP_UNUSED(source_info);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}

static inline z_result_t _z_trigger_subscriptions_del(_z_session_t *zn, _z_wireexpr_t *wireexpr,
                                                      const _z_timestamp_t *timestamp, const _z_n_qos_t qos,
                                                      _z_bytes_t *attachment, z_reliability_t reliability,
                                                      _z_source_info_t *source_info, _z_transport_peer_common_t *peer) {
    _ZP_UNUSED(zn);
    _ZP_UNUSED(wireexpr);
    _ZP_UNUSED(qos);
    _ZP_UNUSED(timestamp);
    _ZP_UNUSED(attachment);
    _ZP_UNUSED(reliability);
    _ZP_UNUSED(source_info);
    _ZP_UNUSED(peer);
    return _Z_RES_OK;
}
#endif  // Z_FEATURE_SUBSCRIPTION == 1

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_SESSION_SUBSCRIPTION_H */
