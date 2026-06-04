-- baselines.lua
-- Pure-Lua reference implementations for the perf-guest-v1 algorithms.
--
-- These are the BASELINE side of the comparison: every perf test case
-- runs the same algorithm twice — once through the NDK guest C path,
-- once through these pure-Lua implementations — and asserts the outputs
-- are byte-identical before comparing performance.
--
-- IMPORTANT: do NOT use table.sort / string.pack shortcuts that call
-- into native C, because that would degenerate the comparison into
-- "host C vs Lua" rather than "NDK guest C vs Lua". The two algos in
-- this commit (FNV-1a 32, CRC32 IEEE) are pure-Lua throughout.

local M = {}

-------------------------------------------------------------------------------
-- FNV-1a 32-bit
-------------------------------------------------------------------------------
local FNV1A_32_OFFSET_BASIS = 0x811C9DC5
local FNV1A_32_PRIME        = 0x01000193

local band = function(v) return v & 0xFFFFFFFF end

function M.fnv1a_lua(s)
    local h = FNV1A_32_OFFSET_BASIS
    for i = 1, #s do
        h = band((h ~ s:byte(i)) * FNV1A_32_PRIME)
    end
    return string.pack("<I4", h)
end

-------------------------------------------------------------------------------
-- CRC32 IEEE (the same polynomial used by zlib / gzip / PNG)
-------------------------------------------------------------------------------
-- Build the 256-entry table once at module-load time.
local crc32_table = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if (c & 1) ~= 0 then
            c = (c >> 1) ~ 0xEDB88320
        else
            c = c >> 1
        end
    end
    crc32_table[i] = c & 0xFFFFFFFF
end

function M.crc32_lua(s)
    local crc = 0xFFFFFFFF
    for i = 1, #s do
        crc = crc32_table[(crc ~ s:byte(i)) & 0xFF] ~ (crc >> 8)
    end
    return string.pack("<I4", crc ~ 0xFFFFFFFF)
end

-------------------------------------------------------------------------------
-- Reference digests for "smoke" payloads (used to detect obvious drift
-- across host environments / Lua versions). Not used for byte-level
-- comparison in perf tests — those compare NDK output vs Lua output
-- on the SAME payload.
-------------------------------------------------------------------------------
M.SMOKE_VECTORS = {
    -- FNV-1a of the empty string is the offset basis itself.
    fnv1a_empty = string.pack("<I4", 0x811C9DC5),
    -- FNV-1a of "a" is 0xE40C292C.
    fnv1a_a     = string.pack("<I4", 0xE40C292C),
    -- CRC32 of the empty string is 0x00000000.
    crc32_empty = string.pack("<I4", 0x00000000),
    -- CRC32 of "123456789" is 0xCBF43926.
    crc32_123456789 = string.pack("<I4", 0xCBF43926),
    -- MD5 of "" is d41d8cd98f00b204e9800998ecf8427e.
    md5_empty = string.fromHex("d41d8cd98f00b204e9800998ecf8427e"),
    -- MD5 of "abc" is 900150983cd24fb0d6963f7d28e17f72.
    md5_abc   = string.fromHex("900150983cd24fb0d6963f7d28e17f72"),
    -- MD5 of "a" is 0cc175b9c0f1b6a831c399e269772661.
    md5_a     = string.fromHex("0cc175b9c0f1b6a831c399e269772661"),
    -- MD5 of "The quick brown fox jumps over the lazy dog" is
    -- 9e107d9d372bb6826bd81d3542a419d6.
    md5_fox   = string.fromHex("9e107d9d372bb6826bd81d3542a419d6"),
}

-------------------------------------------------------------------------------
-- MD5 (RFC 1321)
-------------------------------------------------------------------------------
local md5_s = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
}

local md5_k = {
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
}

local function rol32(v, s)
    return ((v << s) | (v >> (32 - s))) & 0xFFFFFFFF
end

function M.md5_lua(data)
    local a0, b0, c0, d0 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476
    local len = #data
    local tail = data .. string.char(0x80)
    local pad_len = (56 - (#tail % 64)) % 64
    tail = tail .. string.rep("\0", pad_len) .. string.pack("<I8", len * 8)
    local unpack32 = string.unpack

    for off = 1, #tail, 64 do
        local x = {}
        for i = 0, 15 do
            x[i] = unpack32("<I4", tail, off + (i * 4))
        end

        local a, b, c, d = a0, b0, c0, d0
        for i = 0, 63 do
            local f, g
            if i < 16 then
                f = (b & c) | (~b & d)
                g = i
            elseif i < 32 then
                f = (d & b) | (~d & c)
                g = (5 * i + 1) % 16
            elseif i < 48 then
                f = b ~ c ~ d
                g = (3 * i + 5) % 16
            else
                f = c ~ (b | (~d))
                g = (7 * i) % 16
            end
            local tmp = d
            d = c
            c = b
            local sum = (a + f + md5_k[i + 1] + x[g]) & 0xFFFFFFFF
            b = (b + rol32(sum, md5_s[i + 1])) & 0xFFFFFFFF
            a = tmp
        end

        a0 = (a0 + a) & 0xFFFFFFFF
        b0 = (b0 + b) & 0xFFFFFFFF
        c0 = (c0 + c) & 0xFFFFFFFF
        d0 = (d0 + d) & 0xFFFFFFFF
    end

    return string.pack("<I4I4I4I4", a0, b0, c0, d0)
end

-------------------------------------------------------------------------------
-- Base64 encode (RFC 4648 §4)
-------------------------------------------------------------------------------
local b64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ..
                     "abcdefghijklmnopqrstuvwxyz" ..
                     "0123456789+/"

function M.base64_lua(s)
    local out, o = {}, 1
    local n = #s
    local i = 1
    -- 1-indexed: bytes 1,2,3 are at positions i, i+1, i+2. We need
    -- i+2 <= n to know there are at least 3 bytes from position i.
    -- The original draft used `i + 3 <= n` (0-indexed), which
    -- silently skipped the 3-byte case for n=3,6,9,…
    while i + 2 <= n do
        local b1, b2, b3 = s:byte(i), s:byte(i+1), s:byte(i+2)
        local v = (b1 << 16) | (b2 << 8) | b3
        out[o]   = b64_alphabet:sub(((v >> 18) & 0x3F) + 1, ((v >> 18) & 0x3F) + 1)
        out[o+1] = b64_alphabet:sub(((v >> 12) & 0x3F) + 1, ((v >> 12) & 0x3F) + 1)
        out[o+2] = b64_alphabet:sub(((v >>  6) & 0x3F) + 1, ((v >>  6) & 0x3F) + 1)
        out[o+3] = b64_alphabet:sub(( v        & 0x3F) + 1, ( v        & 0x3F) + 1)
        o = o + 4
        i = i + 3
    end
    -- Trailing partial group, if any. After the loop above, the
    -- number of unprocessed bytes is (n - i + 1) in Lua's 1-based
    -- indexing. Valid leftovers are 1 or 2 (3 bytes would have been
    -- a full group, 0 means we just finished). 4+ is impossible.
    local rem = n - i + 1
    if rem == 1 then
        local b1 = s:byte(i)
        local v = b1 << 16
        out[o]   = b64_alphabet:sub(((v >> 18) & 0x3F) + 1, ((v >> 18) & 0x3F) + 1)
        out[o+1] = b64_alphabet:sub(((v >> 12) & 0x3F) + 1, ((v >> 12) & 0x3F) + 1)
        out[o+2] = "="
        out[o+3] = "="
        o = o + 4
    elseif rem == 2 then
        local b1, b2 = s:byte(i), s:byte(i+1)
        local v = (b1 << 16) | (b2 << 8)
        out[o]   = b64_alphabet:sub(((v >> 18) & 0x3F) + 1, ((v >> 18) & 0x3F) + 1)
        out[o+1] = b64_alphabet:sub(((v >> 12) & 0x3F) + 1, ((v >> 12) & 0x3F) + 1)
        out[o+2] = b64_alphabet:sub(((v >>  6) & 0x3F) + 1, ((v >>  6) & 0x3F) + 1)
        out[o+3] = "="
        o = o + 4
    end
    return table.concat(out)
end

-------------------------------------------------------------------------------
-- Heapsort of int32 little-endian payloads (pure Lua, no table.sort).
-------------------------------------------------------------------------------
local function siftdown_lua(arr, start, end_)
    local root = start
    -- 1-indexed heap: left child is at 2*root, right child at 2*root+1.
    -- The original draft used `root * 2 + 1 <= end_` (0-indexed style),
    -- which skipped sifts whenever `2*root == end_` (i.e. a single
    -- child remains); on a 5-element test that dropped one swap and
    -- left the final two elements in the wrong order. The C version
    -- uses 0-indexed indices throughout, so the 1-indexed Lua port
    -- needs the 1-indexed sibling-offset rule.
    while root * 2 <= end_ do
        local child = root * 2
        local swp = root
        if arr[swp] < arr[child] then swp = child end
        if child + 1 <= end_ and arr[swp] < arr[child + 1] then
            swp = child + 1
        end
        if swp == root then return end
        arr[swp], arr[root] = arr[root], arr[swp]
        root = swp
    end
end

function M.heapsort_lua_int32(s)
    local n = #s / 4
    if n < 2 then return s end
    -- Decode the little-endian int32 bytes into a Lua table.
    local arr = {}
    for i = 0, n - 1 do
        local b0, b1, b2, b3 = s:byte(i*4 + 1), s:byte(i*4 + 2),
                               s:byte(i*4 + 3), s:byte(i*4 + 4)
        arr[i + 1] = (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) << 0  -- force int32
        if arr[i + 1] >= 0x80000000 then
            arr[i + 1] = arr[i + 1] - 0x100000000  -- to signed range
        end
    end
    -- Build the max-heap (LuatOS is 1-indexed, so root is at 1).
    for start = math.floor((n - 2) / 2), 0, -1 do
        siftdown_lua(arr, start + 1, n)
    end
    -- Repeatedly swap root with the last unsorted element.
    for end_ = n, 2, -1 do
        arr[1], arr[end_] = arr[end_], arr[1]
        siftdown_lua(arr, 1, end_ - 1)
    end
    -- Re-encode to little-endian bytes.
    local out = {}
    for i = 1, n do
        local v = arr[i]
        if v < 0 then v = v + 0x100000000 end  -- to unsigned for shifting
        local b0 =  v        & 0xFF
        local b1 = (v >>  8) & 0xFF
        local b2 = (v >> 16) & 0xFF
        local b3 = (v >> 24) & 0xFF
        out[i*4 - 3] = string.char(b0)
        out[i*4 - 2] = string.char(b1)
        out[i*4 - 1] = string.char(b2)
        out[i*4    ] = string.char(b3)
    end
    return table.concat(out)
end

return M
