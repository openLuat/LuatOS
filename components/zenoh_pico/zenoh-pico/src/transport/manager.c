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

#include "zenoh-pico/transport/manager.h"

#include <stddef.h>
#include <stdlib.h>

#include "zenoh-pico/link/link.h"
#include "zenoh-pico/runtime/runtime.h"
#include "zenoh-pico/system/common/platform.h"
#include "zenoh-pico/transport/multicast/transport.h"
#include "zenoh-pico/transport/unicast/accept.h"
#include "zenoh-pico/transport/unicast/transport.h"

static z_result_t _z_new_transport_client(_z_transport_t *zt, const _z_string_t *locator, const _z_id_t *local_zid,
                                          const _z_config_t *session_cfg) {
    z_result_t ret = _Z_RES_OK;
    // Init link
    _z_link_t *zl = (_z_link_t *)z_malloc(sizeof(_z_link_t));
    if (zl == NULL) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    memset(zl, 0, sizeof(_z_link_t));
    // Open link
    ret = _z_open_link(zl, locator, session_cfg);
    if (ret != _Z_RES_OK) {
        z_free(zl);
        return ret;
    }
    // Open transport
    switch (zl->_cap._transport) {
        // Unicast transport
        case Z_LINK_CAP_TRANSPORT_UNICAST: {
            _z_transport_unicast_establish_param_t tp_param;
            ret = _z_unicast_open_client(&tp_param, zl, local_zid);
            if (ret != _Z_RES_OK) {
                _z_link_free(&zl);
                return ret;
            }
            ret = _z_unicast_transport_create(zt, zl, &tp_param);
            // Fill peer list
            if (ret == _Z_RES_OK) {
                ret = _z_transport_peer_unicast_add(&zt->_transport._unicast, &tp_param, *_z_link_get_socket(zl), false,
                                                    NULL);
            }
            break;
        }
        // Multicast transport
        case Z_LINK_CAP_TRANSPORT_RAWETH:
        case Z_LINK_CAP_TRANSPORT_MULTICAST: {
            _z_transport_multicast_establish_param_t tp_param = {0};
            ret = _z_multicast_open_client(&tp_param, zl, local_zid);
            if (ret != _Z_RES_OK) {
                _z_link_free(&zl);
                return ret;
            }
            ret = _z_multicast_transport_create(zt, zl, &tp_param);
            break;
        }
        default:
            _Z_ERROR_LOG(_Z_ERR_GENERIC);
            _z_link_free(&zl);
            ret = _Z_ERR_GENERIC;
            break;
    }
    return ret;
}

static z_result_t _z_new_transport_peer(_z_transport_t *zt, const _z_string_t *locator, const _z_id_t *local_zid,
                                        int peer_op, const _z_config_t *session_cfg, _z_runtime_t *runtime) {
    z_result_t ret = _Z_RES_OK;
    // Init link
    _z_link_t *zl = (_z_link_t *)z_malloc(sizeof(_z_link_t));
    if (zl == NULL) {
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    memset(zl, 0, sizeof(_z_link_t));
    // Listen link
    if (peer_op == _Z_PEER_OP_OPEN) {
        ret = _z_open_link(zl, locator, session_cfg);
    } else {
        ret = _z_listen_link(zl, locator, session_cfg);
    }
    if (ret != _Z_RES_OK) {
        z_free(zl);
        return ret;
    }
    switch (zl->_cap._transport) {
        case Z_LINK_CAP_TRANSPORT_UNICAST: {
#if Z_FEATURE_UNICAST_PEER == 1
            _z_transport_unicast_establish_param_t tp_param = {0};
            ret = _z_unicast_open_peer(&tp_param, zl, local_zid, peer_op, NULL);
            if (ret != _Z_RES_OK) {
                _z_link_free(&zl);
                return ret;
            }
            ret = _z_unicast_transport_create(zt, zl, &tp_param);
            _Z_SET_IF_OK(ret, _z_socket_set_blocking(_z_link_get_socket(zl), false));
            if (ret == _Z_RES_OK) {
                if (peer_op == _Z_PEER_OP_OPEN) {
                    ret = _z_transport_peer_unicast_add(&zt->_transport._unicast, &tp_param, *_z_link_get_socket(zl),
                                                        false, NULL);
                } else {
                    _z_fut_t f = _z_fut_null();
                    f._fut_arg = &zt->_transport._unicast;
                    f._fut_fn = _zp_unicast_accept_task_fn;
                    if (_z_fut_handle_is_null(_z_runtime_spawn(runtime, &f))) {
                        _Z_ERROR("Failed to spawn unicast accept task after transport creation.");
                        ret = _Z_ERR_FAILED_TO_SPAWN_TASK;
                    }
                }
            }
#else
            _ZP_UNUSED(runtime);
            _Z_ERROR_LOG(_Z_ERR_TRANSPORT_OPEN_FAILED);
            ret = _Z_ERR_TRANSPORT_OPEN_FAILED;
#endif
            break;
        }
        case Z_LINK_CAP_TRANSPORT_RAWETH:
        case Z_LINK_CAP_TRANSPORT_MULTICAST: {
            _z_transport_multicast_establish_param_t tp_param;
            ret = _z_multicast_open_peer(&tp_param, zl, local_zid);
            if (ret != _Z_RES_OK) {
                _z_link_free(&zl);
                return ret;
            }
            ret = _z_multicast_transport_create(zt, zl, &tp_param);
            break;
        }
        default:
            _Z_ERROR_LOG(_Z_ERR_GENERIC);
            _z_link_free(&zl);
            ret = _Z_ERR_GENERIC;
            break;
    }
    return ret;
}

z_result_t _z_new_transport(_z_transport_t *zt, const _z_id_t *bs, const _z_string_t *locator, z_whatami_t mode,
                            int peer_op, const _z_config_t *session_cfg, _z_runtime_t *runtime) {
    z_result_t ret;

    if (mode == Z_WHATAMI_CLIENT) {
        ret = _z_new_transport_client(zt, locator, bs, session_cfg);
    } else {
        ret = _z_new_transport_peer(zt, locator, bs, peer_op, session_cfg, runtime);
    }

    return ret;
}

z_result_t _z_new_peer(_z_transport_t *zt, const _z_id_t *session_id, const _z_string_t *locator,
                       const _z_config_t *session_cfg) {
    z_result_t ret = _Z_RES_OK;
    switch (zt->_type) {
        case _Z_TRANSPORT_UNICAST_TYPE: {
            _z_sys_net_socket_t socket = {0};
            _Z_RETURN_IF_ERR(_z_open_socket(locator, session_cfg, &socket));
            _z_transport_unicast_establish_param_t tp_param = {0};
            ret = _z_unicast_open_peer(&tp_param, zt->_transport._unicast._common._link, session_id, _Z_PEER_OP_OPEN,
                                       &socket);
            if (ret != _Z_RES_OK) {
                _z_socket_close(&socket);
                return ret;
            }
            ret = _z_socket_set_blocking(&socket, false);
            if (ret != _Z_RES_OK) {
                _z_socket_close(&socket);
                return ret;
            }
            ret = _z_transport_peer_unicast_add(&zt->_transport._unicast, &tp_param, socket, true, NULL);
        } break;

        default:
            break;
    }
    return ret;
}
