_G.sys = require("sys")

sys.taskInit(function()
    -- FFT 测试脚本（PC 模拟器）
    -- 最新固件中，fft 为内置库，可直接使用；
    -- 在纯 Lua 环境可改用 require("fft") 引入。

    -- local fft = rawget(_G, "fft") or require("fft")

    if fft == nil then
        while 1 do
            sys.wait(1000)
            log.info("bsp", "此BSP不支持fft库，请检查")
        end
    end

    -- Parameters
    local N = 2048        -- FFT points (power of 2)
    local fs = 1024       -- Sampling rate (Hz)
    local freq = 50       -- Input sine frequency (Hz)

    log.info("fft", "开始FFT测试", "N=" .. N, "fs=" .. fs, "freq=" .. freq)

    -- Construct input signal: real part as sine, imaginary part as 0
    local real, imag = {}, {}
    for i = 1, N do
      real[i] = math.sin(2 * math.pi * freq * (i - 1) / fs)
      imag[i] = 0
    end
    log.info("fft", "输入信号构造完成", "点数=" .. N)

    -- Generate twiddle factors and execute FFT (in-place calculation)
    local W_real, W_imag = fft.generate_twiddles(N)
    log.info("fft", "旋转因子生成完成")

    fft.run(real, imag, N, W_real, W_imag)
    log.info("fft", "FFT计算完成")

    -- Print first 10 results
    local output_points = math.min(10, N // 2)
    log.info("fft", "开始输出频谱结果", "输出点数=" .. output_points)
    print(string.format("%-6s %-12s %-12s %-12s", "Index", "Real", "Imag", "Magnitude"))
    for i = 1, output_points do
      local r = real[i]
      local im = imag[i]
      local mag = math.sqrt(r * r + im * im)
      print(string.format("%-6d %-12.6f %-12.6f %-12.6f", i - 1, r, im, mag))
    end
    log.info("fft", "频谱结果输出完成")

    -- 查找频谱主峰
    local max_magnitude = 0
    local peak_index = 0
    for i = 1, N // 2 do
      local r = real[i]
      local im = imag[i]
      local mag = math.sqrt(r * r + im * im)
      if mag > max_magnitude then
        max_magnitude = mag
        peak_index = i - 1
      end
    end
    
    local peak_frequency = peak_index * fs / N
    log.info("fft", "频谱主峰检测完成", 
             "峰值频率=" .. string.format("%.2f", peak_frequency) .. "Hz", 
             "峰值幅度=" .. string.format("%.6f", max_magnitude),
             "峰值索引=" .. peak_index)
end)

sys.run()
