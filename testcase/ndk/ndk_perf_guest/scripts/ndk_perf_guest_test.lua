-- ndk_perf_guest_test.lua
-- Test cases for the perf-guest-v1 NDK suite (commit 2 subset).
--
-- Each test_* function:
--   1. Runs the pure-Lua baseline on a known payload.
--   2. Runs the same payload through the NDK guest C path.
--   3. Asserts the NDK output is byte-identical to the Lua output
--      (this is the contract we WANT to break before measuring speed).
--   4. Measures both with measure() and emits PERF|... log lines.
--
-- Commit 2 only ships FNV-1a 32 and CRC32 IEEE. MD5, Base64 and
-- heapsort land in commits 3-4.

local proto = require("perf_proto")
local baselines = require("baselines")
local measure = require("measure")

local tests = {}

-- -----------------------------------------------------------------------
-- Context helpers (NDK session lifecycle).
-- -----------------------------------------------------------------------

local function open_ctx()
    assert(io.exists(proto.IMAGE), "missing " .. proto.IMAGE ..
        " — build components/ndk/guest/examples/perf_guest_v1 first")
    local ctx, err = ndk.rv32i(proto.IMAGE, proto.MEM_SIZE, proto.EXCHANGE_SIZE)
    assert(ctx, tostring(err))
    return ctx
end

local function close_ctx(ctx)
    if not ctx then return end
    pcall(ndk.stop, ctx, 1000)
    pcall(ndk.reset, ctx, 1000)
end

-- Run one perf payload end-to-end: pack request, set data, exec, unpack
-- result. Asserts OK status; returns the NDK output bytes.
local function run_ndk_once(ctx, algo_id, payload, last_chunk)
    local req = proto.pack_request(algo_id, payload, last_chunk)
    assert(req, "pack_request failed")
    assert(ndk.setData(ctx, req), "setData failed")
    local ok, ret, mcause, mtval = ndk.exec(ctx, { steps = 200000, elapsed = 500 })
    assert(ok == true, string.format(
        "ndk.exec failed: ret=%s mcause=%s mtval=%s", tostring(ret),
        tostring(mcause), tostring(mtval)))
    local result_data = assert(ndk.getData(ctx, proto.RESULT_SIZE, proto.RESULT_OFFSET))
    return proto.unpack_result(result_data)
end

-- -----------------------------------------------------------------------
-- FNV-1a 32-bit
-- -----------------------------------------------------------------------

tests.test_fnv1a_smoke_vectors = function()
    -- First make sure the baselines themselves are sane (no host drift).
    assert(baselines.fnv1a_lua("") == baselines.SMOKE_VECTORS.fnv1a_empty,
        "fnv1a baseline drift: empty input")
    assert(baselines.fnv1a_lua("a") == baselines.SMOKE_VECTORS.fnv1a_a,
        "fnv1a baseline drift: 'a' input")
end

tests.test_fnv1a_ndk_vs_lua_64B = function()
    local ctx = open_ctx()
    local payload = string.rep("A", 64)
    local lua_out = baselines.fnv1a_lua(payload)
    local ndk_res = run_ndk_once(ctx, proto.ALGO_FNV1A_32, payload, true)
    assert(ndk_res.status == proto.STATUS_OK, "ndk FNV-1a status not OK: " .. ndk_res.status)
    assert(ndk_res.output_len == 4, "ndk FNV-1a output_len != 4: " .. tostring(ndk_res.output_len))
    local ndk_digest = ndk.getData(ctx, 4, proto.PAYLOAD_OFFSET + #payload)
    assert(ndk_digest == lua_out,
        string.format("FNV-1a mismatch: ndk_len=%d lua_len=%d",
            #ndk_digest, #lua_out))
    close_ctx(ctx)
end

tests.test_fnv1a_ndk_perf_64B = function()
    local ctx = open_ctx()
    local payload = string.rep("A", 64)
    local lua_digest = baselines.fnv1a_lua(payload)

    local lua_res = measure.measure("fnv1a_32.lua", function()
        assert(baselines.fnv1a_lua(payload) == lua_digest)
    end, 6000, 64, 200)

    local ndk_res = measure.measure("fnv1a_32.ndk_guest_c", function()
        local r = run_ndk_once(ctx, proto.ALGO_FNV1A_32, payload, true)
        assert(r.status == proto.STATUS_OK)
        local digest = ndk.getData(ctx, 4, proto.PAYLOAD_OFFSET + #payload)
        assert(digest == lua_digest)
    end, 6000, 64, 200)

    log.info("perf_cmp", string.format(
        "CMP algo=fnv1a_32 size=64B ndk_over_lua=%.2fx", ndk_res.kb_s / lua_res.kb_s))
    close_ctx(ctx)
end

-- -----------------------------------------------------------------------
-- CRC32 IEEE
-- -----------------------------------------------------------------------

tests.test_crc32_smoke_vectors = function()
    assert(baselines.crc32_lua("") == baselines.SMOKE_VECTORS.crc32_empty,
        "crc32 baseline drift: empty input")
    assert(baselines.crc32_lua("123456789") == baselines.SMOKE_VECTORS.crc32_123456789,
        "crc32 baseline drift: '123456789' input")
end

tests.test_crc32_ndk_vs_lua_64B = function()
    local ctx = open_ctx()
    local payload = string.rep("B", 64)
    local lua_out = baselines.crc32_lua(payload)
    local ndk_res = run_ndk_once(ctx, proto.ALGO_CRC32_IEEE, payload, true)
    assert(ndk_res.status == proto.STATUS_OK, "ndk CRC32 status not OK")
    assert(ndk_res.output_len == 4, "ndk CRC32 output_len != 4")
    local ndk_digest = ndk.getData(ctx, 4, proto.PAYLOAD_OFFSET + #payload)
    assert(ndk_digest == lua_out,
        string.format("CRC32 mismatch: ndk=%s lua=%s", ndk_digest, lua_out))
    close_ctx(ctx)
end

tests.test_crc32_ndk_perf_64B = function()
    local ctx = open_ctx()
    local payload = string.rep("B", 64)
    local lua_digest = baselines.crc32_lua(payload)

    local lua_res = measure.measure("crc32_ieee.lua", function()
        assert(baselines.crc32_lua(payload) == lua_digest)
    end, 6000, 64, 200)

    local ndk_res = measure.measure("crc32_ieee.ndk_guest_c", function()
        local r = run_ndk_once(ctx, proto.ALGO_CRC32_IEEE, payload, true)
        assert(r.status == proto.STATUS_OK)
        local digest = ndk.getData(ctx, 4, proto.PAYLOAD_OFFSET + #payload)
        assert(digest == lua_digest)
    end, 6000, 64, 200)

    log.info("perf_cmp", string.format(
        "CMP algo=crc32_ieee size=64B ndk_over_lua=%.2fx", ndk_res.kb_s / lua_res.kb_s))
    close_ctx(ctx)
end

-- -----------------------------------------------------------------------
-- MD5 (commit 3)
-- -----------------------------------------------------------------------

tests.test_md5_smoke_vectors = function()
    assert(baselines.md5_lua("")  == baselines.SMOKE_VECTORS.md5_empty,
        "md5 baseline drift: empty input")
    assert(baselines.md5_lua("a")  == baselines.SMOKE_VECTORS.md5_a,
        "md5 baseline drift: 'a' input")
    assert(baselines.md5_lua("abc") == baselines.SMOKE_VECTORS.md5_abc,
        "md5 baseline drift: 'abc' input")
    assert(baselines.md5_lua("The quick brown fox jumps over the lazy dog")
        == baselines.SMOKE_VECTORS.md5_fox,
        "md5 baseline drift: fox sentence")
end

local MD5_PROFILES = {
    { size = 64,  iters = 6000, warmup = 200 },
    { size = 256, iters = 4000, warmup = 120 },
    { size = 512, iters = 2000, warmup = 80  },
    { size = 1024, iters = 1000, warmup = 40 },
}

for _, profile in ipairs(MD5_PROFILES) do
    tests["test_md5_ndk_vs_lua_" .. profile.size .. "B"] = function()
        local ctx = open_ctx()
        local payload = string.rep("A", profile.size)
        local lua_out = baselines.md5_lua(payload)
        local ndk_res = run_ndk_once(ctx, proto.ALGO_MD5, payload, true)
        assert(ndk_res.status == proto.STATUS_OK,
            "ndk MD5 status not OK: " .. ndk_res.status)
        assert(ndk_res.output_len == 16, "ndk MD5 output_len != 16")
        local ndk_digest = ndk.getData(ctx, 16, proto.PAYLOAD_OFFSET + #payload)
        assert(ndk_digest == lua_out,
            string.format("MD5 mismatch (size=%d): ndk len=%d lua len=%d",
                profile.size, #ndk_digest, #lua_out))
        close_ctx(ctx)
    end

    tests["test_md5_ndk_perf_" .. profile.size .. "B"] = function()
        local ctx = open_ctx()
        local payload = string.rep("A", profile.size)
        local lua_digest = baselines.md5_lua(payload)

        local lua_res = measure.measure("md5.lua", function()
            assert(baselines.md5_lua(payload) == lua_digest)
        end, profile.iters, profile.size, profile.warmup)

        local ndk_res = measure.measure("md5.ndk_guest_c", function()
            local r = run_ndk_once(ctx, proto.ALGO_MD5, payload, true)
            assert(r.status == proto.STATUS_OK)
            local digest = ndk.getData(ctx, 16, proto.PAYLOAD_OFFSET + #payload)
            assert(digest == lua_digest)
        end, profile.iters, profile.size, profile.warmup)

        log.info("perf_cmp", string.format(
            "CMP algo=md5 size=%dB ndk_over_lua=%.2fx",
            profile.size, ndk_res.kb_s / lua_res.kb_s))
        close_ctx(ctx)
    end
end

-- -----------------------------------------------------------------------
-- Base64 encode (commit 4)
-- -----------------------------------------------------------------------

tests.test_base64_smoke_vectors = function()
    -- A few canonical RFC 4648 §10 vectors.
    assert(baselines.base64_lua("")        == "",
        "base64 baseline drift: empty")
    assert(baselines.base64_lua("f")       == "Zg==",
        "base64 baseline drift: 'f'")
    assert(baselines.base64_lua("fo")      == "Zm8=",
        "base64 baseline drift: 'fo'")
    assert(baselines.base64_lua("foo")     == "Zm9v",
        "base64 baseline drift: 'foo'")
    assert(baselines.base64_lua("foob")    == "Zm9vYg==",
        "base64 baseline drift: 'foob'")
    assert(baselines.base64_lua("fooba")   == "Zm9vYmE=",
        "base64 baseline drift: 'fooba'")
    assert(baselines.base64_lua("foobar")  == "Zm9vYmFy",
        "base64 baseline drift: 'foobar'")
end

-- Base64 expands by 4/3 + up to 2 padding bytes. Worst case for
-- input_len=L is 4*ceil(L/3) output bytes. With MAX_CHUNK=960 and
-- PAYLOAD_OFFSET=64 the available payload space is 960 bytes, so
-- the largest safe L is 411 (4*137=548 output + 411 input = 959 ≤ 960).
-- We use 64/192/320/384 so the profiles are clearly under the cap
-- (sizes 512 / 768 — used in the initial commit — fail with BAD_BOUNDS
-- because 512+684=1196 > 960 and 768+1024=1792 > 960).
local BASE64_PROFILES = {
    { size = 64,  iters = 6000, warmup = 200 },
    { size = 192, iters = 4000, warmup = 120 },
    { size = 320, iters = 2000, warmup = 80  },
    { size = 384, iters = 1500, warmup = 60  },
}

for _, profile in ipairs(BASE64_PROFILES) do
    tests["test_base64_ndk_vs_lua_" .. profile.size .. "B"] = function()
        local ctx = open_ctx()
        local payload = string.rep("A", profile.size)
        local lua_out = baselines.base64_lua(payload)
        local ndk_res = run_ndk_once(ctx, proto.ALGO_BASE64_ENC, payload, true)
        assert(ndk_res.status == proto.STATUS_OK,
            "ndk Base64 status not OK: " .. ndk_res.status ..
            " (size=" .. profile.size .. "B output=" .. #lua_out .. "B)")
        local ndk_out = ndk.getData(ctx, #lua_out, proto.PAYLOAD_OFFSET + #payload)
        assert(ndk_out == lua_out,
            string.format("Base64 mismatch (size=%d): ndk len=%d lua len=%d",
                profile.size, #ndk_out, #lua_out))
        close_ctx(ctx)
    end

    tests["test_base64_ndk_perf_" .. profile.size .. "B"] = function()
        local ctx = open_ctx()
        local payload = string.rep("A", profile.size)
        local lua_out = baselines.base64_lua(payload)

        local lua_res = measure.measure("base64_enc.lua", function()
            assert(baselines.base64_lua(payload) == lua_out)
        end, profile.iters, profile.size, profile.warmup)

        local ndk_res = measure.measure("base64_enc.ndk_guest_c", function()
            local r = run_ndk_once(ctx, proto.ALGO_BASE64_ENC, payload, true)
            assert(r.status == proto.STATUS_OK)
            local got = ndk.getData(ctx, #lua_out, proto.PAYLOAD_OFFSET + #payload)
            assert(got == lua_out)
        end, profile.iters, profile.size, profile.warmup)

        log.info("perf_cmp", string.format(
            "CMP algo=base64_enc size=%dB ndk_over_lua=%.2fx",
            profile.size, ndk_res.kb_s / lua_res.kb_s))
        close_ctx(ctx)
    end
end

-- -----------------------------------------------------------------------
-- Heapsort int32 (commit 4)
-- -----------------------------------------------------------------------
-- The Lua baseline does NOT use table.sort (that would be native C and
-- defeat the purpose). It's a pure-Lua heapsort in baselines.lua.

tests.test_heapsort_smoke = function()
    -- 5-element array with both positive and negative values.
    local arr = string.pack("<i4i4i4i4i4", 30, -5, 12, 7, -22)
    local sorted = baselines.heapsort_lua_int32(arr)
    -- Lua:  -22, -5, 7, 12, 30  (little-endian)
    local expected = string.pack("<i4i4i4i4i4", -22, -5, 7, 12, 30)
    assert(sorted == expected,
        string.format("heapsort baseline drift: got %s want %s", sorted, expected))
end

local HEAPSORT_PROFILES = {
    -- n_elems: number of int32 entries; byte size = n_elems * 4
    { n_elems = 16,  iters = 4000, warmup = 120 },  -- 64 B
    { n_elems = 64,  iters = 2000, warmup = 80  },  -- 256 B
    { n_elems = 256, iters = 500,  warmup = 30  },  -- 1024 B
}

-- Build a deterministic but unsorted int32 payload. The sequence
-- (i * 37 + 11) % 200 - 100 produces 256 distinct values from -89 to
-- 110 over the first 256 elements, which exercises positive + negative.
local function make_int32_payload(n_elems)
    local bytes = {}
    for i = 0, n_elems - 1 do
        local v = ((i * 37 + 11) % 200) - 100
        bytes[i*4 + 1] = string.char( v        & 0xFF)
        bytes[i*4 + 2] = string.char((v >>  8) & 0xFF)
        bytes[i*4 + 3] = string.char((v >> 16) & 0xFF)
        bytes[i*4 + 4] = string.char((v >> 24) & 0xFF)
    end
    return table.concat(bytes)
end

for _, profile in ipairs(HEAPSORT_PROFILES) do
    tests["test_heapsort_ndk_vs_lua_n" .. profile.n_elems] = function()
        local ctx = open_ctx()
        local payload = make_int32_payload(profile.n_elems)
        local lua_out = baselines.heapsort_lua_int32(payload)
        local ndk_res = run_ndk_once(ctx, proto.ALGO_HEAPSORT_I32, payload, true)
        assert(ndk_res.status == proto.STATUS_OK,
            "ndk heapsort status not OK: " .. ndk_res.status)
        local ndk_out = ndk.getData(ctx, #lua_out, proto.PAYLOAD_OFFSET)
        assert(ndk_out == lua_out,
            string.format("heapsort mismatch (n=%d): ndk len=%d lua len=%d",
                profile.n_elems, #ndk_out, #lua_out))
        close_ctx(ctx)
    end

    tests["test_heapsort_ndk_perf_n" .. profile.n_elems] = function()
        local ctx = open_ctx()
        local byte_size = profile.n_elems * 4
        local payload = make_int32_payload(profile.n_elems)
        local lua_out = baselines.heapsort_lua_int32(payload)

        local lua_res = measure.measure("heapsort_i32.lua", function()
            assert(baselines.heapsort_lua_int32(payload) == lua_out)
        end, profile.iters, byte_size, profile.warmup)

        local ndk_res = measure.measure("heapsort_i32.ndk_guest_c", function()
            local r = run_ndk_once(ctx, proto.ALGO_HEAPSORT_I32, payload, true)
            assert(r.status == proto.STATUS_OK)
            local got = ndk.getData(ctx, #lua_out, proto.PAYLOAD_OFFSET)
            assert(got == lua_out)
        end, profile.iters, byte_size, profile.warmup)

        log.info("perf_cmp", string.format(
            "CMP algo=heapsort_i32 n=%d ndk_over_lua=%.2fx",
            profile.n_elems, ndk_res.kb_s / lua_res.kb_s))
        close_ctx(ctx)
    end
end

return tests
