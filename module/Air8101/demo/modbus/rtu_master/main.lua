--[[
@module  main
@summary LuatOS 用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.12.31
@author  马梦阳
@usage

本 demo 演示的核心功能为：
1、将设备配置为 modbus RTU 主站模式
2、与从站 1 和 从站 2 进行通信
    1. 对从站 1 进行 2 秒一次的读取保持寄存器 0-1 操作
    2. 对从站 2 进行 4 秒一次的写入保持寄存器 0-1 操作
3、读取温湿度传感器数据
    1. 配置 modbus RTU 主站，读取温湿度传感器数据
    2. 每 2 秒读取一次传感器数据并解析温度和湿度值

注意事项：
1、该示例程序需要搭配 exmodbus 扩展库使用
2、在 main.lua 中 require "param_field" 模块，可以演示标准 modbus RTU 请求报文格式的使用方式
3、在 main.lua 中 require "raw_frame" 模块，可以演示非标准 modbus RTU 请求报文格式的使用方式
4、在 main.lua 中 require "temp_hum_sensor" 模块，可以演示读取485温湿度传感器数值的使用方式
5、require "param_field"、require "raw_frame" 和 require "temp_hum_sensor"，不要同时打开，否则功能会有冲突

特别说明一：
演示代码使用 Air8101 核心板进行演示
由于 Air8101 核心板不带 485 接口，所以在演示时需要外接 485 转串口模块
演示时使用的 485 转串口模块，模块硬件自动切换方向，不需要软件 io 控制
如果外接的 485 转串口模块的方向引脚连接到了 Air8101 核心板的 GPIO 引脚
则需要在 "param_field" 等其他模块代码中配置 rs485_dir_gpio 为对应的 GPIO 引脚号
同时也需要配置 rs485_dir_rx_level 为 0 或 1，默认为 0

特别说明二：
关于 RTU 报文，exmodbus 扩展库支持通过 字段参数 或 原始帧 两种方式进行配置
这两种配置方式本质都由用户将其放入 table 中在调用接口时传入，区别如下：
1、字段参数方式
    这种方式需要用户将请求报文进行解析后，将其放入 table 中，例如：
    读取请求：
    local config = {
        slave_id = 1,                         -- 从站地址
        reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
        start_addr = 0x0000,                  -- 寄存器起始地址
        reg_count = 0x0002,                   -- 寄存器数量
        timeout = 1000                        -- 超时时间
    }
    写入请求：
    local config = {
        slave_id = 2,                         -- 从站地址
        reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
        start_addr = 0x0000,                  -- 寄存器起始地址
        reg_count = 0x0002,                   -- 寄存器数量
        data = {
            [start_addr] = 0x0012,            -- 寄存器 0 的值
            [start_addr + 1] = 0x0034,        -- 寄存器 1 的值
        }
        force_multiple = true, -- 是否强制使用多个寄存器写入操作（写多个线圈功能码：0x0F；写多个寄存器功能码：0x10）
        timeout = 1000                        -- 超时时间
    }
    
2、原始帧方式
    这种方式只需要用户将原始请求报文放入 table 中，例如：
    读取请求：
    local config = {
        raw_request = string.char(
            0x01,       -- 从站地址
            0x03,       -- 功能码：读取保持寄存器
            0x00, 0x00, -- 寄存器起始地址
            0x00, 0x02, -- 寄存器数量
            0xC4, 0x0B  -- CRC16校验码
        )
        timeout = 1000  -- 超时时间
    }
    写入请求：
    local config = {
        raw_request = string.char(
            0x02,       -- 从站地址
            0x10,       -- 功能码：写入保持寄存器
            0x00, 0x00, -- 寄存器起始地址
            0x00, 0x02, -- 寄存器数量
            0x04,       -- 字节数量
            0x00, 0x12, -- 寄存器 0 的值
            0x00, 0x34, -- 寄存器 1 的值
            0x5D, 0x39  -- CRC16校验码
        )
        timeout = 1000  -- 超时时间
    }
如果你需要发送的请求报文是符合 modbus RTU 标准格式，可以使用 字段参数 或者 原始帧 方式
如果你需要发送的请求报文是非标准格式，必须使用 原始帧 方式，使用 字段参数 方式会导致解析的数据不正确
更多说明参考本目录下的 readme.md 文件；
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "RTU_MASTER"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    --配置喂狗超时时间为9秒钟
    wdt.init(9000)
    --启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 以下三种方式只能选择其中一种打开，否则会导致功能冲突

-- 加载 RTU 主站应用模块（字段参数方式）
require "param_field"

-- 加载 RTU 主站应用模块（原始帧方式）
-- require "raw_frame"

-- 加载温湿度传感器模块
-- require "temp_hum_sensor"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
