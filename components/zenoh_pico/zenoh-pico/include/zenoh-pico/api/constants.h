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

#ifndef ZENOH_PICO_API_CONSTANTS_H
#define ZENOH_PICO_API_CONSTANTS_H

#define Z_SELECTOR_TIME "_time="
#define Z_SELECTOR_QUERY_MATCH "_anyke"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * What bitmask for scouting.
 *
 * Enumerators:
 *   Z_WHAT_ROUTER: Router.
 *   Z_WHAT_PEER: Peer.
 *   Z_WHAT_CLIENT: Client.
 */
typedef enum {
    Z_WHAT_ROUTER = 0x01,  // Router
    Z_WHAT_PEER = 0x02,    // Peer
    Z_WHAT_CLIENT = 0x04,  // Client
    Z_WHAT_ROUTER_PEER = (0x01 | 0x02),
    Z_WHAT_ROUTER_CLIENT = (0x01 | 0x04),
    Z_WHAT_PEER_CLIENT = (0x02 | 0x04),
    Z_WHAT_ROUTER_PEER_CLIENT = ((0x01 | 0x02) | 0x04),
} z_what_t;

/**
 * Whatami values, defined as a bitmask.
 *
 * Enumerators:
 *   Z_WHATAMI_ROUTER: Bitmask to filter Zenoh routers.
 *   Z_WHATAMI_PEER: Bitmask to filter for Zenoh peers.
 *   Z_WHATAMI_CLIENT: Bitmask to filter for Zenoh clients.
 */
typedef enum z_whatami_t {
    Z_WHATAMI_ROUTER = 0x01,
    Z_WHATAMI_PEER = 0x02,
    Z_WHATAMI_CLIENT = 0x04,
} z_whatami_t;
#define Z_WHATAMI_DEFAULT Z_WHATAMI_ROUTER;

/**
 * The locality of samples to be received by subscribers or targeted by publishers.
 *
 * Enumerators:
 *   Z_LOCALITY_ANY: Allow both session-local and remote traffic.
 *   Z_LOCALITY_SESSION_LOCAL: Allow session-local traffic only.
 *   Z_LOCALITY_REMOTE: Allow remote traffic only.
 */
typedef enum z_locality_t {
    Z_LOCALITY_ANY = 0,
    Z_LOCALITY_SESSION_LOCAL = 1,
    Z_LOCALITY_REMOTE = 2,
} z_locality_t;

static inline z_locality_t z_locality_default(void) { return Z_LOCALITY_ANY; }

/**
 * Status values for keyexpr canonization operation.
 * Used as return value of canonization-related functions,
 * like :c:func:`z_keyexpr_is_canon` or :c:func:`z_keyexpr_canonize`.
 *
 * Enumerators:
 *   Z_KEYEXPR_CANON_SUCCESS: The key expression is canon.
 *   Z_KEYEXPR_CANON_LONE_DOLLAR_STAR: The key contains a ``$*`` chunk, which must be replaced by ``*``.
 *   Z_KEYEXPR_CANON_SINGLE_STAR_AFTER_DOUBLE_STAR: The key contains ``** / *``, which must be replaced by ``* / **``.
 *   Z_KEYEXPR_CANON_DOUBLE_STAR_AFTER_DOUBLE_STAR: The key contains ``** / **``, which must be replaced by ``**``.
 *   Z_KEYEXPR_CANON_EMPTY_CHUNK: The key contains empty chunks.
 *   Z_KEYEXPR_CANON_STARS_IN_CHUNK: The key contains a ``*`` in a chunk without being escaped by a DSL, which is
 *     forbidden.
 *   Z_KEYEXPR_CANON_DOLLAR_AFTER_DOLLAR_OR_STAR: The key contains ``$*$`` or ``$$``, which is forbidden.
 *   Z_KEYEXPR_CANON_CONTAINS_SHARP_OR_QMARK: The key contains ``#`` or ``?``, which is forbidden.
 *   Z_KEYEXPR_CANON_CONTAINS_UNBOUND_DOLLAR: The key contains a ``$`` which is not bound to a DSL.
 */
typedef enum {
    Z_KEYEXPR_CANON_SUCCESS = 0,
    Z_KEYEXPR_CANON_LONE_DOLLAR_STAR = -1,
    Z_KEYEXPR_CANON_SINGLE_STAR_AFTER_DOUBLE_STAR = -2,
    Z_KEYEXPR_CANON_DOUBLE_STAR_AFTER_DOUBLE_STAR = -3,
    Z_KEYEXPR_CANON_EMPTY_CHUNK = -4,
    Z_KEYEXPR_CANON_STARS_IN_CHUNK = -5,
    Z_KEYEXPR_CANON_DOLLAR_AFTER_DOLLAR_OR_STAR = -6,
    Z_KEYEXPR_CANON_CONTAINS_SHARP_OR_QMARK = -7,
    Z_KEYEXPR_CANON_CONTAINS_UNBOUND_DOLLAR = -8
} zp_keyexpr_canon_status_t;

/**
 * Intersection level of two key expressions.
 *
 * Enumerators:
 *   Z_KEYEXPR_INTERSECTION_LEVEL_DISJOINT: The two key expressions do not intersect.
 *   Z_KEYEXPR_INTERSECTION_LEVEL_INTERSECTS: The two key expressions intersect, i.e. there exists at least one key
 *     expression that is included by both.
 *   Z_KEYEXPR_INTERSECTION_LEVEL_INCLUDES: The first key expression is the superset of the second one.
 *   Z_KEYEXPR_INTERSECTION_LEVEL_EQUALS: The two key expressions are equal.
 */
typedef enum {
    Z_KEYEXPR_INTERSECTION_LEVEL_DISJOINT = 0,
    Z_KEYEXPR_INTERSECTION_LEVEL_INTERSECTS = 1,
    Z_KEYEXPR_INTERSECTION_LEVEL_INCLUDES = 2,
    Z_KEYEXPR_INTERSECTION_LEVEL_EQUALS = 3,
} z_keyexpr_intersection_level_t;

/**
 * Key expression constant strings.
 */
#define _Z_KEYEXPR_AT "@"
#define _Z_KEYEXPR_AT_LEN (sizeof(_Z_KEYEXPR_AT) - 1)
#define _Z_KEYEXPR_ADV_PREFIX "@adv"
#define _Z_KEYEXPR_ADV_PREFIX_LEN (sizeof(_Z_KEYEXPR_ADV_PREFIX) - 1)
#define _Z_KEYEXPR_PUB "pub"
#define _Z_KEYEXPR_PUB_LEN (sizeof(_Z_KEYEXPR_PUB) - 1)
#define _Z_KEYEXPR_SUB "sub"
#define _Z_KEYEXPR_SUB_LEN (sizeof(_Z_KEYEXPR_SUB) - 1)
#define _Z_KEYEXPR_UHLC "uhlc"
#define _Z_KEYEXPR_UHLC_LEN (sizeof(_Z_KEYEXPR_UHLC) - 1)
#define _Z_KEYEXPR_EMPTY "_"
#define _Z_KEYEXPR_EMPTY_LEN (sizeof(_Z_KEYEXPR_EMPTY) - 1)
#define _Z_KEYEXPR_STAR "*"
#define _Z_KEYEXPR_STAR_LEN (sizeof(_Z_KEYEXPR_STAR) - 1)
#define _Z_KEYEXPR_STARSTAR "**"
#define _Z_KEYEXPR_STARSTAR_LEN (sizeof(_Z_KEYEXPR_STARSTAR) - 1)
#define _Z_KEYEXPR_SESSION "session"
#define _Z_KEYEXPR_SESSION_LEN (sizeof(_Z_KEYEXPR_SESSION) - 1)
#define _Z_KEYEXPR_PICO "pico"
#define _Z_KEYEXPR_PICO_LEN (sizeof(_Z_KEYEXPR_PICO) - 1)
#define _Z_KEYEXPR_TRANSPORTS "transports"
#define _Z_KEYEXPR_TRANSPORTS_LEN (sizeof(_Z_KEYEXPR_TRANSPORTS) - 1)
#define _Z_KEYEXPR_TRANSPORT_UNICAST "transport/unicast"
#define _Z_KEYEXPR_TRANSPORT_UNICAST_LEN (sizeof(_Z_KEYEXPR_TRANSPORT_UNICAST) - 1)
#define _Z_KEYEXPR_TRANSPORT_MULTICAST "transport/multicast"
#define _Z_KEYEXPR_TRANSPORT_MULTICAST_LEN (sizeof(_Z_KEYEXPR_TRANSPORT_MULTICAST) - 1)
#define _Z_KEYEXPR_TRANSPORT_RAWETH "transport/raweth"
#define _Z_KEYEXPR_TRANSPORT_RAWETH_LEN (sizeof(_Z_KEYEXPR_TRANSPORT_RAWETH) - 1)
#define _Z_KEYEXPR_LINK "link"
#define _Z_KEYEXPR_LINK_LEN (sizeof(_Z_KEYEXPR_LINK) - 1)
#define _Z_KEYEXPR_PEERS "peers"
#define _Z_KEYEXPR_PEERS_LEN (sizeof(_Z_KEYEXPR_PEERS) - 1)
#define _Z_KEYEXPR_SEPARATOR "/"
#define _Z_KEYEXPR_SEPARATOR_LEN (sizeof(_Z_KEYEXPR_SEPARATOR) - 1)

/**
 * Sample kind values.
 *
 * Enumerators:
 *   Z_SAMPLE_KIND_PUT: The Sample was issued by a ``put`` operation.
 *   Z_SAMPLE_KIND_DELETE: The Sample was issued by a ``delete`` operation.
 */
typedef enum {
    Z_SAMPLE_KIND_PUT = 0,
    Z_SAMPLE_KIND_DELETE = 1,
    Z_SAMPLE_KIND_DEFAULT = Z_SAMPLE_KIND_PUT
} z_sample_kind_t;

/**
 * Consolidation mode values.
 *
 * Enumerators:
 *   Z_CONSOLIDATION_MODE_AUTO: Let Zenoh decide the best consolidation mode depending on the query selector.
 *   Z_CONSOLIDATION_MODE_NONE: No consolidation is applied. Replies may come in any order and any number.
 *   Z_CONSOLIDATION_MODE_MONOTONIC: It guarantees that any reply for a given key expression will be monotonic in time
 *     w.r.t. the previous received replies for the same key expression. I.e., for the same key expression multiple
 *     replies may be received. It is guaranteed that two replies received at t1 and t2 will have timestamp
 *     ts2 > ts1. It optimizes latency.
 *   Z_CONSOLIDATION_MODE_LATEST: It guarantees unicity of replies for the same key expression.
 *     It optimizes bandwidth.
 */
typedef enum {
    Z_CONSOLIDATION_MODE_AUTO = -1,
    Z_CONSOLIDATION_MODE_NONE = 0,
    Z_CONSOLIDATION_MODE_MONOTONIC = 1,
    Z_CONSOLIDATION_MODE_LATEST = 2,
    Z_CONSOLIDATION_MODE_DEFAULT = Z_CONSOLIDATION_MODE_AUTO
} z_consolidation_mode_t;

/**
 * Reliability values.
 *
 * Enumerators:
 *   Z_RELIABILITY_BEST_EFFORT: Defines reliability as ``BEST_EFFORT``
 *   Z_RELIABILITY_RELIABLE: Defines reliability as ``RELIABLE``
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
typedef enum {
    Z_RELIABILITY_BEST_EFFORT = 1,
    Z_RELIABILITY_RELIABLE = 0,
    Z_RELIABILITY_DEFAULT = Z_RELIABILITY_RELIABLE
} z_reliability_t;

/**
 * Congestion control values.
 *
 * Enumerators:
 *   Z_CONGESTION_CONTROL_BLOCK: Defines congestion control as ``BLOCK``. Messages are not dropped in case of
 *     congestion control.
 *   Z_CONGESTION_CONTROL_DROP: Defines congestion control as ``DROP``. Messages are dropped in case
 *     of congestion control.
 */
typedef enum {
    Z_CONGESTION_CONTROL_BLOCK = 1,
    Z_CONGESTION_CONTROL_DROP = 0,
    Z_CONGESTION_CONTROL_DEFAULT = Z_CONGESTION_CONTROL_DROP
} z_congestion_control_t;

static inline z_congestion_control_t z_internal_congestion_control_default_push(void) {
    return Z_CONGESTION_CONTROL_DROP;
}
static inline z_congestion_control_t z_internal_congestion_control_default_request(void) {
    return Z_CONGESTION_CONTROL_BLOCK;
}

/**
 * Priority of Zenoh messages values.
 *
 * Enumerators:
 *   _Z_PRIORITY_CONTROL: Priority for ``Control`` messages.
 *   Z_PRIORITY_REAL_TIME: Priority for ``RealTime`` messages.
 *   Z_PRIORITY_INTERACTIVE_HIGH: Highest priority for ``Interactive`` messages.
 *   Z_PRIORITY_INTERACTIVE_LOW: Lowest priority for ``Interactive`` messages.
 *   Z_PRIORITY_DATA_HIGH: Highest priority for ``Data`` messages.
 *   Z_PRIORITY_DATA: Default priority for ``Data`` messages.
 *   Z_PRIORITY_DATA_LOW: Lowest priority for ``Data`` messages.
 *   Z_PRIORITY_BACKGROUND: Priority for ``Background traffic`` messages.
 */
typedef enum {
    _Z_PRIORITY_CONTROL = 0,
    Z_PRIORITY_REAL_TIME = 1,
    Z_PRIORITY_INTERACTIVE_HIGH = 2,
    Z_PRIORITY_INTERACTIVE_LOW = 3,
    Z_PRIORITY_DATA_HIGH = 4,
    Z_PRIORITY_DATA = 5,
    Z_PRIORITY_DATA_LOW = 6,
    Z_PRIORITY_BACKGROUND = 7,
    Z_PRIORITY_DEFAULT = Z_PRIORITY_DATA
} z_priority_t;

/**
 * Query target values.
 *
 * Enumerators:
 *   Z_QUERY_TARGET_BEST_MATCHING: The nearest complete queryable if any else all matching queryables.
 *   Z_QUERY_TARGET_ALL: All matching queryables.
 *   Z_QUERY_TARGET_ALL_COMPLETE: A set of complete queryables.
 */
typedef enum {
    Z_QUERY_TARGET_BEST_MATCHING = 0,
    Z_QUERY_TARGET_ALL = 1,
    Z_QUERY_TARGET_ALL_COMPLETE = 2,
    Z_QUERY_TARGET_DEFAULT = Z_QUERY_TARGET_BEST_MATCHING
} z_query_target_t;

/**
 * The kinds of accepted query replies.
 *
 * The queryable may serve glob-like key expressions.
 * E.g., the queryable may be declared with the key expression `foo/b$*`.
 * At the same time, it may send replies with more specific key expressions, e.g., `foo/bar` or `foo/baz`.
 * This may cause a situation when the queryable receives a query with the key expression `foo/bar`
 * and replies to it with the key expression `foo/baz`.
 * By default, this behavior is not allowed. Calling `z_query_reply` value on a query for `foo/bar` with key expression
 * `foo/baz` will result in an error on the sending side. But if the query is sent with the `accept_replies` flag set to
 * `Z_REPLY_KEYEXPR_ANY` in either `z_get_options_t` or `z_querier_options_t`, then the reply with a disjoint key
 * expression will be accepted for this query.
 *
 * The queryable may check whether disjoint replies are allowed for a query with `z_query_accepts_replies` function.
 *
 * Enumerators:
 *   Z_REPLY_KEYEXPR_ANY: Accept replies on any key expression.
 *   Z_REPLY_KEYEXPR_MATCHING_QUERY: Accept replies only to intersecting key expressions intersecting with query's own
 * key expression.
 */
typedef enum z_reply_keyexpr_t {
    Z_REPLY_KEYEXPR_ANY = 0,
    Z_REPLY_KEYEXPR_MATCHING_QUERY = 1,
    Z_REPLY_KEYEXPR_DEFAULT = Z_REPLY_KEYEXPR_MATCHING_QUERY
} z_reply_keyexpr_t;

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_API_CONSTANTS_H */
