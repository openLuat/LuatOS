--[[
0@module  sfud_test
@summary sfud_test测试功能模块
@version 1.0
@date    2025.10.11
@author  马亚丹
@usage
本demo演示的功能为：使用Air8101核心板通过SPI核心库/sfud核心库实现对 NOR Flash的操作，演示读数据写数据、删除数据等操作。
以Air8101核心板为例, 接线如下:

Air8101核心板    AirSPINORFLASH_1000配件版
GND(任意)               GND
3.3V                    VCC
SPI0_CS/p44/GPIO22      CS
SPI0_SCK/p28/GPIO14     CLK
SPI0_MOSI/p57/GPIO16    MOSI
SPI0_MISO/p55/GPIO17    MISO

使用SPI0，硬件SPI CS接在gpio15上

运行核心逻辑：
1.以对象的方式配置参数，初始化启用SPI，返回SPI对象
2.用SPI对象初始化sfud，
3.用sfud库挂载flash设备为FatFS文件系统
4.读取文件系统的信息
5.操作文件读写，擦除，并验证写入一致性，追加文件等。

]]

-- SPI配置参数
local SPI_ID = 0        -- SPI总线ID，根据实际情况修改
local CS_PIN = 15       -- CS引脚，根据实际情况修改
local CPHA = 0          -- 时钟相位
local CPOL = 0          -- 时钟极性
local data_Width = 8    -- 数据宽度(位)
local bandrate = 4*1000*1000 -- 波特率(Hz)，初始化为4MHz,8101最低支持4M
gpio.setup(13, 1)        --air8101模组，gpio13控制ldo输出3.3v
-- flash操作起始地址（示例值，需根据需求调整）
local erase_addr = 4096 
-- 擦除数据的大小（示例值，需匹配 Flash block 大小）
local erase_size = 4096   
--需要操作的数据（示例值，需根据需求调整）
local data = "testdata"

-- 1. 以对象方式设置并启用 SPI，返回设备对象
local function spiDev_init_func()
    log.info("sfud", "SPI_ID", SPI_ID, "CS_PIN", CS_PIN)

    --以对象的方式初始化spi，高位在前，主模式，半双工模式
     --spi  flash只支持半双工模式
    spi_device = spi.deviceSetup(SPI_ID, CS_PIN, CPHA, CPOL, data_Width, bandrate, spi.MSB, 1, 0)    
    log.info("硬件spi", "初始化，波特率:", spi_device, bandrate)
    if not spi_device then
        log.error("SPI初始化", "失败")
        return nil
    end
    log.info("SPI初始化", "成功，波特率:",bandrate)
    return spi_device
end


-- 2. 初始化Flash设备，返回设备对象
local function init_sfud_device(spi_device)
    log.info("sfud初始化", "开始")
    local sfud_flash_device = sfud.init(spi_device)
    if not sfud_flash_device then
        log.error("Flash初始化", "失败")        
    else 
        return true
    end
    
end

-- 3. 挂载文件系统
local function mount_filesystem(sfud_device, mount_point)
    log.info("文件系统", "开始挂载:", mount_point)

    -- 检查是否支持挂载功能
    if not sfud.mount then
        log.error("文件系统", "不支持挂载功能")
        return false
    end

    -- 尝试挂载
    local mount_ok = sfud.mount(sfud_device, mount_point)
    if not mount_ok then
        log.warn("文件系统", "挂载失败，尝试重新挂载...")
        mount_ok = sfud.mount(sfud_device, mount_point)
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
    local ok, total_blocks, used_blocks, block_size, fs_type = io.fsstat(mount_point)
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

-- 7. 关闭SPI设备，成功返回0
local function spi_close_func()    
    log.info("关闭spi", spi_device:close())
end

-- 主任务函数：按流程调用各功能函数
local function spinor_test_func()
    --1.判断SPI初始化  
    spi_device = spiDev_init_func()
    if not spi_device then
        log.error("主流程", "SPI初始化失败，终止")
        spi_close_func()
        return
    end

    -- 流程2：初始化sfud设备
    local sfud_init = init_sfud_device(spi_device)
    if not sfud_init then
        log.error("主流程", "sfud 初始化失败，终止")
        spi_close_func()
        return
    end

    -- 流程3：获取Flash设备，并进行数据擦除、读写操作
    local sfud_device = sfud.getDeviceTable()    
    log.info("获取flash设备信息表:", sfud_device)
    log.info("获取 Flash 容量和page大小：", sfud.getInfo(sfud_device))
    log.info("擦除一个块的数据：", sfud.erase(sfud_device, erase_addr, erase_size))   
    log.info("写入数据：", sfud.write(sfud_device, erase_addr, data))    
    log.info("读取数据：", sfud.read(sfud_device, erase_addr, erase_size ))    
    log.info("先擦除再写入数据：", sfud.eraseWrite(sfud_device, erase_addr, data))
    --sys.wait (1000)
    

    -- 流程4：挂载flash为文件系统
    local mount_point = "/sfud_flash"
    if not mount_filesystem(sfud_device, mount_point) then
        log.error("主流程", "文件系统挂载失败，终止")
        spi_close_func()
        return
    end

    -- 流程5：打印文件系统信息
    print_filesystem_info(mount_point)

    -- 流程6：执行文件操作测试
    if not test_file_operations(mount_point) then
        log.warn("主流程", "文件操作测试部分失败")
    end  
 
     -- 流程7：关闭SPI设备
    spi_close_func()
end

sys.taskInit(spinor_test_func)
