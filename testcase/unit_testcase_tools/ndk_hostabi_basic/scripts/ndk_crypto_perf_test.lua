local proto = require("hostabi_proto")

local tests = {}
local IMAGE = "/luadb/hostabi_v1.bin"
local MEM_SIZE = 32 * 1024
local EXCHANGE_SIZE = 1024

local band = function(v) return v & 0xFFFFFFFF end

local function rol32(v, s)
    return ((v << s) | (v >> (32 - s))) & 0xFFFFFFFF
end

local md5_s = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
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

local crc32_table = {}
for i = 0, 255 do
    local crc = i
    for _ = 1, 8 do
        if (crc & 1) ~= 0 then
            crc = (crc >> 1) ~ 0xEDB88320
        else
            crc = crc >> 1
        end
    end
    crc32_table[i] = crc & 0xFFFFFFFF
end

local function md5_bin(data)
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

local function crc32_u32(data)
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        crc = crc32_table[(crc ~ data:byte(i)) & 0xFF] ~ (crc >> 8)
    end
    return crc & 0xFFFFFFFF
end

local function make_blob(cmd, payload)
    local header = proto.pack_cmd(cmd, proto.CRYPTO_INPUT_OFFSET, #payload, proto.CRYPTO_OUTPUT_OFFSET)
    local blob = header
    if #blob < proto.CRYPTO_INPUT_OFFSET then
        blob = blob .. string.rep("\0", proto.CRYPTO_INPUT_OFFSET - #blob)
    end
    blob = blob .. payload
    if #blob < proto.CRYPTO_OUTPUT_OFFSET then
        blob = blob .. string.rep("\0", proto.CRYPTO_OUTPUT_OFFSET - #blob)
    end
    return blob
end

local function load_ctx(payload)
    assert(io.exists(IMAGE), "missing hostabi_v1.bin")
    local ctx, err = ndk.rv32i(IMAGE, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, tostring(err))
    assert(ndk.setData(ctx, payload))
    return ctx
end

local function run_payload(ctx)
    local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
    assert(ok == true, string.format("exec failed ret=%s mcause=%s mtval=%s", tostring(ret), tostring(mcause), tostring(mtval)))
    return proto.unpack_result(assert(ndk.getData(ctx, proto.RESULT_SIZE, proto.RESULT_OFFSET)))
end

local function measure(tag, fn, iters, payload_size, warmup)
    warmup = warmup or 20
    for _ = 1, warmup do
        fn()
    end

    local t0 = mcu.ticks()
    for i = 1, iters do
        fn()
        if i % 500 == 0 then
            sys.wait(1)
        end
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then
        elapsed = 1
    end
    local ops = iters * 1000 / elapsed
    local kbps = (payload_size / 1024) * iters * 1000 / elapsed
    log.info("perf", string.format("[%s] size=%dB iters=%d warmup=%d elapsed=%dms ops=%.1f/s kbps=%.1f",
        tag, payload_size, iters, warmup, elapsed, ops, kbps))
    log.info("perf_raw", string.format("PERF|tag=%s|size=%d|iters=%d|warmup=%d|elapsed_ms=%d|ops_s=%.3f|kb_s=%.3f",
        tag, payload_size, iters, warmup, elapsed, ops, kbps))
    return { elapsed_ms = elapsed, ops_s = ops, kb_s = kbps }
end

function tests.test_ndk_pure_lua_md5_crc32_perf()
    local profiles = {
        { size = 64, iters = 6000, warmup = 200 },
        { size = 256, iters = 4000, warmup = 120 },
        { size = 512, iters = 2000, warmup = 80 },
    }

    for _, p in ipairs(profiles) do
        local payload = string.rep("A", p.size)
        local expected_md5 = md5_bin(payload)
        local expected_crc = crc32_u32(payload)

        local md5_blob = make_blob(proto.CMD_CRYPTO_MD5, payload)
        local crc_blob = make_blob(proto.CMD_CRYPTO_CRC32, payload)
        local md5_ctx = load_ctx(md5_blob)
        local crc_ctx = load_ctx(crc_blob)

        local lua_md5 = measure("md5.lua", function()
            assert(md5_bin(payload) == expected_md5, "lua md5 drift")
        end, p.iters, p.size, p.warmup)

        local ndk_md5 = measure("md5.ndk_c", function()
            local result = run_payload(md5_ctx)
            assert(result.status == proto.STATUS_OK, "ndk md5 status error")
            local digest = ndk.getData(md5_ctx, 16, proto.CRYPTO_OUTPUT_OFFSET)
            assert(digest == expected_md5, "ndk md5 digest mismatch")
        end, p.iters, p.size, p.warmup)

        local lua_crc = measure("crc32.lua", function()
            assert(crc32_u32(payload) == expected_crc, "lua crc32 drift")
        end, p.iters, p.size, p.warmup)

        local ndk_crc = measure("crc32.ndk_c", function()
            local result = run_payload(crc_ctx)
            assert(result.status == proto.STATUS_OK, "ndk crc32 status error")
            assert(result.value0 == expected_crc, string.format("ndk crc32 mismatch: got 0x%08x want 0x%08x", result.value0, expected_crc))
        end, p.iters, p.size, p.warmup)

        log.info("perf_cmp", string.format(
            "CMP size=%dB md5_ndk_vs_lua=%.2fx crc32_ndk_vs_lua=%.2fx",
            p.size, ndk_md5.kb_s / lua_md5.kb_s, ndk_crc.kb_s / lua_crc.kb_s
        ))

        ndk.stop(md5_ctx, 1000)
        ndk.stop(crc_ctx, 1000)
    end
end

return tests
