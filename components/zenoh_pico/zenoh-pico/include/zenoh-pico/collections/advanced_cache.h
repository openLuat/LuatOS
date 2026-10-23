//
// Copyright (c) 2024 ZettaScale Technology
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
#ifndef INCLUDE_ZENOH_PICO_COLLECTIONS_ADVANCED_CACHE_H
#define INCLUDE_ZENOH_PICO_COLLECTIONS_ADVANCED_CACHE_H

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/api/liveliness.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/collections/ring.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Represents the set of options that can be applied to an advaned publishers cache.
 * The cache allows advanced subscribers to recover history and/or lost samples.
 *
 * Members:
 *   bool is_enabled: Must be set to ``true``, to enable the cache.
 *   size_t max_samples: Number of samples to keep for each resource.
 *   z_congestion_control_t congestion_control: The congestion control to apply to replies.
 *   z_priority_t priority: The priority of replies.
 *   bool is_express: If set to ``true``, this cache replies will not be batched. This usually
 *     has a positive impact on latency but negative impact on throughput.
 */
typedef struct {
    bool is_enabled;
    size_t max_samples;
    z_congestion_control_t congestion_control;
    z_priority_t priority;
    bool is_express;
    bool _liveliness;  // TODO: Private as not yet exposed in Zenoh implementation.
} ze_advanced_publisher_cache_options_t;

typedef struct {
    _z_sample_ring_t _cache;
    _z_sample_t *_outbox;
    size_t _outbox_cap;
#if Z_FEATURE_MULTI_THREAD == 1
    _z_mutex_t _mutex;
    _z_mutex_t _outbox_mutex;
#endif
    z_owned_queryable_t _queryable;
    z_owned_liveliness_token_t _liveliness;
    z_congestion_control_t _congestion_control;
    z_priority_t _priority;
    bool _is_express;
} _ze_advanced_cache_t;

#if Z_FEATURE_ADVANCED_PUBLICATION == 1

_ze_advanced_cache_t *_ze_advanced_cache_new(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                             const z_loaned_keyexpr_t *suffix,
                                             const ze_advanced_publisher_cache_options_t options);

z_result_t _ze_advanced_cache_add(_ze_advanced_cache_t *cache, _z_sample_t *sample);

void _ze_advanced_cache_free(_ze_advanced_cache_t **xs);

#endif

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_ZENOH_PICO_COLLECTIONS_ADVANCED_CACHE_H
