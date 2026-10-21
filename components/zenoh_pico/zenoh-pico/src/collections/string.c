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

#include "zenoh-pico/collections/string.h"

#include <stddef.h>
#include <string.h>

#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"

/*-------- string --------*/
_z_string_t _z_string_copy_from_str(const char *value) {
    _z_string_t s;
    s._slice = _z_slice_copy_from_buf((uint8_t *)value, strlen(value));
    return s;
}

_z_string_t _z_string_copy_from_substr(const char *value, size_t len) {
    _z_string_t s;
    s._slice = _z_slice_copy_from_buf((uint8_t *)value, len);
    return s;
}

_z_string_t *_z_string_copy_from_str_as_ptr(const char *value) {
    _z_string_t *s = (_z_string_t *)z_malloc(sizeof(_z_string_t));
    if (s == NULL) {
        return NULL;
    }
    *s = _z_string_copy_from_str(value);
    if (_z_slice_is_empty(&s->_slice) && value != NULL) {
        z_free(s);
        return NULL;
    }
    return s;
}

z_result_t _z_string_copy(_z_string_t *dst, const _z_string_t *src) {
    return _z_slice_copy(&dst->_slice, &src->_slice);
}

z_result_t _z_string_copy_substring(_z_string_t *dst, const _z_string_t *src, size_t offset, size_t len) {
    return _z_slice_n_copy(&dst->_slice, &src->_slice, offset, len);
}

z_result_t _z_string_move(_z_string_t *dst, _z_string_t *src) { return _z_slice_move(&dst->_slice, &src->_slice); }

_z_string_t _z_string_steal(_z_string_t *str) {
    _z_string_t ret;
    ret._slice = _z_slice_steal(&str->_slice);
    return ret;
}

void _z_string_move_str(_z_string_t *dst, char *src) { *dst = _z_string_alias_str(src); }

void _z_string_free(_z_string_t **str) {
    _z_string_t *ptr = *str;
    if (ptr != NULL) {
        _z_string_clear(ptr);

        z_free(ptr);
        *str = NULL;
    }
}
int _z_substring_compare(const _z_string_t *left, size_t left_start, size_t left_len, const _z_string_t *right,
                         size_t right_start, size_t right_len) {
    int result = strncmp(_z_string_data(left) + left_start, _z_string_data(right) + right_start,
                         left_len < right_len ? left_len : right_len);

    if (result == 0) {
        if (left_len < right_len) {
            return -1;
        } else if (left_len > right_len) {
            return 1;
        }
    }

    return result;
}

int _z_string_compare(const _z_string_t *left, const _z_string_t *right) {
    return _z_substring_compare(left, 0, _z_string_len(left), right, 0, _z_string_len(right));
}

bool _z_string_equals(const _z_string_t *left, const _z_string_t *right) {
    if (_z_string_len(left) != _z_string_len(right)) {
        return false;
    }
    return (strncmp(_z_string_data(left), _z_string_data(right), _z_string_len(left)) == 0);
}

_z_string_t _z_string_convert_bytes_le(const _z_slice_t *bs) {
    _z_string_t s = _z_string_null();
    size_t len = bs->len * (size_t)2;
    char *s_val = (char *)z_malloc((len) * sizeof(char));
    if (s_val == NULL) {
        return s;
    }

    const char c[] = "0123456789abcdef";
    size_t pos = bs->len * 2;
    for (size_t i = 0; i < bs->len; i++) {
        s_val[--pos] = c[bs->start[i] & (uint8_t)0x0F];
        s_val[--pos] = c[(bs->start[i] & (uint8_t)0xF0) >> (uint8_t)4];
    }
    s._slice = _z_slice_from_buf_custom_deleter((const uint8_t *)s_val, len, _z_delete_context_default());
    return s;
}

_z_string_t _z_string_preallocate(size_t len) {
    _z_string_t s;
    // As long as _z_string_t is only a slice, no need to do anything more
    if (_z_slice_init(&s._slice, len) != _Z_RES_OK) {
        _Z_ERROR("String allocation failed");
    }
    return s;
}

const char *_z_string_rchr(_z_string_t *str, char filter) {
    const char *curr_res = NULL;
    const char *ret = NULL;
    const char *curr_addr = _z_string_data(str);
    size_t curr_len = _z_string_len(str);
    do {
        curr_res = (char *)memchr(curr_addr, (int)filter, curr_len);
        if (curr_res != NULL) {
            ret = curr_res;
            curr_addr = curr_res + 1;
            curr_len = _z_ptr_char_diff(curr_addr, _z_string_data(str));
            if (curr_len >= _z_string_len(str)) {
                break;
            }
            curr_len = _z_string_len(str) - curr_len;
        }
    } while (curr_res != NULL);
    return ret;
}

char *_z_string_pbrk(_z_string_t *str, const char *filter) {
    const char *data = _z_string_data(str);
    for (size_t idx = 0; idx < _z_string_len(str); idx++) {
        const char *curr_char = filter;
        while (*curr_char != '\0') {
            if (data[idx] == *curr_char) {
                return (char *)&data[idx];
            }
            curr_char++;
        }
    }
    return NULL;
}

/*-------- str --------*/
size_t _z_str_size(const char *src) { return strlen(src) + (size_t)1; }

void _z_str_clear(char *src) { z_free(src); }

void _z_str_free(char **src) {
    char *ptr = *src;
    if (ptr != NULL) {
        _z_str_clear(ptr);

        *src = NULL;
    }
}

void _z_str_copy(char *dst, const char *src) {
    size_t size = _z_str_size(src);
    strncpy(dst, src, size - 1);
    dst[size - 1] = '\0';  // No matter what, strings are always null-terminated upon copy
}

void _z_str_n_copy(char *dst, const char *src, size_t size) {
    strncpy(dst, src, size - 1);
    dst[size - 1] = '\0';  // No matter what, strings are always null-terminated upon copy
}

char *_z_str_clone(const char *src) {
    size_t len = _z_str_size(src);
    char *dst = (char *)z_malloc(len);
    if (dst != NULL) {
        _z_str_n_copy(dst, src, len);
    }

    return dst;
}

char *_z_str_n_clone(const char *src, size_t len) {
    char *dst = (char *)z_malloc(len + 1);
    if (dst != NULL) {
        _z_str_n_copy(dst, src, len + 1);
    }

    return dst;
}

char *_z_str_from_string_clone(const _z_string_t *str) {
    return _z_str_n_clone((const char *)str->_slice.start, str->_slice.len);
}

bool _z_str_eq(const char *left, const char *right) { return strcmp(left, right) == 0; }

int _z_str_cmp(const char *left, const char *right) { return strcmp(left, right); }

z_result_t _z_string_concat_substr(_z_string_t *s, const _z_string_t *left, const char *right, size_t len,
                                   const char *separator, size_t separator_len) {
    if (separator == NULL && separator_len != 0) {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    }
    *s = _z_string_null();
    size_t left_len = _z_string_len(left);
    if (len == 0) {
        return _z_string_copy(s, left);
    } else if (right == NULL) {
        _Z_ERROR_RETURN(_Z_ERR_INVALID);
    } else if (left_len == 0) {
        *s = _z_string_copy_from_substr(right, len);
        if (!_z_string_check(s)) {
            return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
        }
    }

    *s = _z_string_preallocate(left_len + len + separator_len);
    if (!_z_string_check(s)) {
        _Z_ERROR_RETURN(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
    }

    uint8_t *curr_ptr = (uint8_t *)_z_string_data(s);
    // SAFETY: _z_string_preallocate and check of its result above ensures bound checks.
    // Flawfinder: ignore [CWE-120]
    memcpy(curr_ptr, _z_string_data(left), left_len);
    curr_ptr += left_len;
    if (separator_len > 0) {
        // SAFETY: _z_string_preallocate and check of its result above ensures bound checks.
        // Flawfinder: ignore [CWE-120]
        memcpy(curr_ptr, separator, separator_len);
        curr_ptr += separator_len;
    }
    // SAFETY: _z_string_preallocate and check of its result above ensures bound checks.
    // Flawfinder: ignore [CWE-120]
    memcpy(curr_ptr, right, len);
    return _Z_RES_OK;
}
