--[[
@module  raw_spi
@summary raw_spi测试功能模块
@version 1.0
@date    2025.11.03
@author  马亚丹
@usage
本demo演示的功能为：使用Air780EHM/EHV/EGH核心板通过SPI库原始SPI接口实现对 NAND Flash(W25N01GV)的操作，演示读数据写数据等操作。
以 Air780EHM/EHV/EGH核心板为例, 接线如下:
Air780EHM/EHV/EGH       AirSPINAND_1000配件版
GND(任意)          GND
VDD_EXT            VCC
GPIO8/SPI0_CS     CS,片选
SPI0_SLK           CLK,时钟
SPI0_MOSI          DI,主机输出,从机输入
SPI0_MISO          DO,主机输入,从机输出

--使用SPI0，硬件SPI CS接在gpio8上

核心逻辑：
1.初始化并启用spi,如果初始化失败，退出程序
2.spi启用后读取并验证nand flash芯片ID,如果验证失败，退出程序
3.验证nand flash芯片后读取寄存器状态，确认芯片就绪
4.验证是否是坏块，非坏块进行擦除块区，为写入数据做准备
5.擦除块区后，写数据到块区，并读取块区数据与写入数据进行验证
6.关闭写使能并关闭SPI。

]]
-- SPI配置参数
local SPI_ID = 0                   -- SPI总线ID，根据实际情况修改
local CS_PIN = 8                  -- CS引脚，根据实际情况修改
local CPHA = 0                     -- 时钟相位
local CPOL = 0                     -- 时钟极性
local data_Width = 8               -- 数据宽度(位)
local bandrate = 2*1000*1000           -- 波特率(Hz)，初始化为2MHz
local timeout = 1000               -- 操作超时时间(ms)
local cspin = gpio.setup(CS_PIN, 1) --CS脚置于高电平
spi_device = nil


-- 1. 定义功能函数：发送和接收数据
local function spi_transfer_func(sendData, recvLen)
    -- 选中设备
    cspin(0)

    if sendData then
        local sendLen = #sendData
        -- 发送数据
        spi_device:send(sendData, sendLen)
    end

    local recvData = ""
    if recvLen and recvLen > 0 then
        -- 接收数据
        recvData = spi_device:recv(recvLen)
    end

    -- 取消选中
    cspin(1)
    return recvData
end
--2. 定义功能函数： 读状态寄存器（指令0x0F）
local function spi_readStatus_func()
    -- 发送0x0F指令（1字节），接收1字节状态
    local status = spi_transfer_func(string.char(0x0F), 1)
    return status and status:byte(1) or 0
end

-- 3. 定义功能函数：初始化SPI并复位芯片
local function spiDev_init_func()
    log.info("W25N01GV", "初始化SPI1...")
    spi_device = spi.deviceSetup(SPI_ID, nil, CPHA, CPOL, data_Width, bandrate,
        spi.MSB,    --高低位顺序    可选，默认高位在前
    spi.master,     --主模式        可选，默认主
        spi.half    --半双工        spi flash只支持半双工
    )
    if not spi_device then
        log.error("SPI初始化失败")
        return false
    end

    return spi_device
end

--4. 定义功能函数：读取并验证芯片的JEDEC ID
local function spi_readChipId_func()
    -- 读ID指令0x9F，发送2字节指令，接收3字节ID
    -- 发送长度=2（0x9F,0x00），接收长度=3
    local id = spi_transfer_func(string.char(0x9F, 0x00), 3)
    if #id ~= 3 then
        log.error("读ID失败，返回长度：", #id)
        return false
    end
    local b1, b2, b3 = id:byte(1, 3)
    log.info("芯片ID:", string.format("0x%02X 0x%02X 0x%02X", b1, b2, b3))
    -- W25N01GV的标准ID：0xEF（厂商）、0xAA（设备）、0x21（容量）
    if b1 == 0xEF and b2 == 0xAA and b3 == 0x21 then
        return true
    else
        log.error("非W25N01GV芯片")
        return false
    end
end



--5. 定义功能函数：等待写入完成
local function spi_waitForComplete_func()
    while timeout > 0 do
        local status = spi_readStatus_func()
        -- WIP位为0表示写入完成
        if bit.band(status, 0x01) == 0 then
            return true
        end
        sys.wait(10)
        timeout = timeout - 10
    end

    log.error("spi", "等待写入超时")
    return false
end

--6. 定义功能函数：读取数据
local function spi_read_page(page_addr, length, column_addr)
    local is_column_provided = column_addr ~= nil
    column_addr = column_addr or 0x00
    if length <= 0 or length > 2048 then
        log.error("读取长度无效")
        return ""
    end
    -- 0x03指令+4字节地址（3字节页地址+1字节列地址偏移）
    local cmd = string.char(0x03)
        .. string.char(bit.rshift(page_addr, 16) & 0xFF) -- 页地址高8位
        .. string.char(bit.rshift(page_addr, 8) & 0xFF)  -- 页地址中8位
        .. string.char(page_addr & 0xFF)                 -- 页地址低8位
        .. string.char(column_addr & 0xFF)               -- 列地址偏移（页内起始字节）
    local data = spi_transfer_func(cmd, length)
    if is_column_provided then
        log.info("读取主阵列（偏移0x" .. string.format("%02X", column_addr) .. "）", "读到的数据", string.toHex(data), "长度", #data)
    else
        log.info("读到的数据", string.toHex(data), "长度", #data)
    end
    return data
end

-- 7. 定义功能函数：：读取页的数据区+OOB区（指令0x51），用于判断是否是坏块
local function spi_read_page_with_oob(page_addr, data_len, oob_len)
    if data_len < 0 or data_len > 2048 or oob_len < 0 or oob_len > 64 then
        log.error("读取长度无效")
        return "", ""
    end
    -- 0x51指令：读取数据+OOB
    local cmd = string.char(0x51)
        .. string.char(bit.rshift(page_addr, 16) & 0xFF)
        .. string.char(bit.rshift(page_addr, 8) & 0xFF)
        .. string.char(page_addr & 0xFF)
    -- 总读取长度：数据区+OOB区
    local total_data = spi_transfer_func(cmd, data_len + oob_len)
    local data = total_data:sub(1, data_len)
    local oob = total_data:sub(data_len + 1, data_len + oob_len)
    return data, oob
end

-- 8. 定义功能函数：判断是否是坏块
local function is_bad_block(block_addr)
    -- 手册规定：块0~7出厂保证为有效块，可直接跳过检测
    if block_addr >= 0 and block_addr <= 7 then
        log.debug("块", block_addr, "是出厂保证有效块，直接判定为好块")
        return false
    end

    -- 块的第0页
    local page_addr = block_addr * 64
    -- 读取主阵列第1字节（偏移0x01）
    local main_data = spi_read_page(page_addr, 1, 0x01)
    -- 读取OOB区前2字节
    local _, oob = spi_read_page_with_oob(page_addr, 0, 2)

    -- 检测主阵列第1字节是否为0xFF
    local main_bad = false
    if #main_data >= 1 and main_data:byte(1) ~= 0xFF then
        main_bad = true
    end

    -- 检测OOB区前2字节是否为0xFF
    local oob_bad = false
    if #oob >= 2 and (oob:byte(1) ~= 0xFF or oob:byte(2) ~= 0xFF) then
        oob_bad = true
    end

    -- 主阵列第1字节和OOB区前2字节,任一非0xFF则判定为坏块
    local is_bad = main_bad or oob_bad
    log.debug("块", block_addr,
        "主阵列第1字节：0x" .. string.format("%02X", main_data:byte(1) or 0x00),
        "OOB前2字节：0x" .. string.format("%02X, 0x%02X", oob:byte(1) or 0x00, oob:byte(2) or 0x00),
        "判定为" .. (is_bad and "坏块" or "好块"))
    return is_bad
end


-- 9. 定义功能函数： 块擦除（指令0xD8）
local function spi_erase_block(block_addr)
    if is_bad_block(block_addr) then
        log.error("块", block_addr, "是坏块，跳过擦除")
        return false
    end
    -- 写使能
    spi_transfer_func(string.char(0x06))
    local cmd = string.char(0xD8)
        .. string.char(bit.rshift(block_addr, 16) & 0xFF)
        .. string.char(bit.rshift(block_addr, 8) & 0xFF)
        .. string.char(block_addr & 0xFF)
    spi_transfer_func(cmd)
    -- 确保等待擦除完成
    if not spi_waitForComplete_func() then
        log.error("擦除未完成")
        return false
    end
    return true
end

-- 10. 定义功能函数： 页写入
local function spi_write_page(page_addr, data)
    if #data > 2048 then
        log.error("数据超过页大小2048字节")
        return false
    end
    -- 写使能
    spi_transfer_func(string.char(0x06))

    -- 加载缓冲区（0x02指令）
    local cmd_load = string.char(0x02)
        .. string.char(bit.rshift(page_addr, 16) & 0xFF)
        .. string.char(bit.rshift(page_addr, 8) & 0xFF)
        .. string.char(page_addr & 0xFF)
    spi_transfer_func(cmd_load .. data)

    -- 执行编程（0x10指令）
    local cmd_exec = string.char(0x10)
        .. string.char(bit.rshift(page_addr, 16) & 0xFF)
        .. string.char(bit.rshift(page_addr, 8) & 0xFF)
        .. string.char(page_addr & 0xFF)
    spi_transfer_func(cmd_exec)
    return spi_waitForComplete_func()
end

-- 11. 定义功能函数：核心测试函数
local function spi_test_func()
    --spi初始化
    spi_device = spiDev_init_func()
    if not spi_device then
        return
    end
    --读取芯片id
    if not spi_readChipId_func() then
        spi.close(spi_device)
        return
    end
    --坏块检查并进行块擦除，test_block是定义的操作的块编码
    --手册规定：块0~7出厂保证为有效块，可直接跳过检测。块取值0~1023
    local test_block = 7
    log.info("擦除块", test_block, "...")
    if not spi_erase_block(test_block) then
        spi.close(spi_device)
        return
    end
    local test_page = test_block * 64
    local test_data = "Hello, W25N01GV!"
    log.info("写入数据", test_data, "到页", test_page, "块", test_block)
    --写数据到指定块
    if not spi_write_page(test_page, test_data) then
        log.info("写入失败")
        spi.close(spi_device)
        return
    end
    --读取当前块写入的数据，并验证与写入是否一致
    local read_data = spi_read_page(test_page, #test_data)
    if read_data == test_data then
        log.info("数据验证成功:", read_data)
    else
        log.error("数据验证失败")
        log.info("预期:", test_data)
        log.info("实际:", string.toHex(read_data))
    end
    --操作完成关闭SPI
    spi.close(spi_device)
end

sys.taskInit(spi_test_func)
