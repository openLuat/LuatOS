
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "udpsrvdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

_G.udpsrv = require "udpsrv"

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

-- 统一联网函数
sys.taskInit(function()
    local device_id = mcu.unique_id():toHex()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成自动配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        -- wlan.setMac(0, string.fromHex("6055F9779010"))
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        device_id = wlan.getMac()
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2) -- 自动切换SIM卡
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
    elseif w5500 then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        -- LED = gpio.setup(62, 0, gpio.PULLUP)
    elseif socket then
        -- 适配的socket库也OK
        -- 没有其他操作, 单纯给个注释说明
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready", device_id)
end)

sys.taskInit(function()
    sys.waitUntil("net_ready")
    local mytopic = "my_udpsrv"
    -- 注意, udpsrv.create有3个参数, 最后一个参数是网络适配器编号
    local srv = udpsrv.create(12345, mytopic)
    -- 在wifi模组中,通常有STA和AP两个适配器, 若需要在AP监听,则需要指定编号
    -- local srv = udpsrv.create(12345, mytopic, socket.LWIP_AP)
    if srv then
        -- 单播
        srv:send("I am UP", "192.168.1.5", 777)
        -- 广播
        srv:send("I am UP", "255.255.255.255", 777)
        while 1 do
            local ret, data, remote_ip, remote_port = sys.waitUntil(mytopic, 15000)
            if ret then
                -- remote_ip, remote_port 是2023.10.12新增的返回值
                log.info("udpsrv", "收到数据", data:toHex(), remote_ip, remote_port)
                -- 按业务处理收到的数据
            else
                log.info("udpsrv", "没数据,那广播一条")
                srv:send("I am UP", "255.255.255.255", 777)
            end
        end
    else
        log.info("udpsrv", "启动失败")
    end
    -- 如果关闭,调用
    -- srv:close()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
