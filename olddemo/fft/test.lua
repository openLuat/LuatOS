PROJECT = "pcm32_spectrum"
VERSION = "1.0.0"
_G.sys = require("sys")

-- 32bit PCM频谱分析
function generate_32bit_spectrum(pcm_filename, output_filename)
    local sample_rate = 24000
    local fft_points = 256 -- 使用较小的FFT点数节省内存
    local df = sample_rate / fft_points

    log.info("分析", "32bit PCM频谱分析")
    log.info("参数", string.format("采样率: %dHz, FFT点数: %d", sample_rate, fft_points))

    -- 检查文件是否存在
    if not io.exists(pcm_filename) then
        log.error("文件", "PCM文件不存在: " .. pcm_filename)
        return false
    end

    -- 获取文件大小
    local file_size = io.fileSize(pcm_filename)
    if not file_size then
        log.error("文件", "无法获取文件大小")
        return false
    end

    log.info("文件", string.format("文件大小: %d 字节", file_size))
    log.info("文件", string.format("约 %d 个32bit样本", file_size // 4))

    -- 准备FFT缓冲区
    local real_buf = zbuff.create(fft_points * 2)
    local imag_buf = zbuff.create(fft_points * 2)

    local Wc = zbuff.create((fft_points // 2) * 2)
    local Ws = zbuff.create((fft_points // 2) * 2)
    fft.generate_twiddles_q15_to_zbuff(fft_points, Wc, Ws)

    -- 读取文件
    local file = io.open(pcm_filename, "rb")
    if not file then
        log.error("文件", "无法打开PCM文件")
        return false
    end

    -- 读取一个片段（32bit = 4字节 per sample）
    local bytes_to_read = fft_points * 4
    local chunk = file:read(bytes_to_read)
    file:close()

    if not chunk or #chunk < 4 then
        log.error("读取", "文件数据不足")
        return false
    end

    log.info("读取", string.format("读取了 %d 字节", #chunk))

    -- 处理32bit PCM数据
    local samples_processed = 0
    for i = 1, math.floor(#chunk / 4) do
        local byte_pos = (i - 1) * 4 + 1

        -- 32bit小端序解析
        local b1 = chunk:byte(byte_pos) -- 最低字节
        local b2 = chunk:byte(byte_pos + 1)
        local b3 = chunk:byte(byte_pos + 2)
        local b4 = chunk:byte(byte_pos + 3) -- 最高字节

        -- 组合成32位整数
        local sample = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216

        -- 32bit有符号转换 (范围: -2147483648 到 2147483647)
        if sample >= 2147483648 then
            sample = sample - 4294967296
        end

        -- 32bit转U12格式
        local normalized = (sample / 2147483648.0)                    -- 归一化到 -1.0 到 1.0
        local u12_val = math.floor((normalized + 1.0) * 2047.5 + 0.5) -- 转到 0-4095

        if u12_val < 0 then u12_val = 0 end
        if u12_val > 4095 then u12_val = 4095 end

        real_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
        real_buf:writeU16(u12_val)
        imag_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
        imag_buf:writeU16(0)

        samples_processed = samples_processed + 1

        -- 每处理64个样本输出一次进度
        if i % 64 == 0 then
            log.info("处理", string.format("已处理 %d/%d 样本", i, math.floor(#chunk / 4)))
        end
    end

    -- 如果数据不足，用0填充
    for i = samples_processed + 1, fft_points do
        real_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
        real_buf:writeU16(2048) -- 中间值
        imag_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
        imag_buf:writeU16(0)
    end

    log.info("FFT", "开始执行FFT计算...")

    -- 执行FFT
    fft.run(real_buf, imag_buf, fft_points, Wc, Ws, {
        core = "q15",
        input_format = "u12"
    })

    -- 生成输出文件
    local out_file = io.open(output_filename, "w")
    if not out_file then
        log.error("文件", "无法创建输出文件")
        return false
    end

    -- 写入文件头
    local ret, err = out_file:write('{\n')
    if not ret then
        log.error("写入", "写入文件头失败:", err)
        out_file:close()
        return false
    end

    out_file:write('  "sample_rate": 24000,\n')
    out_file:write('  "fft_points": 256,\n')
    out_file:write('  "frequency_resolution": ' .. df .. ',\n')
    out_file:write('  "max_frequency": 12000,\n')
    out_file:write('  "bit_depth": 32,\n')
    out_file:write('  "spectrum_data": [\n')

    -- 收集频谱数据
    local freq_data = {}
    local max_magnitude = 0

    -- 先扫描找到最大值用于归一化
    for k = 1, fft_points // 2 do
        real_buf:seek(k * 2, zbuff.SEEK_SET)
        imag_buf:seek(k * 2, zbuff.SEEK_SET)
        local r = real_buf:readI16()
        local i = imag_buf:readI16()
        local magnitude = math.sqrt(r * r + i * i)
        if magnitude > max_magnitude then
            max_magnitude = magnitude
        end
    end

    -- 生成归一化的频谱数据
    for k = 1, fft_points // 2 do
        real_buf:seek(k * 2, zbuff.SEEK_SET)
        imag_buf:seek(k * 2, zbuff.SEEK_SET)
        local r = real_buf:readI16()
        local i = imag_buf:readI16()
        local magnitude = math.sqrt(r * r + i * i)

        -- 归一化到0-100范围
        local normalized = 0
        if max_magnitude > 0 then
            normalized = (magnitude / max_magnitude) * 100
        end

        table.insert(freq_data, string.format("%.2f", normalized))

        -- 输出主要频点信息
        if normalized > 10 then -- 只显示能量大于10%的频点
            local freq = (k - 1) * df
            log.info("频点", string.format("%.0fHz: %.1f%%", freq, normalized))
        end
    end

    -- 写入频谱数据
    out_file:write('    { "time": 0.0, "freq": [')
    out_file:write(table.concat(freq_data, ", "))
    out_file:write('] }\n')
    out_file:write('  ]\n')
    out_file:write('}\n')

    out_file:close()

    log.info("完成", "32bit PCM频谱分析完成")
    log.info("文件", "频谱数据已保存到: " .. output_filename)

    return true
end

-- 快速测试版本（不生成文件，直接输出）
function quick_32bit_test(pcm_filename)
    local sample_rate = 24000
    local fft_points = 128

    log.info("快速测试", "32bit PCM快速频谱分析")

    -- 检查文件是否存在
    if not io.exists(pcm_filename) then
        log.error("文件", "PCM文件不存在")
        return false
    end

    -- 最小内存分配
    local real_buf = zbuff.create(fft_points * 2)
    local imag_buf = zbuff.create(fft_points * 2)
    local Wc = zbuff.create((fft_points // 2) * 2)
    local Ws = zbuff.create((fft_points // 2) * 2)

    fft.generate_twiddles_q15_to_zbuff(fft_points, Wc, Ws)

    local file = io.open(pcm_filename, "rb")
    if not file then
        log.error("文件", "无法打开文件")
        return false
    end

    local chunk = file:read(512) -- 只读512字节
    file:close()

    if not chunk then
        log.error("读取", "读取文件失败")
        return false
    end

    log.info("读取", string.format("读取了 %d 字节", #chunk))

    -- 处理32bit数据
    local samples_processed = 0
    for i = 1, math.min(fft_points, math.floor(#chunk / 4)) do
        local byte_pos = (i - 1) * 4 + 1
        if byte_pos + 3 <= #chunk then
            local b1 = chunk:byte(byte_pos)
            local b2 = chunk:byte(byte_pos + 1)
            local b3 = chunk:byte(byte_pos + 2)
            local b4 = chunk:byte(byte_pos + 3)

            local sample = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
            if sample >= 2147483648 then sample = sample - 4294967296 end

            -- 简化转换
            local normalized = sample / 2147483648.0
            local u12_val = math.floor((normalized + 1.0) * 2047.5)
            if u12_val < 0 then u12_val = 0 end
            if u12_val > 4095 then u12_val = 4095 end

            real_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
            real_buf:writeU16(u12_val)
            imag_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
            imag_buf:writeU16(0)

            samples_processed = samples_processed + 1
        end
    end

    -- 填充剩余数据
    for i = samples_processed + 1, fft_points do
        real_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
        real_buf:writeU16(2048)
        imag_buf:seek((i - 1) * 2, zbuff.SEEK_SET)
        imag_buf:writeU16(0)
    end

    -- FFT计算
    fft.run(real_buf, imag_buf, fft_points, Wc, Ws, {
        core = "q15",
        input_format = "u12"
    })

    -- 直接输出结果
    log.info("=== 频谱结果 ===")
    local df = sample_rate / fft_points
    local peaks = {}

    for k = 2, fft_points // 2 do -- 跳过直流分量
        real_buf:seek(k * 2, zbuff.SEEK_SET)
        imag_buf:seek(k * 2, zbuff.SEEK_SET)
        local r = real_buf:readI16()
        local i = imag_buf:readI16()
        local magnitude = math.sqrt(r * r + i * i)
        local freq = (k - 1) * df

        if magnitude > 100 then
            table.insert(peaks, { freq = freq, mag = magnitude })
        end
    end

    -- 按幅度排序，显示前10个
    table.sort(peaks, function(a, b) return a.mag > b.mag end)

    for i = 1, math.min(10, #peaks) do
        log.info("峰值" .. i, string.format("%.0fHz (%.1f)", peaks[i].freq, peaks[i].mag))
    end

    if #peaks == 0 then
        log.info("结果", "未检测到明显频率峰值")
    end

    return true
end

-- 极简版本：只分析前几个样本
function minimal_32bit_test(pcm_filename)
    log.info("极简测试", "32bit PCM极简分析")

    if not io.exists(pcm_filename) then
        log.error("文件", "文件不存在")
        return false
    end

    local file_size = io.fileSize(pcm_filename)
    if not file_size or file_size < 16 then
        log.error("文件", "文件太小")
        return false
    end

    log.info("文件", string.format("文件大小: %d 字节", file_size))

    -- 只读取前16个字节（4个样本）
    local data = io.readFile(pcm_filename, "rb", 0, 16)
    if not data then
        log.error("读取", "读取文件失败")
        return false
    end

    log.info("数据", string.format("读取了 %d 字节", #data))

    -- 分析前4个样本
    for i = 1, math.min(4, math.floor(#data / 4)) do
        local byte_pos = (i - 1) * 4 + 1
        if byte_pos + 3 <= #data then
            local b1 = data:byte(byte_pos)
            local b2 = data:byte(byte_pos + 1)
            local b3 = data:byte(byte_pos + 2)
            local b4 = data:byte(byte_pos + 3)

            local sample = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
            if sample >= 2147483648 then sample = sample - 4294967296 end

            local normalized = sample / 2147483648.0
            log.info("样本" .. i, string.format("原始值: %d, 归一化: %.6f", sample, normalized))
        end
    end

    return true
end

-- 主程序
sys.taskInit(function()
    if not fft then
        log.error("FFT", "不支持FFT库")
        return
    end

    sys.wait(3000) -- 等待系统稳定

    local pcm_file = "/luadb/qlx_13sec.pcm"
    local spectrum_file = "/spectrum.json"

    if not io.exists(pcm_file) then
        log.warn("文件", "PCM文件不存在: " .. pcm_file)
        log.info("提示", "请将32bit PCM文件命名为 audio.pcm 并放入文件系统")
        return
    end

    log.info("开始", "32bit PCM频谱分析...")

    -- 先尝试极简测试
    if minimal_32bit_test(pcm_file) then
        log.info("成功", "极简测试完成")

        -- 然后尝试快速测试
        sys.wait(1000)
        if quick_32bit_test(pcm_file) then
            log.info("成功", "快速测试完成")

            -- 最后进行完整分析
            sys.wait(1000)
            if generate_32bit_spectrum(pcm_file, spectrum_file) then
                log.info("完成", "完整频谱分析完成!")

                -- 检查输出文件
                if io.exists(spectrum_file) then
                    local out_size = io.fileSize(spectrum_file)
                    if out_size then
                        log.info("输出", string.format("频谱文件大小: %d 字节", out_size))
                    end
                end
            else
                log.error("失败", "完整频谱分析失败")
            end
        else
            log.error("失败", "快速测试失败")
        end
    else
        log.error("失败", "极简测试失败")
    end

    log.info("程序", "分析流程结束")
    require("tcp_test")
    dtuDemo(1, "112.125.89.8", 32062)
end)

require("test")
