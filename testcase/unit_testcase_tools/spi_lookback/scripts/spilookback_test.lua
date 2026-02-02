local spilookback_test = {}

local device_name = rtos.bsp()

local function spi_configuration()
    if device_name == "Air780EGP" then
        CHIP_TYPE = "718M" -- 可设置为 "718M" 或 "BK7258"
        -- SPI编号，请按实际情况修改！
        spitest_spiId = spi.SPI_0 -- 这里使用SPI 0
        spitest_cs = 8 -- CS使用GPIO3
        spitest_cspin = gpio.setup(spitest_cs, 1) -- 配置CS为输出，初始高电平
    -- elseif device_name == "Air780EPM" then
    --     CHIP_TYPE = "718M" -- 可设置为 "718M" 或 "BK7258"
    --     -- SPI编号，请按实际情况修改！
    --     spitest_spiId = spi.SPI_0 -- 这里使用SPI 0
    --     spitest_cs = 8 -- CS使用GPIO3
    --     spitest_cspin = gpio.setup(spitest_cs, 1) -- 配置CS为输出，初始高电平

    -- elseif device_name == "Air8101" then

    else
        log.info("未知的设备名称")
    end
end

-- 芯片频率表定义
local chipSpeedTables = {
    ["718M"] = {51200000, 43885714, 38400000, 34133333, 30720000, 27927272, 25600000, 23630769, 21942857, 20480000,
                19200000, 18070588, 17066666, 16168421, 15360000, 14628571, 13963636, 13356521, 12800000, 12288000,
                11815384, 11377777, 10971428, 10593103, 10240000, 9909677, 9600000, 9309090, 9035294, 8777142, 8533333,
                8302702, 8084210, 7876923, 7680000, 7492682, 7314285, 7144186, 6981818, 6826666, 6678260, 6536170,
                6400000, 6269387, 6144000, 6023529, 5907692, 5796226, 5688888, 5585454, 5485714, 5389473, 5296551,
                5206779, 5120000, 5036065, 4954838, 4876190, 4800000, 4726153, 4654545, 4585074, 4517647, 4452173,
                4388571, 4326760, 4266666, 4208219, 4151351, 4096000, 4042105, 13000000},
    ["BK7258"] = {49000000, 24500000, 16333333, 12250000, 9800000, 8166666, 7000000, 6125000, 5444444, 4900000, 4454545,
                  4083333}
}

-- 获取当前芯片的频率表
local function getSpeedTable()
    local table = chipSpeedTables[CHIP_TYPE]
    if not table then
        log.error("SPI", "不支持的芯片类型:", CHIP_TYPE)
        log.error("SPI", "支持的芯片类型: 718M, BK7258")
        return {}
    end
    return table
end

-- SPI收发测试函数
local function spiLoopbackTest(speed)
    

    -- 设置SPI参数
    local spi_device = spi.deviceSetup(spitest_spiId, -- SPI ID
    nil, -- CS引脚（手动控制）
    0, -- CPHA
    0, -- CPOL  
    8, -- 数据宽度
    speed, -- 波特率
    -- spi.MSB,    -- 大端序
    spi.LSB, -- 小端序
    spi.master, -- 主模式
    spi.full -- 全双工
    )

    if spi_device then
        log.info("SPI", "设置成功，速率:", speed)
        log.info("SPI", "spi_device :", spi_device)
    else
        log.error("SPI", "设置失败，速率:", speed)
        return false
    end

    -- 根据速率调整测试数据长度
    local dataLength = 1024
    -- if speed < 1000000 then
    --     dataLength = 4  -- 低速时使用较短数据
    --     log.info("SPI 低速", "dataLength :", dataLength)
    -- elseif speed > 20000000 then
    --     dataLength = 10240  -- 高速时使用较长数据
    --     log.info("SPI 高速", "dataLength :", dataLength)
    -- end

    -- 生成测试数据
    local testData = ""
    for i = 1, dataLength do
        testData = testData .. string.char((i * 17) % 256) -- 生成有规律但不重复的数据
    end

    -- log.info("SPI", "准备发送的测试数据:", testData, "数据长度:", #testData)

    -- 执行回环测试
    spitest_cspin(0) -- CS拉低
    local received = spi_device:transfer(testData, #testData, #testData) -- 发送数据 并读取数据

    spitest_cspin(1) -- CS拉高

    -- 关闭SPI
    spi.close(spitest_spiId)

    assert(#received == #testData,
        string.format("spi速率接收数据长度与发送数据长度匹配测试失败: 预期 %s, 实际 %s",
            #testData, #received))
    log.info("spi_test", "SPI速率", speed, "Hz 接收数据长度与发送数据长度匹配测试通过")

    assert(received == testData,
        string.format("spi速率接收数据内容与发送数据内容匹配测试失败: 预期 %s, 实际 %s",
            testData, received))
    log.info("spi_test", "SPI速率", speed, "Hz 接收数据内容与发送数据内容匹配测试通过")

end

-- 自动检测芯片类型（可选功能）
local function autoDetectChip()
    -- 这里可以添加自动检测芯片的逻辑
    -- 例如通过读取芯片ID等方式
    -- 目前返回配置的芯片类型
    return CHIP_TYPE
end

function spilookback_test.test_spi_lookback()
    spi_configuration()
    local detectedChip = autoDetectChip()
    log.info("SPI", "检测到芯片类型:", detectedChip)
    log.info("SPI", "开始SPI速率测试...")
    log.info("SPI", "请确保MISO和MOSI已短接！")

    sys.wait(1000) -- 等待系统稳定

    local speedTable = getSpeedTable()
    if #speedTable == 0 then
        log.error("SPI", "无法获取频率表，测试终止")
        return
    end

    local successCount = 0
    local totalTests = #speedTable

    -- 按速率从高到低排序测试
    table.sort(speedTable, function(a, b)
        return a > b
    end)

    for i, speed in ipairs(speedTable) do
        log.info("SPI", string.format("测试进度: %d/%d", i, totalTests))

        local success = spiLoopbackTest(speed)
        if success then
            successCount = successCount + 1
        end

        sys.wait(1000) -- 短暂延时，避免过于频繁的测试
    end
end

return spilookback_test
