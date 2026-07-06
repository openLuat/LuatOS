-- JSON 编解码性能测试
-- 依赖：json（通常始终内置），无则跳过

local M = {}
local helper = require("perf_helper")

local ITERS = 100

-- 测试用复合对象（约 200 字节 JSON）
local TEST_OBJ = {
    id       = 12345,
    name     = "LuatOS perf test",
    version  = "1.0.0",
    enabled  = true,
    score    = 3.14159,
    tags     = {"embedded", "lua", "rtos"},
    config   = { retry = 3, timeout = 30000, debug = false }
}
local TEST_JSON = nil  -- 延迟初始化

local function skip_if_no_json()
    if not json then
        log.warn("perf_json", "json 库不可用，跳过 JSON 性能测试")
        return true
    end
    return false
end

function M.test_perf_json_encode()
    if skip_if_no_json() then return end
    helper.section("JSON encode 吞吐量")
    -- 预先 encode 一次，获得 JSON 字符串大小用于吞吐量计算
    local sample = json.encode(TEST_OBJ)
    local kb = sample and (#sample / 1024) or 0.0
    log.info("perf", string.format("[JSON encode] 单次输出 %d 字节", sample and #sample or 0))
    helper.measure("JSON encode", function()
        local s = json.encode(TEST_OBJ)
        assert(s and #s > 0, "json.encode 返回空")
    end, ITERS, kb)
    TEST_JSON = sample
end

function M.test_perf_json_decode()
    if skip_if_no_json() then return end
    helper.section("JSON decode 吞吐量")
    if not TEST_JSON then
        TEST_JSON = json.encode(TEST_OBJ)
    end
    local kb = #TEST_JSON / 1024
    helper.measure("JSON decode", function()
        local t = json.decode(TEST_JSON)
        assert(t and type(t) == "table", "json.decode 返回非表")
    end, ITERS, kb)
end

-- 大 JSON 数组（约 4KB）
function M.test_perf_json_large_array()
    if skip_if_no_json() then return end
    helper.section("JSON 大数组 encode/decode")
    local arr = {}
    for i = 1, 50 do
        arr[i] = { index = i, value = i * 3.14, name = "item_" .. i }
    end
    local encoded = json.encode(arr)
    local kb = encoded and (#encoded / 1024) or 0.0
    log.info("perf", string.format("[JSON large] 数组 JSON %d 字节", encoded and #encoded or 0))

    helper.measure("JSON large encode", function()
        local s = json.encode(arr)
        assert(s and #s > 0, "大 JSON encode 失败")
    end, 30, kb)

    helper.measure("JSON large decode", function()
        local t = json.decode(encoded)
        assert(t and #t == 50, "大 JSON decode 失败")
    end, 30, kb)
end

return M
