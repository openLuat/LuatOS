--[[
@module  test_fft
@summary FFT测试功能模块
@version 1.0
@date    2025.10.30
@author  孟伟
@usage
本demo是FFT（快速傅里叶变换）测试，支持Q15定点和F32浮点两种实现方式。
主要功能：
   - 生成200Hz正弦波测试信号
   - 使用Q15定点FFT算法处理数据
   - 使用F32浮点FFT算法处理相同数据
   - 计算并输出两种实现方式的性能对比（执行时间）
   - 分析频谱结果，定位并显示主峰频率

本文件没有对外接口，直接在main.lua中require "test_fft"就可以加载运行；
]]


function test_fft_fun()
    if not fft then
        -- 如果不支持FFT库，进入死循环并提示错误
        while 1 do
            sys.wait(1000) -- 等待1秒
            log.info("bsp", "此BSP不支持fft库，请检查") -- 输出错误信息
        end
    end

    -- FFT 参数配置段

    -- 设置FFT基本参数
    local N = 2048 -- FFT 点数：决定频率分辨率和计算复杂度，必须是2的幂次方
    local fs = 2000 -- 采样频率 (Hz)：根据奈奎斯特定理，可分析的最高频率为fs/2=1000Hz
    local freq = 200 -- 测试信号频率 (Hz)：生成一个200Hz的正弦波作为测试信号

    -- 输出测试开始信息和参数
    log.info("fft", "q15 测试开始", "N=" .. N, "fs=" .. fs, "freq=" .. freq)


    -- 内存分配段：为FFT计算准备缓冲区
    -- 分配 zbuff 缓冲区：
    -- 使用16位整数缓冲区来存储Q15格式的数据
    -- 每个复数点需要2个16位整数（实部和虚部），所以总大小为 N * 2 * 2 字节
    local real_i16 = zbuff.create(N * 2) -- 实部缓冲区：存储时域信号的实部
    local imag_i16 = zbuff.create(N * 2) -- 虚部缓冲区：存储时域信号的虚部（初始为0）


    -- 测试信号生成段：生成一个200Hz的正弦波测试信号
    -- 生成 U12 整数正弦波并写入缓冲区（避免浮点预处理干扰）
    -- U12格式：12位无符号整数，范围0-4095，2048对应0电平
    for i = 0, N - 1 do
        -- 计算时间点：i/fs 表示第i个样本的时间（秒）
        local t = i / fs

        -- 生成200Hz正弦波：sin(2π * 频率 * 时间)
        local x = math.sin(2 * math.pi * freq * t)

        -- 将浮点数转换为U12格式：
        -- 2048为直流偏置（中间值），2047为幅度范围
        -- +0.5是为了四舍五入到最接近的整数
        local val = math.floor(2048 + 2047 * x + 0.5)

        -- 数值范围限制：确保在U12的有效范围内（0-4095）
        if val < 0 then val = 0 end
        if val > 4095 then val = 4095 end

        -- 将数据写入缓冲区：
        -- seek定位到正确的位置，每个样本占2字节
        -- writeU16写入16位无符号整数（低12位有效）
        real_i16:seek(i * 2, zbuff.SEEK_SET); real_i16:writeU16(val) -- 实部写入正弦波数据
        imag_i16:seek(i * 2, zbuff.SEEK_SET); imag_i16:writeU16(0) -- 虚部写入0（实数信号）
    end


    -- 旋转因子生成段：为Q15 FFT计算准备旋转因子
    -- 生成 Q15 旋转因子到 zbuff（避免任何浮点旋转因子）
    -- 旋转因子用于FFT计算中的复数乘法，长度是FFT点数的一半
    local Wc_q15 = zbuff.create((N // 2) * 2) -- 余弦旋转因子缓冲区
    local Ws_q15 = zbuff.create((N // 2) * 2) -- 正弦旋转因子缓冲区（实际存储-sin值）

    -- 生成Q15格式的旋转因子表
    fft.generate_twiddles_q15_to_zbuff(N, Wc_q15, Ws_q15)


    -- 使用定点Q15内核执行FFT
    -- 执行 Q15 FFT（输入为 U12），显式传入 Q15 旋转因子
    local t0 = mcu.ticks() -- 记录开始时间

    -- 执行FFT计算：
    -- real_i16, imag_i16: 输入输出缓冲区（原地计算）
    -- N: FFT点数
    -- Wc_q15, Ws_q15: Q15格式旋转因子
    -- {core = "q15", input_format = "u12"}: 使用Q15定点内核，输入格式为U12
    fft.run(real_i16, imag_i16, N, Wc_q15, Ws_q15, { core = "q15", input_format = "u12" })

    local t1 = mcu.ticks() -- 记录结束时间
    -- 输出Q15 FFT计算耗时
    log.info("fft", "q15 FFT 完成", "耗时:" .. (t1 - t0) .. "ms")


    -- 分析FFT结果，找到主要频率成分
    -- 扫描前半部分频谱（0 ~ fs/2），寻找主峰
    -- 由于频谱的对称性，只需要分析前N/2个点
    local peak_k, peak_pow = 1, -1 -- peak_k: 峰值位置, peak_pow: 峰值功率

    -- 遍历所有频率bin（跳过直流分量k=0）
    for k = 1, (N // 2) - 1 do
        -- 定位到第k个频率点的实部和虚部
        real_i16:seek(k * 2, zbuff.SEEK_SET)
        imag_i16:seek(k * 2, zbuff.SEEK_SET)

        -- 读取实部和虚部值（Q15格式）
        local rr = real_i16:readI16() -- 实部
        local ii = imag_i16:readI16() -- 虚部

        -- 计算功率谱：|X[k]|² = real² + imag²
        -- 功率谱表示该频率成分的能量大小
        local p = rr * rr + ii * ii

        -- 更新峰值信息
        if p > peak_pow then
            peak_pow = p -- 更新最大功率值
            peak_k = k -- 更新峰值位置
        end
    end

    -- 计算峰值对应的实际频率：频率 = bin索引 * 频率分辨率
    -- 频率分辨率 = 采样频率 / FFT点数
    local peak_freq = (peak_k) * fs / N

    -- 输出主峰频率信息
    -- peak_k: 峰值所在的bin索引
    -- peak_freq: 计算出的实际频率（应该接近200Hz）
    log.info("fft", "主峰(Hz/bin)", string.format("%.2f", peak_freq), peak_k)


    -- 使用浮点F32内核进行相同计算，对比性能
    -- 比较：使用 f32 内核处理相同输入（验证 q15 与 f32 结果一致性）
    -- 复制相同的 U12 输入到新的 zbuff（浮点格式）

    -- 为浮点FFT分配缓冲区：每个浮点数占4字节
    local real_f32 = zbuff.create(N * 4) -- 实部缓冲区（浮点）
    local imag_f32 = zbuff.create(N * 4) -- 虚部缓冲区（浮点）

    -- 将Q15数据复制到浮点缓冲区
    for i = 0, N - 1 do
        -- 从Q15缓冲区读取U12数据
        real_i16:seek(i * 2, zbuff.SEEK_SET)
        local val = real_i16:readU16()

        -- 写入浮点缓冲区（直接写入U12原始值，不进行格式转换）
        real_f32:seek(i * 4, zbuff.SEEK_SET)
        imag_f32:seek(i * 4, zbuff.SEEK_SET)
        real_f32:writeF32(val) -- 实部写入原始U12值
        imag_f32:writeF32(0.0) -- 虚部写入0.0
    end

    -- 生成 f32 旋转因子（浮点格式）
    -- 返回Lua table格式的旋转因子，而不是zbuff
    local Wc, Ws = fft.generate_twiddles(N)

    -- 执行 f32 FFT（输入为 U12）
    local t2 = mcu.ticks() -- 记录开始时间

    -- 执行浮点FFT计算：
    -- 使用默认的f32内核，输入格式为u12
    fft.run(real_f32, imag_f32, N, Wc, Ws, { input_format = "u12" })

    local t3 = mcu.ticks() -- 记录结束时间
    local dt_f32 = (t3 - t2) -- 计算浮点FFT耗时

    -- 输出浮点FFT计算耗时
    log.info("fft", "f32 FFT 完成", "耗时:" .. dt_f32 .. "ms")


    -- 结果总结段：对比两种实现的性能


    -- 总结耗时对比：Q15定点 vs F32浮点
    -- 在没有硬件浮点加速的嵌入式设备上，Q15会比F32快很多，
    -- 而780和8000系列都没有硬件浮点加速，建议使用q15计算提高速度，但如果追求计算精度，仍然可以用浮点计算
    log.info("fft", "对比(q15 vs f32, ms)", string.format("%d / %d", (t1 - t0), dt_f32))
end

sys.taskInit(test_fft_fun)
