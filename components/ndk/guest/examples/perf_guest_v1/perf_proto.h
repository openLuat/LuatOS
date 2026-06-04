/*
 * perf_proto.h — perf-guest-v1 protocol definitions.
 *
 * Wire format (host -> guest, then guest -> host):
 *
 *   Exchange buffer (1024 bytes by default; the host configures size).
 *   Layout:
 *
 *     offset 0  : req header (16B, uint32_t[4])
 *       req[0] = algo_id            (PERF_ALGO_*)
 *       req[1] = input_len          (bytes; size of payload the algo consumes)
 *       req[2] = input_offset       (offset within exchange; usually 64)
 *       req[3] = control_word       (bit0: PERF_CTRL_LAST_CHUNK)
 *
 *     offset 16 : result (16B, uint32_t[4])
 *       result[0] = status          (PERF_STATUS_*)
 *       result[1] = output_len      (bytes written into the output area)
 *       result[2] = elapsed_us_lo
 *       result[3] = elapsed_us_hi
 *
 *     offset 32 : event header (16B; do not touch)
 *     offset 48 : event slot 0  (8B;  do not touch)
 *     offset 64 : payload        (up to 960B; input + output)
 *
 *   Each algo is free to interpret payload[0..input_len] however it wants,
 *   as long as it is deterministic for a given input. Output (if any) is
 *   written back starting at input_offset + input_len (i.e. immediately
 *   after the input). This keeps the protocol simple and avoids needing
 *   an out-of-band output_offset.
 *
 *   Time measurement: the guest samples CSR 0x141 / 0x142 (ndk_time_us_*)
 *   before and after the work, and stores the delta into result[2..3]
 *   when PERF_CTRL_LAST_CHUNK is set. This is the ONLY host-ABI call the
 *   perf suite is allowed to make (plus ndk_lprint for debug + SYSCON
 *   0x5555 to exit). The MD5/CRC32 host CSRs (0x230/0x231) are FORBIDDEN
 *   here by design — that would just measure host C vs Lua, not NDK
 *   guest C vs Lua.
 */
#pragma once

#include <stdint.h>

/* Algorithm IDs. Upper nibble is the category, lower nibble the index. */
#define PERF_ALGO_FNV1A_32     0x10u
#define PERF_ALGO_CRC32_IEEE   0x11u
#define PERF_ALGO_BASE64_ENC   0x20u
#define PERF_ALGO_MD5          0x30u
#define PERF_ALGO_HEAPSORT_I32 0x40u

/* Control-word bits. Only PERF_CTRL_LAST_CHUNK is used today; the rest
 * are reserved for future expansion (e.g. streaming, partial outputs). */
#define PERF_CTRL_LAST_CHUNK   (1u << 0)
#define PERF_CTRL_RESERVED1    (1u << 1)

/* Status codes written into result[0]. */
#define PERF_STATUS_OK              0u
#define PERF_STATUS_BAD_ARG         1u
#define PERF_STATUS_BAD_BOUNDS      2u
#define PERF_STATUS_UNSUPPORTED     3u
#define PERF_STATUS_NOT_LAST_CHUNK  4u  /* elapsed_us deliberately not written */

/* Buffer layout constants. The host always sets input_offset = 64. */
#define PERF_REQ_OFFSET        0u
#define PERF_RESULT_OFFSET    16u
#define PERF_EVENT_HDR_OFFSET 32u
#define PERF_PAYLOAD_OFFSET   64u

/* Maximum payload size the host can deliver in a single chunk. The host
 * is responsible for chunking larger inputs; the guest is responsible
 * for asserting the bounds against its own ndk_memory_size().
 *
 * Bumped from 960 to 4032 (= EXCHANGE_SIZE 4096 - PAYLOAD_OFFSET 64)
 * so the perf suite can exercise the full size range up to the
 * 4 KiB exchange cap without silent input truncation. */
#ifndef PERF_MAX_CHUNK
#define PERF_MAX_CHUNK  4032u
#endif

/* Algorithm run signature. Every algo exports one of these; main.c
 * dispatches via a small function-pointer table.
 *
 *   in       : pointer to input bytes (already inside the exchange buffer)
 *   in_len   : number of input bytes
 *   out      : pointer to output area (immediately after in)
 *   out_len  : in  = available output capacity; out = bytes actually written
 *   elapsed_lo / elapsed_hi : out, microsecond delta. The caller writes
 *                             these into result[2..3] when LAST_CHUNK set.
 *
 * Returns a PERF_STATUS_* code. */
typedef uint32_t (*perf_algo_fn)(const uint8_t *in, uint32_t in_len,
                                 uint8_t *out, uint32_t *out_len,
                                 uint32_t *elapsed_lo, uint32_t *elapsed_hi);

/* Extern declarations for the per-algo implementations. */
perf_algo_fn perf_algo_get(uint32_t algo_id);

/* Per-algo function signatures. These are not part of the public ABI;
 * the dispatcher in main.c calls perf_algo_get() to resolve them. */
uint32_t perf_fnv1a_run(const uint8_t *in, uint32_t in_len,
                        uint8_t *out, uint32_t *out_len,
                        uint32_t *elapsed_lo, uint32_t *elapsed_hi);

uint32_t perf_crc32_run(const uint8_t *in, uint32_t in_len,
                        uint8_t *out, uint32_t *out_len,
                        uint32_t *elapsed_lo, uint32_t *elapsed_hi);

uint32_t perf_base64_run(const uint8_t *in, uint32_t in_len,
                         uint8_t *out, uint32_t *out_len,
                         uint32_t *elapsed_lo, uint32_t *elapsed_hi);

uint32_t perf_md5_run(const uint8_t *in, uint32_t in_len,
                      uint8_t *out, uint32_t *out_len,
                      uint32_t *elapsed_lo, uint32_t *elapsed_hi);

uint32_t perf_heapsort_run(const uint8_t *in, uint32_t in_len,
                           uint8_t *out, uint32_t *out_len,
                           uint32_t *elapsed_lo, uint32_t *elapsed_hi);
