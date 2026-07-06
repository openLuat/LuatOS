-- 纯 Lua VM 基准测试
-- 不依赖任何 C 扩展库，始终运行
-- 覆盖：Fibonacci（CPU 整数）、表操作（内存）、浮点数学、字符串操作

local M = {}
local helper = require("perf_helper")

-- 递归 Fibonacci（CPU 密集型整数运算）
local function fib(n)
    if n <= 1 then return n end
    return fib(n - 1) + fib(n - 2)
end

function M.test_perf_lua_fibonacci()
    helper.section("Lua Fibonacci(25)")
    local ITERS = 3
    local t0 = mcu.ticks()
    for i = 1, ITERS do
        local result = fib(25)
        assert(result == 75025, "fib(25) 结果错误: " .. tostring(result))
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end
    log.info("perf", string.format("[fib(25)] %d次 %dms → %.1f ops/s", ITERS, elapsed, ITERS * 1000 / elapsed))
end

-- 表批量插入和遍历（内存分配+GC 压力）
function M.test_perf_lua_table_ops()
    helper.section("Lua 表插入/遍历 (1000元素×10次)")
    local INNER = 1000
    local OUTER = 10
    local t0 = mcu.ticks()
    for i = 1, OUTER do
        local t = {}
        for j = 1, INNER do
            t[j] = j * j
        end
        local sum = 0
        for j = 1, INNER do
            sum = sum + t[j]
        end
        assert(sum == 333833500, "表遍历求和结果错误: " .. tostring(sum))
        sys.wait(2)  -- 避免 WDT
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end
    log.info("perf", string.format("[table ops] %d×%d元素 %dms → %.0f insert+iter/s",
        OUTER, INNER, elapsed, OUTER * INNER * 2 * 1000 / elapsed))
end

-- 浮点数学（FPU 压力）
function M.test_perf_lua_math()
    helper.section("Lua 浮点数学运算（10000次）")
    local ITERS = 10000
    local t0 = mcu.ticks()
    local acc = 0.0
    for i = 1, ITERS do
        acc = acc + math.sin(i * 0.001) * math.cos(i * 0.002)
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end
    -- acc 只是为了防止编译器/JIT 优化掉循环
    log.info("perf", string.format("[math float] %d次 %dms → %.1f ops/s (acc=%.4f)",
        ITERS, elapsed, ITERS * 1000 / elapsed, acc))
end

-- 字符串操作（格式化 + 拼接）
function M.test_perf_lua_string()
    helper.section("Lua string.format × 1000")
    local ITERS = 1000
    helper.measure("string.format", function()
        local s = string.format("id=%d name=%s score=%.2f", 12345, "LuatOS", 3.14)
        assert(#s > 0, "string.format 失败")
    end, ITERS)

    helper.section("Lua string.find × 500")
    local haystack = string.rep("LuatOS embedded Lua RTOS platform; ", 10)
    helper.measure("string.find", function()
        local s, e = string.find(haystack, "RTOS")
        assert(s and s > 0, "string.find 失败")
    end, 500)

    helper.section("Lua string.gsub × 200")
    local src = string.rep("hello world, ", 20)
    helper.measure("string.gsub", function()
        local result = string.gsub(src, "world", "LuatOS")
        assert(result and #result > 0, "string.gsub 失败")
    end, 200)
end

-- 整数排序（table.sort，算法性能）
function M.test_perf_lua_sort()
    helper.section("Lua table.sort（500元素×20次）")
    local INNER = 500
    local OUTER = 20
    local t0 = mcu.ticks()
    for i = 1, OUTER do
        local arr = {}
        -- 生成伪随机数组
        local v = 12345
        for j = 1, INNER do
            v = (v * 1103515245 + 12345) % 2147483648
            arr[j] = v
        end
        table.sort(arr)
        assert(arr[1] <= arr[INNER], "排序结果异常")
        sys.wait(2)
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end
    log.info("perf", string.format("[table.sort] %d×%d元素 %dms → %.1f sorts/s",
        OUTER, INNER, elapsed, OUTER * 1000 / elapsed))
end

return M
