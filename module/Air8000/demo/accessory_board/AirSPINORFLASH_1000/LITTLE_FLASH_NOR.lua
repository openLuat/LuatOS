--[[
@module  LITTLE_FLASh_NOR
@summary LITTLE_FLASh_NOR测试功能模块
@version 1.0
@date    2025.9.05
@author  马亚丹
@usage
本demo演示的功能为：使用Air8000核心板通过SPI库实现对 NOR Flash的操作，演示读数据写数据、删除数据等操作。
以 Air8000核心板为例, 接线如下:
Air8000       AirSPINAND_1000配件版
GND(任意)          GND
VDD_EXT            VCC
GPIO12/SPI1_CS     CS,片选
SPI1_SLK           CLK,时钟
SPI1_MOSI          DI,主机输出,从机输入
SPI1_MISO          DO,主机输入,从机输出
--使用SPI1，硬件SPI CS接在gpio12上

运行核心逻辑：
1.以对象的防止配置参数，初始化启用SPI，返回SPI对象
2.用SPI对象初始化flash设备，返回flash设备对象
3.用lf库挂载flash设备对象为文件系统
4.读取文件系统的信息，以确认内存足够用于文件操作
5.操作文件读写，并验证写入一致性，追加文件等。

]]

-- LuaTools需要PROJECT和VERSION这两个信息
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "little_flash_demo"
VERSION = "1.0.0"  -- 版本升级（功能模块化重构）

log.info("main", "启动", PROJECT, "v" .. VERSION)

sys = require("sys")
sysplus = require("sysplus")



-- 1. 获取SPI配置
local function get_spi_config()
    local bsp = rtos.bsp()
    local configs = {       
        EC618 = {spi_id = 0, cs_pin = 8},
        Air8000 = {spi_id = 1, cs_pin = 12},
        AIR780EPM = {spi_id = 0, cs_pin = 8},  -- 直接写模组名称
    }
    
    -- 优先精确匹配，再模糊匹配
    if configs[bsp] then
        return configs[bsp].spi_id, configs[bsp].cs_pin
    elseif string.find(bsp, "Air8000") then
        return configs.Air8000.spi_id, configs.Air8000.cs_pin
    else
        log.error("get_spi_config", "不支持的硬件:", bsp)
        return nil, nil
    end
end

-- 2. 初始化SPI设备，返回设备对象
local function init_spi_device(spi_id, cs_pin)
    log.info("SPI初始化", "ID:", spi_id, "CS引脚:", cs_pin)
    sys.wait(100)  -- 短暂等待SPI引脚稳定
    
    -- 
    local spi_device = spi.deviceSetup(
        spi_id,     --SPI的id号
        cs_pin,     --CS引脚
        0,          -- 模式0
        0,          -- 空闲电平低
        8,          -- 8位数据
        20*1000*1000,  -- 20MHz时钟
        spi.MSB,    -- 高位在前
        1,          -- 片选有效低电平
        0           -- 不使用DMA
    )
    
    if not spi_device then
        log.error("SPI初始化", "失败")
        return nil
    end
    log.info("SPI初始化", "成功，波特率:20MHz")
    return spi_device
end

-- 3. 初始化Flash设备，返回设备对象
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

-- 4. 挂载文件系统
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

-- 5. 打印文件系统信息
local function print_filesystem_info(mount_point)
    log.info("文件系统信息", "开始查询:", mount_point)
    
    -- 方式1：获取详细信息（总块数/已用块数等）
    local ok, total_blocks, used_blocks, block_size, fs_type = fs.fsstat(mount_point)
    if ok then
        log.info("  总block数:", total_blocks)
        log.info("  已用block数:", used_blocks)
        log.info("  block大小:", block_size, "字节")
        log.info("  文件系统类型:", fs_type)
    else
        log.warn("  无法获取详细信息")
    end
    
    -- 方式2：获取根分区信息（对比参考）
    local root_info = fs.fsstat("/")
    if root_info then
        log.info("文件系统根分区信息:", fs.fsstat("/"))
    end
end

-- 6. 执行文件操作测试
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
    os.remove(append_file)  -- 清除旧文件
    io.writeFile(append_file, "LuatOS 测试")  -- 初始写入
    
    local f_append, append_err = io.open(append_file, "a+")
    if not f_append then
        log.error("  追加失败", append_file, "错误:", append_err)
        return false
    end
    local append_data = " - 追加时间: " .. os.date()
    f_append:write(append_data)
    f_append:close()
    
    local final_data = io.readFile(append_file)
    log.info("  追加后内容:", final_data)
    
    log.info("文件操作测试", "完成")
    return true
end


-- 主任务函数：按流程调用各功能函数
local function spinand_test_func()
    -- -- 流程1：等待硬件就绪
    -- if not wait_for_hardware_ready() then
    --     return
    -- end
    
    -- 流程1：获取SPI配置
    local spi_id, cs_pin = get_spi_config()
    if not spi_id or not cs_pin then
        log.error("主流程", "获取SPI配置失败，终止")
        return
    end
    
    -- 流程2：初始化SPI设备
    local spi_device = init_spi_device(spi_id, cs_pin)
    if not spi_device then
        log.error("主流程", "SPI初始化失败，终止")
        return
    end
    
    -- 流程3：初始化Flash设备
    local flash_device = init_flash_device(spi_device)
    if not flash_device then
        log.error("主流程", "Flash初始化失败，终止")
        return
    end
    
    -- 流程5：挂载文件系统
    local mount_point = "/little_flash"
    if not mount_filesystem(flash_device, mount_point) then
        log.error("主流程", "文件系统挂载失败，终止")
        return
    end
    
    -- 流程5：打印文件系统信息
    print_filesystem_info(mount_point)
    
    -- 流程6：执行文件操作测试
    if not test_file_operations(mount_point) then
        log.warn("主流程", "文件操作测试部分失败")
    end
    
   
end

sys.taskInit(spinand_test_func)   



