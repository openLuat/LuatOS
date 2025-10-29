--[[
@module  ram_spi
@summary ram_spi测试功能模块
@version 1.0
@date    2025.9.05
@author  马亚丹
@usage
本demo演示的功能为：使用Air780EHV核心板通过SPI库实现对Flash的操作，演示读数据写数据、删除数据等操作。
以 Air780EHV核心板为例, 接线如下:

Air780EHV核心板    AirSPINORFLASH_1000配件版
GND(任意)          GND
VDD_EXT            VCC
GPIO8/SPI0_CS     CS,片选
SPI0_SLK           CLK,时钟
SPI0_MOSI          DI,主机输出,从机输入
SPI0_MISO          DO,主机输入,从机输出

--使用SPI0，硬件SPI CS接在gpio8上

运行核心逻辑：
1.初始化并启用spi,如果初始化失败，退出程序
2.spi启用后读取并验证flash芯片ID,如果验证失败，退出程序
3.验证flash芯片后读取寄存器状态，确认芯片就绪
4.擦除扇区，为写入数据做准备
5.擦除扇区后，写数据到扇区，并读取扇区数据与写入数据进行验证
6.关闭写使能并关闭SPI。

]]


-- SPI配置参数
local SPI_ID = 0                   -- SPI总线ID，根据实际情况修改
local CS_PIN = 8                   -- CS引脚，根据实际情况修改
local CPHA = 0                     -- 时钟相位
local CPOL = 0                     -- 时钟极性
local data_Width = 8               -- 数据宽度(位)
local bandrate = 2000000           -- 波特率(Hz)，初始化为2MHz
local timeout = 500                -- 操作超时时间(ms)
local cspin = gpio.setup(CS_PIN, 1) --CS脚置于高电平


-- 1. 设置并启用 SPI
local function spiDev_init_func()
    log.info("ram_spi", "SPI_ID", SPI_ID, "CS_PIN", CS_PIN)
    local spiDevice = spi.setup(SPI_ID,nil, CPHA,CPOL,data_Width,bandrate
    -- spi.MSB,--高低位顺序    可选，默认高位在前
    -- spi.master,--主模式     可选，默认主
    -- spi.full--全双工       可选，默认全双工
    )

    log.info("硬件spi", "初始化，波特率:", spiDevice, bandrate)
    return true
end


-- 2. 定义功能函数：发送和接收数据
local function spi_transfer_func(sendData, recvLen)
    -- 选中设备
    cspin(0)

    if sendData then
        -- 发送数据
        spi.send(SPI_ID, sendData)
    end

    local recvData = ""
    if recvLen and recvLen > 0 then
        -- 接收数据
        recvData = spi.recv(SPI_ID, recvLen)
    end

    -- 取消选中
    cspin(1)
    return recvData
end

-- 3. 定义功能函数：读取并验证芯片ID
local function spi_readChipId_func()
    --0x9F指令读取JEDEC ID
    local id = spi_transfer_func(string.char(0x9F), 3)
    --读取成功会返回 3 字节（制造商 + 设备 ID）
    if #id == 3 then
        local b1, b2, b3 = id:byte(1, 3)
        log.info("spi", "芯片ID: 0x%02X 0x%02X 0x%02X", b1, b2, b3)

        -- 验证是否为W25Q系列：
        --制造商 ID（第 1 字节）： 0xEF（代表 Winbond）
        -- 设备类型（第 2 字节）： 0x40（表示 W25Q 系列 NOR Flash）
        -- 容量代码（第 3 字节）： 0x18（对应 128Mbit = 16MB 容量）
        if b1 == 0xEF and (b2 == 0x40 or b2 == 0x18) then
            return true
        end
    end

    log.error("spi", "读取芯片ID失败")
    return false
end

-- 4. 定义功能函数：写数据使能
local function spi_writeEnable_func()
    --0x06指令设置Write Enable
    spi_transfer_func(string.char(0x06))
    return 0
end

-- 5. 定义功能函数：写数据禁用
local function spi_writeDisable_func()
    --0x04指令设置Write Disable
    spi_transfer_func(string.char(0x04))
end

-- 6. 定义功能函数：读取状态寄存器
local function spi_readStatus_func()
    --0x05指令读取寄存器状态
    local status = spi_transfer_func(string.char(0x05), 1)
    if #status == 1 then
        --返回0 表示WIP=0芯片就绪且未使能写操作
        return status:byte(1)
    end
end


--7.  等待写入完成
local function spi_waitForWriteComplete_func()
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

--8. 扇区擦除，根据需要修改
-- 0x20：扇区擦除（4KB）
-- 0xD8：块擦除（64KB）
-- 0xC7：整片擦除
--address是要擦除的扇区的起始地址，本demo演示扇区擦除，块擦除和整片擦除可自行研究
local function spi_erase_sector(address)
    -- 使能写操作
    if not spi_writeEnable_func() then
        log.error("SPI", "写使能失败")
        return false
    end
    -- 发送扇区擦除指令
    local result = spi_transfer_func(string.char(0x20) ..
        string.char(bit.rshift(address, 16) & 0xFF) ..
        string.char(bit.rshift(address, 8) & 0xFF) ..
        string.char(address & 0xFF))
    if not result then
        log.error("SPI", "发送扇区擦除指令失败")
        return false
    end
    -- 等待写入完成
    return spi_waitForWriteComplete_func()
end

--9. 页编程(写入数据到指定地址)
local function spi_pageProgram_func(address, data)
    -- 检查数据长度(不能超过256字节)
    local len = #data
    if len == 0 or len > 256 then
        log.error("spi", "数据长度无效:", len)
        return false
    end
    -- 准备写入命令和地址
    local cmd = string.char(0x02) ..
        string.char(bit.rshift(address, 16) & 0xFF) ..
        string.char(bit.rshift(address, 8) & 0xFF) ..
        string.char(address & 0xFF)
    -- 写数据使能
    spi_writeEnable_func()
    -- 发送写命令和数据
    spi_transfer_func(cmd .. data)
    -- 等待写入完成
    return spi_waitForWriteComplete_func()
end

-- 10. 读取数据
local function spi_readData_func(address, length)
    if length <= 0 then
        return ""
    end
    -- 准备读取命令和地址
    local cmd = string.char(0x03) ..
        string.char(bit.rshift(address, 16) & 0xFF) ..
        string.char(bit.rshift(address, 8) & 0xFF) ..
        string.char(address & 0xFF)
    -- 发送读取命令并接收数据
    return spi_transfer_func(cmd, length)
end


-- 11. 关闭SPI设备，成功返回0
local function spi_close_func()    
    log.info("关闭spi", spi.close(SPI_ID))
end



--12. 功能演示核心函数
local function spi_test_func()
    --1.判断SPI初始化
    if not spiDev_init_func() then
        return
    end
    --2.判断flash芯片ID
    if not spi_readChipId_func() then
        spi_close_func()
        return
    end

    -- 3.读取寄存器状态
    local status = spi_readStatus_func()
    --返回状态0表示芯片就绪且未使能写操作
    log.info("spi", "寄存器状态为: 0x%02X", status)

    -- 4.擦除扇区（4KB）
    --0x000000是要擦除的扇区的起始地址，即第一个存储单元的位置，
    --擦除从地址0x000000开始的整个 4KB 扇区，该扇区包含地址0x000000到0x000FFF的所有存储单元，可按需修改
    log.info("spi", "擦除扇区 0x000000...")
    if not spi_erase_sector(0x000000) then
        log.error("spi", "擦除失败")
        spi_close_func() --
        return
    end

    -- 5.读取擦除后的数据（应为0xFF）
    local erasedData = spi_readData_func(0x000000, 16)
    log.info("spi", "擦除后数据:", string.toHex(erasedData))

    -- 测试数据
    local testData = "Hello, SPI Flash! "

    -- 6.写入数据到地址0x000000
    log.info("spi", "写入数据:", testData)
    if spi_pageProgram_func(0x000000, testData) then
        -- 读取数据
        log.info("spi", "正在验证数据...")
        local readData = spi_readData_func(0x000000, #testData)

        -- 验证数据
        if readData == testData then
            log.info("spi", "数据验证成功!,读取到数据为：" .. readData)
        else
            log.error("spi", "数据验证失败!")
            log.info("spi", "预期读到的数据是:", testData)
            log.info("spi", "实际读取的数据是:", string.toHex(readData))
        end
    else
        log.error("spi", "写入操作失败")
    end
    -- 7.禁用写操作
    spi_writeDisable_func()
    -- 8.关闭SPI设备
    spi_close_func()
end


sys.taskInit(spi_test_func)
