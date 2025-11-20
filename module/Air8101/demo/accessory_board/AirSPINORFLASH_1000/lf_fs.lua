--[[
@module  lf_fs
@summary lf_fs测试功能模块
@version 1.0
@date    2025.9.05
@author  马亚丹
@usage
本demo演示的功能为：使用Air8101核心板通过SPI核心库/lf核心库/io核心库实现对 NOR Flash的操作，演示读数据写数据、删除数据等操作。
以Air8101核心板为例, 接线如下:

Air8101核心板    AirSPINORFLASH_1000配件版
GND(任意)               GND
3.3V                    VCC
SPI0_CS/p54/GPIO15      CS
SPI0_SCK/p28/GPIO14     CLK
SPI0_MOSI/p57/GPIO16    MOSI
SPI0_MISO/p55/GPIO17    MISO

使用SPI0，硬件SPI CS接在gpio15上

运行核心逻辑：
1.以对象的方式配置参数，初始化启用SPI，返回SPI对象
2.用SPI对象初始化flash设备，返回flash设备对象
3.用lf库挂载flash设备对象为LittleFS文件系统
4.读取文件系统的信息，以确认内存足够用于文件操作
5.操作文件读写，并验证写入一致性，追加文件等。

]]

-- SPI配置参数
local SPI_ID = 0             -- SPI总线ID，根据实际情况修改
local CS_PIN = 15            -- CS引脚，根据实际情况修改
local CPHA = 0               -- 时钟相位
local CPOL = 0               -- 时钟极性
local data_Width = 8         -- 数据宽度(位)
local bandrate = 4 * 1000 * 1000 -- 波特率(Hz)，初始化为4MHz,8101最低支持4M
gpio.setup(13, 1)            --air8101模组，gpio13控制ldo输出3.3v

-- 1. 以对象方式设置并启用 SPI，返回设备对象
local function spiDev_init_func()
    log.info("lf_fs", "SPI_ID", SPI_ID, "CS_PIN", CS_PIN)

    --以对象的方式初始化spi，高位在前，主模式，半双工模式
    --spi  flash只支持半双工模式
    local spi_device = spi.deviceSetup(SPI_ID, CS_PIN, CPHA, CPOL, data_Width, bandrate, spi.MSB, 1, 0)

    log.info("硬件spi", "初始化，波特率:", spi_device, bandrate)
    if not spi_device then
        log.error("SPI初始化", "失败")
        return nil
    end
    log.info("SPI初始化", "成功，波特率:", bandrate)
    return spi_device
end


-- 2. 初始化Flash设备，返回设备对象
local function init_flash_device(spi_device)
    log.info("Flash初始化", "开始")
    local flash_device = lf.init(spi_device)
    if not flash_device then
        log.error("Flash初始化", "失败")
        return nil
    end
    log.info("Flash初始化", "成功，设备:", flash_device)
    return flash_device
end

-- 3. 挂载文件系统
local function mount_filesystem(flash_device, mount_point)
    log.info("文件系统", "开始挂载:", mount_point)

    -- 检查是否支持挂载功能
    if not lf.mount then
        log.error("文件系统", "lf模块不支持挂载功能")
        return false
    end

    -- 尝试挂载
    local mount_ok = lf.mount(flash_device, mount_point)
    if not mount_ok then
        log.warn("文件系统lf", "挂载失败，尝试重新挂载...")
        mount_ok = lf.mount(flash_device, mount_point)
        if not mount_ok then
            log.error("文件系统", "仍挂载失败")
            return false
        end
    end

    log.info("文件系统", "挂载成功:", mount_point)
    return true
end

-- 4. 打印文件系统信息
local function print_filesystem_info(mount_point)
    log.info("文件系统信息", "开始查询:", mount_point)

    -- 获取文件系统详细信息，总块数/已用块数等
    local ok, total_blocks, used_blocks, block_size, fs_type = fs.fsstat(mount_point)
    if ok then
        log.info("  总block数:", total_blocks)
        log.info("  已用block数:", used_blocks)
        log.info("  block大小:", block_size, "字节")
        log.info("  文件系统类型:", fs_type)
    else
        log.warn("  无法获取详细信息")
    end
end

-- 5. 执行文件操作测试
local function test_file_operations(mount_point)
    log.info("文件操作测试", "开始")

    -- 测试写入文件
    local test_file = mount_point .. "/test.txt"
    local f, err = io.open(test_file, "w")
    if not f then
        log.error("  写入失败", test_file, "错误:", err)
        return false
    end
    local write_data = "当前时间: " .. os.date()
    f:write(write_data)
    f:close()
    log.info("  写入成功", test_file, "内容:", write_data)

    -- 测试读取文件
    local read_data, read_err = io.readFile(test_file)
    if not read_data then
        log.error("  读取失败", test_file, "错误:", read_err)
        return false
    end
    log.info("  读取成功", test_file, "内容:", read_data)

    -- 验证内容一致性
    if read_data ~= write_data then
        log.warn("  内容不一致", "写入:", write_data, "读取:", read_data)
    end

    -- 测试文件追加
    local append_file = mount_point .. "/append.txt"
    os.remove(append_file) -- 清除旧文件
    io.writeFile(append_file, "LuatOS 测试") -- 初始写入

    local f_append, append_err = io.open(append_file, "a+")
    if not f_append then
        log.error("  追加失败", append_file, "错误:", append_err)
        return false
    end
    local append_data = " - 追加时间: " .. os.date()
    f_append:write(append_data)
    -- 执行完操作后,一定要关掉文件
    f_append:close()

    local final_data = io.readFile(append_file)
    log.info("  追加后内容:", final_data)

    log.info("文件操作测试", "完成")

    return true
end

-- 7. 关闭SPI设备对象，成功返回true
local function spi_close_func()
    log.info("关闭spi", spi_device:close())
end

-- 主任务函数：按流程调用各功能函数
local function spinor_test_func()
    --1.判断SPI初始化
    spi_device = spiDev_init_func()
    if not spi_device then
        log.error("主流程", "SPI初始化失败，终止")
        return
    end

    -- 流程2：初始化Flash设备
    local flash_device = init_flash_device(spi_device)
    if not flash_device then
        log.error("主流程", "Flash初始化失败，终止")
        spi_close_func()
        return
    end

    -- 流程3：挂载文件系统
    local mount_point = "/little_flash"
    if not mount_filesystem(flash_device, mount_point) then
        log.error("主流程", "文件系统挂载失败，终止")
        spi_close_func()
        return
    end

    -- 流程4：打印文件系统信息
    print_filesystem_info(mount_point)

    -- 流程5：执行文件操作测试
    if not test_file_operations(mount_point) then
        log.warn("主流程", "文件操作测试部分失败")
    end

    -- 6.关闭SPI设备
    spi_close_func()
end

sys.taskInit(spinor_test_func)
