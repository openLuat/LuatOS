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

#include "zenoh-pico/protocol/iobuf.h"

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "zenoh-pico/config.h"
#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"
#include "zenoh-pico/utils/result.h"

/*------------------ IOSli ------------------*/
_z_iosli_t _z_iosli_wrap(const uint8_t *buf, size_t length, size_t r_pos, size_t w_pos) {
    assert((r_pos <= w_pos) && (w_pos <= length));
    _z_iosli_t ios;
    ios._r_pos = r_pos;
    ios._w_pos = w_pos;
    ios._capacity = length;
    ios._is_alloc = false;
    ios._buf = (uint8_t *)buf;
    return ios;
}

_z_iosli_t _z_iosli_steal(_z_iosli_t *ios) {
    _z_iosli_t new_ios = *ios;
    *ios = _z_iosli_null();
    return new_ios;
}

void __z_iosli_init(_z_iosli_t *ios, size_t capacity) {
    ios->_r_pos = 0;
    ios->_w_pos = 0;
    ios->_capacity = capacity;
    ios->_is_alloc = true;
    ios->_buf = (uint8_t *)z_malloc(capacity);
    if (ios->_buf == NULL) {
        ios->_capacity = 0;
        ios->_is_alloc = false;
    }
}

_z_iosli_t _z_iosli_make(size_t capacity) {
    _z_iosli_t ios;
    __z_iosli_init(&ios, capacity);
    return ios;
}

_z_iosli_t *_z_iosli_new(size_t capacity) {
    _z_iosli_t *pios = (_z_iosli_t *)z_malloc(sizeof(_z_iosli_t));
    if (pios != NULL) {
        __z_iosli_init(pios, capacity);
    }
    return pios;
}

_z_slice_t _z_iosli_to_bytes(const _z_iosli_t *ios) {
    _z_slice_t a;
    a.len = _z_iosli_readable(ios);
    a.start = _z_cptr_u8_offset(ios->_buf, (ptrdiff_t)ios->_r_pos);
    return a;
}

void _z_iosli_clear(_z_iosli_t *ios) {
    if ((ios->_is_alloc) && (ios->_buf != NULL)) {
        z_free(ios->_buf);
        ios->_buf = NULL;
    }
}

void _z_iosli_free(_z_iosli_t **ios) {
    _z_iosli_t *ptr = *ios;

    if (ptr != NULL) {
        _z_iosli_clear(ptr);

        z_free(ptr);
        *ios = NULL;
    }
}

void _z_iosli_copy(_z_iosli_t *dst, const _z_iosli_t *src) {
    dst->_r_pos = src->_r_pos;
    dst->_w_pos = src->_w_pos;
    dst->_capacity = src->_capacity;
    dst->_is_alloc = src->_is_alloc;
    if (dst->_is_alloc) {
        dst->_buf = (uint8_t *)z_malloc(src->_capacity);
        if (dst->_buf != NULL) {
            (void)memcpy(dst->_buf, src->_buf, src->_capacity);
        }
    } else {
        dst->_buf = src->_buf;
    }
}

_z_iosli_t *_z_iosli_clone(const _z_iosli_t *src) {
    _z_iosli_t *dst = (_z_iosli_t *)z_malloc(_z_iosli_size(src));
    if (dst != NULL) {
        _z_iosli_copy(dst, src);
    }
    return dst;
}

/*------------------ ZBuf ------------------*/
_z_zbuf_t _z_zbuf_make(size_t capacity) {
    _z_zbuf_t zbf = _z_zbuf_null();
    zbf._ios = _z_iosli_make(capacity);
    if (_z_zbuf_capacity(&zbf) == 0) {
        return zbf;
    }
    _z_slice_t s = _z_slice_from_buf_custom_deleter(zbf._ios._buf, zbf._ios._capacity, _z_delete_context_default());
    zbf._slice = _z_slice_simple_rc_new_from_val(&s);
    if (_z_slice_simple_rc_is_null(&zbf._slice)) {
        _Z_ERROR("slice rc creation failed");
        _z_iosli_clear(&zbf._ios);
    }
    zbf._ios._is_alloc = false;
    return zbf;
}

_z_zbuf_t _z_zbuf_view(_z_zbuf_t *zbf, size_t length) {
    assert(_z_iosli_readable(&zbf->_ios) >= length);
    _z_zbuf_t v;
    v._ios = _z_iosli_wrap(_z_zbuf_get_rptr(zbf), length, 0, length);
    v._slice = zbf->_slice;
    return v;
}

_z_zbuf_t _z_slice_as_zbuf(_z_slice_t slice) {
    return (_z_zbuf_t){
        ._ios = {._buf = (uint8_t *)slice.start,  // Safety: `_z_zbuf_t` is an immutable buffer
                 ._is_alloc = false,
                 ._capacity = slice.len,
                 ._r_pos = 0,
                 ._w_pos = slice.len},
        ._slice = _z_slice_simple_rc_null(),
    };
}

void _z_zbuf_copy_bytes(_z_zbuf_t *dst, const _z_zbuf_t *src) { _z_iosli_copy_bytes(&dst->_ios, &src->_ios); }

void _z_zbuf_copy(_z_zbuf_t *dst, const _z_zbuf_t *src) {
    dst->_slice = _z_slice_simple_rc_clone(&src->_slice);
    _z_iosli_copy_bytes(&dst->_ios, &src->_ios);
}

void _z_zbuf_read_bytes(_z_zbuf_t *zbf, uint8_t *dest, size_t offset, size_t length) {
    _z_iosli_read_bytes(&zbf->_ios, dest, offset, length);
}

void _z_zbuf_clear(_z_zbuf_t *zbf) {
    _z_iosli_clear(&zbf->_ios);
    _z_slice_simple_rc_drop(&zbf->_slice);
}

void _z_zbuf_compact(_z_zbuf_t *zbf) {
    if ((zbf->_ios._r_pos != 0) || (zbf->_ios._w_pos != 0)) {
        size_t len = _z_iosli_readable(&zbf->_ios);
        (void)memmove(zbf->_ios._buf, _z_zbuf_get_rptr(zbf), len);
        _z_zbuf_set_rpos(zbf, 0);
        _z_zbuf_set_wpos(zbf, len);
    }
}

void _z_zbuf_free(_z_zbuf_t **zbf) {
    _z_zbuf_t *ptr = *zbf;

    if (ptr != NULL) {
        _z_iosli_clear(&ptr->_ios);

        z_free(ptr);
        *zbf = NULL;
    }
}

/*------------------ WBuf ------------------*/
static z_result_t _z_wbuf_add_iosli(_z_wbuf_t *wbf, _z_iosli_t *ios) {
    z_result_t res = _z_iosli_svec_append(&wbf->_ioss, ios, false);
    if (res == _Z_RES_OK) {
        wbf->_w_idx++;
    }
    return res;
}

size_t _z_wbuf_len_iosli(const _z_wbuf_t *wbf) { return _z_iosli_svec_len(&wbf->_ioss); }

_z_wbuf_t _z_wbuf_make(size_t capacity, bool is_expandable) {
    _z_wbuf_t wbf;
    if (is_expandable) {
        wbf._ioss = _z_iosli_svec_make(5);  // Dfrag buffer layout: misc, attachment, misc, payload, misc
        wbf._expansion_step = capacity;
    } else {
        wbf._ioss = _z_iosli_svec_make(1);
        wbf._expansion_step = 0;
    }
    _z_iosli_t ios = _z_iosli_make(capacity);
    z_result_t res = _z_iosli_svec_append(&wbf._ioss, &ios, false);
    if (res != _Z_RES_OK) {
        _z_iosli_clear(&ios);
    }
    wbf._w_idx = 0;
    wbf._r_idx = 0;
    return wbf;
}

size_t _z_wbuf_capacity(const _z_wbuf_t *wbf) {
    size_t cap = 0;
    for (size_t i = 0; i < _z_wbuf_len_iosli(wbf); i++) {
        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, i);
        cap = cap + ios->_capacity;
    }
    return cap;
}

size_t _z_wbuf_len(const _z_wbuf_t *wbf) {
    size_t len = 0;
    for (size_t i = wbf->_r_idx; (i < _z_wbuf_len_iosli(wbf)) && (i <= wbf->_w_idx); i++) {
        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, i);
        len = len + _z_iosli_readable(ios);
    }
    return len;
}

size_t _z_wbuf_space_left(const _z_wbuf_t *wbf) {
    _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx);
    return _z_iosli_writable(ios);
}

uint8_t _z_wbuf_read(_z_wbuf_t *wbf) {
    uint8_t ret = 0;

    do {
        assert(wbf->_r_idx <= wbf->_w_idx);
        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, wbf->_r_idx);
        size_t readable = _z_iosli_readable(ios);
        if (readable > (size_t)0) {
            ret = _z_iosli_read(ios);
            break;
        } else {
            wbf->_r_idx = wbf->_r_idx + (size_t)1;
        }
    } while (1);

    return ret;
}

void _z_wbuf_read_bytes(_z_wbuf_t *wbf, uint8_t *dest, size_t offset, size_t length) {
    size_t loffset = offset;
    size_t llength = length;

    do {
        assert(wbf->_r_idx <= wbf->_w_idx);
        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, wbf->_r_idx);
        size_t readable = _z_iosli_readable(ios);
        if (readable > (size_t)0) {
            size_t to_read = (readable <= llength) ? readable : llength;
            _z_iosli_read_bytes(ios, dest, loffset, to_read);
            loffset = loffset + to_read;
            llength = llength - to_read;
        } else {
            wbf->_r_idx = wbf->_r_idx + 1;
        }
    } while (llength > (size_t)0);
}

uint8_t _z_wbuf_get(const _z_wbuf_t *wbf, size_t pos) {
    size_t current = pos;
    size_t i = 0;

    _z_iosli_t *ios;
    do {
        assert(i < _z_iosli_svec_len(&wbf->_ioss));
        ios = _z_wbuf_get_iosli(wbf, i);
        if (current < ios->_capacity) {
            break;
        } else {
            current = current - ios->_capacity;
        }

        i = i + (size_t)1;
    } while (1);

    return _z_iosli_get(ios, current);
}

z_result_t _z_wbuf_write(_z_wbuf_t *wbf, uint8_t b) {
    _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx);
    if (!_z_iosli_can_write(ios)) {
        // Check if we need to allocate new buffer
        if (wbf->_ioss._len <= wbf->_w_idx + 1) {
            if (wbf->_expansion_step == 0) {
                _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NO_SPACE);
            }
            _z_iosli_t tmp = _z_iosli_make(wbf->_expansion_step);
            _Z_CLEAN_RETURN_IF_ERR(_z_wbuf_add_iosli(wbf, &tmp), _z_iosli_clear(&tmp));
        } else {
            wbf->_w_idx++;
        }
        ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx);
    }
    _z_iosli_write(ios, b);
    return _Z_RES_OK;
}

z_result_t _z_wbuf_write_bytes(_z_wbuf_t *wbf, const uint8_t *bs, size_t offset, size_t length) {
    _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx);
    size_t writable = _z_iosli_writable(ios);
    if (writable >= length) {
        _z_iosli_write_bytes(ios, bs, offset, length);
    } else if (wbf->_expansion_step != 0) {
        // Expand buffer to write all the data
        size_t llength = length;
        size_t loffset = offset;
        _z_iosli_write_bytes(ios, bs, loffset, writable);
        llength -= writable;
        loffset += writable;
        while (llength > (size_t)0) {
            _z_iosli_t tmp = _z_iosli_make(wbf->_expansion_step);
            _Z_CLEAN_RETURN_IF_ERR(_z_wbuf_add_iosli(wbf, &tmp), _z_iosli_clear(&tmp));
            ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx);

            writable = _z_iosli_writable(ios);
            if (llength < writable) {
                writable = llength;
            }
            _z_iosli_write_bytes(ios, bs, loffset, writable);
            llength -= writable;
            loffset += writable;
        }
    } else {
        _Z_ERROR_RETURN(_Z_ERR_TRANSPORT_NO_SPACE);
    }
    return _Z_RES_OK;
}

z_result_t _z_wbuf_wrap_bytes(_z_wbuf_t *wbf, const uint8_t *bs, size_t offset, size_t length) {
    z_result_t ret = _Z_RES_OK;

    _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx);
    size_t curr_space = _z_iosli_writable(ios);
    // Block writing on this ioslice
    ios->_capacity = ios->_w_pos;
    // Wrap data
    _z_iosli_t wios = _z_iosli_wrap(bs, length, offset, offset + length);
    _Z_CLEAN_RETURN_IF_ERR(_z_wbuf_add_iosli(wbf, &wios), _z_iosli_clear(&wios));
    // If svec expanded, ios is invalid, refresh pointer.
    ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx - 1);
    // Set remaining space as a new ioslice
    wios = _z_iosli_wrap(_z_ptr_u8_offset(ios->_buf, (ptrdiff_t)ios->_w_pos), curr_space, 0, 0);
    _Z_CLEAN_RETURN_IF_ERR(_z_wbuf_add_iosli(wbf, &wios), _z_iosli_clear(&wios));
    return ret;
}

void _z_wbuf_put(_z_wbuf_t *wbf, uint8_t b, size_t pos) {
    size_t current = pos;
    size_t i = 0;
    _z_iosli_t *ios;
    do {
        assert(i < _z_iosli_svec_len(&wbf->_ioss));
        ios = _z_wbuf_get_iosli(wbf, i);
        if (current < ios->_capacity) {
            break;
        } else {
            current = current - ios->_capacity;
        }

        i = i + (size_t)1;
    } while (1);

    _z_iosli_put(ios, b, current);
}

size_t _z_wbuf_get_rpos(const _z_wbuf_t *wbf) {
    size_t pos = 0;
    _z_iosli_t *ios;
    for (size_t i = 0; i < wbf->_r_idx; i++) {
        ios = _z_wbuf_get_iosli(wbf, i);
        pos = pos + ios->_capacity;
    }
    ios = _z_wbuf_get_iosli(wbf, wbf->_r_idx);
    pos = pos + ios->_r_pos;
    return pos;
}

size_t _z_wbuf_get_wpos(const _z_wbuf_t *wbf) {
    size_t pos = 0;
    _z_iosli_t *ios;
    for (size_t i = 0; i < wbf->_w_idx; i++) {
        ios = _z_wbuf_get_iosli(wbf, i);
        pos = pos + ios->_capacity;
    }
    ios = _z_wbuf_get_iosli(wbf, wbf->_w_idx);
    pos = pos + ios->_w_pos;
    return pos;
}

void _z_wbuf_set_rpos(_z_wbuf_t *wbf, size_t pos) {
    size_t current = pos;
    size_t i = 0;
    do {
        assert(i <= wbf->_w_idx);
        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, i);
        if (current <= ios->_w_pos) {
            wbf->_r_idx = i;
            ios->_r_pos = current;
            break;
        }

        ios->_r_pos = ios->_w_pos;
        current = current - ios->_capacity;

        i = i + (size_t)1;
    } while (1);
}

void _z_wbuf_set_wpos(_z_wbuf_t *wbf, size_t pos) {
    size_t current = pos;
    size_t i = 0;
    do {
        assert(i <= _z_iosli_svec_len(&wbf->_ioss));

        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, i);
        if ((current <= ios->_capacity) && (current >= ios->_r_pos)) {
            wbf->_w_idx = i;
            ios->_w_pos = current;
            break;
        }

        ios->_w_pos = ios->_capacity;
        current = current - ios->_capacity;

        i = i + (size_t)1;
    } while (1);
}

_z_zbuf_t _z_wbuf_to_zbuf(const _z_wbuf_t *wbf) {
    size_t len = _z_wbuf_len(wbf);
    _z_zbuf_t zbf = _z_zbuf_make(len);
    for (size_t i = wbf->_r_idx; i <= wbf->_w_idx; i++) {
        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, i);
        _z_iosli_write_bytes(&zbf._ios, ios->_buf, ios->_r_pos, _z_iosli_readable(ios));
    }
    return zbf;
}

_z_zbuf_t _z_wbuf_moved_as_zbuf(_z_wbuf_t *wbf) {
    // Can only move single buffer wbuf
    assert(_z_iosli_svec_len(&wbf->_ioss) == 1);

    _z_zbuf_t zbf = _z_zbuf_null();
    _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, 0);
    zbf._ios = _z_iosli_steal(ios);
    _z_slice_t s = _z_slice_from_buf_custom_deleter(zbf._ios._buf, zbf._ios._capacity, _z_delete_context_default());
    zbf._slice = _z_slice_simple_rc_new_from_val(&s);
    if (_z_slice_simple_rc_is_null(&zbf._slice)) {
        _Z_ERROR("slice rc creation failed");
    }
    zbf._ios._is_alloc = false;
    _z_wbuf_clear(wbf);
    return zbf;
}

z_result_t _z_wbuf_siphon(_z_wbuf_t *dst, _z_wbuf_t *src, size_t length) {
    z_result_t ret = _Z_RES_OK;
    size_t llength = length;
    _z_iosli_t *wios = _z_wbuf_get_iosli(dst, dst->_w_idx);
    size_t writable = _z_iosli_writable(wios);

    // Siphon does not work (as of now) on expandable dst buffers
    if (writable >= length) {
        do {
            assert(src->_r_idx <= src->_w_idx);
            _z_iosli_t *rios = _z_wbuf_get_iosli(src, src->_r_idx);
            size_t readable = _z_iosli_readable(rios);
            if (readable > (size_t)0) {
                size_t to_read = (readable <= llength) ? readable : llength;
                uint8_t *w_pos = _z_ptr_u8_offset(wios->_buf, (ptrdiff_t)wios->_w_pos);
                (void)memcpy(w_pos, rios->_buf + rios->_r_pos, to_read);
                rios->_r_pos = rios->_r_pos + to_read;
                llength -= to_read;
                wios->_w_pos += to_read;
            } else {
                src->_r_idx++;
            }
        } while (llength > (size_t)0);
    } else {
        _Z_ERROR_LOG(_Z_ERR_TRANSPORT_NO_SPACE);
        ret = _Z_ERR_TRANSPORT_NO_SPACE;
    }
    return ret;
}

void _z_wbuf_copy(_z_wbuf_t *dst, const _z_wbuf_t *src) {
    dst->_r_idx = src->_r_idx;
    dst->_w_idx = src->_w_idx;
    dst->_expansion_step = src->_expansion_step;
    _z_iosli_svec_copy(&dst->_ioss, &src->_ioss, false);
}

void _z_wbuf_reset(_z_wbuf_t *wbf) {
    wbf->_r_idx = 0;
    wbf->_w_idx = 0;

    // Reset to default iosli allocation
    for (size_t i = 0; i < _z_iosli_svec_len(&wbf->_ioss); i++) {
        _z_iosli_t *ios = _z_wbuf_get_iosli(wbf, i);
        if (!ios->_is_alloc) {
            _z_iosli_svec_remove(&wbf->_ioss, i, false);
        } else {
            _z_iosli_reset(ios);
        }
    }
}

void _z_wbuf_clear(_z_wbuf_t *wbf) {
    _z_iosli_svec_clear(&wbf->_ioss);
    *wbf = _z_wbuf_null();
}

void _z_wbuf_free(_z_wbuf_t **wbf) {
    _z_wbuf_t *ptr = *wbf;

    if (ptr != NULL) {
        _z_wbuf_clear(ptr);

        z_free(ptr);
        *wbf = NULL;
    }
}
