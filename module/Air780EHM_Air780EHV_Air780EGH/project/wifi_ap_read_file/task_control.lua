--[[
@module  task_control
@summary 远程文件管理系统控制模块
@version 1.0
@date    2026.07.13
@usage
控制模式配置：
1. 自动启动模式：设置AUTO_START=true，系统开机后自动初始化Air6205、创建AP热点、启动HTTP文件服务器
2. 手动控制模式：设置AUTO_START=false（默认），通过短按boot按键控制系统的启停

Boot按键操作指南：
- 功能：控制系统的启动与停止
- 引脚：GPIO0
- 触发方式：短按（上升沿触发）
- 防抖处理：100ms防抖，防止误操作
- 状态切换：短按一次切换一次系统运行状态

访问方式：
- 手机/电脑连接AP热点（SSID: LuatOS_FileHub, 密码: 12345678）
- 浏览器访问 http://192.168.4.1:80/explorer.html
- 默认用户名: admin, 密码: 123456
]]

-- 导入exremotefile库（文件管理服务器）
local exremotefile = require "exremotefile"

local AUTO_START = false -- 默认使用boot按键控制方式

-- 系统状态变量
local is_running = false

-- 启动系统服务
local function start_services()
    if is_running then
        log.info("main", "系统已在运行中")
        return
    end

    log.info("main", "启动系统服务")

    -- 启动远程文件管理系统
    -- AP默认配置：SSID=LuatOS_FileHub，密码=12345678
    -- 本demo使用Air780EXX开发板+6205核心板的环境，开发板SD卡挂载SPI0，CS片选脚为IO16
    exremotefile.open(nil, {spi_id = 0,spi_cs = 16})

    is_running = true
    log.info("main", "系统服务启动完成")
end

-- 停止系统服务
local function stop_services()
    if not is_running then
        log.info("main", "系统未运行")
        return
    end

    log.info("main", "停止系统服务")

    -- 关闭远程文件管理系统（停止HTTP服务器 + 停止AP热点）
    exremotefile.close()
    is_running = false
    log.info("main", "系统服务已停止")
end

-- 初始化按键，选取boot键(GPIO0)作为功能键
local function press_key()
    log.info("boot", "按键按下")
    sys.publish("PRESS", true)
end
gpio.setup(0, press_key, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 100, 1)

local function config_services()
    -- 根据配置决定是否自动启动服务
    if AUTO_START then
        start_services()
    else
        log.info("main", "系统已就绪，等待boot按键触发")
    end

    while 1 do
        sys.waitUntil("PRESS")
        if is_running then
            stop_services()
        else
            start_services()
        end
    end
end

sys.taskInit(config_services)
