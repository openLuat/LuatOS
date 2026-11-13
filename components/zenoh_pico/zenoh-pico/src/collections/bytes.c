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

#include "zenoh-pico/collections/bytes.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "zenoh-pico/api/olv_macros.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/system/platform.h"
#include "zenoh-pico/utils/endianness.h"
#include "zenoh-pico/utils/result.h"

/*-------- Bytes --------*/
bool _z_bytes_check(const _z_bytes_t *bytes) { return !_z_bytes_is_empty(bytes); }

z_result_t _z_bytes_copy(_z_bytes_t *dst, const _z_bytes_t *src) {
    return _z_arc_slice_svec_copy(&dst->_slices, &src->_slices, true);
}

_z_bytes_t _z_bytes_duplicate(const _z_bytes_t *src) {
    _z_bytes_t dst = _z_bytes_null();
    _z_bytes_copy(&dst, src);
    return dst;
}

size_t _z_bytes_len(const _z_bytes_t *bs) {
    size_t len = 0;
    for (size_t i = 0; i < _z_arc_slice_svec_len(&bs->_slices); ++i) {
        const _z_arc_slice_t *s = _z_arc_slice_svec_get(&bs->_slices, i);
        len += _z_arc_slice_len(s);
    }
    return len;
}

bool _z_bytes_is_empty(const _z_bytes_t *bs) {
    for (size_t i = 0; i < _z_arc_slice_svec_len(&bs->_slices); i++) {
        const _z_arc_slice_t *s = _z_arc_slice_svec_get(&bs->_slices, i);
        if (_z_arc_slice_len(s) > 0) return false;
    }
    return true;
}

void _z_bytes_free(_z_bytes_t **bs) {
    _z_bytes_t *ptr = *bs;

    if (ptr != NULL) {
        _z_bytes_drop(ptr);

        z_free(ptr);
        *bs = NULL;
    }
}

size_t _z_bytes_to_buf(const _z_bytes_t *bytes, uint8_t *dst, size_t len) {
    uint8_t *start = dst;
    size_t remaining = len;
    for (size_t i = 0; i < _z_bytes_num_slices(bytes) && remaining > 0; ++i) {
        // Recopy data
        _z_arc_slice_t *s = _z_bytes_get_slice(bytes, i);
        size_t s_len = _z_arc_slice_len(s);
        size_t len_to_copy = remaining >= s_len ? s_len : remaining;
        memcpy(start, _z_arc_slice_data(s), len_to_copy);
        start += len_to_copy;
        remaining -= len_to_copy;
    }

    return len - remaining;
}
z_result_t _z_bytes_from_slice(_z_bytes_t *b, _z_slice_t *s) {
    *b = _z_bytes_null();
    _z_arc_slice_t arc_s = _z_arc_slice_wrap(s, 0, s->len);
    if (_z_arc_slice_len(&arc_s) != s->len) _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    return _z_arc_slice_svec_append(&b->_slices, &arc_s, true);
}

z_result_t _z_bytes_from_buf(_z_bytes_t *b, const uint8_t *src, size_t len) {
    *b = _z_bytes_null();
    if (len == 0) return _Z_RES_OK;
    _z_slice_t s = _z_slice_copy_from_buf(src, len);
    if (s.len != len) _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    return _z_bytes_from_slice(b, &s);
}

z_result_t _z_bytes_to_slice(const _z_bytes_t *bytes, _z_slice_t *s) {
    // TODO: consider return a slice with custom deleter referencing the corresponding _arc_slice
    // to avoid extra copy
    // Allocate slice
    size_t len = _z_bytes_len(bytes);
    *s = _z_slice_make(len);
    if (!_z_slice_check(s) && len > 0) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }
    uint8_t *start = (uint8_t *)s->start;
    for (size_t i = 0; i < _z_bytes_num_slices(bytes); ++i) {
        // Recopy data
        _z_arc_slice_t *arc_s = _z_bytes_get_slice(bytes, i);
        size_t s_len = _z_arc_slice_len(arc_s);
        memcpy(start, _z_arc_slice_data(arc_s), s_len);
        start += s_len;
    }

    return _Z_RES_OK;
}

z_result_t _z_bytes_append_slice(_z_bytes_t *dst, _z_arc_slice_t *s) {
    z_result_t ret = _Z_RES_OK;
    ret = _z_arc_slice_svec_append(&dst->_slices, s, true);
    if (ret != _Z_RES_OK) {
        _z_arc_slice_drop(s);
    }
    return ret;
}

z_result_t _z_bytes_append_bytes(_z_bytes_t *dst, _z_bytes_t *src) {
    z_result_t res = _Z_RES_OK;
    for (size_t i = 0; i < _z_bytes_num_slices(src); ++i) {
        _z_arc_slice_t s;
        _z_arc_slice_move(&s, _z_bytes_get_slice(src, i));
        res = _z_bytes_append_slice(dst, &s);
        if (res != _Z_RES_OK) {
            break;
        }
    }

    _z_bytes_drop(src);
    return res;
}

_z_slice_t _z_bytes_try_get_contiguous(const _z_bytes_t *bs) {
    if (_z_bytes_num_slices(bs) == 1) {
        _z_arc_slice_t *arc_s = _z_bytes_get_slice(bs, 0);
        return _z_slice_alias_buf(_z_arc_slice_data(arc_s), _z_arc_slice_len(arc_s));
    }
    return _z_slice_null();
}

z_result_t _z_bytes_move(_z_bytes_t *dst, _z_bytes_t *src) {
    if (src->_slices._aliased) {
        *dst = _z_bytes_null();
        _z_bytes_t csrc;
        _Z_RETURN_IF_ERR(_z_arc_slice_svec_copy(&csrc._slices, &src->_slices, false));
        *src = csrc;
    }
    *dst = *src;
    *src = _z_bytes_null();
    return _Z_RES_OK;
}

_z_bytes_reader_t _z_bytes_get_reader(const _z_bytes_t *bytes) {
    _z_bytes_reader_t r;
    r.bytes = bytes;
    r.slice_idx = 0;
    r.byte_idx = 0;
    r.in_slice_idx = 0;
    return r;
}

z_result_t _z_bytes_reader_seek_forward(_z_bytes_reader_t *reader, size_t offset) {
    size_t start_slice = reader->slice_idx;
    for (size_t i = start_slice; i < _z_bytes_num_slices(reader->bytes); ++i) {
        _z_arc_slice_t *s = _z_bytes_get_slice(reader->bytes, i);
        size_t remaining = _z_arc_slice_len(s) - reader->in_slice_idx;
        if (offset >= remaining) {
            reader->slice_idx += 1;
            reader->in_slice_idx = 0;
            reader->byte_idx += remaining;
            offset -= remaining;
        } else {
            reader->in_slice_idx += offset;
            reader->byte_idx += offset;
            offset = 0;
        }
        if (offset == 0) break;
    }

    if (offset > 0) _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
    return _Z_RES_OK;
}

z_result_t _z_bytes_reader_seek_backward(_z_bytes_reader_t *reader, size_t offset) {
    while (offset != 0) {
        if (reader->in_slice_idx == 0) {
            if (reader->slice_idx == 0) _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
            reader->slice_idx--;
            _z_arc_slice_t *s = _z_bytes_get_slice(reader->bytes, reader->slice_idx);
            reader->in_slice_idx = _z_arc_slice_len(s);
        }

        if (offset > reader->in_slice_idx) {
            offset -= reader->in_slice_idx;
            reader->byte_idx -= reader->in_slice_idx;
            reader->in_slice_idx = 0;
        } else {
            reader->byte_idx -= offset;
            reader->in_slice_idx -= offset;
            offset = 0;
        }
    }
    return _Z_RES_OK;
}

z_result_t _z_bytes_reader_seek(_z_bytes_reader_t *reader, int64_t offset, int origin) {
    switch (origin) {
        case SEEK_SET: {
            reader->byte_idx = 0;
            reader->in_slice_idx = 0;
            reader->slice_idx = 0;
            if (offset < 0) _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
            return _z_bytes_reader_seek_forward(reader, (size_t)offset);
        }
        case SEEK_CUR: {
            if (offset >= 0)
                return _z_bytes_reader_seek_forward(reader, (size_t)offset);
            else
                return _z_bytes_reader_seek_backward(reader, (size_t)(-offset));
        }
        case SEEK_END: {
            reader->byte_idx = _z_bytes_len(reader->bytes);
            reader->in_slice_idx = 0;
            reader->slice_idx = _z_bytes_num_slices(reader->bytes);
            if (offset > 0)
                _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
            else
                return _z_bytes_reader_seek_backward(reader, (size_t)(-offset));
        }
        default:
            _Z_ERROR_RETURN(_Z_ERR_GENERIC);
    }
}

int64_t _z_bytes_reader_tell(const _z_bytes_reader_t *reader) { return (int64_t)reader->byte_idx; }

size_t _z_bytes_reader_read(_z_bytes_reader_t *reader, uint8_t *buf, size_t len) {
    uint8_t *buf_start = buf;
    size_t to_read = len;
    for (size_t i = reader->slice_idx; i < _z_bytes_num_slices(reader->bytes); ++i) {
        _z_arc_slice_t *s = _z_bytes_get_slice(reader->bytes, i);
        size_t remaining = _z_arc_slice_len(s) - reader->in_slice_idx;
        if (len >= remaining) {
            memcpy(buf_start, _z_arc_slice_data(s) + reader->in_slice_idx, remaining);
            reader->slice_idx += 1;
            reader->in_slice_idx = 0;
            reader->byte_idx += remaining;
            len -= remaining;
            buf_start += remaining;
        } else {
            memcpy(buf_start, _z_arc_slice_data(s) + reader->in_slice_idx, len);
            reader->in_slice_idx += len;
            reader->byte_idx += len;
            len = 0;
        }
        if (len == 0) break;
    }

    return to_read - len;
}

z_result_t _z_bytes_reader_read_slices(_z_bytes_reader_t *reader, size_t len, _z_bytes_t *out) {
    *out = _z_bytes_null();
    z_result_t res = _Z_RES_OK;

    for (size_t i = reader->slice_idx; i < _z_bytes_num_slices(reader->bytes) && len > 0; ++i) {
        _z_arc_slice_t *s = _z_bytes_get_slice(reader->bytes, i);
        size_t s_len = _z_arc_slice_len(s);

        size_t remaining = s_len - reader->in_slice_idx;
        size_t len_to_copy = remaining > len ? len : remaining;
        _z_arc_slice_t ss = _z_arc_slice_get_subslice(s, reader->in_slice_idx, len_to_copy);
        reader->in_slice_idx += len_to_copy;
        reader->byte_idx += len_to_copy;
        if (reader->in_slice_idx == s_len) {
            reader->slice_idx++;
            reader->in_slice_idx = 0;
        }

        if (_z_slice_simple_rc_is_null(&ss.slice)) {
            _Z_ERROR_LOG(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
            res = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            break;
        }

        res = _z_bytes_append_slice(out, &ss);
        if (res != _Z_RES_OK) {
            _z_arc_slice_drop(&ss);
            break;
        }
        len -= len_to_copy;
    }
    if (len > 0 && res == _Z_RES_OK) {
        _Z_ERROR_LOG(_Z_ERR_DID_NOT_READ);
        res = _Z_ERR_DID_NOT_READ;
    }
    if (res != _Z_RES_OK) {
        _z_bytes_drop(out);
        _Z_ERROR_RETURN(res);
    }
    return _Z_RES_OK;
}

_z_bytes_writer_t _z_bytes_writer_from_bytes(_z_bytes_t *bytes) {
    _z_bytes_writer_t writer;
    writer.cache = NULL;
    writer.bytes = _z_bytes_steal(bytes);
    return writer;
}

_z_bytes_writer_t _z_bytes_writer_empty(void) {
    _z_bytes_writer_t writer;
    writer.cache = NULL;
    writer.bytes = _z_bytes_null();
    return writer;
}

bool _z_bytes_writer_is_empty(const _z_bytes_writer_t *writer) { return _z_bytes_is_empty(&writer->bytes); }

bool _z_bytes_writer_check(const _z_bytes_writer_t *writer) { return !_z_bytes_writer_is_empty(writer); }

z_result_t _z_bytes_writer_ensure_cache(_z_bytes_writer_t *writer) {
    assert(writer->cache != NULL);

    if (_z_slice_simple_rc_value(&writer->cache->slice)->len > writer->cache->len) {
        return _Z_RES_OK;
    }
    // otherwise we allocate a new cache
    _z_slice_t s = _z_slice_make(writer->cache->len * 2);
    if (s.start == NULL) _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    _z_arc_slice_t cache = _z_arc_slice_wrap(&s, 0, 0);
    if (_z_slice_simple_rc_is_null(&cache.slice)) {
        _z_slice_clear(&s);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }

    _Z_CLEAN_RETURN_IF_ERR(_z_bytes_append_slice(&writer->bytes, &cache), _z_arc_slice_drop(&cache));
    writer->cache = _z_bytes_get_slice(&writer->bytes, _z_bytes_num_slices(&writer->bytes) - 1);
    return _Z_RES_OK;
}

z_result_t _z_bytes_writer_init_cache(_z_bytes_writer_t *writer, const uint8_t *src, size_t len) {
    assert(writer->cache == NULL);

    _z_slice_t s = _z_slice_copy_from_buf(src, len);
    if (s.len != len) _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    _z_arc_slice_t arc_s = _z_arc_slice_wrap(&s, 0, len);
    if (_z_slice_simple_rc_is_null(&arc_s.slice)) {
        _z_slice_clear(&s);
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }

    _Z_RETURN_IF_ERR(_z_bytes_append_slice(&writer->bytes, &arc_s));
    writer->cache = _z_bytes_get_slice(&writer->bytes, _z_bytes_num_slices(&writer->bytes) - 1);
    return _Z_RES_OK;
}

z_result_t _z_bytes_writer_write_all(_z_bytes_writer_t *writer, const uint8_t *src, size_t len) {
    if (writer->cache == NULL) {  // no cache - append data as a single slice
        return _z_bytes_writer_init_cache(writer, src, len);
    }

    while (len > 0) {
        _Z_RETURN_IF_ERR(_z_bytes_writer_ensure_cache(writer));
        size_t remaining_in_cache = _z_slice_simple_rc_value(&writer->cache->slice)->len - writer->cache->len;
        size_t to_copy = remaining_in_cache < len ? remaining_in_cache : len;
        uint8_t *buffer_start = (uint8_t *)_z_slice_simple_rc_value(&writer->cache->slice)->start + writer->cache->len;
        memcpy(buffer_start, src, to_copy);
        len -= to_copy;
        writer->cache->len += to_copy;
        src += to_copy;
    }
    return _Z_RES_OK;
}

z_result_t _z_bytes_writer_append_z_bytes(_z_bytes_writer_t *writer, _z_bytes_t *src) {
    _Z_CLEAN_RETURN_IF_ERR(_z_bytes_append_bytes(&writer->bytes, src), _z_bytes_drop(src));
    writer->cache = NULL;
    return _Z_RES_OK;
}

z_result_t _z_bytes_writer_append_slice(_z_bytes_writer_t *writer, _z_arc_slice_t *src) {
    _Z_CLEAN_RETURN_IF_ERR(_z_bytes_append_slice(&writer->bytes, src), _z_arc_slice_drop(src));
    writer->cache = NULL;
    return _Z_RES_OK;
}

_z_bytes_t _z_bytes_writer_finish(_z_bytes_writer_t *writer) {
    _z_bytes_t out;
    _z_bytes_move(&out, &writer->bytes);
    writer->cache = NULL;
    return out;
}

void _z_bytes_writer_clear(_z_bytes_writer_t *writer) {
    _z_bytes_drop(&writer->bytes);
    writer->cache = NULL;
}

z_result_t _z_bytes_writer_move(_z_bytes_writer_t *dst, _z_bytes_writer_t *src) {
    dst->cache = src->cache;
    _z_bytes_move(&dst->bytes, &src->bytes);
    src->cache = NULL;
    return _Z_RES_OK;
}

size_t _z_bytes_reader_remaining(const _z_bytes_reader_t *reader) {
    return _z_bytes_len(reader->bytes) - reader->byte_idx;
}
