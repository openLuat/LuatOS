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

#ifndef ZENOH_PICO_PROTOCOL_IOBUF_H
#define ZENOH_PICO_PROTOCOL_IOBUF_H

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zenoh-pico/collections/arc_slice.h"
#include "zenoh-pico/collections/element.h"
#include "zenoh-pico/collections/slice.h"
#include "zenoh-pico/collections/vec.h"
#include "zenoh-pico/utils/pointers.h"

#ifdef __cplusplus
extern "C" {
#endif

/*------------------ IOSli ------------------*/

typedef struct {
    size_t _r_pos;
    size_t _w_pos;
    size_t _capacity;
    uint8_t *_buf;
    bool _is_alloc;
} _z_iosli_t;

static inline _z_iosli_t _z_iosli_null(void) { return (_z_iosli_t){0}; }
static inline size_t _z_iosli_writable(const _z_iosli_t *ios) { return ios->_capacity - ios->_w_pos; }
static inline size_t _z_iosli_readable(const _z_iosli_t *ios) { return ios->_w_pos - ios->_r_pos; }
static inline bool _z_iosli_can_write(const _z_iosli_t *ios) { return ios->_capacity > ios->_w_pos; }
static inline bool _z_iosli_can_read(const _z_iosli_t *ios) { return ios->_w_pos > ios->_r_pos; }
static inline uint8_t _z_iosli_read(_z_iosli_t *ios) {
    assert(ios->_r_pos < ios->_w_pos);
    return ios->_buf[ios->_r_pos++];
}
static inline uint8_t *_z_iosli_read_as_ref(_z_iosli_t *ios) {
    assert(ios->_r_pos < ios->_w_pos);
    return &ios->_buf[ios->_r_pos++];
}
static inline void _z_iosli_write(_z_iosli_t *ios, uint8_t b) {
    assert(ios->_capacity > ios->_w_pos);
    ios->_buf[ios->_w_pos++] = b;
}
static inline uint8_t _z_iosli_get(const _z_iosli_t *ios, size_t pos) {
    assert(pos < ios->_capacity);
    return ios->_buf[pos];
}
static inline void _z_iosli_put(_z_iosli_t *ios, uint8_t b, size_t pos) {
    assert(pos < ios->_capacity);
    ios->_buf[pos] = b;
}
static inline void _z_iosli_reset(_z_iosli_t *ios) {
    ios->_r_pos = 0;
    ios->_w_pos = 0;
}
static inline size_t _z_iosli_size(const _z_iosli_t *ios) {
    (void)(ios);
    return sizeof(_z_iosli_t);
}
static inline void _z_iosli_read_bytes(_z_iosli_t *ios, uint8_t *dst, size_t offset, size_t length) {
    assert(_z_iosli_readable(ios) >= length);
    uint8_t *w_pos = _z_ptr_u8_offset(dst, (ptrdiff_t)offset);
    (void)memcpy(w_pos, ios->_buf + ios->_r_pos, length);
    ios->_r_pos = ios->_r_pos + length;
}
static inline void _z_iosli_copy_bytes(_z_iosli_t *dst, const _z_iosli_t *src) {
    size_t length = _z_iosli_readable(src);
    assert(dst->_capacity >= length);
    (void)memcpy(dst->_buf + dst->_w_pos, src->_buf + src->_r_pos, length);
    dst->_w_pos += length;
}
static inline void _z_iosli_write_bytes(_z_iosli_t *ios, const uint8_t *bs, size_t offset, size_t length) {
    assert(_z_iosli_writable(ios) >= length);
    uint8_t *w_pos = _z_ptr_u8_offset(ios->_buf, (ptrdiff_t)ios->_w_pos);
    (void)memcpy(w_pos, _z_cptr_u8_offset(bs, (ptrdiff_t)offset), length);
    ios->_w_pos += length;
}

_z_iosli_t _z_iosli_make(size_t capacity);
_z_iosli_t *_z_iosli_new(size_t capacity);
_z_iosli_t _z_iosli_wrap(const uint8_t *buf, size_t length, size_t r_pos, size_t w_pos);
_z_iosli_t _z_iosli_steal(_z_iosli_t *ios);
_z_slice_t _z_iosli_to_bytes(const _z_iosli_t *ios);
size_t _z_iosli_size(const _z_iosli_t *ios);
void _z_iosli_clear(_z_iosli_t *ios);
void _z_iosli_free(_z_iosli_t **ios);
void _z_iosli_copy(_z_iosli_t *dst, const _z_iosli_t *src);
_z_iosli_t *_z_iosli_clone(const _z_iosli_t *src);

_Z_ELEM_DEFINE(_z_iosli, _z_iosli_t, _z_iosli_size, _z_iosli_clear, _z_iosli_copy, _z_noop_move, _z_noop_eq,
               _z_noop_cmp, _z_noop_hash)
_Z_SVEC_DEFINE(_z_iosli, _z_iosli_t)

/*------------------ ZBuf ------------------*/
typedef struct {
    _z_iosli_t _ios;
    _z_slice_simple_rc_t _slice;
} _z_zbuf_t;

static inline size_t _z_zbuf_get_ref_count(const _z_zbuf_t *zbf) { return _z_slice_simple_rc_count(&zbf->_slice); }
static inline _z_zbuf_t _z_zbuf_null(void) { return (_z_zbuf_t){0}; }
static inline void _z_zbuf_reset(_z_zbuf_t *zbf) { _z_iosli_reset(&zbf->_ios); }

static inline uint8_t const *_z_zbuf_start(const _z_zbuf_t *zbf) {
    return _z_ptr_u8_offset(zbf->_ios._buf, (ptrdiff_t)zbf->_ios._r_pos);
}
static inline size_t _z_zbuf_capacity(const _z_zbuf_t *zbf) { return zbf->_ios._capacity; }
static inline size_t _z_zbuf_space_left(const _z_zbuf_t *zbf) { return _z_iosli_writable(&zbf->_ios); }

static inline size_t _z_zbuf_len(const _z_zbuf_t *zbf) { return _z_iosli_readable(&zbf->_ios); }
static inline bool _z_zbuf_can_read(const _z_zbuf_t *zbf) { return _z_iosli_can_read(&zbf->_ios); }
static inline uint8_t _z_zbuf_read(_z_zbuf_t *zbf) { return _z_iosli_read(&zbf->_ios); }
static inline uint8_t *_z_zbuf_read_as_ref(_z_zbuf_t *zbf) { return _z_iosli_read_as_ref(&zbf->_ios); }
static inline uint8_t _z_zbuf_get(const _z_zbuf_t *zbf, size_t pos) { return _z_iosli_get(&zbf->_ios, pos); }

static inline size_t _z_zbuf_get_rpos(const _z_zbuf_t *zbf) { return zbf->_ios._r_pos; }
static inline size_t _z_zbuf_get_wpos(const _z_zbuf_t *zbf) { return zbf->_ios._w_pos; }
static inline void _z_zbuf_set_rpos(_z_zbuf_t *zbf, size_t r_pos) {
    assert(r_pos <= zbf->_ios._w_pos);
    zbf->_ios._r_pos = r_pos;
}
static inline void _z_zbuf_set_wpos(_z_zbuf_t *zbf, size_t w_pos) {
    assert(w_pos <= zbf->_ios._capacity);
    zbf->_ios._w_pos = w_pos;
}
static inline uint8_t *_z_zbuf_get_rptr(const _z_zbuf_t *zbf) { return zbf->_ios._buf + zbf->_ios._r_pos; }
static inline uint8_t *_z_zbuf_get_wptr(const _z_zbuf_t *zbf) { return zbf->_ios._buf + zbf->_ios._w_pos; }

// Constructs a _borrowing_ reader on `slice`
_z_zbuf_t _z_zbuf_make(size_t capacity);
_z_zbuf_t _z_zbuf_view(_z_zbuf_t *zbf, size_t length);
_z_zbuf_t _z_slice_as_zbuf(_z_slice_t slice);

void _z_zbuf_copy_bytes(_z_zbuf_t *dst, const _z_zbuf_t *src);
void _z_zbuf_copy(_z_zbuf_t *dst, const _z_zbuf_t *src);
void _z_zbuf_read_bytes(_z_zbuf_t *zbf, uint8_t *dest, size_t offset, size_t length);
void _z_zbuf_compact(_z_zbuf_t *zbf);
void _z_zbuf_clear(_z_zbuf_t *zbf);
void _z_zbuf_free(_z_zbuf_t **zbf);

/*------------------ WBuf ------------------*/
typedef struct {
    _z_iosli_svec_t _ioss;
    size_t _r_idx;
    size_t _w_idx;
    size_t _expansion_step;
} _z_wbuf_t;

static inline _z_wbuf_t _z_wbuf_null(void) { return (_z_wbuf_t){0}; }
static inline _z_iosli_t *_z_wbuf_get_iosli(const _z_wbuf_t *wbf, size_t idx) {
    return _z_iosli_svec_get(&wbf->_ioss, idx);
}
_z_wbuf_t _z_wbuf_make(size_t capacity, bool is_expandable);

size_t _z_wbuf_capacity(const _z_wbuf_t *wbf);
size_t _z_wbuf_len(const _z_wbuf_t *wbf);
size_t _z_wbuf_space_left(const _z_wbuf_t *wbf);

z_result_t _z_wbuf_write(_z_wbuf_t *wbf, uint8_t b);
z_result_t _z_wbuf_write_bytes(_z_wbuf_t *wbf, const uint8_t *bs, size_t offset, size_t length);
z_result_t _z_wbuf_wrap_bytes(_z_wbuf_t *wbf, const uint8_t *bs, size_t offset, size_t length);
void _z_wbuf_put(_z_wbuf_t *wbf, uint8_t b, size_t pos);

size_t _z_wbuf_get_rpos(const _z_wbuf_t *wbf);
size_t _z_wbuf_get_wpos(const _z_wbuf_t *wbf);
void _z_wbuf_set_rpos(_z_wbuf_t *wbf, size_t r_pos);
void _z_wbuf_set_wpos(_z_wbuf_t *wbf, size_t w_pos);

size_t _z_wbuf_len_iosli(const _z_wbuf_t *wbf);

_z_zbuf_t _z_wbuf_to_zbuf(const _z_wbuf_t *wbf);
_z_zbuf_t _z_wbuf_moved_as_zbuf(_z_wbuf_t *wbf);
z_result_t _z_wbuf_siphon(_z_wbuf_t *dst, _z_wbuf_t *src, size_t length);

void _z_wbuf_copy(_z_wbuf_t *dst, const _z_wbuf_t *src);
void _z_wbuf_reset(_z_wbuf_t *wbf);
void _z_wbuf_clear(_z_wbuf_t *wbf);
void _z_wbuf_free(_z_wbuf_t **wbf);

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_PROTOCOL_IOBUF_H */
