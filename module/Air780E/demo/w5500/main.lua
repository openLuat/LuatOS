--[[
w5500集成演示
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "w5500demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")
sysplus = require("sysplus")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

-- 联网函数
sys.taskInit(function()
    sys.wait(100)
    if w5500 == nil then
        while 1 do
            log.info("w5500", "当前固件未包含w5500库")
            sys.wait(1000)
        end
    end
    -----------------------------
    -- w5500 以太网
    ----------------------------
    -- 接线提示:
    -- 首先要找到SPI端口, SCK时钟, MISO, MOSI, 接好
    -- 供电要足, 尤其是w5500模块是3.3v供电的, 最好能外接供电
    -- 下列默认选取的GPIO不是强制的, 可以替换成其他GPIO的
    -- EC618系列, 如Air780E/Air600E/Air700E
    -- GPIO8接SCS, GPIO1接IRQ/INT, GPIO22接RST
    w5500.init(0, 25600000, 8, 1, 22) 
    w5500.config() --默认是DHCP模式
    -- w5500.config("192.168.1.29", "255.255.255.0", "192.168.1.1") --静态IP模式
    -- w5500.config("192.168.1.122", "255.255.255.0", "192.168.1.1", string.fromHex("102a3b4c5d6e"))
    w5500.bind(socket.ETH0)
    -- 提示: 要接上网线, 否则可能没有任何日志打印
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready")
end)

-- 演示task
local function sockettest()
    -- 等待联网
    sys.waitUntil("net_ready")

    socket.sntp(nil, socket.ETH0)
    sys.wait(500)

    local opts = {}
    opts["adapter"] = socket.ETH0
    while 1 do
        log.info("发起http请求")
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/get", nil, nil, opts).wait()
        log.info("http", code, body)
        sys.wait(5000)
    end
end

sys.taskInit(sockettest)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

