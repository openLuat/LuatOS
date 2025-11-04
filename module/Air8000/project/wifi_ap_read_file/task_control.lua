--[[
@module  task_control
@summary 远程文件管理系统控制模块
@version 1.0
@date    2025.11.4
@author  拓毅恒
@usage
-- 远程文件管理系统控制模块使用方法
-- 功能：控制远程文件管理系统的启动、停止以及操作模式切换

-- 控制模式配置：
-- 1. 自动启动模式：设置AUTO_START=true，系统开机后自动创建AP热点、初始化SD卡并启动HTTP文件服务器
-- 2. 手动控制模式：设置AUTO_START=false（默认），通过短按boot按键控制系统的启停

-- Boot按键操作指南：
-- - 功能：控制远程文件管理系统的启动与停止
-- - 引脚：GPIO0
-- - 触发方式：短按（上升沿触发）
-- - 防抖处理：100ms防抖，防止误操作
-- - 状态切换：短按一次切换一次系统运行状态

-- 使用示例：
-- 1. 自动启动系统：在代码中将AUTO_START设置为true
-- 2. 手动控制系统：短按boot按键切换系统状态
-- 3. 查看状态：通过日志查看系统启动和停止的状态信息

-- 注意：本模块需要在main.lua中通过require方式引入，无需额外调用接口
]]

-- 导入exremotefile库
local exremotefile = require "exremotefile"
local AUTO_START = false -- 默认使用boot按键控制方式

-- 系统状态变量
local is_running = false -- 标记系统是否正在运行


-- 启动系统服务
local function start_services()
    if not is_running then
        log.info("main", "启动系统服务")
        
        -- 自定义参数启动（使用8000开发板）
        -- 启动后连接默认AP热点，访问日志中的地址"http://192.168.4.1:80/explorer.html"来访问文件管理服务器。
        exremotefile.open(nil, {is_8000_development_board = true})

        is_running = true
        log.info("main", "系统服务启动完成")
    end
end

-- 停止系统服务
local function stop_services()
    if is_running then
        log.info("main", "停止系统服务")

        -- 关闭远程文件管理系统
        exremotefile.close()

        is_running = false
        log.info("main", "系统服务已停止")
    end
end

-- 初始化按键，这里选取boot键作为功能键
local function press_key()
    log.info("boot press")
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
        -- 切换系统状态
        if is_running then
            stop_services()
        else
            start_services()
        end
    end
end


sys.taskInit(config_services)
