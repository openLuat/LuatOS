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

#include "zenoh-pico/api/admin_space.h"

#include "zenoh-pico/api/encoding.h"
#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/net/primitives.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/utils/json_encoder.h"

#if Z_FEATURE_ADMIN_SPACE == 1

#define _ZE_ADMIN_SPACE_KE_BUF_LEN 256

typedef struct {
    const char *data;
    size_t len;
} _ze_admin_space_ke_segment_t;

typedef z_result_t (*_ze_admin_space_encode_fn_t)(_z_json_encoder_t *je, void *ctx);
typedef z_result_t (*_ze_admin_space_ke_builder_t)(z_owned_keyexpr_t *ke, const z_id_t *zid);

typedef struct {
    const char *name;
    _ze_admin_space_ke_builder_t build_ke;
    _ze_admin_space_encode_fn_t encode;
} _ze_admin_space_endpoint_t;

static z_result_t _ze_admin_space_build_ke(z_owned_keyexpr_t *ke, const z_id_t *zid,
                                           const _ze_admin_space_ke_segment_t *segments, size_t segment_count) {
    z_internal_keyexpr_null(ke);

    z_owned_string_t zid_str;
    _Z_RETURN_IF_ERR(z_id_to_string(zid, &zid_str));

    const z_loaned_string_t *zid_loan = z_string_loan(&zid_str);
    const char *zid_data = z_string_data(zid_loan);
    size_t zid_len = z_string_len(zid_loan);

    char buf[_ZE_ADMIN_SPACE_KE_BUF_LEN];
    size_t off = 0;

    int n =
        snprintf(buf + off, sizeof(buf) - off, "%s%s%.*s", _Z_KEYEXPR_AT, _Z_KEYEXPR_SEPARATOR, (int)zid_len, zid_data);
    z_string_drop(z_string_move(&zid_str));
    if (n < 0 || (size_t)n >= sizeof(buf) - off) {
        return _Z_ERR_INVALID;
    }
    off += (size_t)n;

    for (size_t i = 0; i < segment_count; i++) {
        n = snprintf(buf + off, sizeof(buf) - off, "%s%.*s", _Z_KEYEXPR_SEPARATOR, (int)segments[i].len,
                     segments[i].data);
        if (n < 0 || (size_t)n >= sizeof(buf) - off) {
            return _Z_ERR_INVALID;
        }
        off += (size_t)n;
    }

    return z_keyexpr_from_substr(ke, buf, off);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_PICO / Z_KEYEXPR_STARSTAR
static z_result_t _ze_admin_space_pico_queryable_ke(z_owned_keyexpr_t *ke, const z_id_t *zid) {
    static const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_PICO, _Z_KEYEXPR_PICO_LEN},
        {_Z_KEYEXPR_STARSTAR, _Z_KEYEXPR_STARSTAR_LEN},
    };
    return _ze_admin_space_build_ke(ke, zid, segments, 2);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_PICO
static z_result_t _ze_admin_space_pico_ke(z_owned_keyexpr_t *ke, const z_id_t *zid) {
    static const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_PICO, _Z_KEYEXPR_PICO_LEN},
    };
    return _ze_admin_space_build_ke(ke, zid, segments, 1);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_PICO / _Z_KEYEXPR_SESSION
static z_result_t _ze_admin_space_pico_session_ke(z_owned_keyexpr_t *ke, const z_id_t *zid) {
    static const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_PICO, _Z_KEYEXPR_PICO_LEN},
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
    };
    return _ze_admin_space_build_ke(ke, zid, segments, 2);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_PICO / _Z_KEYEXPR_SESSION / _Z_KEYEXPR_TRANSPORTS
static z_result_t _ze_admin_space_pico_transports_ke(z_owned_keyexpr_t *ke, const z_id_t *zid) {
    static const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_PICO, _Z_KEYEXPR_PICO_LEN},
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
        {_Z_KEYEXPR_TRANSPORTS, _Z_KEYEXPR_TRANSPORTS_LEN},
    };
    return _ze_admin_space_build_ke(ke, zid, segments, 3);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_PICO / _Z_KEYEXPR_SESSION / _Z_KEYEXPR_TRANSPORTS / 0
static z_result_t _ze_admin_space_pico_transports_0_ke(z_owned_keyexpr_t *ke, const z_id_t *zid) {
    static const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_PICO, _Z_KEYEXPR_PICO_LEN},
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
        {_Z_KEYEXPR_TRANSPORTS, _Z_KEYEXPR_TRANSPORTS_LEN},
        {"0", 1},
    };
    return _ze_admin_space_build_ke(ke, zid, segments, 4);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_PICO / _Z_KEYEXPR_SESSION / _Z_KEYEXPR_TRANSPORTS / 0 / _Z_KEYEXPR_PEERS
static z_result_t _ze_admin_space_pico_transports_0_peers_ke(z_owned_keyexpr_t *ke, const z_id_t *zid) {
    static const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_PICO, _Z_KEYEXPR_PICO_LEN},
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
        {_Z_KEYEXPR_TRANSPORTS, _Z_KEYEXPR_TRANSPORTS_LEN},
        {"0", 1},
        {_Z_KEYEXPR_PEERS, _Z_KEYEXPR_PEERS_LEN},
    };
    return _ze_admin_space_build_ke(ke, zid, segments, 5);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_PICO / _Z_KEYEXPR_SESSION / _Z_KEYEXPR_TRANSPORTS / 0 / _Z_KEYEXPR_PEERS /
// REMOTE_ZID
static z_result_t _ze_admin_space_pico_transports_0_peers_peer_ke(z_owned_keyexpr_t *ke, const z_id_t *zid,
                                                                  const z_id_t *remote_zid) {
    z_owned_string_t remote_zid_str;
    _Z_RETURN_IF_ERR(z_id_to_string(remote_zid, &remote_zid_str));

    const z_loaned_string_t *remote_zid_loan = z_string_loan(&remote_zid_str);
    const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_PICO, _Z_KEYEXPR_PICO_LEN},
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
        {_Z_KEYEXPR_TRANSPORTS, _Z_KEYEXPR_TRANSPORTS_LEN},
        {"0", 1},
        {_Z_KEYEXPR_PEERS, _Z_KEYEXPR_PEERS_LEN},
        {z_string_data(remote_zid_loan), z_string_len(remote_zid_loan)},
    };

    z_result_t ret = _ze_admin_space_build_ke(ke, zid, segments, 6);
    z_string_drop(z_string_move(&remote_zid_str));
    return ret;
}

#if Z_FEATURE_CONNECTIVITY == 1
// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_SESSION / Z_KEYEXPR_STARSTAR
static z_result_t _ze_admin_space_session_queryable_ke(z_owned_keyexpr_t *ke, const z_id_t *zid) {
    static const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
        {_Z_KEYEXPR_STARSTAR, _Z_KEYEXPR_STARSTAR_LEN},
    };
    return _ze_admin_space_build_ke(ke, zid, segments, 2);
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_SESSION / _Z_KEYEXPR_TRANSPORT_UNICAST / PEER_ZID
static z_result_t _ze_admin_space_session_transport_ke(z_owned_keyexpr_t *ke, const z_id_t *zid,
                                                       const z_id_t *peer_zid) {
    z_owned_string_t peer_zid_str;
    _Z_RETURN_IF_ERR(z_id_to_string(peer_zid, &peer_zid_str));

    const z_loaned_string_t *peer_zid_loan = z_string_loan(&peer_zid_str);
    const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
        {_Z_KEYEXPR_TRANSPORT_UNICAST, _Z_KEYEXPR_TRANSPORT_UNICAST_LEN},
        {z_string_data(peer_zid_loan), z_string_len(peer_zid_loan)},
    };

    z_result_t ret = _ze_admin_space_build_ke(ke, zid, segments, 3);
    z_string_drop(z_string_move(&peer_zid_str));
    return ret;
}

// ke = _Z_KEYEXPR_AT / ZID / _Z_KEYEXPR_SESSION / _Z_KEYEXPR_TRANSPORT_UNICAST / PEER_ZID / _Z_KEYEXPR_LINK /
// LINK_ID
static z_result_t _ze_admin_space_session_link_ke(z_owned_keyexpr_t *ke, const z_id_t *zid, const z_id_t *peer_zid,
                                                  const z_id_t *link_id) {
    z_owned_string_t peer_zid_str;
    _Z_RETURN_IF_ERR(z_id_to_string(peer_zid, &peer_zid_str));
    z_owned_string_t link_id_str;
    _Z_CLEAN_RETURN_IF_ERR(z_id_to_string(link_id, &link_id_str), z_string_drop(z_string_move(&peer_zid_str)));

    const z_loaned_string_t *peer_zid_loan = z_string_loan(&peer_zid_str);
    const z_loaned_string_t *link_id_loan = z_string_loan(&link_id_str);
    const _ze_admin_space_ke_segment_t segments[] = {
        {_Z_KEYEXPR_SESSION, _Z_KEYEXPR_SESSION_LEN},
        {_Z_KEYEXPR_TRANSPORT_UNICAST, _Z_KEYEXPR_TRANSPORT_UNICAST_LEN},
        {z_string_data(peer_zid_loan), z_string_len(peer_zid_loan)},
        {_Z_KEYEXPR_LINK, _Z_KEYEXPR_LINK_LEN},
        {z_string_data(link_id_loan), z_string_len(link_id_loan)},
    };

    z_result_t ret = _ze_admin_space_build_ke(ke, zid, segments, 5);
    z_string_drop(z_string_move(&peer_zid_str));
    z_string_drop(z_string_move(&link_id_str));
    return ret;
}
#endif  // Z_FEATURE_CONNECTIVITY == 1

static z_result_t _ze_admin_space_encode_whatami(_z_json_encoder_t *je, z_whatami_t mode) {
    switch (mode) {
        case Z_WHATAMI_ROUTER:
            return _z_json_encoder_write_string(je, "router");
        case Z_WHATAMI_PEER:
            return _z_json_encoder_write_string(je, "peer");
        case Z_WHATAMI_CLIENT:
            return _z_json_encoder_write_string(je, "client");
        default:
            return _Z_ERR_INVALID;
    }
}

#if Z_FEATURE_CONNECTIVITY == 1
static z_result_t _ze_admin_space_encode_connectivity_transport_payload(z_owned_bytes_t *payload, const z_id_t *zid,
                                                                        z_whatami_t whatami, bool is_qos, bool is_shm) {
    z_internal_bytes_null(payload);

    _z_json_encoder_t je;
    _Z_RETURN_IF_ERR(_z_json_encoder_empty(&je));

    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_start_object(&je), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "zid"), _z_json_encoder_clear(&je));
    z_owned_string_t zid_str;
    _Z_CLEAN_RETURN_IF_ERR(z_id_to_string(zid, &zid_str), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_z_string(&je, z_string_loan(&zid_str)),
                           z_string_drop(z_string_move(&zid_str));
                           _z_json_encoder_clear(&je));
    z_string_drop(z_string_move(&zid_str));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "whatami"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_ze_admin_space_encode_whatami(&je, whatami), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "is_qos"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_boolean(&je, is_qos), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "is_shm"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_boolean(&je, is_shm), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_end_object(&je), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_finish(&je, payload), _z_json_encoder_clear(&je));
    return _Z_RES_OK;
}

static z_result_t _ze_admin_space_encode_connectivity_link_payload(z_owned_bytes_t *payload, const _z_string_t *src,
                                                                   const _z_string_t *dst, uint16_t mtu,
                                                                   bool is_streamed, bool is_reliable) {
    z_internal_bytes_null(payload);

    _z_json_encoder_t je;
    _Z_RETURN_IF_ERR(_z_json_encoder_empty(&je));

    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_start_object(&je), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "src"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_z_string(&je, src), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "dst"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_z_string(&je, dst), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "group"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_null(&je), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "mtu"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_u64(&je, (uint64_t)mtu), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "is_reliable"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_boolean(&je, is_reliable), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(&je, "is_streamed"), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_boolean(&je, is_streamed), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_end_object(&je), _z_json_encoder_clear(&je));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_finish(&je, payload), _z_json_encoder_clear(&je));
    return _Z_RES_OK;
}
#endif  // Z_FEATURE_CONNECTIVITY == 1

static z_result_t _ze_admin_space_encode_transport_type(_z_json_encoder_t *je, int type) {
    switch (type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            return _z_json_encoder_write_string(je, "unicast");
        case _Z_TRANSPORT_MULTICAST_TYPE:
            return _z_json_encoder_write_string(je, "multicast");
        case _Z_TRANSPORT_RAWETH_TYPE:
            return _z_json_encoder_write_string(je, "raweth");
        default:
            return _Z_ERR_INVALID;
    }
}

static z_result_t _ze_admin_space_encode_str_intmap(_z_json_encoder_t *je, const _z_str_intmap_t *map) {
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));

    _z_str_intmap_iterator_t it = _z_str_intmap_iterator_make(map);
    while (_z_str_intmap_iterator_next(&it)) {
        size_t key = _z_str_intmap_iterator_key(&it);
        char key_buf[21];  // enough for 64-bit size_t
        int n = snprintf(key_buf, sizeof(key_buf), "%zu", key);
        if (n <= 0 || (size_t)n >= sizeof(key_buf)) {
            return _Z_ERR_INVALID;
        }
        _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, key_buf));

        char *value = _z_str_intmap_iterator_value(&it);
        _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, value));
    }
    return _z_json_encoder_end_object(je);
}

static z_result_t _ze_admin_space_encode_link(_z_json_encoder_t *je, const _z_link_t *link) {
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "link"));
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "type"));
    switch (link->_type) {
        case _Z_LINK_TYPE_TCP:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "tcp"));
            break;
        case _Z_LINK_TYPE_UDP:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "udp"));
            break;
        case _Z_LINK_TYPE_BT:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "bt"));
            break;
        case _Z_LINK_TYPE_SERIAL:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "serial"));
            break;
        case _Z_LINK_TYPE_WS:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "ws"));
            break;
        case _Z_LINK_TYPE_TLS:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "tls"));
            break;
        case _Z_LINK_TYPE_RAWETH:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "raweth"));
            break;
        default:
            return _Z_ERR_INVALID;
    }

    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "endpoint"));
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "locator"));
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "metadata"));
    _Z_RETURN_IF_ERR(_ze_admin_space_encode_str_intmap(je, &link->_endpoint._locator._metadata));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "protocol"));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_z_string(je, &link->_endpoint._locator._protocol));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "address"));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_z_string(je, &link->_endpoint._locator._address));
    _Z_RETURN_IF_ERR(_z_json_encoder_end_object(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "config"));
    _Z_RETURN_IF_ERR(_ze_admin_space_encode_str_intmap(je, &link->_endpoint._config));
    _Z_RETURN_IF_ERR(_z_json_encoder_end_object(je));

    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "capabilities"));
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "transport"));
    switch (link->_cap._transport) {
        case Z_LINK_CAP_TRANSPORT_UNICAST:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "unicast"));
            break;
        case Z_LINK_CAP_TRANSPORT_MULTICAST:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "multicast"));
            break;
        case Z_LINK_CAP_TRANSPORT_RAWETH:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "raweth"));
            break;
        default:
            return _Z_ERR_INVALID;
    }
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "flow"));
    switch (link->_cap._flow) {
        case Z_LINK_CAP_FLOW_DATAGRAM:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "datagram"));
            break;
        case Z_LINK_CAP_FLOW_STREAM:
            _Z_RETURN_IF_ERR(_z_json_encoder_write_string(je, "stream"));
            break;
        default:
            return _Z_ERR_INVALID;
    }
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "is_reliable"));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_boolean(je, link->_cap._is_reliable != 0));
    _Z_RETURN_IF_ERR(_z_json_encoder_end_object(je));
    return _z_json_encoder_end_object(je);
}

static void _ze_admin_space_reply_null(_ze_admin_space_reply_t *reply) {
    z_internal_keyexpr_null(&reply->ke);
    z_internal_bytes_null(&reply->payload);
}

void _ze_admin_space_reply_clear(_ze_admin_space_reply_t *reply) {
    z_keyexpr_drop(z_keyexpr_move(&reply->ke));
    z_bytes_drop(z_bytes_move(&reply->payload));
    _ze_admin_space_reply_null(reply);
}

static z_result_t _ze_admin_space_add_reply_bytes(const z_loaned_keyexpr_t *ke, z_moved_bytes_t *payload,
                                                  _ze_admin_space_reply_list_t **replies) {
    _ze_admin_space_reply_t *reply = z_malloc(sizeof(_ze_admin_space_reply_t));
    if (reply == NULL) {
        z_bytes_drop(payload);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    _ze_admin_space_reply_null(reply);

    _Z_CLEAN_RETURN_IF_ERR(z_keyexpr_clone(&reply->ke, ke), z_bytes_drop(payload); z_free(reply));
    z_bytes_take(&reply->payload, payload);

    _ze_admin_space_reply_list_t *old = *replies;
    _ze_admin_space_reply_list_t *tmp = _ze_admin_space_reply_list_push(*replies, reply);
    if (tmp == old) {
        _ze_admin_space_reply_clear(reply);
        z_free(reply);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    *replies = tmp;

    return _Z_RES_OK;
}

static z_result_t _ze_admin_space_add_reply(_z_json_encoder_t *je, const z_loaned_keyexpr_t *ke,
                                            _ze_admin_space_reply_list_t **replies) {
    z_owned_bytes_t payload;
    z_internal_bytes_null(&payload);
    _Z_RETURN_IF_ERR(_z_json_encoder_finish(je, &payload));
    return _ze_admin_space_add_reply_bytes(ke, z_bytes_move(&payload), replies);
}

static z_result_t _ze_admin_space_encode_transport_common(_z_json_encoder_t *je, const _z_transport_common_t *common) {
    return _ze_admin_space_encode_link(je, common->_link);
}

static z_result_t _ze_admin_space_encode_peer_common(_z_json_encoder_t *je, const _z_transport_peer_common_t *peer) {
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "zid"));
    z_owned_string_t id_string;
    _Z_RETURN_IF_ERR(z_id_to_string(&peer->_remote_zid, &id_string));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_z_string(je, z_string_loan(&id_string)),
                           z_string_drop(z_string_move(&id_string)));
    z_string_drop(z_string_move(&id_string));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "whatami"));
    return _ze_admin_space_encode_whatami(je, peer->_remote_whatami);
}

static z_result_t _ze_admin_space_encode_unicast_peer(_z_json_encoder_t *je, const _z_transport_peer_unicast_t *peer) {
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_ze_admin_space_encode_peer_common(je, &peer->common));
    return _z_json_encoder_end_object(je);
}

static z_result_t _ze_admin_space_encode_multicast_peer(_z_json_encoder_t *je,
                                                        const _z_transport_peer_multicast_t *peer) {
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_ze_admin_space_encode_peer_common(je, &peer->common));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "remote_addr"));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_z_slice(je, &peer->_remote_addr));
    return _z_json_encoder_end_object(je);
}

static z_result_t _ze_admin_space_encode_unicast_peers(_z_json_encoder_t *je,
                                                       const _z_transport_peer_unicast_slist_t *peers) {
    _Z_RETURN_IF_ERR(_z_json_encoder_start_array(je));

    for (; peers != NULL; peers = _z_transport_peer_unicast_slist_next(peers)) {
        const _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(peers);
        _Z_RETURN_IF_ERR(_ze_admin_space_encode_unicast_peer(je, peer));
    }

    return _z_json_encoder_end_array(je);
}

static z_result_t _ze_admin_space_encode_multicast_peers(_z_json_encoder_t *je,
                                                         const _z_transport_peer_multicast_slist_t *peers) {
    _Z_RETURN_IF_ERR(_z_json_encoder_start_array(je));

    for (; peers != NULL; peers = _z_transport_peer_multicast_slist_next(peers)) {
        const _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(peers);
        _Z_RETURN_IF_ERR(_ze_admin_space_encode_multicast_peer(je, peer));
    }

    return _z_json_encoder_end_array(je);
}

static z_result_t _ze_admin_space_encode_transport_unicast(_z_json_encoder_t *je, _z_transport_unicast_t *tp) {
    z_result_t ret = _Z_RES_OK;

    _z_transport_peer_mutex_lock(&tp->_common);

    ret = _ze_admin_space_encode_transport_common(je, &tp->_common);
    if (ret == _Z_RES_OK) {
        ret = _z_json_encoder_write_key(je, "peers");
    }
    if (ret == _Z_RES_OK) {
        ret = _ze_admin_space_encode_unicast_peers(je, tp->_peers);
    }

    _z_transport_peer_mutex_unlock(&tp->_common);
    return ret;
}

static z_result_t _ze_admin_space_encode_transport_multicast(_z_json_encoder_t *je, _z_transport_multicast_t *tp) {
    z_result_t ret = _Z_RES_OK;

    _z_transport_peer_mutex_lock(&tp->_common);

    ret = _ze_admin_space_encode_transport_common(je, &tp->_common);
    if (ret == _Z_RES_OK) {
        ret = _z_json_encoder_write_key(je, "peers");
    }
    if (ret == _Z_RES_OK) {
        ret = _ze_admin_space_encode_multicast_peers(je, tp->_peers);
    }

    _z_transport_peer_mutex_unlock(&tp->_common);
    return ret;
}

static z_result_t _ze_admin_space_encode_transport(_z_json_encoder_t *je, _z_transport_t *tp) {
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "type"));
    _Z_RETURN_IF_ERR(_ze_admin_space_encode_transport_type(je, tp->_type));

    switch (tp->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            _Z_RETURN_IF_ERR(_ze_admin_space_encode_transport_unicast(je, &tp->_transport._unicast));
            break;
        case _Z_TRANSPORT_MULTICAST_TYPE:
            _Z_RETURN_IF_ERR(_ze_admin_space_encode_transport_multicast(je, &tp->_transport._multicast));
            break;
        case _Z_TRANSPORT_RAWETH_TYPE:
            _Z_RETURN_IF_ERR(_ze_admin_space_encode_transport_multicast(je, &tp->_transport._raweth));
            break;
        default:
            break;
    }

    return _z_json_encoder_end_object(je);
}

static z_result_t _ze_admin_space_encode_transport_peers(_z_json_encoder_t *je, _z_transport_t *tp) {
    z_result_t ret = _Z_RES_OK;

    switch (tp->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE: {
            _z_transport_unicast_t *utp = &tp->_transport._unicast;
            _z_transport_peer_mutex_lock(&utp->_common);
            ret = _ze_admin_space_encode_unicast_peers(je, utp->_peers);
            _z_transport_peer_mutex_unlock(&utp->_common);
            break;
        }
        case _Z_TRANSPORT_MULTICAST_TYPE: {
            _z_transport_multicast_t *mtp = &tp->_transport._multicast;
            _z_transport_peer_mutex_lock(&mtp->_common);
            ret = _ze_admin_space_encode_multicast_peers(je, mtp->_peers);
            _z_transport_peer_mutex_unlock(&mtp->_common);
            break;
        }
        case _Z_TRANSPORT_RAWETH_TYPE: {
            _z_transport_multicast_t *rtp = &tp->_transport._raweth;
            _z_transport_peer_mutex_lock(&rtp->_common);
            ret = _ze_admin_space_encode_multicast_peers(je, rtp->_peers);
            _z_transport_peer_mutex_unlock(&rtp->_common);
            break;
        }
        default:
            break;
    }

    return ret;
}

static z_result_t _ze_admin_space_encode_transports(_z_json_encoder_t *je, _z_transport_t *tp) {
    _Z_RETURN_IF_ERR(_z_json_encoder_start_array(je));
    _Z_RETURN_IF_ERR(_ze_admin_space_encode_transport(je, tp));
    return _z_json_encoder_end_array(je);
}

static z_result_t _ze_admin_space_encode_session(_z_json_encoder_t *je, _z_session_t *session) {
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(session));

    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_start_object(je), _z_session_mutex_unlock(session));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(je, "zid"), _z_session_mutex_unlock(session));
    z_owned_string_t zid_str;
    _Z_CLEAN_RETURN_IF_ERR(z_id_to_string(&session->_local_zid, &zid_str), _z_session_mutex_unlock(session));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_z_string(je, z_string_loan(&zid_str)),
                           z_string_drop(z_string_move(&zid_str));
                           _z_session_mutex_unlock(session));
    z_string_drop(z_string_move(&zid_str));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(je, "whatami"), _z_session_mutex_unlock(session));
    _Z_CLEAN_RETURN_IF_ERR(_ze_admin_space_encode_whatami(je, session->_mode), _z_session_mutex_unlock(session));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_write_key(je, "transports"), _z_session_mutex_unlock(session));
    _Z_CLEAN_RETURN_IF_ERR(_ze_admin_space_encode_transports(je, &session->_tp), _z_session_mutex_unlock(session));
    _Z_CLEAN_RETURN_IF_ERR(_z_json_encoder_end_object(je), _z_session_mutex_unlock(session));

    _z_session_mutex_unlock(session);
    return _Z_RES_OK;
}

static z_result_t _ze_admin_space_encode_pico(_z_json_encoder_t *je, void *ctx) {
    _z_session_t *session = (_z_session_t *)ctx;
    _Z_RETURN_IF_ERR(_z_json_encoder_start_object(je));
    _Z_RETURN_IF_ERR(_z_json_encoder_write_key(je, "session"));
    _Z_RETURN_IF_ERR(_ze_admin_space_encode_session(je, session));
    return _z_json_encoder_end_object(je);
}

static z_result_t _ze_admin_space_encode_pico_session(_z_json_encoder_t *je, void *ctx) {
    _z_session_t *session = (_z_session_t *)ctx;
    return _ze_admin_space_encode_session(je, session);
}

static z_result_t _ze_admin_space_encode_pico_transports(_z_json_encoder_t *je, void *ctx) {
    _z_session_t *session = (_z_session_t *)ctx;
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(session));
    z_result_t ret = _ze_admin_space_encode_transports(je, &session->_tp);
    _z_session_mutex_unlock(session);
    return ret;
}

static z_result_t _ze_admin_space_encode_pico_transport_0(_z_json_encoder_t *je, void *ctx) {
    _z_session_t *session = (_z_session_t *)ctx;
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(session));
    z_result_t ret = _ze_admin_space_encode_transport(je, &session->_tp);
    _z_session_mutex_unlock(session);
    return ret;
}

static z_result_t _ze_admin_space_encode_pico_transport_0_peers(_z_json_encoder_t *je, void *ctx) {
    _z_session_t *session = (_z_session_t *)ctx;
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(session));
    z_result_t ret = _ze_admin_space_encode_transport_peers(je, &session->_tp);
    _z_session_mutex_unlock(session);
    return ret;
}

static z_result_t _ze_admin_space_reply_if_intersects(const z_loaned_query_t *query, const z_loaned_keyexpr_t *ke,
                                                      void *ctx, _ze_admin_space_reply_list_t **replies,
                                                      _ze_admin_space_encode_fn_t encode) {
    if (z_keyexpr_intersects(z_query_keyexpr(query), ke)) {
        _z_json_encoder_t je;
        _Z_RETURN_IF_ERR(_z_json_encoder_empty(&je));
        _Z_CLEAN_RETURN_IF_ERR(encode(&je, ctx), _z_json_encoder_clear(&je));
        _Z_CLEAN_RETURN_IF_ERR(_ze_admin_space_add_reply(&je, ke, replies), _z_json_encoder_clear(&je));
    }
    return _Z_RES_OK;
}

typedef struct {
    const _z_transport_peer_unicast_t *peer;
} _ze_admin_space_unicast_peer_ctx_t;

typedef struct {
    const _z_transport_peer_multicast_t *peer;
} _ze_admin_space_multicast_peer_ctx_t;

static z_result_t _ze_admin_space_encode_pico_transport_0_unicast_peer(_z_json_encoder_t *je, void *ctx) {
    const _ze_admin_space_unicast_peer_ctx_t *pctx = (const _ze_admin_space_unicast_peer_ctx_t *)ctx;
    return _ze_admin_space_encode_unicast_peer(je, pctx->peer);
}

static z_result_t _ze_admin_space_encode_pico_transport_0_multicast_peer(_z_json_encoder_t *je, void *ctx) {
    const _ze_admin_space_multicast_peer_ctx_t *pctx = (const _ze_admin_space_multicast_peer_ctx_t *)ctx;
    return _ze_admin_space_encode_multicast_peer(je, pctx->peer);
}

static void _ze_admin_space_query_handle_pico_transport_0_unicast_peers(const z_loaned_query_t *query,
                                                                        const z_id_t *local_zid,
                                                                        _z_transport_unicast_t *tp,
                                                                        _ze_admin_space_reply_list_t **replies) {
    _z_transport_peer_mutex_lock(&tp->_common);

    for (_z_transport_peer_unicast_slist_t *peers = tp->_peers; peers != NULL;
         peers = _z_transport_peer_unicast_slist_next(peers)) {
        const _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(peers);

        z_owned_keyexpr_t ke;
        z_result_t ret;

        ret = _ze_admin_space_pico_transports_0_peers_peer_ke(&ke, local_zid, &peer->common._remote_zid);
        if (ret != _Z_RES_OK) {
            _Z_WARN("Failed to build key expression for pico/session/transports/0/peers peer query: %d", ret);
            continue;
        }

        _ze_admin_space_unicast_peer_ctx_t ctx = {
            .peer = peer,
        };

        ret = _ze_admin_space_reply_if_intersects(query, z_keyexpr_loan(&ke), &ctx, replies,
                                                  _ze_admin_space_encode_pico_transport_0_unicast_peer);
        if (ret != _Z_RES_OK) {
            _Z_WARN("Failed to handle admin space query for pico/session/transports/0/peers peer endpoint: %d", ret);
        }

        z_keyexpr_drop(z_keyexpr_move(&ke));
    }

    _z_transport_peer_mutex_unlock(&tp->_common);
}

static void _ze_admin_space_query_handle_pico_transport_0_multicast_peers(const z_loaned_query_t *query,
                                                                          const z_id_t *local_zid,
                                                                          _z_transport_multicast_t *tp,
                                                                          _ze_admin_space_reply_list_t **replies) {
    _z_transport_peer_mutex_lock(&tp->_common);

    for (_z_transport_peer_multicast_slist_t *peers = tp->_peers; peers != NULL;
         peers = _z_transport_peer_multicast_slist_next(peers)) {
        const _z_transport_peer_multicast_t *peer = _z_transport_peer_multicast_slist_value(peers);

        z_owned_keyexpr_t ke;
        z_result_t ret;

        ret = _ze_admin_space_pico_transports_0_peers_peer_ke(&ke, local_zid, &peer->common._remote_zid);
        if (ret != _Z_RES_OK) {
            _Z_WARN("Failed to build key expression for pico/session/transports/0/peers peer query: %d", ret);
            continue;
        }

        _ze_admin_space_multicast_peer_ctx_t ctx = {
            .peer = peer,
        };

        ret = _ze_admin_space_reply_if_intersects(query, z_keyexpr_loan(&ke), &ctx, replies,
                                                  _ze_admin_space_encode_pico_transport_0_multicast_peer);
        if (ret != _Z_RES_OK) {
            _Z_WARN("Failed to handle admin space query for pico/session/transports/0/peers peer endpoint: %d", ret);
        }

        z_keyexpr_drop(z_keyexpr_move(&ke));
    }

    _z_transport_peer_mutex_unlock(&tp->_common);
}

static void _ze_admin_space_query_handle_pico_transport_0_peers(const z_loaned_query_t *query, _z_session_t *session,
                                                                _ze_admin_space_reply_list_t **replies) {
    switch (session->_tp._type) {
        case _Z_TRANSPORT_UNICAST_TYPE:
            _ze_admin_space_query_handle_pico_transport_0_unicast_peers(query, &session->_local_zid,
                                                                        &session->_tp._transport._unicast, replies);
            break;

        case _Z_TRANSPORT_MULTICAST_TYPE:
            _ze_admin_space_query_handle_pico_transport_0_multicast_peers(query, &session->_local_zid,
                                                                          &session->_tp._transport._multicast, replies);
            break;

        case _Z_TRANSPORT_RAWETH_TYPE:
            _ze_admin_space_query_handle_pico_transport_0_multicast_peers(query, &session->_local_zid,
                                                                          &session->_tp._transport._raweth, replies);
            break;

        default:
            break;
    }
}

static void _ze_admin_space_try_reply(const z_loaned_query_t *query, _z_session_t *session,
                                      _ze_admin_space_reply_list_t **replies, const _ze_admin_space_endpoint_t *ep) {
    z_owned_keyexpr_t ke;
    z_result_t ret = ep->build_ke(&ke, &session->_local_zid);
    if (ret != _Z_RES_OK) {
        _Z_WARN("Failed to build key expression for %s query: %d", ep->name, ret);
        return;
    }

    ret = _ze_admin_space_reply_if_intersects(query, z_keyexpr_loan(&ke), session, replies, ep->encode);
    if (ret != _Z_RES_OK) {
        _Z_WARN("Failed to handle admin space query for %s endpoint: %d", ep->name, ret);
    }

    z_keyexpr_drop(z_keyexpr_move(&ke));
}

static void _ze_admin_space_query_handle_endpoints(const z_loaned_query_t *query, _z_session_t *session,
                                                   const _ze_admin_space_endpoint_t *endpoints, size_t endpoint_count,
                                                   _ze_admin_space_reply_list_t **replies) {
    for (size_t i = 0; i < endpoint_count; i++) {
        _ze_admin_space_try_reply(query, session, replies, &endpoints[i]);
    }
}

static const _ze_admin_space_endpoint_t _ze_admin_space_pico_endpoints[] = {
    {"pico", _ze_admin_space_pico_ke, _ze_admin_space_encode_pico},
    {"pico/session", _ze_admin_space_pico_session_ke, _ze_admin_space_encode_pico_session},
    {"pico/session/transports", _ze_admin_space_pico_transports_ke, _ze_admin_space_encode_pico_transports},
    {"pico/session/transports/0", _ze_admin_space_pico_transports_0_ke, _ze_admin_space_encode_pico_transport_0},
    {"pico/session/transports/0/peers", _ze_admin_space_pico_transports_0_peers_ke,
     _ze_admin_space_encode_pico_transport_0_peers},
};

static void _ze_admin_space_query_handle_pico(const z_loaned_query_t *query, _z_session_t *session,
                                              _ze_admin_space_reply_list_t **replies) {
    _ze_admin_space_query_handle_endpoints(query, session, _ze_admin_space_pico_endpoints,
                                           _ZP_ARRAY_SIZE(_ze_admin_space_pico_endpoints), replies);

    _ze_admin_space_query_handle_pico_transport_0_peers(query, session, replies);
}

#if Z_FEATURE_CONNECTIVITY == 1
static void _ze_admin_space_query_handle_connectivity_session(const z_loaned_query_t *query, _z_session_t *session,
                                                              _ze_admin_space_reply_list_t **replies) {
    _z_session_transport_mutex_lock(session);
    if (session->_tp._type != _Z_TRANSPORT_UNICAST_TYPE) {
        _z_session_transport_mutex_unlock(session);
        return;
    }
    _z_transport_peer_mutex_lock(&session->_tp._transport._unicast._common);

    const _z_transport_common_t *transport_common = &session->_tp._transport._unicast._common;
    const _z_transport_peer_unicast_slist_t *peers = session->_tp._transport._unicast._peers;
    while (peers != NULL) {
        const _z_transport_peer_unicast_t *peer = _z_transport_peer_unicast_slist_value(peers);

        z_owned_keyexpr_t transport_ke;
        z_result_t ret =
            _ze_admin_space_session_transport_ke(&transport_ke, &session->_local_zid, &peer->common._remote_zid);
        if (ret == _Z_RES_OK) {
            if (z_keyexpr_intersects(z_query_keyexpr(query), z_keyexpr_loan(&transport_ke))) {
                z_owned_bytes_t payload;
                ret = _ze_admin_space_encode_connectivity_transport_payload(&payload, &peer->common._remote_zid,
                                                                            peer->common._remote_whatami, false, false);
                if (ret == _Z_RES_OK) {
                    ret =
                        _ze_admin_space_add_reply_bytes(z_keyexpr_loan(&transport_ke), z_bytes_move(&payload), replies);
                }
                if (ret != _Z_RES_OK) {
                    _Z_WARN("Failed to add connectivity transport status reply: %d", ret);
                }
            }
            z_keyexpr_drop(z_keyexpr_move(&transport_ke));
        } else {
            _Z_WARN("Failed to build key expression for connectivity transport status: %d", ret);
        }

        z_owned_keyexpr_t link_ke;
        ret = _ze_admin_space_session_link_ke(&link_ke, &session->_local_zid, &peer->common._remote_zid,
                                              &peer->common._remote_zid);
        if (ret == _Z_RES_OK) {
            if (z_keyexpr_intersects(z_query_keyexpr(query), z_keyexpr_loan(&link_ke))) {
                uint16_t mtu;
                bool is_streamed;
                bool is_reliable;
                _z_transport_link_properties_from_transport(transport_common, &mtu, &is_streamed, &is_reliable);

                z_owned_bytes_t payload;
                z_internal_bytes_null(&payload);
                ret = _ze_admin_space_encode_connectivity_link_payload(
                    &payload, &peer->common._link_src, &peer->common._link_dst, mtu, is_streamed, is_reliable);
                if (ret == _Z_RES_OK) {
                    ret = _ze_admin_space_add_reply_bytes(z_keyexpr_loan(&link_ke), z_bytes_move(&payload), replies);
                }
                if (ret != _Z_RES_OK) {
                    _Z_WARN("Failed to add connectivity link status reply: %d", ret);
                }
            }
            z_keyexpr_drop(z_keyexpr_move(&link_ke));
        } else {
            _Z_WARN("Failed to build key expression for connectivity link status: %d", ret);
        }

        peers = _z_transport_peer_unicast_slist_next(peers);
    }

    _z_transport_peer_mutex_unlock(&session->_tp._transport._unicast._common);
    _z_session_transport_mutex_unlock(session);
}
#endif  // Z_FEATURE_CONNECTIVITY == 1

static void _ze_admin_space_query_reply_all(z_loaned_query_t *query, _ze_admin_space_reply_list_t **replies) {
    _ze_admin_space_reply_list_t *next = *replies;
    while (next != NULL) {
        _ze_admin_space_reply_t *reply = _ze_admin_space_reply_list_value(next);
        z_query_reply_options_t opt;
        z_query_reply_options_default(&opt);
        z_owned_encoding_t encoding;
        if (z_encoding_clone(&encoding, z_encoding_application_json()) == _Z_RES_OK) {
            opt.encoding = z_encoding_move(&encoding);
            z_result_t res = z_query_reply(query, z_keyexpr_loan(&reply->ke), z_bytes_move(&reply->payload), &opt);
            if (res != _Z_RES_OK) {
                z_view_string_t keystr;
                if (z_keyexpr_as_view_string(z_keyexpr_loan(&reply->ke), &keystr) == _Z_RES_OK) {
                    _Z_ERROR("Failed to reply to admin space query on key expression: %.*s",
                             (int)z_string_len(z_view_string_loan(&keystr)),
                             z_string_data(z_view_string_loan(&keystr)));
                } else {
                    _Z_ERROR("Failed to reply to admin space query");
                }
            }
        } else {
            _Z_ERROR("Failed to clone JSON encoding for admin space query reply");
            break;
        }
        next = _ze_admin_space_reply_list_next(next);
    }
}

static void _ze_admin_space_query_handler_impl(z_loaned_query_t *query, void *ctx, bool include_pico,
                                               bool include_connectivity_session) {
    _z_session_weak_t *session_weak = (_z_session_weak_t *)ctx;

    _z_session_rc_t session_rc = _z_session_weak_upgrade_if_open(session_weak);
    if (_Z_RC_IS_NULL(&session_rc)) {
        _Z_ERROR("Dropped admin space query - session closed");
        return;
    }

    _z_session_t *session = _Z_RC_IN_VAL(&session_rc);
    _ze_admin_space_reply_list_t *replies = _ze_admin_space_reply_list_new();

    if (include_pico) {
        _ze_admin_space_query_handle_pico(query, session, &replies);
    }
#if Z_FEATURE_CONNECTIVITY == 1
    if (include_connectivity_session) {
        _ze_admin_space_query_handle_connectivity_session(query, session, &replies);
    }
#else
    _ZP_UNUSED(include_connectivity_session);
#endif

    _ze_admin_space_query_reply_all(query, &replies);
    _ze_admin_space_reply_list_free(&replies);
    _z_session_rc_drop(&session_rc);
}

static void _ze_admin_space_pico_query_handler(z_loaned_query_t *query, void *ctx) {
    _ze_admin_space_query_handler_impl(query, ctx, true, false);
}

#if Z_FEATURE_CONNECTIVITY == 1
static void _ze_admin_space_session_query_handler(z_loaned_query_t *query, void *ctx) {
    _ze_admin_space_query_handler_impl(query, ctx, false, true);
}
#endif

static void _ze_admin_space_query_dropper(void *ctx) {
    _z_session_weak_t *session_weak = (_z_session_weak_t *)ctx;
    _z_session_weak_drop(session_weak);
    z_free(session_weak);
}

static z_result_t _ze_admin_space_undeclare_queryable(const z_loaned_session_t *zs, uint32_t queryable_id) {
    if (queryable_id == 0) {
        return _Z_RES_OK;
    }

    _z_queryable_t queryable = {
        ._entity_id = queryable_id,
        ._zn = _z_session_rc_clone_as_weak(zs),
    };
    if (_Z_RC_IS_NULL(&queryable._zn)) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }

    z_result_t ret = _z_undeclare_queryable(&queryable);
    _z_queryable_clear(&queryable);
    return ret;
}

#if Z_FEATURE_CONNECTIVITY == 1
static z_result_t _ze_admin_space_declare_session_queryable(const z_loaned_session_t *zs, uint32_t *out_queryable_id,
                                                            const z_loaned_keyexpr_t *ke, void *ctx) {
    z_owned_closure_query_t callback;
    z_result_t ret =
        z_closure_query(&callback, _ze_admin_space_session_query_handler, _ze_admin_space_query_dropper, ctx);
    if (ret != _Z_RES_OK) {
        _ze_admin_space_query_dropper(ctx);
        return ret;
    }

    _z_closure_query_t closure = callback._val;
    z_internal_closure_query_null(&callback);

    return _z_register_queryable(out_queryable_id, zs, ke, _Z_QUERYABLE_COMPLETE_DEFAULT, closure.call, closure.drop,
                                 closure.context, Z_LOCALITY_SESSION_LOCAL, NULL);
}
#endif

#if Z_FEATURE_CONNECTIVITY == 1 && Z_FEATURE_PUBLICATION == 1
typedef struct {
    _z_session_weak_t _session;
} _ze_admin_space_connectivity_listener_ctx_t;

static void _ze_admin_space_connectivity_listener_ctx_drop(void *ctx) {
    _ze_admin_space_connectivity_listener_ctx_t *listener_ctx = (_ze_admin_space_connectivity_listener_ctx_t *)ctx;
    if (listener_ctx != NULL) {
        _z_session_weak_drop(&listener_ctx->_session);
        z_free(listener_ctx);
    }
}

static _ze_admin_space_connectivity_listener_ctx_t *_ze_admin_space_connectivity_listener_ctx_new(
    const z_loaned_session_t *zs) {
    _ze_admin_space_connectivity_listener_ctx_t *ctx =
        (_ze_admin_space_connectivity_listener_ctx_t *)z_malloc(sizeof(_ze_admin_space_connectivity_listener_ctx_t));
    if (ctx == NULL) {
        return NULL;
    }

    ctx->_session = _z_session_rc_clone_as_weak(zs);
    if (_Z_RC_IS_NULL(&ctx->_session)) {
        z_free(ctx);
        return NULL;
    }
    return ctx;
}

static z_result_t _ze_admin_space_undeclare_transport_listener(z_loaned_session_t *zs, size_t listener_id) {
    if (listener_id == 0) {
        return _Z_RES_OK;
    }

    z_owned_transport_events_listener_t listener;
    listener._val = (_z_transport_events_listener_t){0};
    listener._val._id = listener_id;
    listener._val._session = _z_session_rc_clone_as_weak(zs);
    if (_Z_RC_IS_NULL(&listener._val._session)) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    return z_undeclare_transport_events_listener(z_transport_events_listener_move(&listener));
}

static z_result_t _ze_admin_space_undeclare_link_listener(z_loaned_session_t *zs, size_t listener_id) {
    if (listener_id == 0) {
        return _Z_RES_OK;
    }

    z_owned_link_events_listener_t listener;
    listener._val = (_z_link_events_listener_t){0};
    listener._val._id = listener_id;
    listener._val._session = _z_session_rc_clone_as_weak(zs);
    if (_Z_RC_IS_NULL(&listener._val._session)) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    return z_undeclare_link_events_listener(z_link_events_listener_move(&listener));
}

static inline void _ze_admin_space_transport_listener_handle_clear(z_owned_transport_events_listener_t *listener) {
    _z_session_weak_drop(&listener->_val._session);
    _z_sync_group_drop(&listener->_val._callback_drop_sync_group);
    listener->_val = (_z_transport_events_listener_t){0};
}

static inline void _ze_admin_space_link_listener_handle_clear(z_owned_link_events_listener_t *listener) {
    _z_session_weak_drop(&listener->_val._session);
    _z_sync_group_drop(&listener->_val._callback_drop_sync_group);
    listener->_val = (_z_link_events_listener_t){0};
}

static z_result_t _ze_admin_space_put_session_local_json(_z_session_t *session, const z_loaned_keyexpr_t *ke,
                                                         z_owned_bytes_t *payload) {
    z_owned_encoding_t encoding;
    z_result_t ret = z_encoding_clone(&encoding, z_encoding_application_json());
    if (ret != _Z_RES_OK) {
        z_bytes_drop(z_bytes_move(payload));
        return ret;
    }

    ret = _z_write(session, ke, &payload->_val, &encoding._val, Z_SAMPLE_KIND_PUT,
                   z_internal_congestion_control_default_push(), Z_PRIORITY_DEFAULT, false, NULL, NULL,
                   Z_RELIABILITY_DEFAULT, NULL, Z_LOCALITY_SESSION_LOCAL);

    z_encoding_drop(z_encoding_move(&encoding));
    z_bytes_drop(z_bytes_move(payload));
    return ret;
}

static z_result_t _ze_admin_space_delete_session_local(_z_session_t *session, const z_loaned_keyexpr_t *ke) {
    return _z_write(session, ke, NULL, NULL, Z_SAMPLE_KIND_DELETE, z_internal_congestion_control_default_push(),
                    Z_PRIORITY_DEFAULT, false, NULL, NULL, Z_RELIABILITY_DEFAULT, NULL, Z_LOCALITY_SESSION_LOCAL);
}

static void _ze_admin_space_publish_transport_event(z_loaned_transport_event_t *event, void *ctx) {
    _ze_admin_space_connectivity_listener_ctx_t *listener_ctx = (_ze_admin_space_connectivity_listener_ctx_t *)ctx;
    if (event == NULL || listener_ctx == NULL) {
        return;
    }

    _z_session_rc_t session_rc = _z_session_weak_upgrade_if_open(&listener_ctx->_session);
    if (_Z_RC_IS_NULL(&session_rc)) {
        return;
    }

    const z_loaned_transport_t *transport = z_transport_event_transport(event);
    if (transport == NULL || z_transport_is_multicast(transport)) {
        _z_session_rc_drop(&session_rc);
        return;
    }

    _z_session_t *session = _Z_RC_IN_VAL(&session_rc);
    z_id_t peer_zid = z_transport_zid(transport);

    z_owned_keyexpr_t ke;
    z_result_t ret = _ze_admin_space_session_transport_ke(&ke, &session->_local_zid, &peer_zid);
    if (ret != _Z_RES_OK) {
        _z_session_rc_drop(&session_rc);
        return;
    }

    if (z_transport_event_kind(event) == Z_SAMPLE_KIND_PUT) {
        z_owned_bytes_t payload;
        ret = _ze_admin_space_encode_connectivity_transport_payload(&payload, &peer_zid, z_transport_whatami(transport),
                                                                    z_transport_is_qos(transport),
                                                                    z_transport_is_shm(transport));
        if (ret == _Z_RES_OK) {
            ret = _ze_admin_space_put_session_local_json(session, z_keyexpr_loan(&ke), &payload);
        }
    } else if (z_transport_event_kind(event) == Z_SAMPLE_KIND_DELETE) {
        ret = _ze_admin_space_delete_session_local(session, z_keyexpr_loan(&ke));
    } else {
        ret = _Z_RES_OK;
    }

    if (ret != _Z_RES_OK) {
        _Z_WARN("Failed to publish RFC connectivity transport event: %d", ret);
    }

    z_keyexpr_drop(z_keyexpr_move(&ke));
    _z_session_rc_drop(&session_rc);
}

static void _ze_admin_space_publish_link_event(z_loaned_link_event_t *event, void *ctx) {
    _ze_admin_space_connectivity_listener_ctx_t *listener_ctx = (_ze_admin_space_connectivity_listener_ctx_t *)ctx;
    if (event == NULL || listener_ctx == NULL) {
        return;
    }

    _z_session_rc_t session_rc = _z_session_weak_upgrade_if_open(&listener_ctx->_session);
    if (_Z_RC_IS_NULL(&session_rc)) {
        return;
    }
    _z_session_t *session = _Z_RC_IN_VAL(&session_rc);

    _z_session_transport_mutex_lock(session);
    bool is_unicast_transport = session->_tp._type == _Z_TRANSPORT_UNICAST_TYPE;
    _z_session_transport_mutex_unlock(session);
    if (!is_unicast_transport) {
        _z_session_rc_drop(&session_rc);
        return;
    }

    const z_loaned_link_t *link = z_link_event_link(event);
    if (link == NULL) {
        _z_session_rc_drop(&session_rc);
        return;
    }
    z_id_t peer_zid = z_link_zid(link);

    z_owned_keyexpr_t ke;
    z_result_t ret = _ze_admin_space_session_link_ke(&ke, &session->_local_zid, &peer_zid, &peer_zid);
    if (ret != _Z_RES_OK) {
        _z_session_rc_drop(&session_rc);
        return;
    }

    if (z_link_event_kind(event) == Z_SAMPLE_KIND_PUT) {
        z_owned_string_t src;
        z_owned_string_t dst;
        z_internal_string_null(&src);
        z_internal_string_null(&dst);

        ret = z_link_src(link, &src);
        if (ret == _Z_RES_OK) {
            ret = z_link_dst(link, &dst);
        }
        if (ret == _Z_RES_OK) {
            z_owned_bytes_t payload;
            ret = _ze_admin_space_encode_connectivity_link_payload(&payload, z_string_loan(&src), z_string_loan(&dst),
                                                                   z_link_mtu(link), z_link_is_streamed(link),
                                                                   z_link_is_reliable(link));
            if (ret == _Z_RES_OK) {
                ret = _ze_admin_space_put_session_local_json(session, z_keyexpr_loan(&ke), &payload);
            }
        }

        z_string_drop(z_string_move(&src));
        z_string_drop(z_string_move(&dst));
    } else if (z_link_event_kind(event) == Z_SAMPLE_KIND_DELETE) {
        ret = _ze_admin_space_delete_session_local(session, z_keyexpr_loan(&ke));
    } else {
        ret = _Z_RES_OK;
    }

    if (ret != _Z_RES_OK) {
        _Z_WARN("Failed to publish RFC connectivity link event: %d", ret);
    }

    z_keyexpr_drop(z_keyexpr_move(&ke));
    _z_session_rc_drop(&session_rc);
}
#endif  // Z_FEATURE_CONNECTIVITY == 1 && Z_FEATURE_PUBLICATION == 1

z_result_t zp_start_admin_space(z_loaned_session_t *zs) {
    _z_session_t *session = _Z_RC_IN_VAL(zs);
    z_id_t zid = z_info_zid(zs);
    z_result_t ret = _Z_RES_OK;
    _z_session_admin_space_mutex_lock(session);
    if (session->_admin_space_queryable_id != 0) {
        goto out;
    }

    _z_session_weak_t *pico_session_weak = _z_session_rc_clone_as_weak_ptr(zs);
    if (_Z_RC_IS_NULL(pico_session_weak)) {
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto out;
    }

    z_owned_keyexpr_t ke;
    ret = _ze_admin_space_pico_queryable_ke(&ke, &zid);
    if (ret != _Z_RES_OK) {
        _z_session_weak_drop(pico_session_weak);
        z_free(pico_session_weak);
        goto out;
    }

    z_owned_closure_query_t callback;
    ret = z_closure_query(&callback, _ze_admin_space_pico_query_handler, _ze_admin_space_query_dropper,
                          pico_session_weak);
    if (ret != _Z_RES_OK) {
        z_keyexpr_drop(z_keyexpr_move(&ke));
        _z_session_weak_drop(pico_session_weak);
        z_free(pico_session_weak);
        goto out;
    }

    z_owned_queryable_t admin_space_queryable;
    ret = z_declare_queryable(zs, &admin_space_queryable, z_keyexpr_loan(&ke), z_closure_query_move(&callback), NULL);
    z_keyexpr_drop(z_keyexpr_move(&ke));
    if (ret != _Z_RES_OK) {
        goto out;
    }

    session->_admin_space_queryable_id = admin_space_queryable._val._entity_id;
    _z_queryable_clear(&admin_space_queryable._val);

#if Z_FEATURE_CONNECTIVITY == 1
    _z_session_weak_t *session_session_weak = _z_session_rc_clone_as_weak_ptr(zs);
    if (_Z_RC_IS_NULL(session_session_weak)) {
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto err_queryable;
    }

    ret = _ze_admin_space_session_queryable_ke(&ke, &zid);
    if (ret != _Z_RES_OK) {
        _z_session_weak_drop(session_session_weak);
        z_free(session_session_weak);
        goto err_queryable;
    }

    ret = _ze_admin_space_declare_session_queryable(zs, &session->_admin_space_session_queryable_id,
                                                    z_keyexpr_loan(&ke), session_session_weak);
    z_keyexpr_drop(z_keyexpr_move(&ke));
    if (ret != _Z_RES_OK) {
        goto err_queryable;
    }

#if Z_FEATURE_PUBLICATION == 1
    session->_admin_space_transport_listener_id = 0;
    session->_admin_space_link_listener_id = 0;

    _ze_admin_space_connectivity_listener_ctx_t *transport_ctx = _ze_admin_space_connectivity_listener_ctx_new(zs);
    if (transport_ctx == NULL) {
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto err_session_queryable;
    }

    z_owned_closure_transport_event_t transport_callback;
    ret = z_closure_transport_event(&transport_callback, _ze_admin_space_publish_transport_event,
                                    _ze_admin_space_connectivity_listener_ctx_drop, transport_ctx);
    if (ret != _Z_RES_OK) {
        _ze_admin_space_connectivity_listener_ctx_drop(transport_ctx);
        goto err_session_queryable;
    }

    z_owned_transport_events_listener_t transport_listener;
    z_transport_events_listener_options_t transport_opts;
    z_transport_events_listener_options_default(&transport_opts);
    ret = z_declare_transport_events_listener(zs, &transport_listener,
                                              z_closure_transport_event_move(&transport_callback), &transport_opts);
    if (ret != _Z_RES_OK) {
        goto err_session_queryable;
    }
    session->_admin_space_transport_listener_id = transport_listener._val._id;
    _ze_admin_space_transport_listener_handle_clear(&transport_listener);

    _ze_admin_space_connectivity_listener_ctx_t *link_ctx = _ze_admin_space_connectivity_listener_ctx_new(zs);
    if (link_ctx == NULL) {
        ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        goto err_transport_listener;
    }

    z_owned_closure_link_event_t link_callback;
    ret = z_closure_link_event(&link_callback, _ze_admin_space_publish_link_event,
                               _ze_admin_space_connectivity_listener_ctx_drop, link_ctx);
    if (ret != _Z_RES_OK) {
        _ze_admin_space_connectivity_listener_ctx_drop(link_ctx);
        goto err_transport_listener;
    }

    z_owned_link_events_listener_t link_listener;
    z_link_events_listener_options_t link_opts;
    z_link_events_listener_options_default(&link_opts);
    ret = z_declare_link_events_listener(zs, &link_listener, z_closure_link_event_move(&link_callback), &link_opts);
    if (ret != _Z_RES_OK) {
        goto err_transport_listener;
    }
    session->_admin_space_link_listener_id = link_listener._val._id;
    _ze_admin_space_link_listener_handle_clear(&link_listener);
#endif
#endif

    ret = _Z_RES_OK;
    goto out;

#if Z_FEATURE_CONNECTIVITY == 1
#if Z_FEATURE_PUBLICATION == 1
err_transport_listener: {
    z_result_t undeclare_transport_listener_ret =
        _ze_admin_space_undeclare_transport_listener(zs, session->_admin_space_transport_listener_id);
    if (undeclare_transport_listener_ret == _Z_RES_OK) {
        session->_admin_space_transport_listener_id = 0;
    } else if (ret == _Z_RES_OK) {
        ret = undeclare_transport_listener_ret;
    }
}
#endif

err_session_queryable: {
    z_result_t undeclare_queryable_ret =
        _ze_admin_space_undeclare_queryable(zs, session->_admin_space_session_queryable_id);
    if (undeclare_queryable_ret == _Z_RES_OK) {
        session->_admin_space_session_queryable_id = 0;
    } else if (ret == _Z_RES_OK) {
        ret = undeclare_queryable_ret;
    }
}
#endif

#if Z_FEATURE_CONNECTIVITY == 1
err_queryable: {
    z_result_t undeclare_queryable_ret = _ze_admin_space_undeclare_queryable(zs, session->_admin_space_queryable_id);
    if (undeclare_queryable_ret == _Z_RES_OK) {
        session->_admin_space_queryable_id = 0;
    } else if (ret == _Z_RES_OK) {
        ret = undeclare_queryable_ret;
    }
}
#endif
out:
    _z_session_admin_space_mutex_unlock(session);
    return ret;
}

z_result_t zp_stop_admin_space(z_loaned_session_t *zs) {
    _z_session_t *session = _Z_RC_IN_VAL(zs);
    z_result_t ret = _Z_RES_OK;

    _z_session_admin_space_mutex_lock(session);
    uint32_t admin_space_queryable_id = session->_admin_space_queryable_id;
#if Z_FEATURE_CONNECTIVITY == 1
    uint32_t admin_space_session_queryable_id = session->_admin_space_session_queryable_id;
#if Z_FEATURE_PUBLICATION == 1
    size_t admin_space_transport_listener_id = session->_admin_space_transport_listener_id;
    size_t admin_space_link_listener_id = session->_admin_space_link_listener_id;

    if (admin_space_queryable_id == 0 && admin_space_session_queryable_id == 0 &&
        admin_space_transport_listener_id == 0 && admin_space_link_listener_id == 0) {
        goto out;
    }
#else
    if (admin_space_queryable_id == 0 && admin_space_session_queryable_id == 0) {
        goto out;
    }
#endif
#else
    if (admin_space_queryable_id == 0) {
        goto out;
    }
#endif

#if Z_FEATURE_CONNECTIVITY == 1 && Z_FEATURE_PUBLICATION == 1
    if (admin_space_transport_listener_id != 0) {
        z_result_t listener_ret = _ze_admin_space_undeclare_transport_listener(zs, admin_space_transport_listener_id);
        if (listener_ret == _Z_RES_OK) {
            session->_admin_space_transport_listener_id = 0;
        } else if (ret == _Z_RES_OK) {
            ret = listener_ret;
        }
    }

    if (admin_space_link_listener_id != 0) {
        z_result_t listener_ret = _ze_admin_space_undeclare_link_listener(zs, admin_space_link_listener_id);
        if (listener_ret == _Z_RES_OK) {
            session->_admin_space_link_listener_id = 0;
        } else if (ret == _Z_RES_OK) {
            ret = listener_ret;
        }
    }
#endif

#if Z_FEATURE_CONNECTIVITY == 1
    if (admin_space_session_queryable_id != 0) {
        z_result_t queryable_ret = _ze_admin_space_undeclare_queryable(zs, admin_space_session_queryable_id);
        if (queryable_ret == _Z_RES_OK) {
            session->_admin_space_session_queryable_id = 0;
        } else if (ret == _Z_RES_OK) {
            ret = queryable_ret;
        }
    }
#endif

    if (admin_space_queryable_id != 0) {
        z_result_t queryable_ret = _ze_admin_space_undeclare_queryable(zs, admin_space_queryable_id);
        if (queryable_ret == _Z_RES_OK) {
            session->_admin_space_queryable_id = 0;
        } else if (ret == _Z_RES_OK) {
            ret = queryable_ret;
        }
    }

out:
    _z_session_admin_space_mutex_unlock(session);
    return ret;
}

#endif  // Z_FEATURE_ADMIN_SPACE == 1
