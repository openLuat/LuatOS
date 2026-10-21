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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_EXTCODEC_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_EXTCODEC_H

#include <stdint.h>

#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/protocol/ext.h"
#include "zenoh-pico/protocol/iobuf.h"

#ifdef __cplusplus
extern "C" {
#endif

/*------------------ Message Extension ------------------*/
z_result_t _z_msg_ext_encode(_z_wbuf_t *wbf, const _z_msg_ext_t *ext, bool has_next);
z_result_t _z_msg_ext_decode(_z_msg_ext_t *ext, _z_zbuf_t *zbf, bool *has_next);
z_result_t _z_msg_ext_decode_na(_z_msg_ext_t *ext, _z_zbuf_t *zbf, bool *has_next);
z_result_t _z_msg_ext_vec_encode(_z_wbuf_t *wbf, const _z_msg_ext_vec_t *extensions);
z_result_t _z_msg_ext_vec_decode(_z_msg_ext_vec_t *extensions, _z_zbuf_t *zbf);
/**
 * Iterates through the extensions in `zbf`, assuming at least one is present at its beginning
 * (calling this function otherwise is UB). Short-circuits if `callback` returns a non-zero value.
 *
 * `callback` will receive `context` as its second argument, and may "steal" its first argument by
 * copying its value and setting it to `_z_msg_ext_make_unit(0)`.
 */
z_result_t _z_msg_ext_decode_iter(_z_zbuf_t *zbf, z_result_t (*callback)(_z_msg_ext_t *, void *), void *context);
/**
 * Iterates through the extensions in `zbf`, assuming at least one is present at its beginning.
 * Returns `_Z_ERR_MESSAGE_EXTENSION_MANDATORY_AND_UNKNOWN` if a mandatory extension is found,
 * `_Z_RES_OK` otherwise.
 */
z_result_t _z_msg_ext_skip_non_mandatories(_z_zbuf_t *zbf, uint8_t trace_id);
/**
 * Logs an error to debug the unknown extension, returning `_Z_ERR_MESSAGE_EXTENSION_MANDATORY_AND_UNKNOWN`.
 *
 * `trace_id` may be any arbitrary value, but is advised to be unique to its call-site,
 * to help debugging should it be necessary.
 */
z_result_t _z_msg_ext_unknown_error(_z_msg_ext_t *extension, uint8_t trace_id);

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_CODEC_EXTCODEC_H */

// NOTE: the following headers are for unit testing only
#ifdef ZENOH_PICO_TEST_H
// ------------------ Message Fields ------------------
z_result_t _z_msg_ext_encode_unit(_z_wbuf_t *wbf, const _z_msg_ext_unit_t *pld);
z_result_t _z_msg_ext_decode_unit(_z_msg_ext_unit_t *pld, _z_zbuf_t *zbf);
z_result_t _z_msg_ext_decode_unit_na(_z_msg_ext_unit_t *pld, _z_zbuf_t *zbf);

z_result_t _z_msg_ext_encode_zint(_z_wbuf_t *wbf, const _z_msg_ext_zint_t *pld);
z_result_t _z_msg_ext_decode_zint(_z_msg_ext_zint_t *pld, _z_zbuf_t *zbf);
z_result_t _z_msg_ext_decode_zint_na(_z_msg_ext_zint_t *pld, _z_zbuf_t *zbf);

z_result_t _z_msg_ext_encode_zbuf(_z_wbuf_t *wbf, const _z_msg_ext_zbuf_t *pld);
z_result_t _z_msg_ext_decode_zbuf(_z_msg_ext_zbuf_t *pld, _z_zbuf_t *zbf);
z_result_t _z_msg_ext_decode_zbuf_na(_z_msg_ext_zbuf_t *pld, _z_zbuf_t *zbf);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_TEST_H */
