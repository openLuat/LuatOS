-- 性能测试公共辅助模块
-- 提供统一的计时、吞吐量输出工具函数

local M = {}

-- 执行 fn 共 iters 次，返回总耗时(ms)并打印结果
-- tag      : 显示标签
-- fn       : 被测函数（无参数）
-- iters    : 迭代次数
-- data_kb  : 每次处理的数据量(KB)，传 nil 则输出 ops/s，否则输出 KB/s
function M.measure(tag, fn, iters, data_kb)
    local t0 = mcu.ticks()
    for i = 1, iters do
        fn()
        -- 每 50 次 yield 一次，防止 WDT 超时
        if i % 50 == 0 then
            sys.wait(2)
        end
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end

    if data_kb then
        local throughput = data_kb * iters * 1000 / elapsed
        log.info("perf", string.format("[%s] %d次 %dms → %.1f KB/s", tag, iters, elapsed, throughput))
    else
        local ops = iters * 1000 / elapsed
        log.info("perf", string.format("[%s] %d次 %dms → %.1f ops/s", tag, iters, elapsed, ops))
    end
    return elapsed
end

-- 打印分组标题
function M.section(name)
    log.info("perf", string.format("========== %s ==========", name))
end

return M
