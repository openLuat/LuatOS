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

#ifndef ZENOH_PICO_UTILS_STRING_H
#define ZENOH_PICO_UTILS_STRING_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char const *start;
    char const *end;
} _z_str_se_t;

typedef struct {
    _z_str_se_t s;
    char const *delimiter;
} _z_splitstr_t;

/**
 * Creates a `_z_str_se_t` from a null-terminated C string.
 */
_z_str_se_t _z_bstrnew(const char *start);

/**
 * The reverse equivalent of libc's `strstr`.
 *
 * Returns NULL if the needle is not found.
 * If found, the return pointer will point to the end of the last occurring
 * needle within the haystack.
 */
char const *_z_rstrstr(const char *haystack_start, const char *haystack_end, const char *needle);

/**
 * A non-null-terminated haystack equivalent of libc's `strstr`.
 *
 * Returns NULL if the needle is not found.
 * If found, the return pointer will point to the start of the first occurrence
 * of the needle within the haystack.
 */
char const *_z_strstr(char const *haystack_start, char const *haystack_end, const char *needle_start);

char const *_z_strstr_skipneedle(char const *haystack_start, char const *haystack_end, const char *needle_start);
char const *_z_bstrstr_skipneedle(_z_str_se_t haystack, _z_str_se_t needle);

bool _z_splitstr_is_empty(const _z_splitstr_t *src);
_z_str_se_t _z_splitstr_next(_z_splitstr_t *str);
_z_str_se_t _z_splitstr_split_once(_z_splitstr_t src, _z_str_se_t *next);
_z_str_se_t _z_splitstr_nextback(_z_splitstr_t *str);

size_t _z_strcnt(char const *haystack_start, const char *harstack_end, const char *needle_start);

size_t _z_str_startswith(const char *s, const char *needle);

// Must be used on a null terminated string with str[strlen(str) + 1] being valid memory.
static inline void _z_str_append(char *str, const char c) {
    size_t len = strlen(str);
    str[len] = c;
    str[len + 1] = '\0';
}

/*
 * Convert a non null terminated `_z_str_se_t` to a uint32_t.
 */
bool _z_str_se_atoui(const _z_str_se_t *str, uint32_t *result);

void *_z_memmem(const void *haystack, size_t haystack_len, const void *needle, size_t needle_len);

/*
 * Safely copies a block of memory into a destination buffer at a given offset, if bounds allow.
 *
 * Parameters:
 *   dest       - Pointer to the destination buffer.
 *   dest_len   - Total size of the destination buffer.
 *   offset     - Pointer to the current write offset; may be NULL to use offset 0 without updating, otherwise will be
 * updated if the copy succeeds.
 *   src        - Pointer to the source data.
 *   len        - Number of bytes to copy.
 *
 * Returns:
 *   true  - If the copy succeeds (bounds are respected and pointers are valid).
 *   false - If the copy would overflow the buffer, or any pointer is NULL.
 */
static inline bool _z_memcpy_checked(void *dest, size_t dest_len, size_t *offset, const void *src, size_t len) {
    if (dest == NULL || src == NULL) {
        return false;
    }

    size_t local_offset = (offset != NULL) ? *offset : 0;
    if (len > dest_len - local_offset) {
        return false;
    }

    char *d_start = (char *)dest + local_offset;
    char *d_end = d_start + len;
    const char *s_start = (const char *)src;
    const char *s_end = s_start + len;

    // Check for overlap: if src and dest ranges intersect
    if ((s_start < d_end && s_end > d_start)) {
        return false;  // Overlap detected
    }

    // SAFETY: Copy is bounds-checked above.
    // Flawfinder: ignore [CWE-120]
    memcpy(d_start, src, len);
    if (offset != NULL) {
        *offset += len;
    }
    return true;
}

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_UTILS_STRING_H */
