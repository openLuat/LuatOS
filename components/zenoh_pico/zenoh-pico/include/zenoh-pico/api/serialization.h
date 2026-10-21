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

#ifndef INCLUDE_ZENOH_PICO_API_SERIALIZATION_H
#define INCLUDE_ZENOH_PICO_API_SERIALIZATION_H

#include "olv_macros.h"
#include "zenoh-pico/api/primitives.h"
#include "zenoh-pico/utils/endianness.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Represents a reader for serialized data.
 */
typedef struct ze_deserializer_t {
    z_bytes_reader_t _reader;
} ze_deserializer_t;

typedef struct _ze_serializer_t {
    _z_bytes_writer_t _writer;
} _ze_serializer_t;

/**
 * Represents a writer for serialized data.
 */
_Z_OWNED_TYPE_VALUE_PREFIX(ze, _ze_serializer_t, serializer)

/**
 * Constructs an empty serializer.
 *
 * Parameters:
 *   serializer: An uninitialized memory location where serializer is to be constructed.
 *
 * Return:
 *   ``0`` in case of success, ``negative value`` otherwise.
 */
z_result_t ze_serializer_empty(ze_owned_serializer_t *serializer);

/**
 * Finishes serialization and returns underlying bytes.
 *
 * Parameters:
 *   serializer: A data serializer.
 *   bytes: An uninitialized memory location where bytes is to be constructed.
 */
void ze_serializer_finish(ze_moved_serializer_t *serializer, z_owned_bytes_t *bytes);

/**
 * Returns a deserializer for :c:type:`z_loaned_bytes_t`.
 *
 * The `bytes` should outlive the reader and should not be modified, while reader is in use.
 *
 * Parameters:
 *   bytes: Data to deserialize.
 *
 * Return:
 *   The constructed :c:type:`ze_deserializer_t`.
 */
ze_deserializer_t ze_deserializer_from_bytes(const z_loaned_bytes_t *bytes);

/**
 * Checks if deserializer parsed all of its data.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *
 * Return:
 *   ``True`` if there is no more data to parse, ``false`` otherwise.
 */
bool ze_deserializer_is_done(const ze_deserializer_t *deserializer);

/**
 * Writes a serialized `uint8_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `uint8_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_uint8(ze_loaned_serializer_t *serializer, uint8_t val) {
    return z_bytes_writer_write_all(&serializer->_writer, &val, 1);
}

/**
 * Writes a serialized `uint16_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `uint16_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_uint16(ze_loaned_serializer_t *serializer, uint16_t val) {
    _z_host_le_store16(val, (uint8_t *)&val);
    return z_bytes_writer_write_all(&serializer->_writer, (uint8_t *)&val, sizeof(val));
}

/**
 * Writes a serialized `uint32_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `uint32_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_uint32(ze_loaned_serializer_t *serializer, uint32_t val) {
    _z_host_le_store32(val, (uint8_t *)&val);
    return z_bytes_writer_write_all(&serializer->_writer, (uint8_t *)&val, sizeof(val));
}

/**
 * Writes a serialized `uint64_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `uint64_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_uint64(ze_loaned_serializer_t *serializer, uint64_t val) {
    _z_host_le_store64(val, (uint8_t *)&val);
    return z_bytes_writer_write_all(&serializer->_writer, (uint8_t *)&val, sizeof(val));
}

/**
 * Writes a serialized `float` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `float` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_float(ze_loaned_serializer_t *serializer, float val) {
    return z_bytes_writer_write_all(&serializer->_writer, (uint8_t *)&val, sizeof(val));
}

/**
 * Writes a serialized `double` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `double` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_double(ze_loaned_serializer_t *serializer, double val) {
    return z_bytes_writer_write_all(&serializer->_writer, (uint8_t *)&val, sizeof(val));
}

/**
 * Writes a serialized 'bool' into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `bool` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_bool(ze_loaned_serializer_t *serializer, bool val) {
    return ze_serializer_serialize_uint8(serializer, val ? 1 : 0);
}

/**
 * Writes a serialized `int8_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `int8_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_int8(ze_loaned_serializer_t *serializer, int8_t val) {
    return ze_serializer_serialize_uint8(serializer, (uint8_t)val);
}

/**
 * Writes a serialized `int16_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `int16_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_int16(ze_loaned_serializer_t *serializer, int16_t val) {
    return ze_serializer_serialize_uint16(serializer, (uint16_t)val);
}

/**
 * Writes a serialized `int32_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `int32_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_int32(ze_loaned_serializer_t *serializer, int32_t val) {
    return ze_serializer_serialize_uint32(serializer, (uint32_t)val);
}

/**
 * Writes a serialized `int64_t` into underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: `int64_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
static inline z_result_t ze_serializer_serialize_int64(ze_loaned_serializer_t *serializer, int64_t val) {
    return ze_serializer_serialize_uint64(serializer, (uint64_t)val);
}

/**
 * Deserializes next portion of data into a `uint8_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `uint8_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_uint8(ze_deserializer_t *deserializer, uint8_t *val) {
    if (z_bytes_reader_read(&deserializer->_reader, val, 1) != 1) {
        _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
    }
    return _Z_RES_OK;
}

/**
 * Deserializes next portion of data into a `uint16_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `uint16_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_uint16(ze_deserializer_t *deserializer, uint16_t *val) {
    if (z_bytes_reader_read(&deserializer->_reader, (uint8_t *)val, sizeof(uint16_t)) != sizeof(uint16_t)) {
        _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
    }
    *val = _z_host_le_load16((const uint8_t *)val);
    return _Z_RES_OK;
}

/**
 * Deserializes next portion of data into a `uint32_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `uint32_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_uint32(ze_deserializer_t *deserializer, uint32_t *val) {
    if (z_bytes_reader_read(&deserializer->_reader, (uint8_t *)val, sizeof(uint32_t)) != sizeof(uint32_t)) {
        _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
    }
    *val = _z_host_le_load32((uint8_t *)val);
    return _Z_RES_OK;
}

/**
 * Deserializes next portion of data into a `uint64_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `uint64_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_uint64(ze_deserializer_t *deserializer, uint64_t *val) {
    if (z_bytes_reader_read(&deserializer->_reader, (uint8_t *)val, sizeof(uint64_t)) != sizeof(uint64_t)) {
        _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
    }
    *val = _z_host_le_load64((uint8_t *)val);
    return _Z_RES_OK;
}

/**
 * Deserializes next portion of data into a `float`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `float` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_float(ze_deserializer_t *deserializer, float *val) {
    if (z_bytes_reader_read(&deserializer->_reader, (uint8_t *)val, sizeof(float)) != sizeof(float)) {
        _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
    }
    return _Z_RES_OK;
}

/**
 * Deserializes next portion of data into a `double`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `double` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_double(ze_deserializer_t *deserializer, double *val) {
    if (z_bytes_reader_read(&deserializer->_reader, (uint8_t *)val, sizeof(double)) != sizeof(double)) {
        _Z_ERROR_RETURN(_Z_ERR_DID_NOT_READ);
    }
    return _Z_RES_OK;
}

/**
 * Deserializes next portion of data into a `bool`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `bool` to contain the deserialized value.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_bool(ze_deserializer_t *deserializer, bool *val) {
    uint8_t res;
    _Z_RETURN_IF_ERR(ze_deserializer_deserialize_uint8(deserializer, &res));
    if (res > 1) {
        return Z_EDESERIALIZE;
    }
    *val = (res == 1);
    return _Z_RES_OK;
}

/**
 * Deserializes next portion of data into a `int8_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `int8_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_int8(ze_deserializer_t *deserializer, int8_t *val) {
    return ze_deserializer_deserialize_uint8(deserializer, (uint8_t *)val);
}

/**
 * Deserializes next portion of data into a `int16_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `int16_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_int16(ze_deserializer_t *deserializer, int16_t *val) {
    return ze_deserializer_deserialize_uint16(deserializer, (uint16_t *)val);
}

/**
 * Deserializes next portion of data into a `int32_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `int32_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_int32(ze_deserializer_t *deserializer, int32_t *val) {
    return ze_deserializer_deserialize_uint32(deserializer, (uint32_t *)val);
}

/**
 * Deserializes next portion of data into a `int64_t`.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   dst: Pointer to an uninitialized `int64_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
static inline z_result_t ze_deserializer_deserialize_int64(ze_deserializer_t *deserializer, int64_t *val) {
    return ze_deserializer_deserialize_uint64(deserializer, (uint64_t *)val);
}

/**
 * Serializes array of bytes and writes it into an underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: Pointer to the data to serialize.
 *   len: Number of bytes to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serializer_serialize_buf(ze_loaned_serializer_t *serializer, const uint8_t *val, size_t len);

/**
 * Serializes slice and writes it into an underlying :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: A slice to serialize.
 *   len: Number of bytes to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serializer_serialize_slice(ze_loaned_serializer_t *serializer, const z_loaned_slice_t *val);

/**
 * Deserializes next portion of data and advances the reader position.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   val: Pointer to an uninitialized :c:type:`z_owned_slice_t` to contain the deserialized slice.
 *
 * Return:
 *   ``0`` if deserialization is successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserializer_deserialize_slice(ze_deserializer_t *deserializer, z_owned_slice_t *val);

/**
 * Serializes a null-terminated string and writes it into an underlying :c:type:`z_owned_bytes_t`.
 * The string should be a valid UTF-8.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: Pointer to the string to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serializer_serialize_str(ze_loaned_serializer_t *serializer, const char *val);

/**
 * Serializes a substring and writes it into an underlying :c:type:`z_owned_bytes_t`.
 * The substring should be a valid UTF-8.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   start: Pointer to the start of the substring to serialize.
 *   len: Length of the substring to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serializer_serialize_substr(ze_loaned_serializer_t *serializer, const char *start, size_t len);

/**
 * Serializes a string and writes it into an underlying :c:type:`z_owned_bytes_t`.
 * The string should be a valid UTF-8.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   val: Pointer to the string to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serializer_serialize_string(ze_loaned_serializer_t *serializer, const z_loaned_string_t *val);

/**
 * Deserializes next portion of data and advances the reader position.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   val: Pointer to an uninitialized :c:type:`z_owned_string_t` to contain the deserialized string.
 *
 * Return:
 *   ``0`` if deserialization is successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserializer_deserialize_string(ze_deserializer_t *deserializer, z_owned_string_t *val);

/**
 * Initiate serialization of a sequence of multiple elements.
 *
 * Parameters:
 *   serializer: A serializer instance.
 *   len: Length of the sequence. Could be read during deserialization using
 *     :c:func:`ze_deserializer_deserialize_sequence_length`.
 *
 * Return:
 *   ``0`` if deserialization is successful, or a ``negative value`` otherwise.
 */
z_result_t ze_serializer_serialize_sequence_length(ze_loaned_serializer_t *serializer, size_t len);

/**
 * Initiate deserialization of a sequence of multiple elements.
 *
 * Parameters:
 *   deserializer: A deserializer instance.
 *   len: A pointer where the length of the sequence (previously passed via
 *     :c:func:`ze_serializer_serialize_sequence_length`) will be written.
 *
 * Return:
 *   ``0`` if deserialization is successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserializer_deserialize_sequence_length(ze_deserializer_t *deserializer, size_t *len);

/**
 * Serializes data into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized data.
 *   data: Pointer to the data to serialize.
 *   len: Number of bytes to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_buf(z_owned_bytes_t *bytes, const uint8_t *data, size_t len);

/**
 * Serializes a string into a :c:type:`z_owned_bytes_t`.
 *
 * The string should be a valid UTF-8.
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized string.
 *   s: Pointer to the string to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_string(z_owned_bytes_t *bytes, const z_loaned_string_t *s);

/**
 * Serializes a null-terminated string into a :c:type:`z_owned_bytes_t`.
 * The string should be a valid UTF-8.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized string.
 *   value: Pointer to the string to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_str(z_owned_bytes_t *bytes, const char *value);

/**
 * Serializes a substring into a :c:type:`z_owned_bytes_t`.
 * The substring should be a valid UTF-8.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized string.
 *   start: Pointer to the the start of string to serialize.
 *   len: Length of the substring to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_substr(z_owned_bytes_t *bytes, const char *start, size_t len);

/**
 * Serializes a slice into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized slice.
 *   slice: Pointer to the slice to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_slice(z_owned_bytes_t *bytes, const z_loaned_slice_t *slice);

/**
 * Serializes a `int8_t` into a :c:type:`z_owned_bytes_t` .
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `int8_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_int8(z_owned_bytes_t *bytes, int8_t val);

/**
 * Serializes a `int16_t` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `int16_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_int16(z_owned_bytes_t *bytes, int16_t val);

/**
 * Serializes a `int32_t` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `int32_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_int32(z_owned_bytes_t *bytes, int32_t val);

/**
 * Serializes a `int64_t` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `int64_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_int64(z_owned_bytes_t *bytes, int64_t val);

/**
 * Serializes a `uint8_t` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `uint8_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_uint8(z_owned_bytes_t *bytes, uint8_t val);

/**
 * Serializes a `uint16_t` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `uint16_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_uint16(z_owned_bytes_t *bytes, uint16_t val);

/**
 * Serializes a `uint32_t` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `uint32_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_uint32(z_owned_bytes_t *bytes, uint32_t val);

/**
 * Serializes a `uint64_t` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `uint64_t` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_uint64(z_owned_bytes_t *bytes, uint64_t val);

/**
 * Serializes a `float` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `float` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_float(z_owned_bytes_t *bytes, float val);

/**
 * Serializes a `double` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `double` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_double(z_owned_bytes_t *bytes, double val);

/**
 * Serializes a `bool` into a :c:type:`z_owned_bytes_t`.
 *
 * Parameters:
 *   bytes: An uninitialized :c:type:`z_owned_bytes_t` to contain the serialized int.
 *   val: `bool` value to serialize.
 *
 * Return:
 *   ``0`` if serialization is successful, ``negative value`` otherwise.
 */
z_result_t ze_serialize_bool(z_owned_bytes_t *bytes, bool val);

/**
 * Deserializes data into a :c:type:`z_owned_slice_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   str: Pointer to an uninitialized :c:type:`z_owned_slice_t` to contain the deserialized slice.
 *
 * Return:
 *   ``0`` if deserialization is successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_slice(const z_loaned_bytes_t *bytes, z_owned_slice_t *dst);

/**
 * Deserializes data into a :c:type:`z_owned_string_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   str: Pointer to an uninitialized :c:type:`z_owned_string_t` to contain the deserialized string.
 *
 * Return:
 *   ``0`` if deserialization is successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_string(const z_loaned_bytes_t *bytes, z_owned_string_t *str);

/**
 * Deserializes data into a `int8_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `int8_t` to contain the deserialized.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_int8(const z_loaned_bytes_t *bytes, int8_t *dst);

/**
 * Deserializes data into a `int16_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `int16_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_int16(const z_loaned_bytes_t *bytes, int16_t *dst);

/**
 * Deserializes data into a `int32_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `int32_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_int32(const z_loaned_bytes_t *bytes, int32_t *dst);

/**
 * Deserializes data into a `int64_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `int64_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_int64(const z_loaned_bytes_t *bytes, int64_t *dst);

/**
 * Deserializes data into a `uint8_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `uint8_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_uint8(const z_loaned_bytes_t *bytes, uint8_t *dst);

/**
 * Deserializes data into a `uint16_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `uint16_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_uint16(const z_loaned_bytes_t *bytes, uint16_t *dst);

/**
 * Deserializes data into a `uint32_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `uint32_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_uint32(const z_loaned_bytes_t *bytes, uint32_t *dst);

/**
 * Deserializes data into a `uint64_t`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `uint64_t` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_uint64(const z_loaned_bytes_t *bytes, uint64_t *dst);

/**
 * Deserializes data into a `float`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `float` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_float(const z_loaned_bytes_t *bytes, float *dst);

/**
 * Deserializes data into a `double`.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `double` to contain the deserialized number.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_double(const z_loaned_bytes_t *bytes, double *dst);

/**
 * Deserializes data into a boolean.
 *
 * Parameters:
 *   bytes: Pointer to a :c:type:`z_loaned_bytes_t` to deserialize.
 *   dst: Pointer to an uninitialized `bool` to contain the deserialized value.
 *
 * Return:
 *   ``0`` if deserialization successful, or a ``negative value`` otherwise.
 */
z_result_t ze_deserialize_bool(const z_loaned_bytes_t *bytes, bool *dst);

_Z_OWNED_FUNCTIONS_NO_COPY_DEF_PREFIX(ze, serializer)
#ifdef __cplusplus
}
#endif

#endif
