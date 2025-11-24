_G.sys = require("sys")

sys.taskInit(function()
    -- 使用 zbuff 验证 FFT 输入（float32）
    if not fft then
        while 1 do sys.wait(1000) log.info("bsp", "此BSP不支持fft库，请检查") end
    end

    local N = 2048     -- FFT 点数（2 的幂）
    local fs = 1024    -- 采样率（Hz）
    local freq = 50    -- 输入正弦频率（Hz）

    log.info("fft", "zbuff 测试开始", "N=" .. N, "fs=" .. fs, "freq=" .. freq)

    -- 分配 zbuff：实部/虚部（N*4 字节），旋转因子（N/2*4 字节）
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)
    local W_real = zbuff.create((N // 2) * 4)
    local W_imag = zbuff.create((N // 2) * 4)

    -- 写入实部为正弦、虚部为 0（按 float32 写入）
    for i = 0, N - 1 do
        local v = math.sin(2 * math.pi * freq * i / fs)
        real:seek(i * 4, zbuff.SEEK_SET)
        real:writeF32(v)
        imag:seek(i * 4, zbuff.SEEK_SET)
        imag:writeF32(0.0)
    end
    log.info("fft", "zbuff 输入信号构造完成")

    -- 生成旋转因子到表（先用表，再复制到 zbuff）
    local tWr, tWi = fft.generate_twiddles(N)
    for k = 0, (N // 2) - 1 do
        W_real:seek(k * 4, zbuff.SEEK_SET)
        W_real:writeF32(tWr[k + 1])
        W_imag:seek(k * 4, zbuff.SEEK_SET)
        W_imag:writeF32(tWi[k + 1])
    end
    log.info("fft", "旋转因子写入 zbuff 完成")

    -- 在 FFT 之前，回读若干样点，确认写入的正弦值正确（应近似正弦）
    do
        local sample_idx = {0, 1, 2, 3, 4, 5, 25, 50}
        for _, i in ipairs(sample_idx) do
            real:seek(i * 4, zbuff.SEEK_SET)
            local val = real:readF32()
            log.info("fft", "real sample", i, string.format("%.6f", val))
        end
    end

    -- 执行 FFT（原地，就地操作 zbuff）
    fft.run(real, imag, N, W_real, W_imag)
    log.info("fft", "FFT计算完成(zbuff)")

    -- 读取前 10 个频点并打印（按 float32 读取）
    local output_points = math.min(10, N // 2)
    print(string.format("%-6s %-12s %-12s %-12s", "Index", "Real", "Imag", "Magnitude"))
    for i = 0, output_points - 1 do
        real:seek(i * 4, zbuff.SEEK_SET)
        imag:seek(i * 4, zbuff.SEEK_SET)
        local r = real:readF32()
        local im = imag:readF32()
        local mag = math.sqrt(r * r + im * im)
        print(string.format("%-6d %-12.6f %-12.6f %-12.6f", i, r, im, mag))
    end

    -- 主峰检测（读取全部前半谱）
    local max_mag, peak_idx = 0, 0
    for i = 0, (N // 2) - 1 do
        real:seek(i * 4, zbuff.SEEK_SET)
        imag:seek(i * 4, zbuff.SEEK_SET)
        local r = real:readF32()
        local im = imag:readF32()
        local mag = math.sqrt(r * r + im * im)
        if mag > max_mag then max_mag, peak_idx = mag, i end
    end
    local peak_f = peak_idx * fs / N
    log.info("fft", "主峰(Hz/幅值/索引)", string.format("%.2f", peak_f), string.format("%.6f", max_mag), peak_idx)
end)

sys.run()


