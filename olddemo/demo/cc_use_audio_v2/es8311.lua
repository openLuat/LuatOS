--[[
    ES8311 音频编解码器 (Audio Codec) 驱动
    适用于 LuatOS 平台，通过 I2C 接口控制 ES8311 芯片
    支持的功能：初始化、采样率配置、音量控制、静音、电源管理等
    寄存器地址参考 ES8311 datasheet
]]

local es8311 = {}

-- MCLK 分频系数表
-- 每条记录对应一组 (MCLK频率, 采样率) 的寄存器配置参数
-- 字段顺序：mclk(主时钟Hz), rate(采样率Hz), preDiv(预分频), preMulti(预倍频),
--           adcDiv(ADC分频), dacDiv(DAC分频), fsMode(帧同步模式),
--           lrch(LR通道), lrcl(LR时钟), bclkDiv(位时钟分频),
--           adcOsr(ADC过采样率), dacOsr(DAC过采样率)
local codec_div_tbl = {
    { 12288000, 8000,  0x06, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 18432000, 8000,  0x03, 0x02, 0x03, 0x03, 0x00, 0x05, 0xFF, 0x18, 0x10, 0x20 },
    { 16384000, 8000,  0x08, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 8192000,  8000,  0x04, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 6144000,  8000,  0x03, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 4096000,  8000,  0x02, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 3072000,  8000,  0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 2048000,  8000,  0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 1536000,  8000,  0x03, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 1024000,  8000,  0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 12288000, 16000, 0x03, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 18432000, 16000, 0x03, 0x02, 0x03, 0x03, 0x00, 0x02, 0xFF, 0x0C, 0x10, 0x20 },
    { 16384000, 16000, 0x04, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 8192000,  16000, 0x02, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 6144000,  16000, 0x03, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 4096000,  16000, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 3072000,  16000, 0x03, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 2048000,  16000, 0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 1536000,  16000, 0x03, 0x08, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 1024000,  16000, 0x01, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x20 },
    { 11289600, 22050, 0x02, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 5644800,  22050, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 2822400,  22050, 0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 1411200,  22050, 0x01, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 12288000, 32000, 0x03, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 18432000, 32000, 0x03, 0x04, 0x03, 0x03, 0x00, 0x02, 0xFF, 0x0C, 0x10, 0x10 },
    { 16384000, 32000, 0x02, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 8192000,  32000, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 6144000,  32000, 0x03, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 4096000,  32000, 0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 3072000,  32000, 0x03, 0x08, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 2048000,  32000, 0x01, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 1536000,  32000, 0x03, 0x08, 0x01, 0x01, 0x01, 0x00, 0x7F, 0x02, 0x10, 0x10 },
    { 1024000,  32000, 0x01, 0x08, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 11289600, 44100, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 5644800,  44100, 0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 2822400,  44100, 0x01, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 1411200,  44100, 0x01, 0x08, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 12288000, 48000, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 18432000, 48000, 0x03, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 6144000,  48000, 0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 3072000,  48000, 0x01, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 1536000,  48000, 0x01, 0x08, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 12288000, 96000, 0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 18432000, 96000, 0x03, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 6144000,  96000, 0x01, 0x04, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 3072000,  96000, 0x01, 0x08, 0x01, 0x01, 0x00, 0x00, 0xFF, 0x04, 0x10, 0x10 },
    { 1536000,  96000, 0x01, 0x08, 0x01, 0x01, 0x01, 0x00, 0x7F, 0x02, 0x10, 0x10 },
}

-- 根据 MCLK 主时钟频率和采样率查找对应的分频系数配置
-- @param mclk 主时钟频率 (Hz)
-- @param rate 目标采样率 (Hz)
-- @return 匹配的分频系数表项，未找到则返回 nil
local function get_coeff(mclk, rate)
    for _, v in ipairs(codec_div_tbl) do
        if v[2] == rate and v[1] == mclk then
            return v
        end
    end
    return nil
end

-- I2C 写寄存器
-- @param i2c_id I2C 总线 ID
-- @param reg_addr 寄存器地址
-- @param data 要写入的数据 (单字节)
local function write_reg(i2c_id, reg_addr, data)
    local result,read_data
    result = i2c.send(i2c_id, 0x18, string.char(reg_addr, data)) -- ES8311 I2C 器件地址为 0x18
    if result then
        read_data = i2c.readReg(i2c_id, 0x18, reg_addr, 1)
        if read_data and #read_data > 0 then
            read_data = string.byte(read_data, 1)
            if data ~= read_data then
                log.error("es8311 write_reg failed reg_addr", reg_addr, "read data", read_data, "write data", data)
            end
        end
    else
        log.error("es8311 write_reg failed")
    end

end

-- I2C 读寄存器
-- @param i2c_id I2C 总线 ID
-- @param reg_addr 寄存器地址
-- @return 读取到的寄存器值 (单字节)，失败返回 0
local function read_reg(i2c_id, reg_addr)
    local data = i2c.readReg(i2c_id, 0x18, reg_addr, 1) -- ES8311 I2C 器件地址为 0x18
    if data and #data > 0 then
        return string.byte(data, 1)
    end
    return 0
end

-- 复位 ES8311 芯片
-- 写寄存器 0x00 bit[7]=1 进入复位状态，然后清除复位位并启动
-- @param i2c_id I2C 总线 ID
local function es8311_reset(i2c_id)
    write_reg(i2c_id, 0x00, 0x1F) -- 设置时钟和复位控制
    write_reg(i2c_id, 0x00, 0x80) -- 退出复位 (bit[7]=1)
    write_reg(i2c_id, 0x0D, 0x01) -- 启动主时钟
end

-- 设置 DAC 静音
-- 寄存器 0x31 bit[5] 控制 DAC 静音 (1=静音, 0=正常)
-- @param i2c_id I2C 总线 ID
-- @param enable true=静音, false/ni=取消静音
function es8311.set_mute(i2c_id, enable)
    write_reg(i2c_id, 0x31, enable and 0x20 or 0x00)
end

-- 获取当前静音状态
-- @param i2c_id I2C 总线 ID
-- @return 1=已静音, 0=未静音
function es8311.get_mute(i2c_id)
    local reg = read_reg(i2c_id, 0x31)
    return ((reg & 0x20) ~= 0 and 1 or 0)
end

-- 设置 DAC 音量 (0~100)
-- 内部将 0~100 百分比映射到寄存器 0~255 数值范围
-- @param i2c_id I2C 总线 ID
-- @param vol 音量 0~100 (超过 100 不生效)
function es8311.set_voice_vol(i2c_id, vol)
    if vol > 100 then return end
    write_reg(i2c_id, 0x32, vol * 2550 // 1000)
end

-- 获取当前 DAC 音量百分比
-- @param i2c_id I2C 总线 ID
-- @return 音量百分比 0~100
function es8311.get_voice_vol(i2c_id)
    local reg = read_reg(i2c_id, 0x32)
    return reg * 1000 // 2550
end

-- 设置 MIC 增益 (0~100)
-- 内部将 0~100 百分比映射到寄存器 0~255 数值范围
-- @param i2c_id I2C 总线 ID
-- @param vol 音量 0~100 (超过 100 不生效)
function es8311.set_mic_vol(i2c_id, vol)
    if vol > 100 then return end
    write_reg(i2c_id, 0x17, vol * 2550 // 1000)
end

-- 获取当前 MIC 增益百分比
-- @param i2c_id I2C 总线 ID
-- @return 增益百分比 0~100
function es8311.get_mic_vol(i2c_id)
    local reg = read_reg(i2c_id, 0x17)
    return reg * 1000 // 2550
end

-- 设置 I2S 音频数据格式 (I2S格式)
-- 清除寄存器 0x09(DAC) 和 0x0A(ADC) 的 format 位 (bit[1:0]=00)
-- @param i2c_id I2C 总线 ID
function es8311.set_format(i2c_id)
    local dac = read_reg(i2c_id, 0x09)
    local adc = read_reg(i2c_id, 0x0A)
    dac = dac & ~0x03 -- 清除 DAC 格式位
    adc = adc & ~0x03 -- 清除 ADC 格式位
    write_reg(i2c_id, 0x09, dac)
    write_reg(i2c_id, 0x0A, adc)
end

-- 配置采样率
-- 根据采样率和 MCLK 分频系数从 codec_div_tbl 查找对应的寄存器配置
-- 涉及寄存器 0x02(主时钟控制), 0x05(ADC/DAC分频), 0x03(ADC控制),
--           0x04(DAC控制), 0x07(LRCLK), 0x08(BCLK分频), 0x06(DAC过采样)
-- @param i2c_id I2C 总线 ID
-- @param sample_rate 目标采样率 (Hz)，如 8000, 16000, 44100, 48000 等
-- @param mclk_div MCLK 与采样率的倍频系数 (MCLK = sample_rate * mclk_div)
-- @return true=成功, false=失败 (无匹配的分频配置)
function es8311.set_sample_rate(i2c_id, sample_rate, mclk_div)
    local mclk = sample_rate * mclk_div
    local coeff = get_coeff(mclk, sample_rate)
    if not coeff then
        log.error("es8311", "Unable to configure sample rate %dHz with %dHz MCLK", sample_rate, mclk)
        return false
    end
    -- 寄存器 0x02: 预分频系数 (bit[7:5]) 和 预倍频系数 (bit[4:3])
    local reg = read_reg(i2c_id, 0x02) & ~0xF0
    reg = reg | ((coeff[3] - 1) << 5)

    local datmp = 0
    if coeff[4] == 2 then datmp = 1
    elseif coeff[4] == 4 then datmp = 2
    elseif coeff[4] == 8 then datmp = 3
    end
    reg = reg | (datmp << 3)
    write_reg(i2c_id, 0x02, reg)

    -- 寄存器 0x05: ADC/DAC 分频系数
    reg = ((coeff[5] - 1) << 4) | (coeff[6] - 1)
    write_reg(i2c_id, 0x05, reg)

    -- 寄存器 0x03: ADC 帧同步模式和过采样率
    reg = read_reg(i2c_id, 0x03) & 0x80
    reg = reg | (coeff[7] << 6) | coeff[11]
    write_reg(i2c_id, 0x03, reg)

    -- 寄存器 0x04: DAC 过采样率
    reg = read_reg(i2c_id, 0x04) & 0x80
    reg = reg | (coeff[12])
    write_reg(i2c_id, 0x04, reg)

    -- 寄存器 0x07: LRCLK 分频 (左右通道时钟)

    reg = read_reg(i2c_id, 0x07) & 0xC0
    reg = reg | (coeff[8])
    write_reg(i2c_id, 0x07, reg)

    -- 寄存器 0x08: BCLK 分频 (位时钟)
    reg = coeff[9]
    write_reg(i2c_id, 0x08, reg)

    -- 寄存器 0x06: DAC 过采样率微调
    reg = read_reg(i2c_id, 0x06) & 0xE0
    if coeff[10] < 19 then
        reg = reg | (coeff[10] - 1)
    else
        reg = reg | (coeff[10])
    end
    write_reg(i2c_id, 0x06, reg)

    return true
end

-- 设置音频数据位宽
-- 支持 16/18/20/24/32 位，配置 DAC(0x09) 和 ADC(0x0A) 的 WL 位 (bit[4:2])
-- @param i2c_id I2C 总线 ID
-- @param samplebits 数据位宽 (16, 18, 20, 24, 32)
-- @return true=成功, false=不支持该位宽
function es8311.set_data_bits(i2c_id, samplebits)
    local wl_map = { [16] = 3, [18] = 2, [20] = 1, [24] = 0, [32] = 4 }
    local wl = wl_map[samplebits]
    if not wl then return false end

    local dac = read_reg(i2c_id, 0x09)
    local adc = read_reg(i2c_id, 0x0A)
    dac = dac & ~0x1C -- 清除 DAC 位宽位
    dac = dac | (wl << 2)
    adc = adc & ~0x1C -- 清除 ADC 位宽位
    adc = adc | (wl << 2)
    write_reg(i2c_id, 0x09, dac)
    write_reg(i2c_id, 0x0A, adc)
    return true
end


-- 初始化 ES8311 音频编解码器
-- 检查芯片 ID (0xFD=0x83, 0xFE=0x11), 执行复位和完整的寄存器初始化序列
-- @param i2c_id I2C 总线 ID
-- @param voltage 电源电压选择: 0x00=3.3V, 0x01=1.8V, 默认为 3.3V
-- @return true=初始化成功, false=芯片ID校验失败
function es8311.init(i2c_id, voltage)
    if voltage == nil then voltage = 0x00 end   -- voltage = 0x00 3.3v, 0x01 1.8V
	write_reg(i2c_id, 0x44, 0x08)
	write_reg(i2c_id, 0x44, 0x08)
	write_reg(i2c_id, 0x10, 0x61)
    -- 读取芯片 ID 进行校验 (寄存器 0xFD=CHIP_ID1, 0xFE=CHIP_ID2, 0xFF=CHIP_VER)
    local temp1 = read_reg(i2c_id, 0xFD)
    local temp2 = read_reg(i2c_id, 0xFE)
    local temp3 = read_reg(i2c_id, 0xFF)
    if temp1 ~= 0x83 or temp2 ~= 0x11 then
        log.error("es8311", string.format("codec err, id = 0x%02X 0x%02X ver = 0x%02X", temp1, temp2, temp3))
        return false
    end
    log.info("es8311", "init voltage", voltage)
    es8311_reset(i2c_id)

    -- 寄存器 0x45: GPIO 输出使能
    write_reg(i2c_id, 0x45, 0x00)
    -- 寄存器 0x01: 系统时钟控制，主时钟使能
    write_reg(i2c_id, 0x01, 0x30)

    -- 寄存器 0x09, 0x0A: 清除主控模式位 (bit[6]=0, 从机模式)
    local reg09 = read_reg(i2c_id, 0x09)
    write_reg(i2c_id, 0x09, reg09 & ~0x40)
    local reg0a = read_reg(i2c_id, 0x0A)
    write_reg(i2c_id, 0x0A, reg0a & ~0x40)

    -- 寄存器 0x0B: GPIO1 配置, 0x0C: GPIO2 配置
    write_reg(i2c_id, 0x0B, 0x00)
    write_reg(i2c_id, 0x0C, 0x00)
    -- 寄存器 0x10: 模拟参考电压配置 (根据电压参数调整偏置)
    write_reg(i2c_id, 0x10, (0x60 * voltage) + 0x03)
    -- 寄存器 0x11: 模拟输入 PGA 增益，设为最大 +24dB
    write_reg(i2c_id, 0x11, 0x7F)

    -- 寄存器 0x01: 使能所有时钟模块
    write_reg(i2c_id, 0x01, 0x3F)

    -- 寄存器 0x00: 退出复位，启动芯片
    write_reg(i2c_id, 0x00, 0x80 + (0 << 6))
    write_reg(i2c_id, 0x0D, 0x01)

    -- 寄存器 0x14: 模拟系统控制 2
    write_reg(i2c_id, 0x14, 0x18)
    -- 寄存器 0x12: 模拟系统控制 1
    write_reg(i2c_id, 0x12, 0x28)
    -- 寄存器 0x13: 模拟系统控制 0
    write_reg(i2c_id, 0x13, 0x00)

    -- 寄存器 0x0E: 模拟输出选择 (DAC 输出使能)
    write_reg(i2c_id, 0x0E, 0x02)
    -- 寄存器 0x0F: 模拟输入选择
    write_reg(i2c_id, 0x0F, 0x44)
    -- 寄存器 0x15: 模拟偏置控制
    write_reg(i2c_id, 0x15, 0x00)
    -- 寄存器 0x1B: ADC 数字音量控制 (0dB)
    write_reg(i2c_id, 0x1B, 0x0A)
    -- 寄存器 0x1C: ADC 自动增益控制 (AGC)
    write_reg(i2c_id, 0x1C, 0x6A)
    -- 寄存器 0x37: 电荷泵设置
    write_reg(i2c_id, 0x37, 0x08)

    return true
end

-- 从待机或低功耗状态恢复 ES8311
-- 重新使能时钟、退出复位、恢复 DAC/ADC 输出通路
-- @param i2c_id I2C 总线 ID
function es8311.resume(i2c_id)
    write_reg(i2c_id, 0x0D, 0x01) -- 启动主时钟
    write_reg(i2c_id, 0x45, 0x00) -- GPIO 输出使能关闭
    write_reg(i2c_id, 0x01, 0x3F) -- 使能所有时钟模块
    write_reg(i2c_id, 0x00, 0x80) -- 退出复位
    write_reg(i2c_id, 0x0D, 0x01) -- 再次启动主时钟
    --write_reg(i2c_id, 0x02, 0x00) -- 主时钟控制恢复默认
    write_reg(i2c_id, 0x37, 0x08) -- 电荷泵恢复
    write_reg(i2c_id, 0x15, 0x40) -- 模拟偏置使能
    write_reg(i2c_id, 0x12, 0x00) -- 模拟系统控制 1 清零
    write_reg(i2c_id, 0x14, 0x18) -- 模拟系统控制 2 恢复
    write_reg(i2c_id, 0x0E, 0x00) -- 模拟输出选择清零
end

-- 进入待机模式 (低功耗，保留寄存器状态)
-- 关闭模拟输出、DAC/ADC，降低功耗
-- @param i2c_id I2C 总线 ID
function es8311.standby(i2c_id)
    write_reg(i2c_id, 0x32, 0x00) -- DAC 音量清零
    write_reg(i2c_id, 0x17, 0x00) -- MIC 增益清零
    write_reg(i2c_id, 0x0E, 0xFF) -- 关闭模拟输出
    write_reg(i2c_id, 0x12, 0x02) -- 模拟系统控制 1 低功耗
    write_reg(i2c_id, 0x14, 0x00) -- 模拟系统控制 2 关闭
    write_reg(i2c_id, 0x0D, 0xFA) -- 关闭部分时钟模块
    write_reg(i2c_id, 0x15, 0x00) -- 模拟偏置关闭
    write_reg(i2c_id, 0x37, 0x08) -- 电荷泵保持
    write_reg(i2c_id, 0x02, 0x10) -- 主时钟进入低功耗分频
    write_reg(i2c_id, 0x00, 0x00) -- 复位
    write_reg(i2c_id, 0x00, 0x1F) -- 保持复位状态
    write_reg(i2c_id, 0x01, 0x30) -- 仅保留主时钟
    write_reg(i2c_id, 0x01, 0x00) -- 关闭所有时钟
    write_reg(i2c_id, 0x45, 0x01) -- GPIO 输出使能
end

-- 完全关闭 ES8311 电源
-- 相比 standby 更彻底地断电，寄存器状态会丢失
-- @param i2c_id I2C 总线 ID
function es8311.power_down(i2c_id)
    write_reg(i2c_id, 0x32, 0x00) -- DAC 音量清零
    write_reg(i2c_id, 0x17, 0x00) -- MIC 增益清零
    write_reg(i2c_id, 0x0E, 0xFF) -- 关闭模拟输出
    write_reg(i2c_id, 0x12, 0x02) -- 模拟系统控制 1 低功耗
    write_reg(i2c_id, 0x14, 0x00) -- 模拟系统控制 2 关闭
    write_reg(i2c_id, 0x0D, 0xF9) -- 关闭所有时钟模块 (比 standby 多关一位)
    write_reg(i2c_id, 0x15, 0x00) -- 模拟偏置关闭
    write_reg(i2c_id, 0x37, 0x08) -- 电荷泵保持
    write_reg(i2c_id, 0x02, 0x10) -- 主时钟进入低功耗分频
    write_reg(i2c_id, 0x00, 0x00) -- 复位
    write_reg(i2c_id, 0x00, 0x1F) -- 保持复位状态
    write_reg(i2c_id, 0x01, 0x30) -- 仅保留主时钟
    write_reg(i2c_id, 0x01, 0x00) -- 关闭所有时钟
    write_reg(i2c_id, 0x45, 0x00) -- GPIO 输出关闭 (区别于 standby 的 0x01)
    write_reg(i2c_id, 0x0D, 0xFC) -- 进一步关闭时钟
    write_reg(i2c_id, 0x02, 0x00) -- 主时钟控制完全关闭
end

return es8311
