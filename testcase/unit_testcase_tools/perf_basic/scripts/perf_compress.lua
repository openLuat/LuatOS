-- miniz 压缩/解压性能测试
-- 依赖：miniz 库，无则跳过

local M = {}
local helper = require("perf_helper")

local DATA_1KB    = string.rep("LuatOS benchmark test data, performance measure. ", 21):sub(1, 1024)
local DATA_REPEAT = string.rep("ABCDE", 205):sub(1, 1024)  -- 高度可压缩数据
local ITERS = 100

local function skip_if_no_miniz()
    if not miniz then
        log.warn("perf_compress", "miniz 库不可用，跳过压缩性能测试")
        return true
    end
    return false
end

function M.test_perf_compress_mixed()
    if skip_if_no_miniz() then return end
    helper.section("miniz 压缩（混合内容 1KB）")
    local compressed = miniz.compress(DATA_1KB)
    assert(compressed and #compressed > 0, "压缩失败")
    log.info("perf", string.format("[miniz] 混合 1KB → %d 字节 (%.1f%%)", #compressed, #compressed * 100 / #DATA_1KB))
    helper.measure("miniz compress mixed", function()
        local c = miniz.compress(DATA_1KB)
        assert(c and #c > 0, "压缩失败")
    end, ITERS, 1)
end

function M.test_perf_compress_repeat()
    if skip_if_no_miniz() then return end
    helper.section("miniz 压缩（高重复内容 1KB）")
    local compressed = miniz.compress(DATA_REPEAT)
    assert(compressed and #compressed > 0, "压缩失败")
    log.info("perf", string.format("[miniz] 重复 1KB → %d 字节 (%.1f%%)", #compressed, #compressed * 100 / #DATA_REPEAT))
    helper.measure("miniz compress repeat", function()
        local c = miniz.compress(DATA_REPEAT)
        assert(c and #c > 0, "压缩失败")
    end, ITERS, 1)
end

function M.test_perf_uncompress()
    if skip_if_no_miniz() then return end
    helper.section("miniz 解压（混合内容 1KB）")
    local compressed = miniz.compress(DATA_1KB)
    assert(compressed and #compressed > 0, "预压缩失败")
    helper.measure("miniz uncompress", function()
        local d = miniz.uncompress(compressed)
        assert(d == DATA_1KB, "解压数据不一致")
    end, ITERS, 1)
end

-- 大数据块（8KB）压缩，模拟固件/脚本文件场景
function M.test_perf_compress_8kb()
    if skip_if_no_miniz() then return end
    helper.section("miniz 压缩（混合内容 8KB）")
    local data8kb = string.rep(DATA_1KB, 8)
    local compressed = miniz.compress(data8kb)
    if not compressed then
        log.warn("perf_compress", "8KB 压缩返回 nil，可能超出平台内存限制，跳过")
        return
    end
    local kb = #data8kb / 1024
    log.info("perf", string.format("[miniz] 混合 8KB → %d 字节 (%.1f%%)", #compressed, #compressed * 100 / #data8kb))
    helper.measure("miniz compress 8KB", function()
        local c = miniz.compress(data8kb)
        assert(c and #c > 0, "8KB 压缩失败")
    end, 20, kb)
end

return M
