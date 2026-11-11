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

#include "zenoh-pico/utils/config.h"
#include "zenoh-pico/utils/auth.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "zenoh-pico/collections/string.h"
#include "zenoh-pico/utils/pointers.h"
#include "zenoh-pico/utils/string.h"

z_result_t _z_config_init(_z_config_t *ps) {
    _z_str_intmap_init(ps);
    return 0;
}

static void config_entry_free(void **ptr) {
    _z_int_void_map_entry_t *entry = *ptr;
    if (!entry) return;
    size_t key = *(size_t *)entry->_key;
    if ((key == Z_CONFIG_USER_KEY || key == Z_CONFIG_PASSWORD_KEY) && entry->_val)
        _z_secure_zero(entry->_val, strlen(entry->_val));
    z_free(entry->_key); z_free(entry->_val); z_free(entry); *ptr = NULL;
}
void _z_config_clear(_z_config_t *config) { _z_int_void_map_clear(config, config_entry_free); }
void _z_config_free(_z_config_t **config) {
    if (config && *config) { _z_config_clear(*config); z_free(*config); *config = NULL; }
}
static z_result_t _zp_config_insert_owned(_z_config_t *ps, uint8_t key, char *value, bool append) {
    if (value == NULL) return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    char *res = _z_int_void_map_insert(ps, key, value, config_entry_free, !append);
    if (res == NULL) {
        if (key == Z_CONFIG_USER_KEY || key == Z_CONFIG_PASSWORD_KEY) _z_secure_zero(value, strlen(value));
        z_free(value);
        return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    }
    return _Z_RES_OK;
}

z_result_t _z_config_duplicate(_z_config_t *dst, const _z_config_t *src) {
    *dst = _z_str_intmap_make();
    _z_str_intmap_iterator_t iter = _z_str_intmap_iterator_make(src);
    while (_z_str_intmap_iterator_next(&iter)) {
        uint8_t key = (uint8_t)_z_str_intmap_iterator_key(&iter);
        char *value = _z_str_intmap_iterator_value(&iter);
        z_result_t ret = _zp_config_insert_owned(dst, key, value ? _z_str_clone(value) : NULL, true);
        if (ret != _Z_RES_OK) { _z_config_clear(dst); return ret; }
    }
    /* insert在桶头插入；反转新桶以保持CONNECT候选原有顺序。 */
    if (dst->_vals) for (size_t i = 0; i < dst->_capacity; ++i) {
        _z_list_t *node = dst->_vals[i], *previous = NULL;
        while (node) { _z_list_t *next = node->_next; node->_next = previous; previous = node; node = next; }
        dst->_vals[i] = previous;
    }
    return _Z_RES_OK;
}
_z_config_t _z_config_clone_value(const _z_config_t *src) {
    _z_config_t dst; (void)_z_config_duplicate(&dst, src); return dst;
}

z_result_t _zp_config_insert(_z_config_t *ps, uint8_t key, const char *value) {
    if (value == NULL) return Z_EINVAL;
    return _zp_config_insert_owned(ps, key, _z_str_clone(value), key == Z_CONFIG_CONNECT_KEY);
}

z_result_t _zp_config_insert_string(_z_config_t *ps, uint8_t key, const _z_string_t *value) {
    if (!value) return Z_EINVAL;
    if (key == Z_CONFIG_USER_KEY || key == Z_CONFIG_PASSWORD_KEY) {
        size_t n = _z_string_len(value); const char *p = _z_string_data(value);
        if (!n || n > _Z_USRPWD_MAX || !p || memchr(p, 0, n) || memchr(p, '\r', n) || memchr(p, '\n', n))
            return _Z_ERR_AUTH_CONFIG;
    }
    return _zp_config_insert_owned(ps, key, _z_str_from_string_clone(value), false);
}

char *_z_config_get(const _z_config_t *ps, uint8_t key) { return _z_str_intmap_get(ps, key); }

z_result_t _z_config_get_all(const _z_config_t *ps, _z_string_svec_t *locators, uint8_t key) {
    _z_list_t *cfg_list = _z_str_intmap_get_all(ps, key);
    while (cfg_list != NULL) {
        _z_int_void_map_entry_t *entry = (_z_int_void_map_entry_t *)_z_list_value(cfg_list);
        if (*(size_t *)entry->_key == key) {
            char *val = (char *)entry->_val;
            _z_string_t borrowed = _z_string_alias_str(val), s = _z_string_null();
            z_result_t ret = _z_string_copy(&s, &borrowed);
            if (ret != _Z_RES_OK) { _z_string_clear(&s); return ret; }
            ret = _z_string_svec_append(locators, &s, true);
            if (ret != _Z_RES_OK) { _z_string_clear(&s); return ret; }
        }
        cfg_list = _z_list_next(cfg_list);
    }
    return _Z_RES_OK;
}

/*------------------ int-string map ------------------*/
z_result_t _z_str_intmap_from_strn(_z_str_intmap_t *strint, const char *s, uint8_t argc, _z_str_intmapping_t argv[],
                                   size_t n) {
    z_result_t ret = _Z_RES_OK;
    *strint = _z_str_intmap_make();

    // Check the string contains only the right
    const char *start = s;
    const char *end = &s[n - 1];
    size_t curr_len = n;
    while (curr_len > 0) {
        const char *p_key_start = start;
        const char *p_key_end = memchr(p_key_start, INT_STR_MAP_KEYVALUE_SEPARATOR, curr_len);

        if (p_key_end != NULL) {
            // Verify the key is valid based on the provided mapping
            size_t p_key_len = _z_ptr_char_diff(p_key_end, p_key_start);
            bool found = false;
            uint8_t key = 0;
            for (uint8_t i = 0; i < argc; i++) {
                if (p_key_len != strlen(argv[i]._str)) {
                    continue;
                }
                if (strncmp(p_key_start, argv[i]._str, p_key_len) != 0) {
                    continue;
                }

                found = true;
                key = argv[i]._key;
                break;
            }

            if (found == false) {
                break;
            }

            // Read and populate the value
            const char *p_value_start = _z_cptr_char_offset(p_key_end, 1);
            size_t value_max_size = curr_len - _z_ptr_char_diff(p_value_start, start);
            const char *p_value_end = memchr(p_key_end, INT_STR_MAP_LIST_SEPARATOR, value_max_size);

            size_t p_value_len = 0;
            if (p_value_end == NULL) {
                p_value_end = end;
                p_value_len = value_max_size + 1;
            } else {
                p_value_len = _z_ptr_char_diff(p_value_end, p_value_start) + 1;
            }
            char *p_value = (char *)z_malloc(p_value_len);
            if (p_value != NULL) {
                _z_str_n_copy(p_value, p_value_start, p_value_len);
                _z_str_intmap_insert(strint, key, p_value);

                // Process next key value
                start = _z_cptr_char_offset(p_value_end, 1);
                curr_len = n - _z_ptr_char_diff(start, s);
            } else {
                _Z_ERROR_LOG(_Z_ERR_SYSTEM_OUT_OF_MEMORY);
                ret = _Z_ERR_SYSTEM_OUT_OF_MEMORY;
            }
        }
    }

    return ret;
}

z_result_t _z_str_intmap_from_str(_z_str_intmap_t *strint, const char *s, uint8_t argc, _z_str_intmapping_t argv[]) {
    return _z_str_intmap_from_strn(strint, s, argc, argv, strlen(s));
}

size_t _z_str_intmap_strlen(const _z_str_intmap_t *s, uint8_t argc, _z_str_intmapping_t argv[]) {
    // Calculate the string length to allocate
    size_t len = 0;
    for (size_t i = 0; i < argc; i++) {
        char *v = _z_str_intmap_get(s, argv[i]._key);
        if (v != NULL) {
            if (len != (size_t)0) {
                len = len + (size_t)1;  // List separator
            }
            len = len + strlen(argv[i]._str);  // Key
            len = len + (size_t)1;             // KeyValue separator
            len = len + strlen(v);             // Value
        }
    }

    return len;
}

void _z_str_intmap_onto_str(char *dst, size_t dst_len, const _z_str_intmap_t *s, uint8_t argc,
                            _z_str_intmapping_t argv[]) {
    if (dst == NULL || dst_len == 0) {
        return;
    }

    // Remaining length excluding '\0'
    size_t len = dst_len - (size_t)1;
    dst[0] = '\0';
    for (size_t i = 0; i < argc; i++) {
        char *v = _z_str_intmap_get(s, argv[i]._key);
        if (v != NULL) {
            if (len > (size_t)0 && dst[0] != '\0') {
                _z_str_append(dst, INT_STR_MAP_LIST_SEPARATOR);  // List separator
                len = len - (size_t)1;
            }

            size_t key_len = strnlen(argv[i]._str, len);
            if (len > (size_t)0) {
                size_t n = key_len < len ? key_len : len;
                // Flawfinder: ignore [CWE-120]
                (void)strncat(dst, argv[i]._str, n);  // Key
                len = len - n;
            }

            if (len > (size_t)0) {
                _z_str_append(dst, INT_STR_MAP_KEYVALUE_SEPARATOR);  // KeyValue separator
                len = len - (size_t)1;
            }

            size_t value_len = strnlen(v, len);
            if (len > (size_t)0) {
                size_t n = value_len < len ? value_len : len;
                // Flawfinder: ignore [CWE-120]
                (void)strncat(dst, v, n);  // Value
                len = len - n;
            }
        }
    }
}

char *_z_str_intmap_to_str(const _z_str_intmap_t *s, uint8_t argc, _z_str_intmapping_t argv[]) {
    // Calculate the string length to allocate
    size_t len = _z_str_intmap_strlen(s, argc, argv) + (size_t)1;
    // Build the string
    char *dst = (char *)z_malloc(len);
    if (dst != NULL) {
        _z_str_intmap_onto_str(dst, len, s, argc, argv);
    }
    return dst;
}
