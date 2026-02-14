local adc_tests = {}

-- 仅cpu温度和vbat电压进行自动化测试
-- 单次cpu温度测试:
-- 温度范围：
local MIN_TEMP = -40 -- 最低工作温度
local MAX_TEMP = 85 -- 最高工作温度
-- vabt电压范围：
local MIN_Voltage = 3000 -- 最小电压
local MAX_Voltage = 4300 -- 最大电压

function adc_tests.test_GetCpuThermal_rang()
    local result = adc.open(adc.CH_CPU)
    assert(result == true, "CPU内部温度的通道打开失败")
    local cpu_temp = adc.get(adc.CH_CPU)
    assert(cpu_temp ~= -1, "使用adc.get()读取CPU温度失败")
    local temp_celsius = cpu_temp / 1000

    assert(temp_celsius >= MIN_TEMP and temp_celsius <= MAX_TEMP,
        string.format("CPU温度超限: %.2f °C (允许范围: %d-%d °C)", temp_celsius, MIN_TEMP, MAX_TEMP))
    log.info("✓ 测试通过: 使用adc.get()读取的cpu温度在指定范围内")
end

function adc_tests.test_ReadCpuThermal_rang()
    local result = adc.open(adc.CH_CPU)
    assert(result == true, "CPU内部温度的通道打开失败")
    local result, cpu_temp = adc.read(adc.CH_CPU)
    local temp_celsius = cpu_temp / 1000
    assert(temp_celsius >= MIN_TEMP and temp_celsius <= MAX_TEMP,
        string.format("CPU温度超限: %.2f °C (允许范围: %d-%d °C)", temp_celsius, MIN_TEMP, MAX_TEMP))
    log.info("✓ 测试通过: 使用adc.read()读取的cpu温度在指定范围内")
end

-- 多次CPU温度测试：是否在范围内
function adc_tests.test_GetCpuThermalMultiple_rang()
    -- 配置
    local SAMPLE_COUNT = 10 -- 采样次数
    local SAMPLE_INTERVAL = 100 -- 采样间隔(ms)
    -- 1. 打开通道
    assert(adc.open(adc.CH_CPU), "CPU温度通道打开失败")

    for i = 1, SAMPLE_COUNT do
        local raw = adc.get(adc.CH_CPU)
        assert(raw ~= -1, string.format("第%d次采样失败", i))

        local temp = raw / 1000 -- 转换为℃
        -- 检查范围
        assert(temp >= MIN_TEMP and temp <= MAX_TEMP, string.format("第%d次采样CPU温度超限: %.2f℃", i, temp))

        if i < SAMPLE_COUNT then
            sys.wait(SAMPLE_INTERVAL)
        end
    end
    adc.close(adc.CH_CPU)
    log.info("✓ ：多次CPU温度测试通过,均在指定范围内")
end

-- vbat供电电压测试：
-- 单次vbat供电电压测试：
function adc_tests.test_GetVbatVoltage_rang()
    local result = adc.open(adc.CH_VBAT)
    assert(result == true, "VBAT供电电压的通道打开失败")
    local Vbat_voltage = adc.get(adc.CH_VBAT)
    assert(Vbat_voltage >= MIN_Voltage and Vbat_voltage <= MAX_Voltage,
        string.format("VBAT供电电压超限:(允许范围: %d-%d mV)", Vbat_voltage, MIN_Voltage, MAX_Voltage))
    log.info("✓ 测试通过: 使用adc.read()读取的VBAT供电电压在指定范围内")
end

function adc_tests.test_ReadVbatVoltage_rang()
    local result = adc.open(adc.CH_VBAT)
    assert(result == true, "VBAT供电电压的通道打开失败")
    local result, Vbat_voltage = adc.read(adc.CH_VBAT)
    assert(Vbat_voltage >= MIN_Voltage and Vbat_voltage <= MAX_Voltage,
        string.format("VBAT供电电压超限:(允许范围: %d-%d mV)", Vbat_voltage, MIN_Voltage, MAX_Voltage))
    log.info("✓ 测试通过: 使用adc.get()读取的VBAT供电电压在指定范围内")
end

-- 多次vbat供电电压测试：
function adc_tests.test_GetVbatVoltageMultiple_rang()
    -- 配置
    local SAMPLE_COUNT = 10 -- 采样次数
    local SAMPLE_INTERVAL = 100 -- 采样间隔(ms)
    -- 1. 打开通道
    local result = adc.open(adc.CH_VBAT)
    assert(result == true, "VBAT供电电压的通道打开失败")
    for i = 1, SAMPLE_COUNT do
        local Vbat_voltage = adc.get(adc.CH_VBAT)
        assert(Vbat_voltage ~= -1, string.format("第%d次采样失败", i))
        -- 检查范围
        assert(Vbat_voltage >= MIN_Voltage and Vbat_voltage <= MAX_Voltage,
            string.format("第%d次采样vbat电压超限: %d mV", i, Vbat_voltage))

        if i < SAMPLE_COUNT then
            sys.wait(SAMPLE_INTERVAL)
        end
    end
    adc.close(adc.CH_VBAT)
    log.info("✓ ：多次VBAT供电电压测试通过,均在指定范围内")
end

return adc_tests
