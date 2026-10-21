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

#ifndef INCLUDE_ZENOH_PICO_API_PRIMITIVES_H
#define INCLUDE_ZENOH_PICO_API_PRIMITIVES_H

#ifndef SPHINX_DOCS
// For some reason sphinx/clang doesn't handle bool types correctly if stdbool.h is included
#include <stdbool.h>
#endif
#include <stdint.h>

#include "olv_macros.h"
#include "zenoh-pico/api/types.h"
#include "zenoh-pico/collections/advanced_cache.h"
#include "zenoh-pico/net/query.h"
#include "zenoh-pico/net/session.h"
#include "zenoh-pico/net/subscribe.h"
#include "zenoh-pico/protocol/core.h"
#include "zenoh-pico/session/keyexpr.h"
#include "zenoh-pico/session/session.h"
#include "zenoh-pico/system/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Builds a :c:type:`z_view_string_t` by wrapping a ``const char *`` string.
 *
 * Parameters:
 *   str: Pointer to an uninitialized :c:type:`z_view_string_t`.
 *   value: Pointer to a null terminated string.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_view_string_from_str(z_view_string_t *str, const char *value);

/**
 * Builds a :c:type:`z_view_string_t` by wrapping a ``const char *`` substring.
 *
 * Parameters:
 *   str: Pointer to an uninitialized :c:type:`z_view_string_t`.
 *   value: Pointer to a null terminated string.
 *   len: Size of the string.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_view_string_from_substr(z_view_string_t *str, const char *value, size_t len);

/**
 * Builds a :c:type:`z_keyexpr_t` from a null-terminated string.
 * It is a loaned key expression that aliases ``name``.
 * This function will fail if the string is not in canon form.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_view_keyexpr_t`.
 *   name: Pointer to string representation of the keyexpr as a null terminated string.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_view_keyexpr_from_str(z_view_keyexpr_t *keyexpr, const char *name);

/**
 * Builds a :c:type:`z_keyexpr_t` from a null-terminated string.
 * It is a loaned key expression that aliases ``name``.
 * Input key expression is not checked for correctness.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_view_keyexpr_t`.
 *   name: Pointer to string representation of the keyexpr as a null terminated string.
 */
void z_view_keyexpr_from_str_unchecked(z_view_keyexpr_t *keyexpr, const char *name);

/**
 * Builds a :c:type:`z_view_keyexpr_t` from a null-terminated string with auto canonization.
 * It is a loaned key expression that aliases ``name``.
 * The string is canonized in-place before being passed to keyexpr, possibly shortening it by modifying len.
 * May SEGFAULT if `name` is NULL or lies in read-only memory (as values initialized with string literals do).
 * `name` must outlive the constructed key expression.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_view_keyexpr_t`.
 *   name: Pointer to string representation of the keyexpr as a null terminated string.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_view_keyexpr_from_str_autocanonize(z_view_keyexpr_t *keyexpr, char *name);

/**
 * Builds a :c:type:`z_keyexpr_t` by aliasing a substring.
 * It is a loaned key expression that aliases ``name``.
 * This function will fail if the string is not in canon form.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_view_keyexpr_t`.
 *   name: Pointer to string representation of the keyexpr.
 *   len: Size of the string.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_view_keyexpr_from_substr(z_view_keyexpr_t *keyexpr, const char *name, size_t len);

/**
 * Builds a :c:type:`z_view_keyexpr_t` from a substring with auto canonization.
 * It is a loaned key expression that aliases ``name``.
 * The string is canonized in-place before being passed to keyexpr, possibly shortening it by modifying len.
 * May SEGFAULT if `name` is NULL or lies in read-only memory (as values initialized with string literals do).
 * `name` must outlive the constructed key expression.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_view_keyexpr_t`.
 *   name: Pointer to string representation of the keyexpr.
 *   len: Pointer to the size of the string.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_view_keyexpr_from_substr_autocanonize(z_view_keyexpr_t *keyexpr, char *name, size_t *len);

/**
 * Builds a :c:type:`z_keyexpr_t` from a substring.
 * It is a loaned key expression that aliases ``name``.
 * Input key expression is not checked for correctness.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_view_keyexpr_t`.
 *   name: Pointer to string representation of the keyexpr.
 *   len: Size of the string.
 */
void z_view_keyexpr_from_substr_unchecked(z_view_keyexpr_t *keyexpr, const char *name, size_t len);

/**
 * Gets a string view from a :c:type:`z_keyexpr_t`.
 *
 * Parameters:
 *   keyexpr: Pointer to a loaned instance of :c:type:`z_keyexpr_t`.
 *   str: Pointer to an uninitialized :c:type:`z_view_string_t`.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_keyexpr_as_view_string(const z_loaned_keyexpr_t *keyexpr, z_view_string_t *str);

/**
 * Constructs key expression by concatenation of key expression in `left` with a string in `right`.
 *
 * To avoid odd behaviors, concatenating a key expression starting with `*` to one ending with `*` is forbidden by this
 * operation, as this would extremely likely cause bugs.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_owned_keyexpr_t` to store the keyexpr.
 *   left: Pointer to :c:type:`z_loaned_keyexpr_t` to keyexpr to concatenate to.
 *   right: Pointer to the start of the substring that will be concatenated.
 *   len: Length of the substring to concatenate.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_keyexpr_concat(z_owned_keyexpr_t *key, const z_loaned_keyexpr_t *left, const char *right, size_t len);

/**
 * Constructs key expression by performing path-joining (automatically inserting '/'). The resulting key expression is
 * automatically canonized.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_owned_keyexpr_t` to store the keyexpr.
 *   left: Pointer to :c:type:`z_loaned_keyexpr_t` to the left part of the resulting key expression.
 *   right: Pointer to :c:type:`z_loaned_keyexpr_t` to the right part of the resulting key expression.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 */
z_result_t z_keyexpr_join(z_owned_keyexpr_t *key, const z_loaned_keyexpr_t *left, const z_loaned_keyexpr_t *right);

/**
 * Appends the suffix portion of a key expression to another key expression (automatically inserting '/').
 *
 * Only the suffix portion of the key expression is preserved. All other components of the resulting key
 * expression will be discarded.
 * The resulting key expression is automatically canonized.
 *
 * Parameters:
 *   prefix: Pointer to :c:type:`z_owned_keyexpr_t` to the key expression to append to.
 *   right: Pointer to :c:type:`z_loaned_keyexpr_t` whose suffix will be appended.
 *
 * Return:
 *   ``0`` if the append was successful; a ``negative value`` otherwise.
 */
z_result_t _z_keyexpr_append_suffix(z_owned_keyexpr_t *prefix, const z_loaned_keyexpr_t *right);

/**
 * Appends a string segment to a key expression (automatically inserting '/'). The resulting key expression is
 * automatically canonized.
 *
 * Parameters:
 *   prefix: Pointer to :c:type:`z_owned_keyexpr_t` to the key expression to append to.
 *   right: Pointer to a character array representing the string to append.
 *   len: Length of the string segment in ``right`` to append.
 *
 * Return:
 *   ``0`` if append successful, ``negative value`` otherwise.
 */
z_result_t _z_keyexpr_append_substr(z_owned_keyexpr_t *prefix, const char *right, size_t len);

/**
 * Appends a null-terminated string to a key expression (automatically inserting '/'). The resulting key expression is
 * automatically canonized.
 *
 * Parameters:
 *   prefix: Pointer to :c:type:`z_owned_keyexpr_t` to the key expression to append to.
 *   right: Pointer to a null-terminated string to append.
 *
 * Return:
 *   ``0`` if append successful, ``negative value`` otherwise.
 */
static inline z_result_t _z_keyexpr_append_str(z_owned_keyexpr_t *prefix, const char *right) {
    // SAFETY: right is documented to be null-terminated.
    // Flawfinder: ignore [CWE-126]
    return _z_keyexpr_append_substr(prefix, right, right ? strlen(right) : 0);
}

/**
 * Appends multiple null-terminated strings to a key expression (automatically inserting '/' between each component).
 * The resulting key expression is automatically canonized.
 *
 * Parameters:
 *   prefix: Pointer to :c:type:`z_owned_keyexpr_t` representing the key expression to append to.
 *   strs: Array of ``count`` null-terminated strings to append, in order.
 *   count: Number of strings in the array.
 *
 * Return:
 *   ``0`` if all appends were successful, ``negative value`` if any append failed.
 */
z_result_t _z_keyexpr_append_str_array(z_owned_keyexpr_t *prefix, const char *strs[], size_t count);

#define _Z_KEYEXPR_APPEND_STR_ARRAY(prefix, ...)                       \
    _z_keyexpr_append_str_array(prefix, (const char *[]){__VA_ARGS__}, \
                                sizeof((const char *[]){__VA_ARGS__}) / sizeof(const char *))

/**
 * Returns the relation between `left` and `right` from the `left`'s point of view.
 *
 * Note that this is slower than `z_keyexpr_intersects` and `keyexpr_includes`, so you should favor these methods for
 * most applications.
 *
 * Parameters:
 *   left: Pointer to :c:type:`z_loaned_keyexpr_t` representing left key expression.
 *   right: Pointer to :c:type:`z_loaned_keyexpr_t` representing right key expression.
 *
 * Return:
 *   Relation between `left` and `right` from the `left`'s point of view.
 */
z_keyexpr_intersection_level_t z_keyexpr_relation_to(const z_loaned_keyexpr_t *left, const z_loaned_keyexpr_t *right);

/**
 * Checks if a given keyexpr is valid and in canonical form.
 *
 * Parameters:
 *   start: Pointer to the keyexpr in its string representation as a non-null terminated string.
 *   len: Number of characters in ``start``.
 *
 * Return:
 *   ``0`` if the passed string is a valid (and canon) key expression, or a ``negative value`` otherwise.
 *   Error codes are defined in :c:enum:`zp_keyexpr_canon_status_t`.
 */
z_result_t z_keyexpr_is_canon(const char *start, size_t len);

/**
 * Canonizes of a given keyexpr in string representation.
 * The canonization is performed over the passed string, possibly shortening it by modifying ``len``.
 *
 * Parameters:
 *   start: Pointer to the keyexpr in its string representation as a non-null terminated string.
 *   len: Number of characters in ``start``.
 *
 * Return:
 *   ``0`` if canonization successful, or a ``negative value`` otherwise.
 *   Error codes are defined in :c:enum:`zp_keyexpr_canon_status_t`.
 */
z_result_t z_keyexpr_canonize(char *start, size_t *len);

/**
 * Canonizes of a given keyexpr in string representation.
 * The canonization is performed over the passed string, possibly shortening it by setting null at the end.
 *
 * Parameters:
 *   start: Pointer to the keyexpr in its string representation as a null terminated string.
 *
 * Return:
 *   ``0`` if canonization successful, or a ``negative value`` otherwise.
 *   Error codes are defined in :c:enum:`zp_keyexpr_canon_status_t`.
 */
z_result_t z_keyexpr_canonize_null_terminated(char *start);

/**
 * Checks if a given keyexpr contains another keyexpr in its set.
 *
 * Parameters:
 *   l: Pointer to a :c:type:`z_loaned_keyexpr_t`.
 *   r: Pointer to a :c:type:`z_loaned_keyexpr_t`.
 *
 * Return:
 *   ``true`` if ``l`` includes ``r``, i.e. the set defined by ``l`` contains every key belonging to the set
 *   defined by ``r``. Otherwise, returns ``false``.
 */
bool z_keyexpr_includes(const z_loaned_keyexpr_t *l, const z_loaned_keyexpr_t *r);

/**
 * Checks if a given keyexpr intersects with another keyexpr.
 *
 * Parameters:
 *   l: Pointer to a :c:type:`z_loaned_keyexpr_t`.
 *   r: Pointer to a :c:type:`z_loaned_keyexpr_t`.
 *
 * Return:
 *   ``true`` if keyexprs intersect, i.e. there exists at least one key which is contained in both of the
 *   sets defined by ``l`` and ``r``. Otherwise, returns ``false``.
 */
bool z_keyexpr_intersects(const z_loaned_keyexpr_t *l, const z_loaned_keyexpr_t *r);

/**
 * Checks if two keyexpr are equal.
 *
 * Parameters:
 *   l: Pointer to a :c:type:`z_loaned_keyexpr_t`.
 *   r: Pointer to a :c:type:`z_loaned_keyexpr_t`.
 *
 * Return:
 *   ``true`` if both ``l`` and ``r`` are equal. Otherwise, returns  ``false``.
 */
bool z_keyexpr_equals(const z_loaned_keyexpr_t *l, const z_loaned_keyexpr_t *r);

/**
 * Builds a new, zenoh-allocated, default configuration.
 * It consists in a default set of properties for zenoh session configuration.
 *
 * Parameters:
 *   config: Pointer to uninitialized :c:type:`z_owned_config_t`.
 *
 * Return:
 *   ``0`` in case of success, or a ``negative value`` otherwise.
 */
z_result_t z_config_default(z_owned_config_t *config);

/**
 * Gets the property with the given integer key from the configuration.
 *
 * Parameters:
 *   config: Pointer to a :c:type:`z_loaned_config_t` to get the property from.
 *   key: Integer key of the requested property.
 *
 * Return:
 *   The requested property value.
 */
const char *zp_config_get(const z_loaned_config_t *config, uint8_t key);

/**
 * Inserts or replaces the property with the given integer key in the configuration.
 *
 * Parameters:
 *   config: Pointer to a :c:type:`z_loaned_config_t` to modify.
 *   key: Integer key of the property to be inserted.
 *   value: Property value to be inserted.
 *
 * Return:
 *   ``0`` if insertion is successful, ``negative value`` otherwise.
 */
z_result_t zp_config_insert(z_loaned_config_t *config, uint8_t key, const char *value);

/**
 * Builds a :c:type:`z_owned_encoding_t` from a null terminated string.
 *
 * Parameters:
 *   encoding: Pointer to an uninitialized :c:type:`z_owned_encoding_t`.
 *   s: Pointer to the null terminated string to use.
 *
 * Return:
 *   ``0`` if creation is successful,``negative value`` otherwise.
 */
z_result_t z_encoding_from_str(z_owned_encoding_t *encoding, const char *s);

/**
 * Builds a :c:type:`z_owned_encoding_t` from a null terminated string.
 *
 * Parameters:
 *   encoding: Pointer to an uninitialized :c:type:`z_owned_encoding_t`.
 *   s: Pointer to the string to use.
 *   len: Number of characters from the string s to use.
 *
 * Return:
 *   ``0`` if creation is successful,``negative value`` otherwise.
 */
z_result_t z_encoding_from_substr(z_owned_encoding_t *encoding, const char *s, size_t len);

/**
 * Sets a schema to this encoding from a null-terminated string. Zenoh does not define what a schema is and its
 * semantics is left to the implementer. E.g. a common schema for `text/plain` encoding is `utf-8`.
 *
 * Parameters:
 *   encoding: Pointer to initialized :c:type:`z_loaned_encoding_t`.
 *   schema: Pointer to the null terminated string to use as a schema.
 *
 * Return:
 *   ``0`` in case of success,``negative value`` otherwise.
 */
z_result_t z_encoding_set_schema_from_str(z_loaned_encoding_t *encoding, const char *schema);

/**
 * Sets a schema to this encoding from a substring. Zenoh does not define what a schema is and its semantics is left
 * to the implementer. E.g. a common schema for `text/plain` encoding is `utf-8`.
 *
 * Parameters:
 *   encoding: Pointer to initialized :c:type:`z_loaned_encoding_t`.
 *   schema: Pointer to the substring start.
 *   len: Number of characters to consider.
 *
 * Return:
 *   ``0`` if in case of success,``negative value`` otherwise.
 */
z_result_t z_encoding_set_schema_from_substr(z_loaned_encoding_t *encoding, const char *schema, size_t len);

/**
 * Builds a string from a :c:type:`z_loaned_encoding_t`.
 *
 * Parameters:
 *   encoding: Pointer to the :c:type:`z_loaned_encoding_t` to use.
 *   string: Pointer to an uninitialized :c:type:`z_owned_string_t` to store the string.
 *
 * Return:
 *   ``0`` if creation is successful,``negative value`` otherwise.
 */
z_result_t z_encoding_to_string(const z_loaned_encoding_t *encoding, z_owned_string_t *string);

/**
 * Checks if two encodings are equal.
 *
 * Parameters:
 *   left: Pointer to the first :c:type:`z_loaned_encoding_t` to compare.
 *   right: Pointer to the second :c:type:`z_loaned_encoding_t` to compare.
 *
 * Return:
 *   ``true`` if `left` equals `right`, ``false`` otherwise.
 */
bool z_encoding_equals(const z_loaned_encoding_t *left, const z_loaned_encoding_t *right);

/**
 * Gets the bytes data from a reply error payload by aliasing it.
 *
 * Parameters:
 *   reply_err: Pointer to a :c:type:`z_loaned_reply_err_t` to get data from.
 *
 * Return:
 *   Pointer to the data as a :c:type:`z_loaned_bytes_t`.
 */
const z_loaned_bytes_t *z_reply_err_payload(const z_loaned_reply_err_t *reply_err);

/**
 * Gets a reply error encoding by aliasing it.
 *
 * Parameters:
 *   reply_err: Pointer to the :c:type:`z_loaned_reply_err_t` to get the encoding from.
 *
 * Return:
 *   Pointer to the encoding as a :c:type:`z_loaned_encoding_t`.
 */
const z_loaned_encoding_t *z_reply_err_encoding(const z_loaned_reply_err_t *reply_err);

/**
 * Builds a :c:type:`z_owned_slice_t` by copying a buffer into it.
 *
 * Parameters:
 *   slice: Pointer to an uninitialized :c:type:`z_owned_slice_t`.
 *   data: Pointer to the data that will be copied into slice.
 *   len: Number of bytes to copy.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_slice_copy_from_buf(z_owned_slice_t *slice, const uint8_t *data, size_t len);

/**
 * Builds a :c:type:`z_owned_slice_t` by transferring ownership over a data to it.
 *
 * Parameters:
 *   slice: Pointer to an uninitialized :c:type:`z_owned_slice_t`.
 *   data: Pointer to the data to be owned by `slice`.
 *   len: Number of bytes in `data`.
 *   deleter: A thread-safe delete function to free the `data`. Will be called once when `slice` is dropped.
 *     Can be NULL in the case where `data` is allocated in static memory.
 *   context: An optional context to be passed to the `deleter`.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_slice_from_buf(z_owned_slice_t *slice, uint8_t *data, size_t len,
                            void (*deleter)(void *data, void *context), void *context);

/**
 * Builds a :c:type:`z_view_slice_t`.
 *
 * Parameters:
 *   slice: Pointer to an uninitialized :c:type:`z_view_slice_t`.
 *   data: Pointer to the data to be pointed by `slice`.
 *   len: Number of bytes in `data`.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_view_slice_from_buf(z_view_slice_t *slice, const uint8_t *data, size_t len);

/**
 * Builds an empty :c:type:`z_owned_slice_t`.
 *
 * Parameters:
 *   slice: Pointer to an uninitialized :c:type:`z_owned_slice_t`.
 */
void z_slice_empty(z_owned_slice_t *slice);

/**
 * Gets date pointer of a bytes array.
 *
 * Parameters:
 *   slice: Pointer to a :c:type:`z_loaned_slice_t` to get data from.
 *
 * Return:
 *   The data pointer.
 */
const uint8_t *z_slice_data(const z_loaned_slice_t *slice);

/**
 * Gets the total number of bytes in a bytes array.
 *
 * Parameters:
 *   slice: Pointer to a :c:type:`z_loaned_slice_t` to get length from.
 *
 * Return:
 *   The number of bytes.
 */
size_t z_slice_len(const z_loaned_slice_t *slice);

/**
 * Checks if slice is empty
 *
 * Parameters:
 *   slice: Pointer to a :c:type:`z_loaned_slice_t` to check.
 *
 * Return:
 *   ``true`` if the container is empty, ``false`` otherwise.
 */
bool z_slice_is_empty(const z_loaned_slice_t *slice);

/**
 * Converts data into a :c:type:`z_owned_slice_t`
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to decode.
 *   dst: Pointer to an uninitialized :c:type:`z_owned_slice_t` to contain the decoded slice.
 *
 * Return:
 *   ``0`` if decode is successful, or a ``negative value`` otherwise.
 */
z_result_t z_bytes_to_slice(const z_loaned_bytes_t *bytes, z_owned_slice_t *dst);

/**
 * Converts data into a :c:type:`z_owned_string_t`
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to decode.
 *   str: Pointer to an uninitialized :c:type:`z_owned_string_t` to contain the decoded string.
 *
 * Return:
 *   ``0`` if decode is successful, or a ``negative value`` otherwise.
 */
z_result_t z_bytes_to_string(const z_loaned_bytes_t *bytes, z_owned_string_t *str);

/**
 * Converts a slice into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded slice.
 *   slice: Pointer to the slice to convert. The slice will be consumed upon function return.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_from_slice(z_owned_bytes_t *bytes, z_moved_slice_t *slice);

/**
 * Converts a slice into a :c:type:`z_owned_bytes_t` by copying.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded slice.
 *   slice: Pointer to the slice to convert.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_copy_from_slice(z_owned_bytes_t *bytes, const z_loaned_slice_t *slice);

/**
 * Converts data into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded data.
 *   data: Pointer to the data to convert. Ownership is transferred to the `bytes`.
 *   len: Number of bytes to consider.
 *   deleter: A thread-safe delete function to free the `data`. Will be called once when `bytes` is dropped.
 *     Can be NULL in the case where `data` is allocated in static memory.
 *   context: An optional context to be passed to the `deleter`.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_from_buf(z_owned_bytes_t *bytes, uint8_t *data, size_t len,
                            void (*deleter)(void *data, void *context), void *context);

/**
 * Converts data into a :c:type:`z_owned_bytes_t` by copying.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded data.
 *   data: Pointer to the data to convert.
 *   len: Number of bytes to consider.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_copy_from_buf(z_owned_bytes_t *bytes, const uint8_t *data, size_t len);

/**
 * Converts statically allocated constant data into a :c:type:`z_owned_bytes_t` by aliasing.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded data.
 *   data: Pointer to the statically allocated constant data to encode.
 *   len: Number of bytes to consider.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_from_static_buf(z_owned_bytes_t *bytes, const uint8_t *data, size_t len);

/**
 * Converts a string into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded string.
 *   s: Pointer to the string to convert. The string will be consumed upon function return.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_from_string(z_owned_bytes_t *bytes, z_moved_string_t *s);

/**
 * Converts a string into a :c:type:`z_owned_bytes_t` by copying.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded string.
 *   s: Pointer to the string to convert.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_copy_from_string(z_owned_bytes_t *bytes, const z_loaned_string_t *s);

/**
 * Converts a null-terminated string into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded string.
 *   value: Pointer to the string to converts. Ownership is transferred to the `bytes`.
 *   deleter: A thread-safe delete function to free the `value`. Will be called once when `bytes` is dropped.
 *     Can be NULL in the case where `value` is allocated in static memory.
 *   context: An optional context to be passed to the `deleter`.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_from_str(z_owned_bytes_t *bytes, char *value, void (*deleter)(void *value, void *context),
                            void *context);

/**
 * Converts a null-terminated string into a :c:type:`z_owned_bytes_t` by copying.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded string.
 *   value: Pointer to the string to converts.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_copy_from_str(z_owned_bytes_t *bytes, const char *value);

/**
 * Converts a statically allocated constant null-terminated string into a :c:type:`z_owned_bytes_t` by aliasing.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the encoded string.
 *   value: Pointer to the statically allocated constant string to convert.
 *
 * Return:
 *   ``0`` if conversion is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_from_static_str(z_owned_bytes_t *bytes, const char *value);

/**
 * Constructs an empty payload.
 *
 * Parameters:
 *   bytes: Pointer to an unitialized :c:type:`z_loaned_bytes_t` instance.
 */
void z_bytes_empty(z_owned_bytes_t *bytes);

/**
 * Returns total number of bytes in the container.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to decode.
 *
 * Return:
 *   Number of the bytes in the container.
 */
size_t z_bytes_len(const z_loaned_bytes_t *bytes);

/**
 * Checks if container is empty
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to decode.
 *
 * Return:
 *   ``true`` if conainer is empty,  ``false`` otherwise.
 */
bool z_bytes_is_empty(const z_loaned_bytes_t *bytes);

#if defined(Z_FEATURE_UNSTABLE_API)
/**
 * Attempts to get a contiguous view to the underlying bytes (unstable).
 *
 * This is only possible if data is not fragmented, otherwise the function will fail.
 * In case of fragmented data, consider using `z_bytes_get_slice_iterator()`.
 *
 * Parameters:
 *   bytes: An instance of Zenoh data.
 *   view: An uninitialized memory location where a contiguous view on data will be constructed.
 *
 * Return:
 *   ``0`` in case of success, ``negative value`` otherwise.
 */
z_result_t z_bytes_get_contiguous_view(const z_loaned_bytes_t *bytes, z_view_slice_t *view);
#endif

/**
 * Returns an iterator on raw bytes slices contained in the `z_loaned_bytes_t`.
 *
 * Zenoh may store data in non-contiguous regions of memory, this iterator
 * then allows to access raw data directly without any attempt of deserializing it.
 * Please note that no guarantee is provided on the internal memory layout.
 * The only provided guarantee is on the bytes order that is preserved.
 *
 * Parameters:
 *   bytes: Data to iterate over.
 *
 * Return:
 *   The constructed :c:type:`z_bytes_slice_iterator_t`.
 */
z_bytes_slice_iterator_t z_bytes_get_slice_iterator(const z_loaned_bytes_t *bytes);

/**
 * Constructs :c:type:`z_view_slice_t` providing view to the next slice.
 *
 * Parameters:
 *   iter: An iterator over slices of serialized data.
 *   out: An uninitialized :c:type:`z_view_slice_t` that will contain next slice.
 *
 * Return:
 *   ``false`` when iterator reaches the end,  ``true`` otherwise.
 */
bool z_bytes_slice_iterator_next(z_bytes_slice_iterator_t *iter, z_view_slice_t *out);

/**
 * Returns a reader for the `bytes`.
 *
 * The `bytes` should outlive the reader and should not be modified, while reader is in use.
 *
 * Parameters:
 *   bytes: Data to read.
 *
 * Return:
 *   The constructed :c:type:`z_bytes_reader_t`.
 */
z_bytes_reader_t z_bytes_get_reader(const z_loaned_bytes_t *bytes);

/**
 * Reads data into specified destination.
 *
 * Parameters:
 *   reader: Data reader to read from.
 *   dst: Buffer where the read data is written.
 *   len: Maximum number of bytes to read.
 *
 * Return:
 *   Number of bytes read. If return value is smaller than `len`, it means that the end of the data was reached.
 */
size_t z_bytes_reader_read(z_bytes_reader_t *reader, uint8_t *dst, size_t len);

/**
 * Sets the `reader` position indicator for the payload to the value pointed to by offset.
 * The new position is exactly `offset` bytes measured from the beginning of the payload if origin is `SEEK_SET`,
 * from the current reader position if origin is `SEEK_CUR`, and from the end of the payload if origin is `SEEK_END`.
 *
 * Parameters:
 *   reader: Data reader to reposition.
 *   offset: New position ffset in bytes.
 *   origin: Origin for the new position.
 *
 * Return:
 *   ``0`` in case of success, ``negative value`` otherwise.
 */
z_result_t z_bytes_reader_seek(z_bytes_reader_t *reader, int64_t offset, int origin);

/**
 * Gets the read position indicator.
 *
 * Parameters:
 *   reader: Data reader to get position of.
 *
 * Return:
 *   Read position indicator on success or -1L if failure occurs.
 */
int64_t z_bytes_reader_tell(z_bytes_reader_t *reader);

/**
 * Gets number of bytes that can still be read.
 *
 * Parameters:
 *   reader: Data reader.
 *
 * Return:
 *   Number of bytes that can still be read.
 */
size_t z_bytes_reader_remaining(const z_bytes_reader_t *reader);

/**
 * Constructs an empty writer for payload.
 *
 * Parameters:
 *   writer: An uninitialized memory location where writer is to be constructed.
 *
 * Return:
 *   ``0`` in case of success, ``negative value`` otherwise.
 */
z_result_t z_bytes_writer_empty(z_owned_bytes_writer_t *writer);

/**
 * Finishes writing and returns underlying bytes.
 *
 * Parameters:
 *   writer: A data writer.
 *   bytes: An uninitialized memory location where bytes is to be constructed.
 */
void z_bytes_writer_finish(z_moved_bytes_writer_t *writer, z_owned_bytes_t *bytes);

/**
 * Writes `len` bytes from `src` into underlying :c:type:`z_loaned_bytes_t`.
 *
 * Parameters:
 *   writer: A data writer.
 *   src: Buffer to write from.
 *   len: Number of bytes to write.
 *
 * Return:
 *   ``0`` if write is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_writer_write_all(z_loaned_bytes_writer_t *writer, const uint8_t *src, size_t len);

/**
 * Appends bytes.
 * This allows to compose a serialized data out of multiple `z_owned_bytes_t` that may point to different memory
 * regions. Said in other terms, it allows to create a linear view on different memory regions without copy.
 *
 * Parameters:
 *   writer: A data writer.
 *   bytes: A data to append.
 *
 * Return:
 *   ``0`` if write is successful, ``negative value`` otherwise.
 */
z_result_t z_bytes_writer_append(z_loaned_bytes_writer_t *writer, z_moved_bytes_t *bytes);

/**
 * Create timestamp.
 *
 * Parameters:
 *   ts: An uninitialized :c:type:`z_timestamp_t`.
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to get the id from.
 *
 * Return:
 *   ``0`` if encode is successful, ``negative value`` otherwise (for example if RTC is not available on the system).
 */
z_result_t z_timestamp_new(z_timestamp_t *ts, const z_loaned_session_t *zs);

/**
 * Returns NTP64 time associated with this timestamp.
 *
 * Parameters:
 *   ts: Pointer to the valid :c:type:`z_timestamp_t`.
 *
 * Return:
 *   NTP64 time value
 */
uint64_t z_timestamp_ntp64_time(const z_timestamp_t *ts);

/**
 * Returns id associated with this timestamp.
 *
 * Parameters:
 *   ts: Pointer to the valid :c:type:`z_timestamp_t`.
 *
 * Return:
 *   Associated id represented by c:type:`z_id_t`
 */
z_id_t z_timestamp_id(const z_timestamp_t *ts);

/**
 * Creates an entity global id.
 *
 * Parameters:
 *   gid: An uninitialized :c:type:`z_entity_global_id_t`.
 *   zid: Pointer to a :c:type:`z_id_t` zenoh id.
 *   eid: :c:type:`uint32_t` entity id.
 */
z_result_t z_entity_global_id_new(z_entity_global_id_t *gid, const z_id_t *zid, uint32_t eid);

/**
 * Returns the entity id of the entity global id.
 *
 * Parameters:
 *   gid: Pointer to the valid :c:type:`z_entity_global_id_t`.
 *
 * Return:
 *   Entity id represented by c:type:`uint32_t`.
 */
uint32_t z_entity_global_id_eid(const z_entity_global_id_t *gid);

/**
 * Returns the zenoh id of entity global id.
 *
 * Parameters:
 *   gid: Pointer to the valid :c:type:`z_entity_global_id_t`.
 *
 * Return:
 *   Zenoh id represented by c:type:`z_id_t`.
 */
z_id_t z_entity_global_id_zid(const z_entity_global_id_t *gid);

/**
 * Constructs a new source info.
 *
 * Parameters:
 *   source_id: Non-null pointer to a :c:type:`z_entity_global_id_t` global entity id.
 *   source_sn: :c:type:`uint32_t` sequence number.
 *
 * Return:
 *   Source info.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_source_info_t z_source_info_new(const z_entity_global_id_t *source_id, uint32_t source_sn);

/**
 * Returns the sequence number associated with this source info.
 *
 * Parameters:
 *   info: Pointer to the :c:type:`z_source_info_t` to get the sequence number from.
 *
 * Return:
 *   :c:type:`uint32_t` sequence number.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
uint32_t z_source_info_sn(const z_source_info_t *info);

/**
 * Returns the id associated with this source info.
 *
 * Parameters:
 *   info: Pointer to the :c:type:`z_source_info_t` to get the id from.
 *
 * Return:
 *   Global entity ID as a :c:type:`z_entity_global_id_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_entity_global_id_t z_source_info_id(const z_source_info_t *info);

/**
 * Builds a default query target.
 *
 * Return:
 *   The constructed :c:type:`z_query_target_t`.
 */
z_query_target_t z_query_target_default(void);

/**
 * Builds a default query reply key expression type.
 *
 * Return:
 *   The constructed :c:type:`z_reply_keyexpr_t`.
 */
z_reply_keyexpr_t z_reply_keyexpr_default(void);

/**
 * Builds an automatic query consolidation :c:type:`z_query_consolidation_t`.
 *
 * A query consolidation strategy will automatically be selected depending on the query selector.
 * If selector contains time range properties, no consolidation is performed.
 * Otherwise the :c:func:`z_query_consolidation_latest` strategy is used.
 *
 * Return:
 *   The constructed :c:type:`z_query_consolidation_t`.
 */
z_query_consolidation_t z_query_consolidation_auto(void);

/**
 * Builds a default :c:type:`z_query_consolidation_t`.
 *
 * Return:
 *   The constructed :c:type:`z_query_consolidation_t`.
 */
z_query_consolidation_t z_query_consolidation_default(void);

/**
 * Builds a latest query consolidation :c:type:`z_query_consolidation_t`.
 *
 * This strategy optimizes bandwidth on all links in the system but will provide a very poor latency.
 *
 * Return:
 *   The constructed :c:type:`z_query_consolidation_t`.
 */
z_query_consolidation_t z_query_consolidation_latest(void);

/**
 * Builds a monotonic query consolidation :c:type:`z_query_consolidation_t`.
 *
 * This strategy offers the best latency. Replies are directly transmitted to the application when received
 * without needing to wait for all replies. This mode does not guarantee that there will be no duplicates.
 *
 * Return:
 *   The constructed :c:type:`z_query_consolidation_t`.
 */
z_query_consolidation_t z_query_consolidation_monotonic(void);

/**
 * Builds a no query consolidation :c:type:`z_query_consolidation_t`.
 *
 * This strategy is useful when querying timeseries data bases or when using quorums.
 *
 * Return:
 *   The constructed :c:type:`z_query_consolidation_t`.
 */
z_query_consolidation_t z_query_consolidation_none(void);

/**
 * Gets a query parameters field.
 *
 * Parameters:
 *   query: Pointer to the :c:type:`z_loaned_query_t` to get the parameters from.
 *   parameters: Pointer to an uninitialized :c:type:`z_view_string_t` to contain the parameters.
 */
void z_query_parameters(const z_loaned_query_t *query, z_view_string_t *parameters);

/**
 * Queries may or may not accept replies on key expressions that do not intersect with their own key expression.
 * This getter allows you to check whether or not a specific query does so.
 *
 * Parameters:
 *   query: Pointer to the :c:type:`z_loaned_query_t` to get the target from.
 *
 * Return:
 *   The query reply key expression type as a :c:type:`z_reply_keyexpr_t`.
 */
z_reply_keyexpr_t z_query_accepts_replies(const z_loaned_query_t *query);

/**
 * Gets a query payload by aliasing it.
 *
 * Parameters:
 *   query: Pointer to the :c:type:`z_loaned_query_t` to get the value from.
 *
 * Return:
 *   Pointer to the payload as a :c:type:`z_loaned_bytes_t`.
 */
const z_loaned_bytes_t *z_query_payload(const z_loaned_query_t *query);

/**
 * Gets a query encoding by aliasing it.
 *
 * Parameters:
 *   query: Pointer to the :c:type:`z_loaned_query_t` to get the value from.
 *
 * Return:
 *   Pointer to the encoding as a :c:type:`z_loaned_encoding_t`.
 */
const z_loaned_encoding_t *z_query_encoding(const z_loaned_query_t *query);

/**
 * Gets a query attachment value by aliasing it.
 *
 * Parameters:
 *   query: Pointer to the :c:type:`z_loaned_query_t` to get the attachment from.
 *
 * Return:
 *   Pointer to the attachment as a :c:type:`z_loaned_bytes_t`.
 */
const z_loaned_bytes_t *z_query_attachment(const z_loaned_query_t *query);

/**
 * Gets a query keyexpr by aliasing it.
 *
 * Parameters:
 *   query: Pointer to the :c:type:`z_loaned_query_t` to get the keyexpr from.
 *
 * Return:
 *   The keyexpr wrapped as a:c:type:`z_keyexpr_t`.
 */
const z_loaned_keyexpr_t *z_query_keyexpr(const z_loaned_query_t *query);

/**
 * Gets a query source info by aliasing it.
 *
 * Parameters:
 *   query: Pointer to the :c:type:`z_loaned_query_t` to get the value from.
 *
 * Return:
 *   Pointer to the source info as a :c:type:`z_source_info_t`. Will return NULL if source info was not set by querier.
 */
const z_source_info_t *z_query_source_info(const z_loaned_query_t *query);

/**
 * Builds a new sample closure.
 * It consists of a structure that contains all the elements for stateful, memory-leak-free callbacks.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_sample_t`.
 *   call: Pointer to the callback function. ``context`` will be passed as its last argument.
 *   drop: Pointer to the function that will free the callback state. ``context`` will be passed as its last argument.
 *   context: Pointer to an arbitrary state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise
 */
z_result_t z_closure_sample(z_owned_closure_sample_t *closure, z_closure_sample_callback_t call,
                            z_closure_drop_callback_t drop, void *context);

/**
 * Calls a sample closure.
 *
 * Parameters:
 *   closure: Pointer to the :c:type:`z_loaned_closure_sample_t` to call.
 *   sample: Pointer to the :c:type:`z_loaned_sample_t` to pass to the closure.
 */
void z_closure_sample_call(const z_loaned_closure_sample_t *closure, z_loaned_sample_t *sample);

/**
 * Builds a new query closure.
 * It consists of a structure that contains all the elements for stateful, memory-leak-free callbacks.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_query_t`.
 *   call: Pointer to the callback function. ``context`` will be passed as its last argument.
 *   drop: Pointer to the function that will free the callback state. ``context`` will be passed as its last argument.
 *   context: Pointer to an arbitrary state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise
 */
z_result_t z_closure_query(z_owned_closure_query_t *closure, z_closure_query_callback_t call,
                           z_closure_drop_callback_t drop, void *context);

/**
 * Calls a query closure.
 *
 * Parameters:
 *   closure: Pointer to the :c:type:`z_loaned_closure_query_t` to call.
 *   query: Pointer to the :c:type:`z_loaned_query_t` to pass to the closure.
 */
void z_closure_query_call(const z_loaned_closure_query_t *closure, z_loaned_query_t *query);

/**
 * Builds a new reply closure.
 * It consists of a structure that contains all the elements for stateful, memory-leak-free callbacks.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_reply_t`.
 *   call: Pointer to the callback function. ``context`` will be passed as its last argument.
 *   drop: Pointer to the function that will free the callback state. ``context`` will be passed as its last argument.
 *   context: Pointer to an arbitrary state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise
 */
z_result_t z_closure_reply(z_owned_closure_reply_t *closure, z_closure_reply_callback_t call,
                           z_closure_drop_callback_t drop, void *context);

/**
 * Calls a reply closure.
 *
 * Parameters:
 *   closure: Pointer to the :c:type:`z_loaned_closure_reply_t` to call.
 *   reply: Pointer to the :c:type:`z_loaned_reply_t` to pass to the closure.
 */
void z_closure_reply_call(const z_loaned_closure_reply_t *closure, z_loaned_reply_t *reply);

/**
 * Builds a new hello closure.
 * It consists of a structure that contains all the elements for stateful, memory-leak-free callbacks.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_hello_t`.
 *   call: Pointer to the callback function. ``context`` will be passed as its last argument.
 *   drop: Pointer to the function that will free the callback state. ``context`` will be passed as its last argument.
 *   context: Pointer to an arbitrary state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise
 */
z_result_t z_closure_hello(z_owned_closure_hello_t *closure, z_closure_hello_callback_t call,
                           z_closure_drop_callback_t drop, void *context);

/**
 * Calls a hello closure.
 *
 * Parameters:
 *   closure: Pointer to the :c:type:`z_loaned_closure_hello_t` to call.
 *   hello: Pointer to the :c:type:`z_loaned_hello_t` to pass to the closure.
 */
void z_closure_hello_call(const z_loaned_closure_hello_t *closure, z_loaned_hello_t *hello);

/**
 * Builds a new zid closure.
 * It consists of a structure that contains all the elements for stateful, memory-leak-free callbacks.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_zid_t`.
 *   call: Pointer to the callback function. ``context`` will be passed as its last argument.
 *   drop: Pointer to the function that will free the callback state. ``context`` will be passed as its last argument.
 *   context: Pointer to an arbitrary state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise
 */
z_result_t z_closure_zid(z_owned_closure_zid_t *closure, z_closure_zid_callback_t call, z_closure_drop_callback_t drop,
                         void *context);

/**
 * Calls a zid closure.
 *
 * Parameters:
 *   closure: Pointer to the :c:type:`z_loaned_closure_zid_t` to call.
 *   zid: Pointer to the :c:type:`z_id_t` to pass to the closure.
 */
void z_closure_zid_call(const z_loaned_closure_zid_t *closure, const z_id_t *id);

#if Z_FEATURE_CONNECTIVITY == 1
/**
 * Builds a new transport closure.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_transport_t`.
 *   call: Pointer to the callback function.
 *   drop: Pointer to callback-state cleanup function.
 *   context: Pointer to arbitrary callback state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_closure_transport(z_owned_closure_transport_t *closure, z_closure_transport_callback_t call,
                               z_closure_drop_callback_t drop, void *context);

/**
 * Calls a transport closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_closure_transport_call(const z_loaned_closure_transport_t *closure, z_loaned_transport_t *transport);

/**
 * Builds a new link closure.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_link_t`.
 *   call: Pointer to the callback function.
 *   drop: Pointer to callback-state cleanup function.
 *   context: Pointer to arbitrary callback state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_closure_link(z_owned_closure_link_t *closure, z_closure_link_callback_t call,
                          z_closure_drop_callback_t drop, void *context);

/**
 * Calls a link closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_closure_link_call(const z_loaned_closure_link_t *closure, z_loaned_link_t *link);

/**
 * Builds a new transport event closure.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_transport_event_t`.
 *   call: Pointer to the callback function.
 *   drop: Pointer to callback-state cleanup function.
 *   context: Pointer to arbitrary callback state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_closure_transport_event(z_owned_closure_transport_event_t *closure,
                                     z_closure_transport_event_callback_t call, z_closure_drop_callback_t drop,
                                     void *context);

/**
 * Calls a transport event closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_closure_transport_event_call(const z_loaned_closure_transport_event_t *closure,
                                    z_loaned_transport_event_t *event);

/**
 * Builds a new link event closure.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_link_event_t`.
 *   call: Pointer to the callback function.
 *   drop: Pointer to callback-state cleanup function.
 *   context: Pointer to arbitrary callback state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_closure_link_event(z_owned_closure_link_event_t *closure, z_closure_link_event_callback_t call,
                                z_closure_drop_callback_t drop, void *context);

/**
 * Calls a link event closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_closure_link_event_call(const z_loaned_closure_link_event_t *closure, z_loaned_link_event_t *event);
#endif

/**
 * Builds a new matching status closure.
 * It consists of a structure that contains all the elements for stateful, memory-leak-free callbacks.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`z_owned_closure_matching_status_t`.
 *   call: Pointer to the callback function. ``context`` will be passed as its last argument.
 *   drop: Pointer to the function that will free the callback state. ``context`` will be passed as its last argument.
 *   context: Pointer to an arbitrary state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise
 */
z_result_t z_closure_matching_status(z_owned_closure_matching_status_t *closure,
                                     z_closure_matching_status_callback_t call, z_closure_drop_callback_t drop,
                                     void *context);

/**
 * Calls a matching status closure.
 *
 * Parameters:
 *   closure: Pointer to the :c:type:`z_loaned_closure_matching_status_t` to call.
 *   status: Pointer to the :c:type:`z_matching_status_t` to pass to the closure.
 */
void z_closure_matching_status_call(const z_loaned_closure_matching_status_t *closure,
                                    const z_matching_status_t *status);

/**
 * Builds a new sample miss closure.
 * It consists of a structure that contains all the elements for stateful, memory-leak-free callbacks.
 *
 * Parameters:
 *   closure: Pointer to an uninitialized :c:type:`ze_owned_closure_miss_t`.
 *   call: Pointer to the callback function. ``context`` will be passed as its last argument.
 *   drop: Pointer to the function that will free the callback state. ``context`` will be passed as its last argument.
 *   context: Pointer to an arbitrary state.
 *
 * Return:
 *   ``0`` in case of success, negative error code otherwise
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t ze_closure_miss(ze_owned_closure_miss_t *closure, ze_closure_miss_callback_t call,
                           z_closure_drop_callback_t drop, void *context);

/**
 * Calls a sample miss closure.
 *
 * Parameters:
 *   closure: Pointer to the :c:type:`ze_loaned_closure_miss_t` to call.
 *   status: Pointer to the :c:type:`ze_miss_t` to pass to the closure.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
void ze_closure_miss_call(const ze_loaned_closure_miss_t *closure, const ze_miss_t *miss);

/**************** Loans ****************/
_Z_OWNED_FUNCTIONS_DEF(string)
_Z_OWNED_FUNCTIONS_DEF(keyexpr)
_Z_OWNED_FUNCTIONS_DEF(config)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(session)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(subscriber)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(publisher)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(querier)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(matching_listener)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(queryable)
_Z_OWNED_FUNCTIONS_DEF(hello)
_Z_OWNED_FUNCTIONS_DEF(reply)
_Z_OWNED_FUNCTIONS_DEF(string_array)
_Z_OWNED_FUNCTIONS_DEF(sample)
_Z_OWNED_FUNCTIONS_DEF(query)
_Z_OWNED_FUNCTIONS_DEF(slice)
_Z_OWNED_FUNCTIONS_DEF(bytes)
_Z_OWNED_FUNCTIONS_NO_COPY_DEF(bytes_writer)
_Z_OWNED_FUNCTIONS_DEF(reply_err)
_Z_OWNED_FUNCTIONS_DEF(encoding)

_Z_OWNED_FUNCTIONS_DEF(cancellation_token)

#if Z_FEATURE_CONNECTIVITY == 1
_Z_OWNED_FUNCTIONS_DEF(transport)
_Z_OWNED_FUNCTIONS_DEF(link)
_Z_OWNED_FUNCTIONS_DEF(transport_event)
_Z_OWNED_FUNCTIONS_DEF(link_event)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(transport_events_listener)
_Z_OWNED_FUNCTIONS_NO_COPY_NO_MOVE_DEF(link_events_listener)
#endif

_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_sample)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_query)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_reply)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_hello)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_zid)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_matching_status)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF_PREFIX(ze, closure_miss)
#if Z_FEATURE_CONNECTIVITY == 1
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_transport)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_link)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_transport_event)
_Z_OWNED_FUNCTIONS_CLOSURE_DEF(closure_link_event)
#endif

_Z_VIEW_FUNCTIONS_DEF(keyexpr)
_Z_VIEW_FUNCTIONS_DEF(string)
_Z_VIEW_FUNCTIONS_DEF(slice)

/**
 * Loans a :c:type:`z_owned_sample_t`.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_owned_sample_t` to loan.
 *
 * Return:
 *   Pointer to the loaned sample as a :c:type:`z_loaned_sample_t`.
 */
const z_loaned_sample_t *z_sample_loan(const z_owned_sample_t *sample);

/**
 * Gets data from a :c:type:`z_loaned_string_t`.
 *
 * Parameters:
 *   str: Pointer to a :c:type:`z_loaned_string_t` to get data from.
 *
 * Return:
 *   Pointer to the string data.
 */
const char *z_string_data(const z_loaned_string_t *str);

/**
 * Gets string length from a :c:type:`z_loaned_string_t`.
 *
 * Parameters:
 *   str: Pointer to a :c:type:`z_loaned_string_t` to get length from.
 *
 * Return:
 *   Length of the string.
 */
size_t z_string_len(const z_loaned_string_t *str);

/**
 * Builds a :c:type:`z_string_t` by copying a ``const char *`` string.
 *
 * Parameters:
 *   str: Pointer to an uninitialized :c:type:`z_owned_string_t`.
 *   value: Pointer to a null terminated string to be copied.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_string_copy_from_str(z_owned_string_t *str, const char *value);

/**
 * Builds a :c:type:`z_owned_string_t` by transferring ownership over a null-terminated string to it.
 *
 * Parameters:
 *   str: Pointer to an uninitialized :c:type:`z_owned_string_t`.
 *   value: Pointer to a null terminated string to be owned by `str`.
 *   deleter: A thread-safe delete function to free the `value`. Will be called once when `str` is dropped.
 *     Can be NULL in the case where `value` is allocated in static memory.
 *   context: An optional context to be passed to the `deleter`.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_string_from_str(z_owned_string_t *str, char *value, void (*deleter)(void *value, void *context),
                             void *context);

/**
 * Builds an empty :c:type:`z_owned_string_t`.
 *
 * Parameters:
 *   str: Pointer to an uninitialized :c:type:`z_owned_string_t`.
 */
void z_string_empty(z_owned_string_t *str);

/**
 * Builds a :c:type:`z_string_t` by wrapping a substring specified by ``const char *`` and length `len`.
 *
 * Parameters:
 *   str: Pointer to an uninitialized :c:type:`z_owned_string_t`.
 *   value: Pointer to a string.
 *   len: String size.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_string_copy_from_substr(z_owned_string_t *str, const char *value, size_t len);

/**
 * Checks if string is empty
 *
 * Parameters:
 *   str: Pointer to a :c:type:`z_loaned_string_t` to check.
 *
 * Return:
 *  ``true`` if the string is empty, ``false`` otherwise.
 */
bool z_string_is_empty(const z_loaned_string_t *str);

/**
 * Returns :c:type:`z_loaned_slice_t` for the string
 *
 * Parameters:
 *   str: Pointer to a :c:type:`z_loaned_string_t` to get a slice.
 *
 * Return:
 *   slice containing string data
 */
const z_loaned_slice_t *z_string_as_slice(const z_loaned_string_t *str);

/**
 * Returns default :c:type:`z_priority_t` value
 */
z_priority_t z_priority_default(void);

#if Z_FEATURE_SCOUTING == 1
/**
 * Returns id of Zenoh entity that transmitted hello message.
 *
 * Parameters:
 *   hello: Pointer to a :c:type:`z_loaned_hello_t` message.
 *
 * Return:
 *   Id of the Zenoh entity that transmitted hello message.
 */
z_id_t z_hello_zid(const z_loaned_hello_t *hello);

/**
 * Returns type of Zenoh entity that transmitted hello message.
 *
 * Parameters:
 *   hello: Pointer to a :c:type:`z_loaned_hello_t` message.
 *
 * Return:
 *   Type of the Zenoh entity that transmitted hello message.
 */
z_whatami_t z_hello_whatami(const z_loaned_hello_t *hello);

/**
 * Returns an array of locators of Zenoh entity that sent hello message.
 *
 * Parameters:
 *   hello: Pointer to a :c:type:`z_loaned_hello_t` message.
 *
 * Return:
 *   :c:type:`z_loaned_string_array_t` containing locators.
 */
const z_loaned_string_array_t *zp_hello_locators(const z_loaned_hello_t *hello);

/**
 * Constructs an array of locators of Zenoh entity that sent hello message.
 *
 * Note that it is a method for zenoh-c compatiblity, in zenoh-pico :c:func:`zp_hello_locators`
 * can be used.
 *
 * Parameters:
 *   hello: Pointer to a :c:type:`z_loaned_hello_t` message.
 *   locators_out: An uninitialized memory location where :c:type:`z_owned_string_array_t` will be constructed.
 */
void z_hello_locators(const z_loaned_hello_t *hello, z_owned_string_array_t *locators_out);

/**
 * Constructs a non-owned non-null-terminated string from the kind of zenoh entity.
 *
 * The string has static storage (i.e. valid until the end of the program).
 *
 * Parameters:
 *   whatami: A whatami bitmask of zenoh entity kind.
 *   str_out: An uninitialized memory location where strring will be constructed.
 *
 * Return:
 *   ``0`` in case of success, ``negative value`` otherwise.
 */
z_result_t z_whatami_to_view_string(z_whatami_t whatami, z_view_string_t *str_out);

/************* Primitives **************/

/**
 * Scouts for other Zenoh entities like routers and/or peers.
 *
 * Parameters:
 *   config: Moved :c:type:`z_owned_config_t` to configure the scouting with.
 *   callback: Moved :c:type:`z_owned_closure_hello_t` callback.
 *   options: Pointer to a :c:type:`z_scout_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if scouting was successfully triggered, ``negative value`` otherwise.
 */
z_result_t z_scout(z_moved_config_t *config, z_moved_closure_hello_t *callback, const z_scout_options_t *options);

/**
 * Builds a :c:type:`z_scout_options_t` with default value.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_scout_options_t`.
 */
void z_scout_options_default(z_scout_options_t *options);
#endif

/**
 * Opens a Zenoh session.
 *
 * Parameters:
 *   zs: Pointer to an uninitialized :c:type:`z_owned_session_t` to store the session info.
 *   config: Moved :c:type:`z_owned_config_t` to configure the session with.
 *   options: Pointer to a :c:type:`z_open_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if open is successful, ``negative value`` otherwise.
 */
z_result_t z_open(z_owned_session_t *zs, z_moved_config_t *config, const z_open_options_t *options);

/**
 * Builds a :c:type:`z_open_options_t` with default value.
 */
void z_open_options_default(z_open_options_t *options);

/**
 * Closes a Zenoh session.
 *
 * Parameters:
 *   zs: Loaned :c:type:`z_owned_session_t` to close.
 *   options: Pointer to a :c:type:`z_close_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if close is successful, ``negative value`` otherwise.
 */
z_result_t z_close(z_loaned_session_t *zs, const z_close_options_t *options);

/**
 * Checks if Zenoh session is closed.
 *
 * Parameters:
 *   zs: Loaned :c:type:`z_owned_session_t`.
 *
 * Return:
 *   ``true`` if session is closed, ``false`` otherwise.
 */
bool z_session_is_closed(const z_loaned_session_t *zs);

#ifdef Z_FEATURE_UNSTABLE_API
/**
 * Gets the entity global Id of Zenoh session (unstable).
 *
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to get the id from.
 *
 * Return:
 *   The entity global Id of the session as :c:type:`z_entity_t`.
 */
z_entity_global_id_t z_session_id(const z_loaned_session_t *zs);
#endif
/**
 * Fetches Zenoh IDs of all connected peers.
 *
 * The callback will be called once for each ID. It is guaranteed to never be called concurrently,
 * and to be dropped before this function exits.
 *
 * Parameters:
 *   zs: Pointer to :c:type:`z_loaned_session_t` to fetch peer id from.
 *   callback: Moved :c:type:`z_owned_closure_zid_t` callback.
 *
 * Return:
 *   ``0`` if operation was successfully triggered, ``negative value`` otherwise.
 */
z_result_t z_info_peers_zid(const z_loaned_session_t *zs, z_moved_closure_zid_t *callback);

/**
 * Fetches Zenoh IDs of all connected routers.
 *
 * The callback will be called once for each ID. It is guaranteed to never be called concurrently,
 * and to be dropped before this function exits.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to fetch router id from.
 *   callback: Moved :c:type:`z_owned_closure_zid_t` callback.
 *
 * Return:
 *   ``0`` if operation was successfully triggered, ``negative value`` otherwise.
 */
z_result_t z_info_routers_zid(const z_loaned_session_t *zs, z_moved_closure_zid_t *callback);

/**
 * Gets the local Zenoh ID associated to a given Zenoh session.
 *
 * If this function returns an array of 16 zeros, this means the session is invalid.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to get the id from.
 *
 * Return:
 *   The local Zenoh ID of the session as :c:type:`z_id_t`.
 */
z_id_t z_info_zid(const z_loaned_session_t *zs);

static inline void _z_transport_link_properties_from_transport(const _z_transport_common_t *transport, uint16_t *mtu,
                                                               bool *is_streamed, bool *is_reliable) {
    *mtu = 0;
    *is_streamed = false;
    *is_reliable = false;

    if (transport != NULL && transport->_link != NULL) {
        *mtu = transport->_link->_mtu;
        *is_streamed = transport->_link->_cap._flow == Z_LINK_CAP_FLOW_STREAM;
        *is_reliable = transport->_link->_cap._is_reliable;
    }
}

#if Z_FEATURE_CONNECTIVITY == 1
void _z_info_transport_from_peer(_z_info_transport_t *out, const _z_transport_peer_common_t *peer, bool is_multicast);
bool _z_info_transport_filter_match(const _z_info_transport_t *transport, const _z_info_transport_t *filter);

/**
 * Fetches all currently connected transports.
 *
 * The callback is called once for each transport and is dropped before this function exits.
 *
 * Parameters:
 *   zs: Pointer to :c:type:`z_loaned_session_t`.
 *   callback: Moved :c:type:`z_owned_closure_transport_t` callback.
 *
 * Return:
 *   ``0`` if operation was successfully triggered, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_info_transports(const z_loaned_session_t *zs, z_moved_closure_transport_t *callback);

/**
 * Constructs default value for :c:type:`z_info_links_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_info_links_options_default(z_info_links_options_t *options);

/**
 * Fetches all currently connected links.
 *
 * The callback is called once for each link and is dropped before this function exits.
 *
 * Parameters:
 *   zs: Pointer to :c:type:`z_loaned_session_t`.
 *   callback: Moved :c:type:`z_owned_closure_link_t` callback.
 *   options: Optional :c:type:`z_info_links_options_t`.
 *
 * Return:
 *   ``0`` if operation was successfully triggered, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_info_links(const z_loaned_session_t *zs, z_moved_closure_link_t *callback,
                        z_info_links_options_t *options);

/**
 * Constructs default value for :c:type:`z_transport_events_listener_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_transport_events_listener_options_default(z_transport_events_listener_options_t *options);

/**
 * Declares a transport events listener.
 *
 * Parameters:
 *   zs: Pointer to :c:type:`z_loaned_session_t`.
 *   listener: Uninitialized location where listener will be constructed.
 *   callback: Moved :c:type:`z_owned_closure_transport_event_t`.
 *   options: Optional :c:type:`z_transport_events_listener_options_t`.
 *
 * Return:
 *   ``0`` on success, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_declare_transport_events_listener(const z_loaned_session_t *zs,
                                               z_owned_transport_events_listener_t *listener,
                                               z_moved_closure_transport_event_t *callback,
                                               const z_transport_events_listener_options_t *options);

/**
 * Declares a background transport events listener.
 *
 * The listener runs in background and cannot be undeclared explicitly.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_declare_background_transport_events_listener(const z_loaned_session_t *zs,
                                                          z_moved_closure_transport_event_t *callback,
                                                          const z_transport_events_listener_options_t *options);

/**
 * Undeclares a transport events listener.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_undeclare_transport_events_listener(z_moved_transport_events_listener_t *listener);

/**
 * Constructs default value for :c:type:`z_link_events_listener_options_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_link_events_listener_options_default(z_link_events_listener_options_t *options);

/**
 * Declares a link events listener.
 *
 * Parameters:
 *   zs: Pointer to :c:type:`z_loaned_session_t`.
 *   listener: Uninitialized location where listener will be constructed.
 *   callback: Moved :c:type:`z_owned_closure_link_event_t`.
 *   options: Optional :c:type:`z_link_events_listener_options_t`.
 *
 * Return:
 *   ``0`` on success, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_declare_link_events_listener(const z_loaned_session_t *zs, z_owned_link_events_listener_t *listener,
                                          z_moved_closure_link_event_t *callback,
                                          z_link_events_listener_options_t *options);

/**
 * Declares a background link events listener.
 *
 * The listener runs in background and cannot be undeclared explicitly.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_declare_background_link_events_listener(const z_loaned_session_t *zs,
                                                     z_moved_closure_link_event_t *callback,
                                                     z_link_events_listener_options_t *options);

/**
 * Undeclares a link events listener.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_undeclare_link_events_listener(z_moved_link_events_listener_t *listener);

/**
 * Gets a transport remote Zenoh ID.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_id_t z_transport_zid(const z_loaned_transport_t *transport);

/**
 * Gets a transport remote entity kind.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_whatami_t z_transport_whatami(const z_loaned_transport_t *transport);

/**
 * Returns whether QoS is enabled for this transport.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
bool z_transport_is_qos(const z_loaned_transport_t *transport);

/**
 * Returns whether this transport is multicast.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
bool z_transport_is_multicast(const z_loaned_transport_t *transport);

/**
 * Returns whether shared memory is enabled for this transport.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
bool z_transport_is_shm(const z_loaned_transport_t *transport);

/**
 * Gets a link remote Zenoh ID.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_id_t z_link_zid(const z_loaned_link_t *link);

/**
 * Gets a link source endpoint string.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_link_src(const z_loaned_link_t *link, z_owned_string_t *str_out);

/**
 * Gets a link destination endpoint string.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_result_t z_link_dst(const z_loaned_link_t *link, z_owned_string_t *str_out);

/**
 * Gets a link MTU.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
uint16_t z_link_mtu(const z_loaned_link_t *link);

/**
 * Returns whether the link is stream-based.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
bool z_link_is_streamed(const z_loaned_link_t *link);

/**
 * Returns whether the link transport is reliable.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
bool z_link_is_reliable(const z_loaned_link_t *link);

/**
 * Gets a link group string.
 *
 * Parameters:
 *   link: Pointer to a :c:type:`z_loaned_link_t`.
 *   str_out: Pointer to an uninitialized :c:type:`z_owned_string_t` to store the result.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_link_group(const z_loaned_link_t *link, z_owned_string_t *str_out);

/**
 * Gets a link auth identifier string.
 *
 * Parameters:
 *   link: Pointer to a :c:type:`z_loaned_link_t`.
 *   str_out: Pointer to an uninitialized :c:type:`z_owned_string_t` to store the result.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_link_auth_identifier(const z_loaned_link_t *link, z_owned_string_t *str_out);

/**
 * Gets link interfaces.
 *
 * Parameters:
 *   link: Pointer to a :c:type:`z_loaned_link_t`.
 *   interfaces_out: Pointer to an uninitialized :c:type:`z_owned_string_array_t` to store the result.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
void z_link_interfaces(const z_loaned_link_t *link, z_owned_string_array_t *interfaces_out);

/**
 * Gets link priority range.
 *
 * Parameters:
 *   link: Pointer to a :c:type:`z_loaned_link_t`.
 *   min_out: Pointer to store the minimum priority value.
 *   max_out: Pointer to store the maximum priority value.
 *
 * Return:
 *   ``true`` if link has priority information, ``false`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
bool z_link_priorities(const z_loaned_link_t *link, uint8_t *min_out, uint8_t *max_out);

/**
 * Gets link reliability.
 *
 * Parameters:
 *   link: Pointer to a :c:type:`z_loaned_link_t`.
 *   reliability_out: Pointer to store the reliability value.
 *
 * Return:
 *   ``true`` if link has reliability information, ``false`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
bool z_link_reliability(const z_loaned_link_t *link, z_reliability_t *reliability_out);

/**
 * Gets transport event kind.
 *
 * Returns ``Z_SAMPLE_KIND_PUT`` when a transport is connected and ``Z_SAMPLE_KIND_DELETE`` when disconnected.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_sample_kind_t z_transport_event_kind(const z_loaned_transport_event_t *event);

/**
 * Gets transport event transport.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
const z_loaned_transport_t *z_transport_event_transport(const z_loaned_transport_event_t *event);

/**
 * Gets mutable transport event transport.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_loaned_transport_t *z_transport_event_transport_mut(z_loaned_transport_event_t *event);

/**
 * Gets link event kind.
 *
 * Returns ``Z_SAMPLE_KIND_PUT`` when a link is added and ``Z_SAMPLE_KIND_DELETE`` when removed.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_sample_kind_t z_link_event_kind(const z_loaned_link_event_t *event);

/**
 * Gets link event link.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
const z_loaned_link_t *z_link_event_link(const z_loaned_link_event_t *event);

/**
 * Gets mutable link event link.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future
 * release.
 */
z_loaned_link_t *z_link_event_link_mut(z_loaned_link_event_t *event);
#endif

/**
 * Converts a Zenoh ID into a string for print purposes.
 *
 * Parameters:
 *   id: Pointer to the id to convert.
 *   str: Pointer to uninitialized :c:type:`z_owned_string_t` to store the string.
 *
 * Return:
 *   ``0`` if operation is successful, ``negative value`` otherwise.
 */
z_result_t z_id_to_string(const z_id_t *id, z_owned_string_t *str);

/**
 * Gets the keyexpr from a sample by aliasing it.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the keyexpr from.
 *
 * Return:
 *   The keyexpr wrapped as a :c:type:`z_loaned_keyexpr_t`.
 */
const z_loaned_keyexpr_t *z_sample_keyexpr(const z_loaned_sample_t *sample);

/**
 * Gets the payload of a sample by aliasing it.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the payload from.
 *
 * Return:
 *   The payload wrapped as a :c:type:`z_loaned_bytes_t`.
 */
const z_loaned_bytes_t *z_sample_payload(const z_loaned_sample_t *sample);

/**
 * Gets the timestamp of a sample by aliasing it.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the timestamp from.
 *
 * Return:
 *   The pointer to timestamp wrapped as a :c:type:`z_timestamp_t`. Returns NULL if no timestamp was set.
 */
const z_timestamp_t *z_sample_timestamp(const z_loaned_sample_t *sample);

/**
 * Gets the encoding of a sample by aliasing it.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the encoding from.
 *
 * Return:
 *   The encoding wrapped as a :c:type:`z_loaned_encoding_t`.
 */
const z_loaned_encoding_t *z_sample_encoding(const z_loaned_sample_t *sample);

/**
 * Gets the kind of a sample by aliasing it.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the kind from.
 *
 * Return:
 *   The sample kind wrapped as a :c:type:`z_sample_kind_t`.
 */
z_sample_kind_t z_sample_kind(const z_loaned_sample_t *sample);

#ifdef Z_FEATURE_UNSTABLE_API
/**
 * Gets the reliability a sample was received with (unstable).
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the reliability from.
 *
 * Return:
 *   The reliability wrapped as a :c:type:`z_reliability_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_reliability_t z_sample_reliability(const z_loaned_sample_t *sample);

/**
 * Gets the source info for the sample (unstable).
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the source info from.
 *
 * Return:
 *   The source info wrapped as a :c:type:`z_source_info_t`. Will return NULL if source info was not set by sender.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
const z_source_info_t *z_sample_source_info(const z_loaned_sample_t *sample);
#endif

/**
 * Got a sample qos congestion control value.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the congestion control from.
 *
 * Return:
 *   The congestion control wrapped as a :c:type:`z_congestion_control_t`.
 */
z_congestion_control_t z_sample_congestion_control(const z_loaned_sample_t *sample);

/**
 * Got whether sample qos express flag was set or not.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the express flag from.
 *
 * Return:
 *   The express flag value.
 */
bool z_sample_express(const z_loaned_sample_t *sample);

/**
 * Gets sample qos priority value.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the qos priority from.
 *
 * Return:
 *   The priority wrapped as a :c:type:`z_priority_t`.
 */
z_priority_t z_sample_priority(const z_loaned_sample_t *sample);

/**
 * Gets the attachment of a sample by aliasing it.
 *
 * Parameters:
 *   sample: Pointer to a :c:type:`z_loaned_sample_t` to get the attachment from.
 *
 * Return:
 *   Pointer to the attachment as a :c:type:`z_loaned_bytes_t`.
 */
const z_loaned_bytes_t *z_sample_attachment(const z_loaned_sample_t *sample);

#if Z_FEATURE_PUBLICATION == 1
/**
 * Builds a :c:type:`z_put_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_put_options_t`.
 */
void z_put_options_default(z_put_options_t *options);

/**
 * Builds a :c:type:`z_delete_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_delete_options_t`.
 */
void z_delete_options_default(z_delete_options_t *options);

/**
 * Puts data for a given keyexpr.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to put the data through.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to put the data for.
 *   payload: Moved :c:type:`z_owned_bytes_t` containing the data to put.
 *   options: Pointer to a :c:type:`z_put_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_put(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr, z_moved_bytes_t *payload,
                 const z_put_options_t *options);

/**
 * Deletes data for a given keyexpr.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to delete the data through.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to delete the data for.
 *   options: Pointer to a :c:type:`z_delete_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if delete operation is successful, ``negative value`` otherwise.
 */
z_result_t z_delete(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr, const z_delete_options_t *options);

/**
 * Builds a :c:type:`z_publisher_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_delete_options_t`.
 */
void z_publisher_options_default(z_publisher_options_t *options);

/**
 * Declares a publisher for a given keyexpr.
 *
 * Data can be put and deleted with this publisher with the help of the
 * :c:func:`z_publisher_put` and :c:func:`z_publisher_delete` functions.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the publisher through.
 *   pub: Pointer to an uninitialized :c:type:`z_owned_publisher_t`.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the publisher with.
 *   options: Pointer to a :c:type:`z_publisher_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 */
z_result_t z_declare_publisher(const z_loaned_session_t *zs, z_owned_publisher_t *pub,
                               const z_loaned_keyexpr_t *keyexpr, const z_publisher_options_t *options);

/**
 * Undeclares the publisher.
 *
 * Parameters:
 *   pub: Moved :c:type:`z_owned_publisher_t` to undeclare.
 *
 * Return:
 *   ``0`` if undeclare is successful, ``negative value`` otherwise.
 */
z_result_t z_undeclare_publisher(z_moved_publisher_t *pub);

/**
 * Builds a :c:type:`z_publisher_put_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_publisher_put_options_t`.
 */
void z_publisher_put_options_default(z_publisher_put_options_t *options);

/**
 * Builds a :c:type:`z_publisher_delete_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_publisher_delete_options_t`.
 */
void z_publisher_delete_options_default(z_publisher_delete_options_t *options);

/**
 * Puts data for the keyexpr bound to the given publisher.
 *
 * Parameters:
 *   pub: Pointer to a :c:type:`z_loaned_publisher_t` from where to put the data.
 *   payload: Moved :c:type:`z_owned_bytes_t` containing the data to put.
 *   options: Pointer to a :c:type:`z_publisher_put_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_publisher_put(const z_loaned_publisher_t *pub, z_moved_bytes_t *payload,
                           const z_publisher_put_options_t *options);

#if Z_FEATURE_ADVANCED_PUBLICATION == 1
z_result_t _z_publisher_put_impl(const z_loaned_publisher_t *pub, z_moved_bytes_t *payload,
                                 const z_publisher_put_options_t *options, _ze_advanced_cache_t *cache);
#else
z_result_t _z_publisher_put_impl(const z_loaned_publisher_t *pub, z_moved_bytes_t *payload,
                                 const z_publisher_put_options_t *options);
#endif

/**
 * Deletes data from the keyexpr bound to the given publisher.
 *
 * Parameters:
 *   pub: Pointer to a :c:type:`z_loaned_publisher_t` from where to delete the data.
 *   options: Pointer to a :c:type:`z_publisher_delete_options_t` to configure the delete operation.
 *
 * Return:
 *   ``0`` if delete operation is successful, ``negative value`` otherwise.
 */
z_result_t z_publisher_delete(const z_loaned_publisher_t *pub, const z_publisher_delete_options_t *options);

#if Z_FEATURE_ADVANCED_PUBLICATION == 1
z_result_t _z_publisher_delete_impl(const z_loaned_publisher_t *pub, const z_publisher_delete_options_t *options,
                                    _ze_advanced_cache_t *cache);
#else
z_result_t _z_publisher_delete_impl(const z_loaned_publisher_t *pub, const z_publisher_delete_options_t *options);
#endif

/**
 * Gets the keyexpr from a publisher.
 *
 * Parameters:
 *   publisher: Pointer to a :c:type:`z_loaned_publisher_t` to get the keyexpr from.
 *
 * Return:
 *   The keyexpr wrapped as a :c:type:`z_loaned_keyexpr_t`.
 */
const z_loaned_keyexpr_t *z_publisher_keyexpr(const z_loaned_publisher_t *publisher);

#if defined(Z_FEATURE_UNSTABLE_API)
/**
 * Gets the entity global Id from a publisher.
 *
 * Parameters:
 *   publisher: Pointer to a :c:type:`z_loaned_publisher_t` to get the entity global Id from.
 *
 * Return:
 *   The entity gloabl Id wrapped as a :c:type:`z_entity_global_id_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_entity_global_id_t z_publisher_id(const z_loaned_publisher_t *publisher);
#endif

#if Z_FEATURE_MATCHING == 1
/**
 * Declares a matching listener, registering a callback for notifying subscribers matching with a given publisher.
 * The callback will be run in the background until the corresponding publisher is dropped.
 *
 * Parameters:
 *   publisher: A publisher to associate with matching listener.
 *   callback: A closure that will be called every time the matching status of the publisher changes (If last subscriber
 * disconnects or when the first subscriber connects).
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 */
z_result_t z_publisher_declare_background_matching_listener(const z_loaned_publisher_t *publisher,
                                                            z_moved_closure_matching_status_t *callback);
/**
 * Constructs matching listener, registering a callback for notifying subscribers matching with a given publisher.
 *
 * Parameters:
 *   publisher: A publisher to associate with matching listener.
 *   matching_listener: An uninitialized memory location where matching listener will be constructed. The matching
 * listener's callback will be automatically dropped when the publisher is dropped. callback: A closure that will be
 * called every time the matching status of the publisher changes (If last subscriber disconnects or when the first
 * subscriber connects).
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 */
z_result_t z_publisher_declare_matching_listener(const z_loaned_publisher_t *publisher,
                                                 z_owned_matching_listener_t *matching_listener,
                                                 z_moved_closure_matching_status_t *callback);
/**
 * Gets publisher matching status - i.e. if there are any subscribers matching its key expression.
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 */
z_result_t z_publisher_get_matching_status(const z_loaned_publisher_t *publisher, z_matching_status_t *matching_status);

/**
 * Undeclares the matching listener.
 *
 * Parameters:
 *   listener: Moved :c:type:`z_owned_matching_listener_t` to undeclare.
 *
 * Return:
 *   ``0`` if undeclare is successful, ``negative value`` otherwise.
 */
z_result_t z_undeclare_matching_listener(z_moved_matching_listener_t *listener);

#endif  // Z_FEATURE_MATCHING == 1

#endif  // Z_FEATURE_PUBLICATION == 1

#if Z_FEATURE_QUERY == 1
/**
 * Builds a :c:type:`z_get_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_get_options_t`.
 */
void z_get_options_default(z_get_options_t *options);

/**
 * Sends a distributed query for a given keyexpr.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to send the query through.
 *   keyexpr: Pointer to a  :c:type:`z_loaned_keyexpr_t` to send the query for.
 *   parameters: Pointer to the parameters as a null-terminated string.
 *   callback: Moved :c:type:`z_owned_closure_reply_t` callback.
 *   options: Pointer to a :c:type:`z_get_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_get(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr, const char *parameters,
                 z_moved_closure_reply_t *callback, z_get_options_t *options);

/**
 * Sends a distributed query for a given keyexpr.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to send the query through.
 *   keyexpr: Pointer to a  :c:type:`z_loaned_keyexpr_t` to send the query for.
 *   parameters: Pointer to the parameters string.
 *   parameters_len: Length of the parameters string.
 *   callback: Moved :c:type:`z_owned_closure_reply_t` callback.
 *   options: Pointer to a :c:type:`z_get_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_get_with_parameters_substr(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                        const char *parameters, size_t parameters_len,
                                        z_moved_closure_reply_t *callback, z_get_options_t *options);

/**
 *  Constructs the default value for :c:type:`z_querier_get_options_t`.
 */
void z_querier_get_options_default(z_querier_get_options_t *options);

/**
 *  Constructs the default value for :c:type:`z_querier_options_t`.
 */
void z_querier_options_default(z_querier_options_t *options);

/**
 * Constructs and declares a querier on the given key expression.
 *
 * The queries can be send with the help of the `z_querier_get()` function.
 *
 * Parameters:
 *   zs: The Zenoh session.
 *   querier: An uninitialized location in memory where querier will be constructed.
 *   keyexpr: The key expression to send queries on.
 *   options: Additional options for the querier.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */

z_result_t z_declare_querier(const z_loaned_session_t *zs, z_owned_querier_t *querier,
                             const z_loaned_keyexpr_t *keyexpr, z_querier_options_t *options);

/**
 * Frees memory and resets querier to its gravestone state.
 */
z_result_t z_undeclare_querier(z_moved_querier_t *querier);

/**
 * Query data from the matching queryables in the system.
 *
 * Replies are provided through a callback function.
 *
 * Parameters:
 *   querier: The querier to make query from.
 *   parameters: The query's parameters null-terminated string, similar to a url's query segment.
 *   callback: The callback function that will be called on reception of replies for this query. It will be
 * 				automatically dropped once all replies are processed.
 *   options: Additional options for the get. All owned fields will be consumed.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_querier_get(const z_loaned_querier_t *querier, const char *parameters, z_moved_closure_reply_t *callback,
                         z_querier_get_options_t *options);

/**
 * Query data from the matching queryables in the system.
 *
 * Replies are provided through a callback function.
 *
 * Parameters:
 *   querier: The querier to make query from.
 *   parameters: The query's parameters string, similar to a url's query segment.
 *   parameters_len: Length of the parameters string
 *   callback: The callback function that will be called on reception of replies for this query. It will be
 * 				automatically dropped once all replies are processed.
 *   options: Additional options for the get. All owned fields will be consumed.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_querier_get_with_parameters_substr(const z_loaned_querier_t *querier, const char *parameters,
                                                size_t parameters_len, z_moved_closure_reply_t *callback,
                                                z_querier_get_options_t *options);

/**
 *  Returns the key expression of the querier.
 */
const z_loaned_keyexpr_t *z_querier_keyexpr(const z_loaned_querier_t *querier);

#if defined(Z_FEATURE_UNSTABLE_API)
/**
 * Gets the entity global Id from a querier.
 *
 * Parameters:
 *   publisher: Pointer to a :c:type:`z_loaned_querier_t` to get the entity global Id from.
 *
 * Return:
 *   The entity gloabl Id wrapped as a :c:type:`z_entity_global_global_id_t`.
 */
z_entity_global_id_t z_querier_id(const z_loaned_querier_t *querier);
#endif

#if Z_FEATURE_MATCHING == 1
/**
 * Declares a matching listener, registering a callback for notifying queryables matching the given querier key
 * expression and target. The callback will be run in the background until the corresponding querier is dropped.
 *
 * Parameters:
 *   querier: A querier to associate with matching listener.
 *   callback: A closure that will be called every time the matching status of the querier changes (If last
 *             queryable disconnects or when the first queryable connects).
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_querier_declare_background_matching_listener(const z_loaned_querier_t *querier,
                                                          z_moved_closure_matching_status_t *callback);
/**
 * Constructs matching listener, registering a callback for notifying queryables matching with a given querier's
 * key expression and target.
 *
 * Parameters:
 *   querier: A querier to associate with matching listener.
 *   matching_listener: An uninitialized memory location where matching listener will be constructed. The matching
 *                      listener's callback will be automatically dropped when the querier is dropped.
 *   callback: A closure that will be called every time the matching status of the querier changes (If last
 *             queryable disconnects or when the first queryable connects).
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_querier_declare_matching_listener(const z_loaned_querier_t *querier,
                                               z_owned_matching_listener_t *matching_listener,
                                               z_moved_closure_matching_status_t *callback);
/**
 * Gets querier matching status - i.e. if there are any queryables matching its key expression and target.
 *
 * Return:
 *   ``0`` if put operation is successful, ``negative value`` otherwise.
 */
z_result_t z_querier_get_matching_status(const z_loaned_querier_t *querier, z_matching_status_t *matching_status);

#endif  // Z_FEATURE_MATCHING == 1

/**
 * Checks if queryable answered with an OK, which allows this value to be treated as a sample.
 *
 * Parameters:
 *   reply: Pointer to a :c:type:`z_loaned_reply_t` to check.
 *
 * Return:
 *   ``true`` if queryable answered with an OK, ``false`` otherwise.
 */
bool z_reply_is_ok(const z_loaned_reply_t *reply);

/**
 * Gets the content of an OK reply.
 *
 * You should always make sure that :c:func:`z_reply_is_ok` returns ``true`` before calling this function.
 *
 * Parameters:
 *   reply: Pointer to a :c:type:`z_loaned_reply_t` to get content from.
 *
 * Return:
 *   The OK reply content wrapped as a :c:type:`z_loaned_sample_t`.
 */
const z_loaned_sample_t *z_reply_ok(const z_loaned_reply_t *reply);

/**
 * Gets the contents of an error reply.
 *
 * You should always make sure that :c:func:`z_reply_is_ok` returns ``false`` before calling this function.
 *
 * Parameters:
 *   reply: Pointer to a :c:type:`z_loaned_reply_t` to get content from.
 *
 * Return:
 *   The error reply content wrapped as a :c:type:`z_loaned_reply_err_t`.
 */
const z_loaned_reply_err_t *z_reply_err(const z_loaned_reply_t *reply);

#ifdef Z_FEATURE_UNSTABLE_API
/**
 * Gets the id of the zenoh instance that answered this Reply.
 *
 * Parameters:
 *   reply: Pointer to a :c:type:`z_loaned_reply_t` to get content from.
 *
 * Return:
 * 	 `true` if id is present
 */
bool z_reply_replier_id(const z_loaned_reply_t *reply, z_entity_global_id_t *out_id);
#endif  // Z_FEATURE_UNSTABLE_API

#endif  // Z_FEATURE_QUERY == 1

#if Z_FEATURE_QUERYABLE == 1
/**
 * Builds a :c:type:`z_queryable_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_queryable_options_t`.
 */
void z_queryable_options_default(z_queryable_options_t *options);

/**
 * Declares a queryable for a given keyexpr.
 * Note that dropping queryable drops its callback.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the subscriber through.
 *   queryable: Pointer to an uninitialized :c:type:`z_owned_queryable_t` to contain the queryable.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the subscriber with.
 *   callback: Pointer to a :c:type:`z_owned_closure_query_t` callback.
 *   options: Pointer to a :c:type:`z_queryable_options_t` to configure the declare.
 *
 * Return:
 *   ``0`` if declare operation is successful, ``negative value`` otherwise.
 */
z_result_t z_declare_queryable(const z_loaned_session_t *zs, z_owned_queryable_t *queryable,
                               const z_loaned_keyexpr_t *keyexpr, z_moved_closure_query_t *callback,
                               const z_queryable_options_t *options);

/**
 * Undeclares the queryable.
 *
 * Parameters:
 *   pub: Moved :c:type:`z_owned_queryable_t` to undeclare.
 *
 * Return:
 *   ``0`` if undeclare is successful, ``negative value`` otherwise.
 */
z_result_t z_undeclare_queryable(z_moved_queryable_t *pub);

/**
 * Declares a background queryable for a given keyexpr. The queryable callback will be called
 * to proccess incoming queries until the corresponding session is closed or dropped.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the subscriber through.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the subscriber with.
 *   callback: Pointer to a :c:type:`z_owned_closure_query_t` callback.
 *   options: Pointer to a :c:type:`z_queryable_options_t` to configure the declare.
 *
 * Return:
 *   ``0`` if declare operation is successful, ``negative value`` otherwise.
 */
z_result_t z_declare_background_queryable(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                          z_moved_closure_query_t *callback, const z_queryable_options_t *options);

/**
 * Builds a :c:type:`z_query_reply_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_query_reply_options_t`.
 */
void z_query_reply_options_default(z_query_reply_options_t *options);

/**
 * Sends a reply to a query.
 *
 * This function must be called inside of a :c:type:`z_owned_closure_query_t` callback associated to the
 * :c:type:`z_owned_queryable_t`, passing the received query as parameters of the callback function. This function can
 * be called multiple times to send multiple replies to a query. The reply will be considered complete when the callback
 * returns.
 *
 * Parameters:
 *   query: Pointer to a :c:type:`z_loaned_query_t` to reply.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the reply with.
 *   payload: Pointer to the reply data.
 *   options: Pointer to a :c:type:`z_query_reply_options_t` to configure the reply.
 *
 * Return:
 *   ``0`` if reply operation is successful, ``negative value`` otherwise.
 */
z_result_t z_query_reply(const z_loaned_query_t *query, const z_loaned_keyexpr_t *keyexpr, z_moved_bytes_t *payload,
                         const z_query_reply_options_t *options);

z_result_t _z_query_reply_sample(const z_loaned_query_t *query, z_loaned_sample_t *sample,
                                 const z_query_reply_options_t *options);

z_result_t z_query_take_from_loaned(z_owned_query_t *dst, z_loaned_query_t *src);

/**
 * Builds a :c:type:`z_query_reply_del_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_query_reply_del_options_t`.
 */
void z_query_reply_del_options_default(z_query_reply_del_options_t *options);

/**
 * Sends a reply delete to a query.
 *
 * This function must be called inside of a :c:type:`z_owned_closure_query_t` callback associated to the
 * :c:type:`z_owned_queryable_t`, passing the received query as parameters of the callback function. This function can
 * be called multiple times to send multiple replies to a query. The reply will be considered complete when the callback
 * returns.
 *
 * Parameters:
 *   query: Pointer to a :c:type:`z_loaned_query_t` to reply.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the reply with.
 *   options: Pointer to a :c:type:`z_query_reply_del_options_t` to configure the reply.
 *
 * Return:
 *   ``0`` if reply operation is successful, ``negative value`` otherwise.
 */
z_result_t z_query_reply_del(const z_loaned_query_t *query, const z_loaned_keyexpr_t *keyexpr,
                             const z_query_reply_del_options_t *options);

/**
 * Builds a :c:type:`z_query_reply_err_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_query_reply_err_options_t`.
 */
void z_query_reply_err_options_default(z_query_reply_err_options_t *options);

/**
 * Sends a reply error to a query.
 *
 * This function must be called inside of a :c:type:`z_owned_closure_query_t` callback associated to the
 * :c:type:`z_owned_queryable_t`, passing the received query as parameters of the callback function. This function can
 * be called multiple times to send multiple replies to a query. The reply will be considered complete when the callback
 * returns.
 *
 * Parameters:
 *   query: Pointer to a :c:type:`z_loaned_query_t` to reply.
 *   payload: Moved reply error data payload.
 *   options: Pointer to a :c:type:`z_query_reply_err_options_t` to configure the reply error.
 *
 * Return:
 *   ``0`` if reply operation is successful, ``negative value`` otherwise.
 */
z_result_t z_query_reply_err(const z_loaned_query_t *query, z_moved_bytes_t *payload,
                             const z_query_reply_err_options_t *options);

#if defined(Z_FEATURE_UNSTABLE_API)
/**
 * Gets the entity global Id from a queryable.
 *
 * Parameters:
 *   publisher: Pointer to a :c:type:`z_loaned_queryable_t` to get the entity global Id from.
 *
 * Return:
 *   The entity gloabl Id wrapped as a :c:type:`z_loaned_queryable_t`.
 */
z_entity_global_id_t z_queryable_id(const z_loaned_queryable_t *queryable);
#endif

/**
 * Gets the keyexpr from a queryable.
 *
 * Parameters:
 *   queryable: Pointer to a :c:type:`z_loaned_queryable_t` to get the keyexpr from.
 *
 * Return:
 *   The keyexpr wrapped as a :c:type:`z_loaned_keyexpr_t`. Will return NULL if
 *   corresponding session is closed or dropped.
 *   The lifetime of key expression pointer is bound to those of queryable and its session.
 */
const z_loaned_keyexpr_t *z_queryable_keyexpr(const z_loaned_queryable_t *queryable);

#endif

/**
 * Builds a new keyexpr.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_owned_keyexpr_t` to store the keyexpr.
 *   name: Pointer to the null-terminated string of the keyexpr.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_keyexpr_from_str(z_owned_keyexpr_t *keyexpr, const char *name);

/**
 * Builds a new keyexpr from a substring.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_owned_keyexpr_t` to store the keyexpr.
 *   name: Pointer to the start of the substring for keyxpr.
 *   len: Length of the substring to consider.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_keyexpr_from_substr(z_owned_keyexpr_t *keyexpr, const char *name, size_t len);

/**
 * Builds a :c:type:`z_owned_keyexpr_t` from a null-terminated string with auto canonization.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_owned_keyexpr_t`.
 *   name: Pointer to string representation of the keyexpr as a null terminated string.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_keyexpr_from_str_autocanonize(z_owned_keyexpr_t *keyexpr, const char *name);

/**
 * Builds a :c:type:`z_owned_keyexpr_t` from a substring with auto canonization.
 *
 * Parameters:
 *   keyexpr: Pointer to an uninitialized :c:type:`z_owned_keyexpr_t` to store the keyexpr.
 *   name: Pointer to the start of the substring for keyexpr.
 *   len: Length of the substring to consider. After the function return it will be equal to the canonized key
 *     expression string length.
 *
 * Return:
 *   ``0`` if creation is successful, ``negative value`` otherwise.
 */
z_result_t z_keyexpr_from_substr_autocanonize(z_owned_keyexpr_t *keyexpr, const char *name, size_t *len);

/**
 * Declares a keyexpr, so that it is mapped on a numerical id.
 *
 * This numerical id is used on the network to save bandwidth and ease the retrieval of the concerned resource
 * in the routing tables.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the keyexpr through.
 *   declared_keyexpr: Pointer to an uninitialized :c:type:`z_owned_keyexpr_t` to contain the declared keyexpr.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the keyexpr with.
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 */
z_result_t z_declare_keyexpr(const z_loaned_session_t *zs, z_owned_keyexpr_t *declared_keyexpr,
                             const z_loaned_keyexpr_t *keyexpr);

/**
 * Undeclares a keyexpr.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to undeclare the data through.
 *   keyexpr: Moved :c:type:`z_owned_keyexpr_t` to undeclare.
 *
 * Return:
 *   ``0`` if undeclare is successful, ``negative value`` otherwise.
 */
z_result_t z_undeclare_keyexpr(const z_loaned_session_t *zs, z_moved_keyexpr_t *keyexpr);

/**
 * Constructs a new empty string array.
 *
 * Parameters:
 *   a: Pointer to an uninitialized :c:type:`z_owned_string_array_t` to store the array of strings.
 */
void z_string_array_new(z_owned_string_array_t *a);

/**
 * Appends specified value to the end of the string array by alias.
 *
 * Parameters:
 *   a: Pointer to :c:type:`z_loaned_string_array_t`.
 *   value: Pointer to the string to be added.
 *
 * Return:
 *   The new length of the array.
 */
size_t z_string_array_push_by_alias(z_loaned_string_array_t *a, const z_loaned_string_t *value);

/**
 * Appends specified value to the end of the string array by copying.
 *
 * Parameters:
 *   a: Pointer to :c:type:`z_loaned_string_array_t`.
 *   value: Pointer to the string to be added.
 *
 * Return:
 *   The new length of the array.
 */
size_t z_string_array_push_by_copy(z_loaned_string_array_t *a, const z_loaned_string_t *value);

/**
 * Returns the value at the position of index in the string array.
 *
 * Parameters:
 *   a: Pointer to :c:type:`z_loaned_string_array_t`.
 *   k: index value.
 *
 * Return:
 *   `NULL` if the index is out of bounds.
 */
const z_loaned_string_t *z_string_array_get(const z_loaned_string_array_t *a, size_t k);

/**
 * Returns the number of elements in the array.
 */
size_t z_string_array_len(const z_loaned_string_array_t *a);

/**
 * Returns ``true`` if the array is empty, ``false`` otherwise.
 */
bool z_string_array_is_empty(const z_loaned_string_array_t *a);

#if Z_FEATURE_SUBSCRIPTION == 1
/**
 * Builds a :c:type:`z_subscriber_options_t` with default values.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`z_subscriber_options_t`.
 */
void z_subscriber_options_default(z_subscriber_options_t *options);

/**
 * Declares a subscriber for a given keyexpr.
 * Note that dropping subscriber drops its callback.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the subscriber through.
 *   sub: Pointer to a :c:type:`z_owned_subscriber_t` to contain the subscriber.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the subscriber with.
 *   callback: Pointer to a`z_owned_closure_sample_t` callback.
 *   options: Pointer to a :c:type:`z_subscriber_options_t` to configure the operation
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 */
z_result_t z_declare_subscriber(const z_loaned_session_t *zs, z_owned_subscriber_t *sub,
                                const z_loaned_keyexpr_t *keyexpr, z_moved_closure_sample_t *callback,
                                const z_subscriber_options_t *options);

/**
 * Undeclares the subscriber.
 *
 * Parameters:
 *   pub: Moved :c:type:`z_owned_subscriber_t` to undeclare.
 *
 * Return:
 *   ``0`` if undeclare is successful, ``negative value`` otherwise.
 */
z_result_t z_undeclare_subscriber(z_moved_subscriber_t *pub);

/**
 * Declares a background subscriber for a given keyexpr. Subscriber callback will be called to process the messages,
 * until the corresponding session is closed or dropped.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to declare the subscriber through.
 *   keyexpr: Pointer to a :c:type:`z_loaned_keyexpr_t` to bind the subscriber with.
 *   callback: Pointer to a`z_owned_closure_sample_t` callback.
 *   options: Pointer to a :c:type:`z_subscriber_options_t` to configure the operation
 *
 * Return:
 *   ``0`` if declare is successful, ``negative value`` otherwise.
 */
z_result_t z_declare_background_subscriber(const z_loaned_session_t *zs, const z_loaned_keyexpr_t *keyexpr,
                                           z_moved_closure_sample_t *callback, const z_subscriber_options_t *options);

/**
 * Gets the keyexpr from a subscriber.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`z_loaned_subscriber_t` to get the keyexpr from.
 *
 * Return:
 *   The keyexpr wrapped as a :c:type:`z_loaned_keyexpr_t`. Will return `NULL` if corresponding session
 *   is closed or dropped.
 *   The lifetime of key expression pointer is bound to those of subscriber and its session.
 */
const z_loaned_keyexpr_t *z_subscriber_keyexpr(const z_loaned_subscriber_t *subscriber);

#if defined(Z_FEATURE_UNSTABLE_API)
/**
 * Gets the entity global Id from a subscriber.
 *
 * Parameters:
 *   subscriber: Pointer to a :c:type:`z_loaned_subscriber_t` to get the entity global Id from.
 *
 * Return:
 *   The entity gloabl Id wrapped as a :c:type:`z_entity_global_global_id_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_entity_global_id_t z_subscriber_id(const z_loaned_subscriber_t *subscriber);
#endif
#endif

#if Z_FEATURE_BATCHING == 1

/**
 * Activate the batching mechanism, any message that would have been sent on the network by a subsequent api call (e.g
 * z_put, z_get) will be instead stored until either: the batch is full, flushed with :c:func:`zp_batch_flush`, batching
 * is stopped with :c:func:`zp_batch_stop`, a message needs to be sent immediately.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` that will start batching messages.
 *
 * Return:
 *   ``0`` if batching started, ``negative value`` otherwise.
 */
z_result_t zp_batch_start(const z_loaned_session_t *zs);

/**
 * Send the currently batched messages on the network.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` that will send its batched messages.
 *
 * Return:
 *   ``0`` if batch successfully sent, ``negative value`` otherwise.
 */
z_result_t zp_batch_flush(const z_loaned_session_t *zs);

/**
 * Deactivate the batching mechanism and send the currently batched on the network.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` that will stop batching messages.
 *
 * Return:
 *   ``0`` if batching stopped and batch successfully sent, ``negative value`` otherwise.
 */
z_result_t zp_batch_stop(const z_loaned_session_t *zs);
#endif
#if Z_FEATURE_MULTI_THREAD == 1 || defined(SPHINX_DOCS)
/************* Multi Thread Tasks helpers **************/
/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`zp_task_read_options_t`.
 */
void zp_task_read_options_default(zp_task_read_options_t *options);

/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to start the task from.
 *   options: Pointer to a :c:type:`zp_task_read_options_t` to configure the task.
 *
 * Return:
 *   ``0`` if task started successfully, ``negative value`` otherwise.
 */
z_result_t zp_start_read_task(z_loaned_session_t *zs, const zp_task_read_options_t *options);

/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to stop the task from.
 *
 * Return:
 *   ``0`` if task stopped successfully, ``negative value`` otherwise.
 */
z_result_t zp_stop_read_task(z_loaned_session_t *zs);

/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 */
bool zp_read_task_is_running(const z_loaned_session_t *zs);

/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`zp_task_lease_options_t`.
 */
void zp_task_lease_options_default(zp_task_lease_options_t *options);

/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to start the task from.
 *   options: Pointer to a :c:type:`zp_task_lease_options_t` to configure the task.
 *
 * Return:
 *   ``0`` if task started successfully, ``negative value`` otherwise.
 */
z_result_t zp_start_lease_task(z_loaned_session_t *zs, const zp_task_lease_options_t *options);

/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to stop the task from.
 *
 * Return:
 *   ``0`` if task stopped successfully, ``negative value`` otherwise.
 */
z_result_t zp_stop_lease_task(z_loaned_session_t *zs);

/**
 * Deprecated, if Z_FEATURE_MULTI_THREAD is enabled background tasks are now started automatically when session is
 * created.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is enabled.
 */
bool zp_lease_task_is_running(const z_loaned_session_t *zs);
#endif
#if Z_FEATURE_MULTI_THREAD == 0 || defined(SPHINX_DOCS)
/************* Single Thread helpers **************/
/**
 * Deprecated, please use :c:func:`zp_spin_once` instead, which will run a single pending zenoh task
 * (including read, lease, keep alive, accept, connect, etc...) from the task queue.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`zp_read_options_t`.
 */
void zp_read_options_default(zp_read_options_t *options);

/**
 * Deprecated, please use :c:func:`zp_spin_once` instead, which will run a single pending zenoh task
 * (including read, lease, keep alive, accept, connect, etc...) from the task queue.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to execute the read for.
 *   options: Pointer to a :c:type:`zp_read_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 */
z_result_t zp_read(const z_loaned_session_t *zs, const zp_read_options_t *options);

/**
 * Deprecated, please use :c:func:`zp_spin_once` instead, which will run a single pending zenoh task
 * (including read, lease, keep alive, accept, connect, etc...) from the task queue.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`zp_send_keep_alive_options_t`.
 */
void zp_send_keep_alive_options_default(zp_send_keep_alive_options_t *options);

/**
 * Deprecated, please use :c:func:`zp_spin_once` instead, which will run a single pending zenoh task
 * (including read, lease, keep alive, accept, connect, etc...) from the task queue.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to execute the send for.
 *   options: Pointer to a :c:type:`zp_send_keep_alive_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 */
z_result_t zp_send_keep_alive(const z_loaned_session_t *zs, const zp_send_keep_alive_options_t *options);

/**
 * Deprecated, please use :c:func:`zp_spin_once` instead, which will run a single pending zenoh task
 * (including read, lease, keep alive, accept, connect, etc...) from the task queue.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 *
 * Parameters:
 *   options: Pointer to an uninitialized :c:type:`zp_send_join_options_t`.
 */
void zp_send_join_options_default(zp_send_join_options_t *options);

/**
 * Deprecated, please use :c:func:`zp_spin_once` instead, which will run a single pending zenoh task
 * (including read, lease, keep alive, accept, connect, etc...) from the task queue.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to execute the send for.
 *   options: Pointer to a :c:type:`zp_send_keep_alive_options_t` to configure the operation.
 *
 * Return:
 *   ``0`` if execution was successful, ``negative value`` otherwise.
 */
z_result_t zp_send_join(const z_loaned_session_t *zs, const zp_send_join_options_t *options);

/**
 * Spins zenoh executor once, executing a single pending task (such as read, lease, keep alive, accept, connect, etc...)
 * from the task queue.
 *
 * Note: only if Z_FEATURE_MULTI_THREAD is disabled.
 *
 * Parameters:
 *   zs: Pointer to a :c:type:`z_loaned_session_t` to spin executor for.
 */
void zp_spin_once(const z_loaned_session_t *zs);
#endif

#ifdef Z_FEATURE_UNSTABLE_API
/**
 * Gets the default reliability value (unstable).
 *
 * Return:
 *   The reliability wrapped as a :c:type:`z_reliability_t`.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_reliability_t z_reliability_default(void);
#endif

#ifdef Z_FEATURE_UNSTABLE_API
#if Z_FEATURE_QUERY == 1
/**
 * Construct a new cancellation token. Can be used to interrupt get operations.  (unstable).
 *
 * Parameters:
 *   cancellation_token: Pointer to an uninitialized :c:type:`z_owned_cancellation_token_t`.
 *
 * Return:
 *   ``0`` if creation successful, ``negative value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t z_cancellation_token_new(z_owned_cancellation_token_t *cancellation_token);

/**
 * Interrupt all currently running get calls, to which clones of the token were passed.  (unstable).
 *
 * Parameters:
 *   cancellation_token: Pointer to token to cancel.
 *
 * Return:
 *   ``0`` in case of success (in this case all pending operations are guaranteed to be cancelled or terminated),
 * ``negative error value`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
z_result_t z_cancellation_token_cancel(z_loaned_cancellation_token_t *cancellation_token);

/**
 * Verify if token was cancelled  (unstable).
 *
 * Parameters:
 *   cancellation_token: Pointer to cancellation token.
 *
 * Return:
 *   ``true`` if token was cancelled (i.e if :c:func:`z_cancellation_token_cancel` was called on it or one of its
 * clones), ``false`` otherwise.
 *
 * .. warning:: This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 */
bool z_cancellation_token_is_cancelled(const z_loaned_cancellation_token_t *cancellation_token);
#endif
#endif

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_API_PRIMITIVES_H */
