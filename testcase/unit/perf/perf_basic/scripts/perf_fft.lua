-- FFT 计算性能测试
-- 依赖：fft 库，无则跳过
-- 测试两个规模：N=1024（嵌入式常用）和 N=4096（更大规模）

local M = {}
local helper = require("perf_helper")

local ITERS_1024 = 20
local ITERS_4096 = 5

local function skip_if_no_fft()
    if not fft then
        log.warn("perf_fft", "fft 库不可用，跳过 FFT 性能测试")
        return true
    end
    return false
end

-- 生成测试用信号缓冲区（float32 格式，使用 zbuff，N*4 字节）
local function make_signal(N)
    if not zbuff then
        return nil, nil
    end
    -- fft.run 默认 float32 模式，每个元素 4 字节
    local real_buf = zbuff.create(N * 4)
    local imag_buf = zbuff.create(N * 4)
    return real_buf, imag_buf
end

function M.test_perf_fft_1024()
    if skip_if_no_fft() then return end
    if not zbuff then
        log.warn("perf_fft", "zbuff 库不可用，跳过 FFT 性能测试")
        return
    end
    helper.section("FFT N=1024 延迟")
    local N = 1024
    local Wc, Ws = fft.generate_twiddles(N)
    assert(Wc and Ws, "fft.generate_twiddles 失败")
    local real_buf, imag_buf = make_signal(N)
    assert(real_buf and imag_buf, "信号缓冲区创建失败")

    helper.measure("FFT N=1024", function()
        -- fft.run 修改缓冲区，每次需要副本
        local real_cp = zbuff.create(N * 4, real_buf:toStr())
        local imag_cp = zbuff.create(N * 4, imag_buf:toStr())
        fft.run(real_cp, imag_cp, N, Wc, Ws)
    end, ITERS_1024)
end

function M.test_perf_fft_4096()
    if skip_if_no_fft() then return end
    if not zbuff then
        log.warn("perf_fft", "zbuff 库不可用，跳过 FFT 性能测试")
        return
    end
    helper.section("FFT N=4096 延迟")
    local N = 4096
    local Wc, Ws = fft.generate_twiddles(N)
    assert(Wc and Ws, "fft.generate_twiddles 失败")
    local real_buf, imag_buf = make_signal(N)
    assert(real_buf and imag_buf, "信号缓冲区创建失败")

    helper.measure("FFT N=4096", function()
        local real_cp = zbuff.create(N * 4, real_buf:toStr())
        local imag_cp = zbuff.create(N * 4, imag_buf:toStr())
        fft.run(real_cp, imag_cp, N, Wc, Ws)
    end, ITERS_4096)
end

return M
