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

#include "zenoh-pico/utils/string.h"

#include <stdbool.h>
#include <string.h>

#include "zenoh-pico/utils/pointers.h"

_z_str_se_t _z_bstrnew(const char *start) { return (_z_str_se_t){.start = start, .end = strchr(start, 0)}; }

char const *_z_rstrstr(char const *haystack_start, char const *haystack_end, const char *needle_start) {
    char const *hs = haystack_start;
    char const *he = haystack_end;

    const char *needle_end = strchr(needle_start, 0);
    hs = _z_cptr_char_offset(hs, (ptrdiff_t)_z_ptr_char_diff(needle_end, needle_start));
    char const *result = NULL;
    while ((result == false) && (he >= hs)) {
        char found = 1;
        char const *needle = _z_cptr_char_offset(needle_end, -1);
        char const *haystack = _z_cptr_char_offset(he, -1);
        while (needle >= needle_start) {
            if (needle[0] != haystack[0]) {
                found = 0;
                break;
            }

            needle = _z_cptr_char_offset(needle, -1);
            haystack = _z_cptr_char_offset(haystack, -1);
        }
        if (found == true) {
            result = he;
        }
        he = _z_cptr_char_offset(he, -1);
    }
    return result;
}

char const *_z_bstrstr(_z_str_se_t haystack, _z_str_se_t needle) {
    haystack.end = _z_cptr_char_offset(haystack.end, -1 * (ptrdiff_t)_z_ptr_char_diff(needle.end, needle.start));
    char const *result = NULL;
    for (; (result == false) && (haystack.start <= haystack.end);
         haystack.start = _z_cptr_char_offset(haystack.start, 1)) {
        bool found = true;
        char const *n = needle.start;
        char const *h = haystack.start;
        while (_z_ptr_char_diff(needle.end, n) > 0) {
            if (n[0] != h[0]) {
                found = false;
                break;
            }

            n = _z_cptr_char_offset(n, 1);
            h = _z_cptr_char_offset(h, 1);
        }
        if (found == true) {
            result = haystack.start;
        }
    }
    return result;
}
char const *_z_strstr(char const *haystack_start, char const *haystack_end, const char *needle_start) {
    const char *needle_end = strchr(needle_start, 0);
    return _z_bstrstr((_z_str_se_t){.start = haystack_start, .end = haystack_end},
                      (_z_str_se_t){.start = needle_start, .end = needle_end});
}
char const *_z_strstr_skipneedle(char const *haystack_start, char const *haystack_end, const char *needle_start) {
    const char *needle_end = strchr(needle_start, 0);
    return _z_bstrstr_skipneedle((_z_str_se_t){.start = haystack_start, .end = haystack_end},
                                 (_z_str_se_t){.start = needle_start, .end = needle_end});
}

char const *_z_bstrstr_skipneedle(_z_str_se_t haystack, _z_str_se_t needle) {
    char const *result = _z_bstrstr(haystack, needle);
    if (result != NULL) {
        result = _z_cptr_char_offset(result, (ptrdiff_t)_z_ptr_char_diff(needle.end, needle.start));
    }
    return result;
}

bool _z_splitstr_is_empty(const _z_splitstr_t *src) { return src->s.start == NULL; }
_z_str_se_t _z_splitstr_next(_z_splitstr_t *str) {
    _z_str_se_t result = str->s;
    if (str->s.start != NULL) {
        result.end = _z_strstr(result.start, result.end, str->delimiter);
        if (result.end == NULL) {
            result.end = str->s.end;
        }
        if (result.end == str->s.end) {
            str->s = (_z_str_se_t){.start = NULL, .end = NULL};
        } else {
            str->s.start = _z_cptr_char_offset(result.end, (ptrdiff_t)strlen(str->delimiter));
        }
    }
    return result;
}
_z_str_se_t _z_splitstr_split_once(_z_splitstr_t src, _z_str_se_t *next) {
    *next = _z_splitstr_next(&src);
    return src.s;
}

_z_str_se_t _z_splitstr_nextback(_z_splitstr_t *str) {
    _z_str_se_t result = str->s;
    if (str->s.start != NULL) {
        result.start = _z_rstrstr(result.start, result.end, str->delimiter);
        if (result.start == NULL) {
            result.start = str->s.start;
        }
        if (result.start == str->s.start) {
            str->s = (_z_str_se_t){.start = NULL, .end = NULL};
        } else {
            str->s.end = _z_cptr_char_offset(result.start, -1 * (ptrdiff_t)strlen(str->delimiter));
        }
    }
    return result;
}

size_t _z_strcnt(char const *haystack_start, const char *harstack_end, const char *needle_start) {
    char const *hs = haystack_start;

    size_t result = 0;
    while (hs != NULL) {
        result = result + (size_t)1;
        hs = _z_strstr_skipneedle(hs, harstack_end, needle_start);
    }
    return result;
}

size_t _z_str_startswith(const char *s, const char *needle) {
    size_t i = 0;
    for (; needle[i] != '\0'; i++) {
        if (s[i] != needle[i]) {
            i = 0;
            break;
        }
    }
    return i;
}

bool _z_str_se_atoui(const _z_str_se_t *str, uint32_t *result) {
    uint32_t value = 0;
    size_t len = _z_ptr_char_diff(str->end, str->start);

    if (len == 0 || len > 10) {
        return false;
    }

    const uint32_t threshold = UINT32_MAX / 10;
    const uint32_t rem_threshold = UINT32_MAX % 10;

    for (size_t i = 0; i < len; i++) {
        const char c = str->start[i];
        if (c < '0' || c > '9') {
            return false;
        }
        uint32_t digit = (uint32_t)(c - '0');

        if (value > threshold || (value == threshold && digit > rem_threshold)) {
            return false;
        }
        value = value * 10 + digit;
    }

    *result = value;
    return true;
}

void *_z_memmem(const void *haystack, size_t haystack_len, const void *needle, size_t needle_len) {
    if (haystack == NULL || needle == NULL || haystack_len < needle_len) {
        return NULL;
    }

    const uint8_t *h = haystack;
    const uint8_t *h_end = h + haystack_len;
    const uint8_t *n = needle;

    while (h <= h_end - needle_len) {
        if (memcmp(h, n, needle_len) == 0) {
            return (void *)h;
        }
        h++;
    }
    return NULL;
}
