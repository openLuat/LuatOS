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
-- 1. 自动启动模式：设置AUTO_START=true（默认），系统开机后自动创建AP热点、初始化SD卡并启动HTTP文件服务器
-- 2. 手动控制模式：设置AUTO_START=false，通过拉低GPIO5控制系统的启停

-- 手动控制操作指南：
-- - 功能：控制远程文件管理系统的启动与停止
-- - 引脚：GPIO5
-- - 触发方式：短按（下降沿触发）
-- - 防抖处理：因杜邦线测试时脉冲无法控制，所以暂无设计。实际设计板子时，根据自己的需求可以更改防抖配置以及打开防抖
-- - 状态切换：短按一次切换一次系统运行状态

-- 使用示例：
-- 1. 自动启动系统：在代码中将AUTO_START设置为true（默认）
-- 2. 手动控制系统：在代码中将AUTO_START设置为false，通过拉低GPIO5切换系统状态
-- 3. 查看状态：通过日志查看系统启动和停止的状态信息

-- 注意：本模块需要在main.lua中通过require方式引入，无需额外调用接口
]]

-- 导入exremotefile库
local exremotefile = require "exremotefile"
local AUTO_START = true -- 默认使用自动启动方式

-- 系统状态变量
local is_running = false -- 标记系统是否正在运行


-- 启动系统服务
local function start_services()
    if not is_running then
        log.info("main", "启动系统服务")
        
        -- 自定义参数启动（使用8101核心板）
        -- 启动后连接默认AP热点，访问日志中的地址"http://192.168.4.1:80/explorer.html"来访问文件管理服务器。
        exremotefile.open(nil, {is_sdio = true})
        -- exremotefile.open()

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

-- 初始化按键，这里选取GPIO5作为功能键
local function press_key()
    log.info("GPIO press")
    sys.publish("PRESS", true)
end
gpio.setup(5, press_key, gpio.PULLUP, gpio.BOTH)
-- gpio.debounce(0, 100, 1) -- 实际设计板子时，根据自己的需求可以更改防抖配置以及打开防抖

local function config_services()
    -- 根据配置决定是否自动启动服务
    if AUTO_START then
        start_services()
    else
        log.info("main", "系统已就绪，等待按键触发")
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
