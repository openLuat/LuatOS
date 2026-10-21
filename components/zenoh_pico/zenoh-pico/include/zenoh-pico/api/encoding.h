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

#ifndef ZENOH_PICO_API_ENCODING_H
#define ZENOH_PICO_API_ENCODING_H

#include "zenoh-pico/api/types.h"

#ifdef __cplusplus
extern "C" {
#endif
/**
 * Default encoding values used by Zenoh.
 *
 * An encoding has a similar role to Content-type in HTTP: it indicates, when present, how data should be interpreted by
 * the application.
 *
 * Please note the Zenoh protocol does not impose any encoding value nor it operates on it.
 * It can be seen as some optional metadata that is carried over by Zenoh in such a way the application may perform
 * different operations depending on the encoding value.
 *
 * A set of associated constants are provided to cover the most common encodings for user convenience.
 * This is particularly useful in helping Zenoh to perform additional wire-level optimizations.
 *
 * Register your encoding metadata from a string with :c:func:`z_encoding_from_str`. To get the optimization, you need
 * Z_FEATURE_ENCODING_VALUES to 1 and your string should follow the format: "<constant>;<optional additional data>"
 *
 * E.g: "text/plain;utf8"
 *
 * Or you can set the value to the constants directly with this list of constants:
 */

#if Z_FEATURE_ENCODING_VALUES == 1
// - Below are Primitives types, supported in all Zenoh bindings
/**
 * Just some bytes.
 *
 * Constant alias for string: `"zenoh/bytes"`.
 *
 * This encoding supposes that the payload was created with c:func:`z_bytes_from_buf`, c:func:`z_bytes_from_slice` or
 * similar functions and its data can be accessed via c:func:`z_bytes_to_slice`.
 */
const z_loaned_encoding_t *z_encoding_zenoh_bytes(void);
extern const z_owned_encoding_t ZP_ENCODING_ZENOH_BYTES;

/**
 * A UTF-8 string.
 * Constant alias for string: `"zenoh/string"`.
 *
 * This encoding supposes that the payload was created with c:func:`z_bytes_from_str`, c:func:`z_bytes_from_string` or
 * similar functions and its data can be accessed via c:func:`z_bytes_to_string`.
 */
const z_loaned_encoding_t *z_encoding_zenoh_string(void);
extern const z_owned_encoding_t ZP_ENCODING_ZENOH_STRING;

/**
 * Zenoh serialized data.
 * Constant alias for string: `"zenoh/serialized"`.
 *
 * This encoding supposes that the payload was created with serialization functions.
 * The `schema` field may contain the details of serialziation format.
 */
const z_loaned_encoding_t *z_encoding_zenoh_serialized(void);
extern const z_owned_encoding_t ZP_ENCODING_ZENOH_SERIALIZED;

/**
 * An application-specific stream of bytes.
 * Constant alias for string: `"application/octet-stream"`.
 */
const z_loaned_encoding_t *z_encoding_application_octet_stream(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_OCTET_STREAM;

/**
 * A textual file.
 * Constant alias for string: `"text/plain"`.
 */
const z_loaned_encoding_t *z_encoding_text_plain(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_PLAIN;

/**
 * JSON data intended to be consumed by an application.
 * Constant alias for string: `"application/json"`.
 */
const z_loaned_encoding_t *z_encoding_application_json(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_JSON;

/**
 * JSON data intended to be human readable.
 * Constant alias for string: `"text/json"`.
 */
const z_loaned_encoding_t *z_encoding_text_json(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_JSON;

/**
 * A Common Data Representation (CDR)-encoded data.
 * Constant alias for string: `"application/cdr"`.
 */
const z_loaned_encoding_t *z_encoding_application_cdr(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_CDR;

/**
 * A Concise Binary Object Representation (CBOR)-encoded data.
 * Constant alias for string: `"application/cbor"`.
 */
const z_loaned_encoding_t *z_encoding_application_cbor(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_CBOR;

/**
 * YAML data intended to be consumed by an application.
 * Constant alias for string: `"application/yaml"`.
 */
const z_loaned_encoding_t *z_encoding_application_yaml(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_YAML;

/**
 * YAML data intended to be human readable.
 * Constant alias for string: `"text/yaml"`.
 */
const z_loaned_encoding_t *z_encoding_text_yaml(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_YAML;

/**
 * JSON5 encoded data that are human readable.
 * Constant alias for string: `"text/json5"`.
 */
const z_loaned_encoding_t *z_encoding_text_json5(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_JSON5;

/**
 * A Python object serialized using `pickle <https://docs.python.org/3/library/pickle.html>`_.
 * Constant alias for string: `"application/python-serialized-object"`.
 */
const z_loaned_encoding_t *z_encoding_application_python_serialized_object(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_PYTHON_SERIALIZED_OBJECT;

/**
 * An application-specific protobuf-encoded data.
 * Constant alias for string: `"application/protobuf"`.
 */
const z_loaned_encoding_t *z_encoding_application_protobuf(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_PROTOBUF;

/**
 * A Java serialized object.
 * Constant alias for string: `"application/java-serialized-object"`.
 */
const z_loaned_encoding_t *z_encoding_application_java_serialized_object(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_JAVA_SERIALIZED_OBJECT;

/**
 * An `openmetrics <https://github.com/OpenObservability/OpenMetrics>`_ data, commonly used by
 * `Prometheus <https://prometheus.io/>`_.
 * Constant alias for string: `"application/openmetrics-text"`.
 */
const z_loaned_encoding_t *z_encoding_application_openmetrics_text(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_OPENMETRICS_TEXT;

/**
 * A Portable Network Graphics (PNG) image.
 * Constant alias for string: `"image/png"`.
 */
const z_loaned_encoding_t *z_encoding_image_png(void);
extern const z_owned_encoding_t ZP_ENCODING_IMAGE_PNG;

/**
 * A Joint Photographic Experts Group (JPEG) image.
 * Constant alias for string: `"image/jpeg"`.
 */
const z_loaned_encoding_t *z_encoding_image_jpeg(void);
extern const z_owned_encoding_t ZP_ENCODING_IMAGE_JPEG;

/**
 * A Graphics Interchange Format (GIF) image.
 * Constant alias for string: `"image/gif"`.
 */
const z_loaned_encoding_t *z_encoding_image_gif(void);
extern const z_owned_encoding_t ZP_ENCODING_IMAGE_GIF;

/**
 * A BitMap (BMP) image.
 * Constant alias for string: `"image/bmp"`.
 */
const z_loaned_encoding_t *z_encoding_image_bmp(void);
extern const z_owned_encoding_t ZP_ENCODING_IMAGE_BMP;

/**
 * A Web Portable (WebP) image.
 * Constant alias for string: `"image/webp"`.
 */
const z_loaned_encoding_t *z_encoding_image_webp(void);
extern const z_owned_encoding_t ZP_ENCODING_IMAGE_WEBP;

/**
 * An XML file intended to be consumed by an application.
 * Constant alias for string: `"application/xml"`.
 */
const z_loaned_encoding_t *z_encoding_application_xml(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_XML;

/**
 * An encoded list of tuples, each consisting of a name and a value.
 * Constant alias for string: `"application/x-www-form-urlencoded"`.
 */
const z_loaned_encoding_t *z_encoding_application_x_www_form_urlencoded(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_X_WWW_FORM_URLENCODED;

/**
 * An HTML file.
 * Constant alias for string: `"text/html"`.
 */
const z_loaned_encoding_t *z_encoding_text_html(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_HTML;

/**
 * An XML file that is human-readable.
 * Constant alias for string: `"text/xml"`.
 */
const z_loaned_encoding_t *z_encoding_text_xml(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_XML;

/**
 * A CSS file.
 * Constant alias for string: `"text/css"`.
 */
const z_loaned_encoding_t *z_encoding_text_css(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_CSS;

/**
 * A JavaScript file.
 * Constant alias for string: `"text/javascript"`.
 */
const z_loaned_encoding_t *z_encoding_text_javascript(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_JAVASCRIPT;

/**
 * A Markdown file.
 * Constant alias for string: `"text/markdown"`.
 */
const z_loaned_encoding_t *z_encoding_text_markdown(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_MARKDOWN;

/**
 * A CSV file.
 * Constant alias for string: `"text/csv"`.
 */
const z_loaned_encoding_t *z_encoding_text_csv(void);
extern const z_owned_encoding_t ZP_ENCODING_TEXT_CSV;

/**
 * An application-specific SQL query.
 * Constant alias for string: `"application/sql"`.
 */
const z_loaned_encoding_t *z_encoding_application_sql(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_SQL;

/**
 * Constrained Application Protocol (CoAP) data intended for CoAP-to-HTTP and HTTP-to-CoAP proxies.
 * Constant alias for string: `"application/coap-payload"`.
 */
const z_loaned_encoding_t *z_encoding_application_coap_payload(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_COAP_PAYLOAD;

/**
 * Defines a JSON document structure for expressing a sequence of operations to apply to a JSON document.
 * Constant alias for string: `"application/json-patch+json"`.
 */
const z_loaned_encoding_t *z_encoding_application_json_patch_json(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_JSON_PATCH_JSON;

/**
 * A JSON text sequence consists of any number of JSON texts, all encoded in UTF-8.
 * Constant alias for string: `"application/json-seq"`.
 */
const z_loaned_encoding_t *z_encoding_application_json_seq(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_JSON_SEQ;

/**
 * A JSONPath defines a string syntax for selecting and extracting JSON values from within a given JSON value.
 * Constant alias for string: `"application/jsonpath"`.
 */
const z_loaned_encoding_t *z_encoding_application_jsonpath(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_JSONPATH;

/**
 * A JSON Web Token (JWT).
 * Constant alias for string: `"application/jwt"`.
 */
const z_loaned_encoding_t *z_encoding_application_jwt(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_JWT;

/**
 * An application-specific MPEG-4 encoded data, either audio or video.
 * Constant alias for string: `"application/mp4"`.
 */
const z_loaned_encoding_t *z_encoding_application_mp4(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_MP4;

/**
 * A SOAP 1.2 message serialized as XML 1.0.
 * Constant alias for string: `"application/soap+xml"`.
 */
const z_loaned_encoding_t *z_encoding_application_soap_xml(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_SOAP_XML;

/**
 * A YANG-encoded data commonly used by the Network Configuration Protocol (NETCONF).
 * Constant alias for string: `"application/yang"`.
 */
const z_loaned_encoding_t *z_encoding_application_yang(void);
extern const z_owned_encoding_t ZP_ENCODING_APPLICATION_YANG;

/**
 * A MPEG-4 Advanced Audio Coding (AAC) media.
 * Constant alias for string: `"audio/aac"`.
 */
const z_loaned_encoding_t *z_encoding_audio_aac(void);
extern const z_owned_encoding_t ZP_ENCODING_AUDIO_AAC;

/**
 * A Free Lossless Audio Codec (FLAC) media.
 * Constant alias for string: `"audio/flac"`.
 */
const z_loaned_encoding_t *z_encoding_audio_flac(void);
extern const z_owned_encoding_t ZP_ENCODING_AUDIO_FLAC;

/**
 * An audio codec defined in MPEG-1, MPEG-2, MPEG-4, or registered at the MP4 registration authority.
 * Constant alias for string: `"audio/mp4"`.
 */
const z_loaned_encoding_t *z_encoding_audio_mp4(void);
extern const z_owned_encoding_t ZP_ENCODING_AUDIO_MP4;

/**
 * An Ogg-encapsulated audio stream.
 * Constant alias for string: `"audio/ogg"`.
 */
const z_loaned_encoding_t *z_encoding_audio_ogg(void);
extern const z_owned_encoding_t ZP_ENCODING_AUDIO_OGG;

/**
 * A Vorbis-encoded audio stream.
 * Constant alias for string: `"audio/vorbis"`.
 */
const z_loaned_encoding_t *z_encoding_audio_vorbis(void);
extern const z_owned_encoding_t ZP_ENCODING_AUDIO_VORBIS;

/**
 * A h261-encoded video stream.
 * Constant alias for string: `"video/h261"`.
 */
const z_loaned_encoding_t *z_encoding_video_h261(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_H261;

/**
 * A h263-encoded video stream.
 * Constant alias for string: `"video/h263"`.
 */
const z_loaned_encoding_t *z_encoding_video_h263(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_H263;

/**
 * A h264-encoded video stream.
 * Constant alias for string: `"video/h264"`.
 */
const z_loaned_encoding_t *z_encoding_video_h264(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_H264;

/**
 * A h265-encoded video stream.
 * Constant alias for string: `"video/h265"`.
 */
const z_loaned_encoding_t *z_encoding_video_h265(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_H265;

/**
 * A h266-encoded video stream.
 * Constant alias for string: `"video/h266"`.
 */
const z_loaned_encoding_t *z_encoding_video_h266(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_H266;

/**
 * A video codec defined in MPEG-1, MPEG-2, MPEG-4, or registered at the MP4 registration authority.
 * Constant alias for string: `"video/mp4"`.
 */
const z_loaned_encoding_t *z_encoding_video_mp4(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_MP4;

/**
 * An Ogg-encapsulated video stream.
 * Constant alias for string: `"video/ogg"`.
 */
const z_loaned_encoding_t *z_encoding_video_ogg(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_OGG;

/**
 * An uncompressed, studio-quality video stream.
 * Constant alias for string: `"video/raw"`.
 */
const z_loaned_encoding_t *z_encoding_video_raw(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_RAW;

/**
 * A VP8-encoded video stream.
 * Constant alias for string: `"video/vp8"`.
 */
const z_loaned_encoding_t *z_encoding_video_vp8(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_VP8;

/**
 * A VP9-encoded video stream.
 * Constant alias for string: `"video/vp9"`.
 */
const z_loaned_encoding_t *z_encoding_video_vp9(void);
extern const z_owned_encoding_t ZP_ENCODING_VIDEO_VP9;

/**
 * Returns a loaned default `z_loaned_encoding_t`.
 */
const z_loaned_encoding_t *z_encoding_loan_default(void);

#endif

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_API_ENCODING_H */
