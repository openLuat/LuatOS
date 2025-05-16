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
    local rtos_bsp = rtos.bsp()
    log.info("setup w5500 for", rtos_bsp)
    if rtos_bsp:startsWith("ESP32") then
        -- ESP32C3, GPIO5接SCS, GPIO6接IRQ/INT, GPIO8接RST
        w5500.init(2, 20000000, 5, 6, 8) 
    elseif rtos_bsp:startsWith("EC618") then
        -- EC618系列, 如Air780E/Air600E/Air700E
        -- GPIO8接SCS, GPIO1接IRQ/INT, GPIO22接RST
        w5500.init(0, 25600000, 8, 1, 22) 
    elseif rtos_bsp:startsWith("EC718") then
        -- EC718P系列, 如Air780EP/Air780EPV
        -- GPIO8接SCS, GPIO29接IRQ/INT, GPIO30接RST
        w5500.init(0, 25600000, 8, 29, 30)
    elseif rtos_bsp == "AIR101" or rtos_bsp == "AIR103" or rtos_bsp == "AIR601" then
        -- PA1接SCS, PB01接IRQ/INT, PA7接RST
        w5500.init(0, 20000000, pin.PA01, pin.PB01, pin.PA07)
    elseif rtos_bsp == "AIR105" then
        -- PC14接SCS, PC01接IRQ/INT, PC00接RST
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配w5500, 请查证")
        end
    end
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

    -- 注意这里的adapter参数, 所在bsp可能有多种适配器, 例如Air780E本身也有4G网络适配器
    -- 所以这里要指定使用哪个网络适配器去访问
    -- 同理, socket/mqtt/websocket/ftp库均有类似的配置项
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

