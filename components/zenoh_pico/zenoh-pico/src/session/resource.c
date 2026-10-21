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

#include "zenoh-pico/session/resource.h"

#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/api/types.h"
#include "zenoh-pico/config.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/session/utils.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"

bool _z_resource_eq(const _z_resource_t *other, const _z_resource_t *this_) { return this_->_id == other->_id; }

void _z_resource_clear(_z_resource_t *res) { _z_keyexpr_clear(&res->_key); }

size_t _z_resource_size(_z_resource_t *p) {
    _ZP_UNUSED(p);
    return sizeof(_z_resource_t);
}

void _z_resource_copy(_z_resource_t *dst, const _z_resource_t *src) {
    _z_keyexpr_copy(&dst->_key, &src->_key);
    dst->_id = src->_id;
}

void _z_resource_free(_z_resource_t **res) {
    _z_resource_t *ptr = *res;

    if (ptr != NULL) {
        _z_resource_clear(ptr);

        z_free(ptr);
        *res = NULL;
    }
}

/*------------------ Entity ------------------*/
uint32_t _z_get_entity_id(_z_session_t *zn) { return zn->_entity_id++; }

uint16_t _z_get_resource_id(_z_session_t *zn) { return zn->_resource_id++; }

/*------------------ Resource ------------------*/
_z_resource_t *_z_get_resource_by_id_inner(_z_resource_slist_t *rl, const _z_zint_t id) {
    _z_resource_t *ret = NULL;

    _z_resource_slist_t *xs = rl;
    while (xs != NULL) {
        _z_resource_t *r = _z_resource_slist_value(xs);
        if (r->_id == id) {
            ret = r;
            break;
        }

        xs = _z_resource_slist_next(xs);
    }

    return ret;
}

_z_resource_t *_z_get_resource_by_key_inner(_z_resource_slist_t *rl, const _z_keyexpr_t *keyexpr) {
    _z_resource_t *ret = NULL;
    _z_resource_slist_t *xs = rl;
    while (xs != NULL) {
        _z_resource_t *r = _z_resource_slist_value(xs);
        if (_z_keyexpr_equals(&r->_key, keyexpr)) {
            ret = r;
            break;
        }

        xs = _z_resource_slist_next(xs);
    }

    return ret;
}

static z_result_t _z_get_keyexpr_from_wireexpr_inner(_z_keyexpr_t *ret, _z_resource_slist_t *xs,
                                                     const _z_wireexpr_t *expr, bool alias_wireexpr_if_possible) {
    *ret = _z_keyexpr_null();
    _z_zint_t id = expr->_id;

    if (id == Z_RESOURCE_ID_NONE) {  // Check if ke is already expanded
        if (alias_wireexpr_if_possible) {
            ret->_keyexpr = _z_string_alias(expr->_suffix);
            return _Z_RES_OK;
        } else {
            return _z_string_copy(&ret->_keyexpr, &expr->_suffix);
        }
    } else {
        _z_resource_t *res = _z_get_resource_by_id_inner(xs, id);
        if (res == NULL) {
            return _Z_ERR_KEYEXPR_UNKNOWN;
        }
        _z_keyexpr_t ke_prefix = _z_keyexpr_alias(&res->_key);
        return _z_string_concat(&ret->_keyexpr, &ke_prefix._keyexpr, &expr->_suffix, NULL, 0);
    }
}

z_result_t _z_get_keyexpr_from_wireexpr(_z_session_t *zn, _z_keyexpr_t *out, const _z_wireexpr_t *expr,
                                        _z_transport_peer_common_t *peer, bool alias_wireexpr_if_possible) {
    *out = _z_keyexpr_null();
    z_result_t ret = _Z_ERR_NULL;
    if (expr != NULL && _z_wireexpr_check(expr)) {
        _z_session_mutex_lock(zn);
        _z_resource_slist_t *decls =
            (_z_wireexpr_is_local(expr) || (peer == NULL)) ? zn->_local_resources : peer->_remote_resources;
        ret = _z_get_keyexpr_from_wireexpr_inner(out, decls, expr, alias_wireexpr_if_possible);
        _z_session_mutex_unlock(zn);
    }
    return ret;
}

z_result_t _z_register_resource_inner(_z_session_t *zn, const _z_wireexpr_t *expr, uint16_t id,
                                      _z_transport_peer_common_t *peer, uint16_t *out_id) {
    _z_resource_slist_t **resources = (peer == NULL) ? &zn->_local_resources : &peer->_remote_resources;
    _z_resource_slist_t *parent_resources =
        (expr->_mapping == _Z_KEYEXPR_MAPPING_LOCAL) ? zn->_local_resources : peer->_remote_resources;

    _z_keyexpr_t new_key = _z_keyexpr_null();
    if (expr->_id != Z_RESOURCE_ID_NONE) {
        _z_resource_t *res = _z_get_resource_by_id_inner(parent_resources, expr->_id);
        if (res == NULL) {
            _Z_ERROR("Unknown scope: %d, for mapping: %zu", (unsigned int)expr->_id, (size_t)expr->_mapping);
            return _Z_ERR_ENTITY_DECLARATION_FAILED;
        }
        if (_z_wireexpr_has_suffix(expr)) {
            if (_z_string_concat(&new_key._keyexpr, &res->_key._keyexpr, &expr->_suffix, NULL, 0) != _Z_RES_OK) {
                _Z_ERROR("Failed to allocate memory for new string");
                return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            }
        } else if (id == Z_RESOURCE_ID_NONE && *resources == parent_resources) {
            // declaration of already declared resource
            res->_refcount++;
            *out_id = res->_id;
            return _Z_RES_OK;
        } else {  // redeclaration of exisiting resource
            new_key = _z_keyexpr_alias(&res->_key);
        }
    } else {
        new_key = _z_keyexpr_alias_from_string(&expr->_suffix);
    }

    if (id == Z_RESOURCE_ID_NONE) {
        _z_resource_t *res = _z_get_resource_by_key_inner(*resources, &new_key);
        if (res != NULL) {  // declaration of already declared resource
            res->_refcount++;
            _z_keyexpr_clear(&new_key);
            *out_id = res->_id;
            return _Z_RES_OK;
        }
    }
    _z_keyexpr_t ke;
    _Z_RETURN_IF_ERR(_z_keyexpr_move(&ke, &new_key));

    *resources = _z_resource_slist_push_empty(*resources);
    _z_resource_t *res = _z_resource_slist_value(*resources);
    res->_refcount = 1;
    res->_key = ke;
    res->_id = id == Z_RESOURCE_ID_NONE ? _z_get_resource_id(zn) : id;
    *out_id = res->_id;
    return _Z_RES_OK;
}

z_result_t _z_register_resource(_z_session_t *zn, const _z_wireexpr_t *expr, uint16_t id,
                                _z_transport_peer_common_t *peer, uint16_t *out_id) {
    _Z_RETURN_IF_ERR(_z_session_mutex_lock_if_open(zn));
    z_result_t ret = _z_register_resource_inner(zn, expr, id, peer, out_id);
    _z_session_mutex_unlock(zn);

    return ret;
}

z_result_t _z_unregister_resource(_z_session_t *zn, uint16_t id, _z_transport_peer_common_t *peer) {
    bool is_local = true;
    uintptr_t mapping = _Z_KEYEXPR_MAPPING_LOCAL;
    if (peer != NULL) {
        is_local = false;
        mapping = (uintptr_t)peer;
    }
    _Z_DEBUG("unregistering: id %d, mapping: %d", id, (unsigned int)mapping);
    _z_session_mutex_lock(zn);
    _z_resource_slist_t **resources = is_local ? &zn->_local_resources : &peer->_remote_resources;
    _z_resource_t res = {0};
    res._id = id;
    _z_resource_slist_t *res_ptr = _z_resource_slist_find(*resources, _z_resource_eq, &res);
    z_result_t ret = _Z_RESOURCE_POSITIVE_REF_COUNT;
    if (res_ptr == NULL) {
        ret = _Z_ERR_KEYEXPR_UNKNOWN;
    } else {
        _z_resource_slist_value(res_ptr)->_refcount--;
        if (_z_resource_slist_value(res_ptr)->_refcount == 0) {
            ret = _Z_RES_OK;
            *resources = _z_resource_slist_drop_first_filter(*resources, _z_resource_eq, &res);
        }
    }
    _z_session_mutex_unlock(zn);
    return ret;
}

void _z_flush_local_resources(_z_session_t *zn) {
    _z_session_mutex_lock(zn);
    _z_resource_slist_free(&zn->_local_resources);
    _z_session_mutex_unlock(zn);
}
