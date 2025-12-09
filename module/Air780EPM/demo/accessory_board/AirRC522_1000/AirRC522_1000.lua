--[[
@module  AirRC522_1000
@summary AirRC522_1000测试功能模块
@version 1.0
@date    2025.07.23
@author  马亚丹
@usage
本demo演示的功能为：使用Air780EPM核心板通过SPI实现对RC522的操作，演示读写数据等操作。
以 Air780EPM核心板为例, 接线如下:
Air780EPM核心板            AirRC522_1000
GND(任意)                    GND
3V3                          3.3V
83/SPI0CS                    SDA
86/SPI0CLK                   SCK
85/SPI0MOSI                  MOSI
84/SPI0MISO                  MISO
19/GPIO22(可选任意空闲IO)     RST

核心逻辑：
1. 初始化并启用spi,如果初始化失败，退出程序
2. 初始化RC522模块,如果初始化失败，退出程序
3. 循环检测卡片。
4. 向卡片指定块号写入数据，并读取数据验证一致性
5. 读取卡片所有数据
]]



rc522 = require "rc522"


-- 硬件配置参数（Air780EPM适配）
local RC522_CONFIG = {
    spi_id = 0,                 -- SPI通道
    cs_pin = 8,                 -- 片选引脚
    rst_pin = 22,               -- 复位引脚
    spi_baud = 2 * 1000 * 1000, -- SPI波特率
}

-- 全局变量（模块内可见）
local spi_dev = nil -- SPI设备对象

-- 1. 初始化SPI接口
local function init_spi()
    log.info("RC522", "初始化SPI接口")
    -- 配置SPI参数：模式0，8位数据，高位在前
    spi_dev = spi.setup(
        RC522_CONFIG.spi_id,
        RC522_CONFIG.cs_pin,
        0,          -- 极性0
        0,          -- 相位0
        8,          -- 数据位
        RC522_CONFIG.spi_baud,
        spi.MSB,    -- 高位优先
        spi.master, --主模式
        spi.half    --半双工
    )

    if not spi_dev then
        log.error("RC522", "SPI初始化失败")
        return false
    end
    log.info("RC522", "SPI初始化成功")
    return true
end

-- 2. 初始化RC522模块
local function init_rc522()
    log.info("RC522", "初始化RC522传感器")
    -- 初始化RC522硬件（SPI ID、CS引脚、RST引脚）
    local init_ok = rc522.init(
        RC522_CONFIG.spi_id,
        RC522_CONFIG.cs_pin,
        RC522_CONFIG.rst_pin
    )

    if not init_ok then
        log.error("RC522", "传感器初始化失败")
        return false
    end
    log.info("RC522", "传感器初始化成功")
    return true
end

-- 3. 写数据
local function write_ic_card(block, data)
    -- 步骤1：验证数据长度
    if #data > 16 then
        log.error("RC522", "数据过长（最大16字节）")
        return false
    end

    -- 步骤2：写入数据块
    local write_ok = rc522.write_datablock(block, data)
    if not write_ok then
        log.error("RC522", "数据写入失败，块号:", block)
        return false
    end

    log.info("RC522", "数据写入成功，块号:", block, "写入数据是：", string.char(table.unpack(data)):toHex())
    return true
end

-- 4. 检测并读取IC卡数据
local function read_ic_card()
    -- 检测是否有卡片靠近
    local status, array_id = rc522.request(rc522.reqall)
    if not status then
        log.info("RC522", "未检测到卡片")
        return false
    end
    log.info("RC522", "检测到卡片，类型：", array_id:toHex())

    -- 防冲突检测,获取卡片唯一ID
    local status, card_uid = rc522.anticoll(array_id)
    if not status then
        log.error("RC522", "防冲突检测失败")
        return false
    end
    log.info("RC522", "卡片UID：", card_uid:toHex())

    -- -- 选择卡片,激活卡片进行后续操作
    local select_ok = rc522.select(card_uid)
    if not select_ok then
        log.error("RC522", "卡片选择失败")
        return false
    end

    -- 写数据测试
    local TEST_BLOCK = 9
    -- 待写入的数据
    local TEST_DATA = { 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }
    if write_ic_card(TEST_BLOCK, TEST_DATA) then
        -- 读数据验证
        local read_ok, read_data = rc522.read_datablock(TEST_BLOCK)

        if read_ok and read_data == string.char(table.unpack(TEST_DATA)) then
            log.info("RC522", "写入验证成功，数据是:", read_data:toHex())
        else
            log.warn("RC522", "写入验证失败，实际读取的数据是:", read_data:toHex())
        end
    end

    -- 读取卡片数据块（0-63块）
    log.info("RC522", "开始读取卡片数据...")
    for block = 0, 63 do
        local read_ok, data = rc522.read_datablock(block)
        if read_ok and data then
            log.info(string.format("块[%d]", block), data:toHex())
        else
            log.warn(string.format("块[%d]读取失败", block))
        end
        --每读取完一个块等待20ms(时间可按需修改)
        sys.wait(20)
    end

    -- 停止卡片操作
    rc522.halt()
    return true
end
-- 5. 关闭SPI设备，成功返回0
local function spi_close_func()
    log.info("关闭spi", spi.close(RC522_CONFIG.spi_id))
end

-- 6. 主测试任务
local function rc522_main_test()
    -- 初始化硬件
    if not init_spi() then
        spi_close_func()
        return
    end
    if not init_rc522() then
        spi_close_func()
        return
    end

    -- 循环检测卡片
    log.info("RC522", "开始检测卡片")
    while true do
        read_ic_card()
        -- 循环检测间隔：2s
        sys.wait(2000)
    end
end

-- 启动主任务
sys.taskInit(rc522_main_test)
