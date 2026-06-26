-- perf_proto.lua
-- Protocol definitions for the perf-guest-v1 NDK test suite.
--
-- The guest program is at /luadb/perf_guest_v1.bin. It exposes five
-- guest-C-implemented algorithms (FNV-1a, CRC32, Base64, MD5, heapsort)
-- and rejects the host-ABI shortcuts (CSR 0x230/0x231) by design.
--
-- Wire format (see components/ndk/guest/examples/perf_guest_v1/perf_proto.h):
--   offset 0  : req header (16B, uint32_t[4])
--   offset 16 : result    (16B, uint32_t[4])
--   offset 32 : event hdr (16B; do not touch)
--   offset 64 : payload   (input + output, up to 960B)

local M = {}

-- Algorithm IDs (must match perf_proto.h)
M.ALGO_FNV1A_32     = 0x10
M.ALGO_CRC32_IEEE   = 0x11
M.ALGO_BASE64_ENC   = 0x20
M.ALGO_MD5          = 0x30
M.ALGO_HEAPSORT_I32 = 0x40

-- Control word bits
M.CTRL_LAST_CHUNK = 1

-- Status codes
M.STATUS_OK              = 0
M.STATUS_BAD_ARG         = 1
M.STATUS_BAD_BOUNDS      = 2
M.STATUS_UNSUPPORTED     = 3
M.STATUS_NOT_LAST_CHUNK  = 4

-- Exchange buffer constants. The 4 KiB exchange lets us exercise the
-- full algorithm range (MD5 up to 3.5 KiB, heapsort up to ~1 K
-- int32s, base64 up to ~3 KiB input) without per-test size
-- tuning. The guest's overall RAM stays at 32 KiB; only the
-- shared buffer grows. Bumped from the original 1 KiB after
-- multiple per-test size cap adjustments proved to be wasted
-- effort — 4 KiB is well within typical SoC SRAM budgets and
-- matches the buffer size the LuatOS host uses elsewhere.
M.IMAGE          = "/luadb/perf_guest_v1.bin"
M.MEM_SIZE       = 32 * 1024
M.EXCHANGE_SIZE  = 4096
M.PAYLOAD_OFFSET = 64
M.RESULT_OFFSET  = 16
M.RESULT_SIZE    = 16

-- Maximum payload we can deliver in a single chunk. The host is
-- expected to chunk anything larger; the guest caps it defensively
-- at this value as well.
M.MAX_CHUNK = M.EXCHANGE_SIZE - M.PAYLOAD_OFFSET  -- = 4032

-- Build the request blob: 16B header + payload (placed at PAYLOAD_OFFSET).
function M.pack_request(algo_id, payload, last_chunk)
    if #payload > M.MAX_CHUNK then
        return nil, "payload too large: " .. #payload
    end
    local header = string.pack("<I4I4I4I4",
        algo_id,
        #payload,
        M.PAYLOAD_OFFSET,
        last_chunk and M.CTRL_LAST_CHUNK or 0)
    local blob = header
    if #blob < M.PAYLOAD_OFFSET then
        blob = blob .. string.rep("\0", M.PAYLOAD_OFFSET - #blob)
    end
    blob = blob .. payload
    return blob
end

-- Unpack the 16B result region. Returns a table:
--   { status, output_len, elapsed_us_lo, elapsed_us_hi, elapsed_us }
-- where elapsed_us is the combined 64-bit value (clamped to ~4M seconds).
function M.unpack_result(data)
    assert(#data == M.RESULT_SIZE, "result blob wrong size: " .. #data)
    local status, output_len, lo, hi = string.unpack("<I4I4I4I4", data, 1)
    local elapsed_us = (hi * (2 ^ 32)) + lo
    return {
        status      = status,
        output_len  = output_len,
        elapsed_lo  = lo,
        elapsed_hi  = hi,
        elapsed_us  = elapsed_us,
    }
end

-- Status code name for log output.
function M.status_name(s)
    if s == M.STATUS_OK              then return "OK" end
    if s == M.STATUS_BAD_ARG         then return "BAD_ARG" end
    if s == M.STATUS_BAD_BOUNDS      then return "BAD_BOUNDS" end
    if s == M.STATUS_UNSUPPORTED     then return "UNSUPPORTED" end
    if s == M.STATUS_NOT_LAST_CHUNK  then return "NOT_LAST_CHUNK" end
    return "?"
end

-- Algorithm name for log output.
function M.algo_name(algo_id)
    if algo_id == M.ALGO_FNV1A_32     then return "fnv1a_32" end
    if algo_id == M.ALGO_CRC32_IEEE   then return "crc32_ieee" end
    if algo_id == M.ALGO_BASE64_ENC   then return "base64_enc" end
    if algo_id == M.ALGO_MD5          then return "md5" end
    if algo_id == M.ALGO_HEAPSORT_I32 then return "heapsort_i32" end
    return string.format("algo_0x%02X", algo_id)
end

return M
