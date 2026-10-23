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

#ifndef ZENOH_PICO_COLLECTIONS_BYTES_H
#define ZENOH_PICO_COLLECTIONS_BYTES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "arc_slice.h"
#include "vec.h"
#include "zenoh-pico/protocol/iobuf.h"

#ifdef __cplusplus
extern "C" {
#endif

_Z_ELEM_DEFINE(_z_arc_slice, _z_arc_slice_t, _z_arc_slice_size, _z_arc_slice_drop, _z_arc_slice_copy, _z_arc_slice_move,
               _z_noop_eq, _z_noop_cmp, _z_noop_hash)
_Z_SVEC_DEFINE(_z_arc_slice, _z_arc_slice_t)

/*-------- Bytes --------*/
/**
 * A container for slices.
 *
 * Members:
 *   _z_slice_vec_t _slices: contents of the container.
 */

typedef struct {
    _z_arc_slice_svec_t _slices;
} _z_bytes_t;

// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_bytes_t _z_bytes_null(void) { return (_z_bytes_t){0}; }
static inline void _z_bytes_alias_arc_slice(_z_bytes_t *dst, _z_arc_slice_t *s) {
    dst->_slices = _z_arc_slice_svec_alias_element(s);
}
static inline _z_bytes_t _z_bytes_alias(const _z_bytes_t *src) {
    if (src == NULL) {
        return _z_bytes_null();
    }
    _z_bytes_t dst;
    dst._slices = src->_slices;
    return dst;
}
static inline _z_bytes_t _z_bytes_steal(_z_bytes_t *src) {
    _z_bytes_t b = *src;
    src->_slices._len = 0;
    src->_slices._val = NULL;
    return b;
}
static inline size_t _z_bytes_num_slices(const _z_bytes_t *bs) { return _z_arc_slice_svec_len(&bs->_slices); }
static inline _z_arc_slice_t *_z_bytes_get_slice(const _z_bytes_t *bs, size_t i) {
    if (i >= _z_bytes_num_slices(bs)) return NULL;
    return _z_arc_slice_svec_get(&bs->_slices, i);
}
static inline void _z_bytes_drop(_z_bytes_t *bytes) { _z_arc_slice_svec_clear(&bytes->_slices); }

bool _z_bytes_check(const _z_bytes_t *bytes);
z_result_t _z_bytes_append_bytes(_z_bytes_t *dst, _z_bytes_t *src);
z_result_t _z_bytes_append_slice(_z_bytes_t *dst, _z_arc_slice_t *s);
z_result_t _z_bytes_copy(_z_bytes_t *dst, const _z_bytes_t *src);
_z_bytes_t _z_bytes_duplicate(const _z_bytes_t *src);
z_result_t _z_bytes_move(_z_bytes_t *dst, _z_bytes_t *src);
void _z_bytes_free(_z_bytes_t **bs);
size_t _z_bytes_len(const _z_bytes_t *bs);
bool _z_bytes_is_empty(const _z_bytes_t *bs);
z_result_t _z_bytes_to_slice(const _z_bytes_t *bytes, _z_slice_t *s);
z_result_t _z_bytes_from_slice(_z_bytes_t *b, _z_slice_t *s);
size_t _z_bytes_to_buf(const _z_bytes_t *bytes, uint8_t *dst, size_t len);
z_result_t _z_bytes_from_buf(_z_bytes_t *b, const uint8_t *src, size_t len);
_z_slice_t _z_bytes_try_get_contiguous(const _z_bytes_t *bs);

typedef struct {
    size_t slice_idx;
    size_t in_slice_idx;
    size_t byte_idx;
    const _z_bytes_t *bytes;
} _z_bytes_reader_t;

_z_bytes_reader_t _z_bytes_get_reader(const _z_bytes_t *bytes);
z_result_t _z_bytes_reader_seek(_z_bytes_reader_t *reader, int64_t offset, int origin);
int64_t _z_bytes_reader_tell(const _z_bytes_reader_t *reader);
z_result_t _z_bytes_reader_read_slices(_z_bytes_reader_t *reader, size_t len, _z_bytes_t *out);
size_t _z_bytes_reader_read(_z_bytes_reader_t *reader, uint8_t *buf, size_t len);

typedef struct {
    _z_arc_slice_t *cache;
    _z_bytes_t bytes;
} _z_bytes_writer_t;

bool _z_bytes_writer_is_empty(const _z_bytes_writer_t *writer);
bool _z_bytes_writer_check(const _z_bytes_writer_t *writer);
_z_bytes_writer_t _z_bytes_writer_from_bytes(_z_bytes_t *bytes);
_z_bytes_writer_t _z_bytes_writer_empty(void);
z_result_t _z_bytes_writer_write_all(_z_bytes_writer_t *writer, const uint8_t *src, size_t len);
z_result_t _z_bytes_writer_append_z_bytes(_z_bytes_writer_t *writer, _z_bytes_t *bytes);
z_result_t _z_bytes_writer_append_slice(_z_bytes_writer_t *writer, _z_arc_slice_t *bytes);
_z_bytes_t _z_bytes_writer_finish(_z_bytes_writer_t *writer);
void _z_bytes_writer_clear(_z_bytes_writer_t *writer);
z_result_t _z_bytes_writer_move(_z_bytes_writer_t *dst, _z_bytes_writer_t *src);
size_t _z_bytes_reader_remaining(const _z_bytes_reader_t *reader);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_COLLECTIONS_BYTES_H */
