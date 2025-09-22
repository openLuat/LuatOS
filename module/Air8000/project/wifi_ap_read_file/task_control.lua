-- 业务逻辑触发方式配置
-- 配置说明：
-- 1. 设置为true: 开机自动创建ap热点，初始化sd卡，创建http 文件服务器
-- 2. 设置为false: 默认不创建ap热点，不初始化sd卡，不创建http 文件服务器；通过短按boot按键控制开关

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
